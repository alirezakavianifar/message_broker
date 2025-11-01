"""
Message Broker Worker

Consumes messages from Redis queue and delivers them to the main server
with retry logic and concurrent processing support.
"""

import asyncio
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any

import httpx
import redis
import yaml
from logging.handlers import TimedRotatingFileHandler
from prometheus_client import Counter, Histogram, Gauge, start_http_server

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# ============================================================================
# Configuration
# ============================================================================

class WorkerConfig:
    """Worker configuration"""
    
    def __init__(self):
        self.load_config()
    
    def load_config(self):
        """Load configuration from YAML and environment"""
        config_file = Path(__file__).parent / "config.yaml"
        
        # Load YAML config
        if config_file.exists():
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
        else:
            config = {}
        
        # Redis configuration
        self.redis_host = os.getenv("REDIS_HOST", "localhost")
        self.redis_port = int(os.getenv("REDIS_PORT", "6379"))
        self.redis_db = int(os.getenv("REDIS_DB", "0"))
        self.redis_password = os.getenv("REDIS_PASSWORD", "")
        self.redis_queue = "message_queue"
        
        # Main server configuration
        self.main_server_url = os.getenv("MAIN_SERVER_URL", "https://localhost:8000")
        self.deliver_endpoint = "/internal/messages/deliver"
        self.status_endpoint = "/internal/messages/{message_id}/status"
        
        # TLS configuration
        self.worker_cert = os.getenv("WORKER_CERT_PATH", "certs/worker.crt")
        self.worker_key = os.getenv("WORKER_KEY_PATH", "certs/worker.key")
        self.ca_cert = os.getenv("CA_CERT_PATH", "certs/ca.crt")
        
        # Worker configuration
        self.worker_id = os.getenv("WORKER_ID", f"worker-{os.getpid()}")
        self.concurrency = int(os.getenv("WORKER_CONCURRENCY", "4"))
        self.retry_interval = int(os.getenv("WORKER_RETRY_INTERVAL", "30"))
        self.max_attempts = int(os.getenv("WORKER_MAX_ATTEMPTS", "10000"))
        self.poll_interval = 5  # Seconds for BRPOP timeout
        self.batch_size = int(os.getenv("WORKER_BATCH_SIZE", "10"))
        
        # Logging configuration
        self.log_level = os.getenv("LOG_LEVEL", "INFO")
        self.log_dir = Path(os.getenv("LOG_FILE_PATH", "logs"))
        self.log_dir.mkdir(exist_ok=True)
        
        # Metrics configuration
        self.metrics_enabled = os.getenv("WORKER_METRICS_ENABLED", "true").lower() == "true"
        self.metrics_port = int(os.getenv("WORKER_METRICS_PORT", "9100"))

# Global configuration instance
config = WorkerConfig()

# ============================================================================
# Logging Setup
# ============================================================================

def setup_logging():
    """Setup logging with daily rotation"""
    logger = logging.getLogger("worker")
    logger.setLevel(getattr(logging, config.log_level))
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - [%(worker_id)s] - %(message)s'
    )
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)
    
    # File handler with daily rotation
    # Use try-except to handle Windows log rotation issues with multiple workers
    try:
        log_file = config.log_dir / "worker.log"
        file_handler = TimedRotatingFileHandler(
            log_file,
            when='midnight',
            interval=1,
            backupCount=7,
            encoding='utf-8',
            delay=True  # Delay file opening to reduce lock conflicts
        )
        file_handler.setLevel(logging.DEBUG)
        file_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - [%(worker_id)s] - [%(filename)s:%(lineno)d] - %(message)s'
        )
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        # If file logging fails (e.g., permission issues), continue with console only
        print(f"Warning: Could not setup file logging: {e}")
        print("Continuing with console logging only...")
    
    return logger

logger = setup_logging()

# Add worker_id to logger context
class WorkerLoggerAdapter(logging.LoggerAdapter):
    """Logger adapter to include worker_id in all log messages"""
    def process(self, msg, kwargs):
        return msg, {**kwargs, 'extra': {'worker_id': config.worker_id}}

logger = WorkerLoggerAdapter(logger, {})

# ============================================================================
# Prometheus Metrics
# ============================================================================

# Message processing metrics
messages_processed = Counter(
    'worker_messages_processed_total',
    'Total number of messages processed',
    ['worker_id', 'status']
)

messages_delivered = Counter(
    'worker_messages_delivered_total',
    'Total number of messages successfully delivered',
    ['worker_id']
)

messages_failed = Counter(
    'worker_messages_failed_total',
    'Total number of messages that failed delivery',
    ['worker_id', 'reason']
)

messages_retried = Counter(
    'worker_messages_retried_total',
    'Total number of message retry attempts',
    ['worker_id']
)

delivery_duration = Histogram(
    'worker_delivery_duration_seconds',
    'Message delivery duration in seconds',
    ['worker_id']
)

queue_wait_time = Histogram(
    'worker_queue_wait_seconds',
    'Time message spent in queue before processing',
    ['worker_id']
)

active_workers = Gauge(
    'worker_active_workers',
    'Number of active worker processes'
)

processing_messages = Gauge(
    'worker_processing_messages',
    'Number of messages currently being processed',
    ['worker_id']
)

# ============================================================================
# Redis Queue Manager
# ============================================================================

class RedisQueueManager:
    """Redis queue manager for atomic message consumption"""
    
    def __init__(self):
        self.client = None
        self.connect()
    
    def connect(self):
        """Connect to Redis"""
        try:
            self.client = redis.Redis(
                host=config.redis_host,
                port=config.redis_port,
                db=config.redis_db,
                password=config.redis_password if config.redis_password else None,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_keepalive=True,
                health_check_interval=30
            )
            # Test connection
            self.client.ping()
            logger.info(f"Connected to Redis at {config.redis_host}:{config.redis_port}")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            raise
    
    def pop_message(self, timeout: int = 5) -> Optional[Dict[str, Any]]:
        """
        Pop message from queue (blocking operation with timeout)
        
        Args:
            timeout: Timeout in seconds for BRPOP
            
        Returns:
            Message dictionary or None if timeout
        """
        try:
            result = self.client.brpop(config.redis_queue, timeout=timeout)
            if result:
                _, message_json = result
                message = json.loads(message_json)
                logger.debug(f"Popped message: {message.get('message_id')}")
                return message
            return None
        except Exception as e:
            logger.error(f"Failed to pop message from queue: {e}")
            return None
    
    def push_message(self, message: Dict[str, Any]) -> bool:
        """
        Push message back to queue (for retry)
        
        Args:
            message: Message dictionary
            
        Returns:
            True if successful
        """
        try:
            message_json = json.dumps(message)
            self.client.lpush(config.redis_queue, message_json)
            return True
        except Exception as e:
            logger.error(f"Failed to push message back to queue: {e}")
            return False
    
    def get_queue_size(self) -> int:
        """Get current queue size"""
        try:
            return self.client.llen(config.redis_queue)
        except Exception:
            return 0

# Global Redis manager
redis_manager = RedisQueueManager()

# ============================================================================
# Main Server Client
# ============================================================================

class MainServerClient:
    """HTTP client for main server communication with mutual TLS"""
    
    def __init__(self):
        self.base_url = config.main_server_url
        self.timeout = httpx.Timeout(30.0)
        self.client = None
    
    def _get_client(self) -> httpx.AsyncClient:
        """Get or create HTTP client"""
        if self.client is None or self.client.is_closed:
            self.client = httpx.AsyncClient(
                cert=(config.worker_cert, config.worker_key),
                verify=config.ca_cert,
                timeout=self.timeout
            )
        return self.client
    
    async def deliver_message(self, message_data: Dict[str, Any]) -> bool:
        """
        Deliver message to main server
        
        Args:
            message_data: Message data to deliver
            
        Returns:
            True if successful, False otherwise
        """
        url = f"{self.base_url}{config.deliver_endpoint}"
        
        payload = {
            "message_id": message_data.get("message_id"),
            "worker_id": config.worker_id
        }
        
        try:
            client = self._get_client()
            response = await client.post(url, json=payload)
            response.raise_for_status()
            
            logger.debug(f"Message delivered: {message_data.get('message_id')}")
            return True
            
        except httpx.HTTPStatusError as e:
            logger.error(
                f"Main server returned error {e.response.status_code} "
                f"for message {message_data.get('message_id')}: {e.response.text}"
            )
            return False
        except httpx.RequestError as e:
            logger.error(
                f"Failed to connect to main server for message "
                f"{message_data.get('message_id')}: {e}"
            )
            return False
        except Exception as e:
            logger.error(
                f"Unexpected error delivering message {message_data.get('message_id')}: {e}"
            )
            return False
    
    async def update_status(
        self,
        message_id: str,
        status: str,
        attempt_count: int,
        error_message: Optional[str] = None
    ) -> bool:
        """
        Update message status on main server
        
        Args:
            message_id: Message UUID
            status: New status (queued, processing, delivered, failed)
            attempt_count: Current attempt count
            error_message: Optional error message
            
        Returns:
            True if successful
        """
        url = f"{self.base_url}{config.status_endpoint.format(message_id=message_id)}"
        
        payload = {
            "status": status,
            "attempt_count": attempt_count,
            "error_message": error_message
        }
        
        try:
            client = self._get_client()
            response = await client.put(url, json=payload)
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to update status for message {message_id}: {e}")
            return False
    
    async def close(self):
        """Close HTTP client"""
        if self.client and not self.client.is_closed:
            await self.client.aclose()

# ============================================================================
# Message Processor
# ============================================================================

class MessageProcessor:
    """Process messages with retry logic"""
    
    def __init__(self, worker_id: str):
        self.worker_id = worker_id
        self.main_server_client = MainServerClient()
        self.running = True
    
    async def process_message(self, message: Dict[str, Any]) -> bool:
        """
        Process a single message
        
        Args:
            message: Message dictionary
            
        Returns:
            True if successfully delivered, False if needs retry
        """
        message_id = message.get("message_id")
        attempt_count = message.get("attempt_count", 0)
        
        start_time = time.time()
        processing_messages.labels(worker_id=self.worker_id).inc()
        
        try:
            # Calculate queue wait time
            queued_at = message.get("queued_at")
            if queued_at:
                try:
                    queued_time = datetime.fromisoformat(queued_at.replace('Z', '+00:00'))
                    wait_seconds = (datetime.utcnow() - queued_time.replace(tzinfo=None)).total_seconds()
                    queue_wait_time.labels(worker_id=self.worker_id).observe(wait_seconds)
                except Exception:
                    pass
            
            # Check max attempts
            if attempt_count >= config.max_attempts:
                logger.warning(
                    f"Message {message_id} exceeded max attempts ({config.max_attempts}), "
                    f"marking as failed"
                )
                await self.main_server_client.update_status(
                    message_id,
                    "failed",
                    attempt_count,
                    f"Exceeded maximum attempts ({config.max_attempts})"
                )
                messages_failed.labels(
                    worker_id=self.worker_id,
                    reason="max_attempts_exceeded"
                ).inc()
                return True  # Don't retry
            
            # Attempt delivery
            logger.info(
                f"Processing message {message_id} "
                f"(attempt {attempt_count + 1}/{config.max_attempts})"
            )
            
            success = await self.main_server_client.deliver_message(message)
            
            duration = time.time() - start_time
            delivery_duration.labels(worker_id=self.worker_id).observe(duration)
            
            if success:
                # Success - message delivered
                logger.info(f"Message {message_id} delivered successfully")
                messages_delivered.labels(worker_id=self.worker_id).inc()
                messages_processed.labels(
                    worker_id=self.worker_id,
                    status="delivered"
                ).inc()
                return True
            else:
                # Failed - needs retry
                logger.warning(f"Message {message_id} delivery failed, will retry")
                messages_retried.labels(worker_id=self.worker_id).inc()
                return False
                
        except Exception as e:
            logger.error(f"Error processing message {message_id}: {e}", exc_info=True)
            messages_failed.labels(
                worker_id=self.worker_id,
                reason="processing_error"
            ).inc()
            return False
        finally:
            processing_messages.labels(worker_id=self.worker_id).dec()
    
    async def handle_retry(self, message: Dict[str, Any]):
        """
        Handle message retry logic
        
        Args:
            message: Message dictionary
        """
        message_id = message.get("message_id")
        attempt_count = message.get("attempt_count", 0)
        
        # Increment attempt count
        message["attempt_count"] = attempt_count + 1
        
        # Update status on main server
        await self.main_server_client.update_status(
            message_id,
            "queued",  # Back to queued status
            message["attempt_count"],
            f"Retry attempt {message['attempt_count']}"
        )
        
        # Wait for retry interval
        logger.info(
            f"Waiting {config.retry_interval}s before retrying message {message_id}"
        )
        await asyncio.sleep(config.retry_interval)
        
        # Push back to queue
        if redis_manager.push_message(message):
            logger.info(f"Message {message_id} re-queued for retry")
        else:
            logger.error(f"Failed to re-queue message {message_id}")
            messages_failed.labels(
                worker_id=self.worker_id,
                reason="requeue_failed"
            ).inc()
    
    async def cleanup(self):
        """Cleanup resources"""
        await self.main_server_client.close()

# ============================================================================
# Worker
# ============================================================================

class Worker:
    """Main worker class that manages message processing"""
    
    def __init__(self, worker_id: str):
        self.worker_id = worker_id
        self.processor = MessageProcessor(worker_id)
        self.running = True
        self.processing_tasks = set()
    
    async def run(self):
        """Main worker loop"""
        logger.info(f"Worker {self.worker_id} starting...")
        logger.info(f"Configuration: retry_interval={config.retry_interval}s, "
                   f"max_attempts={config.max_attempts}, concurrency={config.concurrency}")
        
        active_workers.inc()
        
        try:
            while self.running:
                try:
                    # Pop message from queue (blocking with timeout)
                    message = redis_manager.pop_message(timeout=config.poll_interval)
                    
                    if message is None:
                        # Timeout - no message available
                        continue
                    
                    # Process message asynchronously
                    task = asyncio.create_task(self._process_message_wrapper(message))
                    self.processing_tasks.add(task)
                    task.add_done_callback(self.processing_tasks.discard)
                    
                    # Limit concurrent processing
                    while len(self.processing_tasks) >= config.concurrency:
                        await asyncio.sleep(0.1)
                    
                except Exception as e:
                    logger.error(f"Error in worker loop: {e}", exc_info=True)
                    await asyncio.sleep(1)
            
            # Wait for remaining tasks to complete
            if self.processing_tasks:
                logger.info(f"Waiting for {len(self.processing_tasks)} tasks to complete...")
                await asyncio.gather(*self.processing_tasks, return_exceptions=True)
            
        finally:
            active_workers.dec()
            await self.processor.cleanup()
            logger.info(f"Worker {self.worker_id} stopped")
    
    async def _process_message_wrapper(self, message: Dict[str, Any]):
        """Wrapper for message processing with retry logic"""
        try:
            success = await self.processor.process_message(message)
            
            if not success and self.running:
                # Handle retry
                await self.processor.handle_retry(message)
        except Exception as e:
            logger.error(f"Error in message processing wrapper: {e}", exc_info=True)
    
    def stop(self):
        """Stop the worker"""
        logger.info(f"Stopping worker {self.worker_id}...")
        self.running = False

# ============================================================================
# Main
# ============================================================================

# Global worker instance for signal handling
worker_instance = None

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, initiating graceful shutdown...")
    if worker_instance:
        worker_instance.stop()

async def main():
    """Main entry point"""
    global worker_instance
    
    # Setup signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Start Prometheus metrics server
    if config.metrics_enabled:
        try:
            start_http_server(config.metrics_port)
            logger.info(f"Prometheus metrics server started on port {config.metrics_port}")
        except Exception as e:
            logger.warning(f"Failed to start metrics server: {e}")
    
    # Create and run worker
    worker_instance = Worker(config.worker_id)
    
    try:
        await worker_instance.run()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.error(f"Fatal error in worker: {e}", exc_info=True)
        raise
    finally:
        logger.info("Worker shutdown complete")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutdown complete")
    except Exception as e:
        logger.error(f"Failed to start worker: {e}", exc_info=True)
        sys.exit(1)

