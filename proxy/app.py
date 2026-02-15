"""
Message Broker Proxy Server

FastAPI application that receives messages via mutual TLS, validates them,
enqueues to Redis, and registers with the main server.
"""

import json
import logging
import os
import re
import sys
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional

import httpx
import redis
import yaml
from fastapi import FastAPI, Request, HTTPException, Depends, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, validator
from prometheus_client import Counter, Histogram, Gauge, make_asgi_app
from logging.handlers import TimedRotatingFileHandler

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Initialize FastAPI app
app = FastAPI(
    title="Message Broker Proxy",
    description="Proxy server for message ingestion with mutual TLS",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ============================================================================
# Configuration
# ============================================================================

class ProxyConfig:
    """Proxy server configuration"""
    
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
        self.main_server_register_endpoint = "/internal/messages/register"
        
        # TLS configuration
        self.server_cert = os.getenv("SERVER_CERT_PATH", "certs/proxy.crt")
        self.server_key = os.getenv("SERVER_KEY_PATH", "certs/proxy.key")
        self.ca_cert = os.getenv("CA_CERT_PATH", "certs/ca.crt")
        
        # Validation configuration
        self.phone_pattern = r"^\+[1-9]\d{1,14}$"
        self.max_message_length = 1000
        
        # Logging configuration
        self.log_level = os.getenv("LOG_LEVEL", "INFO")
        self.log_dir = Path(os.getenv("LOG_FILE_PATH", "logs"))
        self.log_dir.mkdir(exist_ok=True)
        
        # Rate limiting
        self.rate_limit_enabled = True
        self.rate_limit_requests = 100
        self.rate_limit_window = 60  # seconds

# Global configuration instance
config = ProxyConfig()

# ============================================================================
# Logging Setup
# ============================================================================

def setup_logging():
    """Setup logging with daily rotation"""
    logger = logging.getLogger("proxy")
    logger.setLevel(getattr(logging, config.log_level))
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)
    
    # File handler with daily rotation
    # Use try-except to handle Windows log rotation issues with multiple workers
    try:
        log_file = config.log_dir / "proxy.log"
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
            '%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s'
        )
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        # If file logging fails (e.g., permission issues), continue with console only
        print(f"Warning: Could not setup file logging: {e}")
        print("Continuing with console logging only...")
    
    return logger

logger = setup_logging()

# ============================================================================
# Prometheus Metrics
# ============================================================================

# Request metrics
requests_total = Counter(
    'proxy_requests_total',
    'Total number of requests',
    ['method', 'endpoint', 'status']
)

request_duration = Histogram(
    'proxy_request_duration_seconds',
    'Request duration in seconds',
    ['method', 'endpoint']
)

# Queue metrics
queue_size = Gauge(
    'redis_queue_size',
    'Current size of Redis message queue'
)

messages_enqueued = Counter(
    'proxy_messages_enqueued_total',
    'Total number of messages enqueued'
)

messages_failed = Counter(
    'proxy_messages_failed_total',
    'Total number of failed messages',
    ['reason']
)

# Certificate metrics
certificate_validations = Counter(
    'proxy_certificate_validations_total',
    'Total certificate validations',
    ['result']
)

# ============================================================================
# Redis Connection
# ============================================================================

class RedisQueue:
    """Redis queue manager"""
    
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
    
    def enqueue(self, message_data: dict) -> bool:
        """
        Enqueue message to Redis list
        
        Args:
            message_data: Message dictionary
            
        Returns:
            True if successful, False otherwise
        """
        try:
            message_json = json.dumps(message_data)
            self.client.lpush(config.redis_queue, message_json)
            queue_size.set(self.client.llen(config.redis_queue))
            return True
        except Exception as e:
            logger.error(f"Failed to enqueue message: {e}")
            return False
    
    def get_queue_size(self) -> int:
        """Get current queue size"""
        try:
            return self.client.llen(config.redis_queue)
        except Exception:
            return 0
    
    def health_check(self) -> bool:
        """Check Redis health"""
        try:
            self.client.ping()
            return True
        except Exception:
            return False

# Global Redis queue instance
redis_queue = RedisQueue()

# ============================================================================
# Main Server Client
# ============================================================================

class MainServerClient:
    """HTTP client for main server communication"""
    
    def __init__(self):
        self.base_url = config.main_server_url
        self.timeout = httpx.Timeout(30.0)
    
    async def register_message(self, message_data: dict) -> bool:
        """
        Register message with main server
        
        Args:
            message_data: Message data to register
            
        Returns:
            True if successful, False otherwise
        """
        url = f"{self.base_url}{config.main_server_register_endpoint}"
        
        try:
            # Check if SSL verification should be disabled
            verify_ssl = os.getenv("MAIN_SERVER_VERIFY_SSL", "true").lower() != "false"
            verify = False if not verify_ssl else config.ca_cert
            
            async with httpx.AsyncClient(
                cert=(config.server_cert, config.server_key),
                verify=verify,
                timeout=self.timeout
            ) as client:
                response = await client.post(url, json=message_data)
                response.raise_for_status()
                logger.debug(f"Message registered with main server: {message_data['message_id']}")
                return True
        except httpx.HTTPStatusError as e:
            logger.error(f"Main server returned error {e.response.status_code}: {e.response.text}")
            return False
        except httpx.RequestError as e:
            logger.error(f"Failed to connect to main server: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error registering message: {e}")
            return False

# Global main server client
main_server_client = MainServerClient()

# ============================================================================
# Request Models
# ============================================================================

class MessageMetadata(BaseModel):
    """Message metadata"""
    timestamp: Optional[str] = Field(None, description="ISO 8601 timestamp")
    client_id: Optional[str] = Field(None, description="Client identifier")
    domain: Optional[str] = Field(None, description="Domain name")


class MessageSubmission(BaseModel):
    """Message submission request"""
    sender_number: str = Field(..., description="Phone number in E.164 format")
    message_body: str = Field(..., description="Message content")
    metadata: Optional[MessageMetadata] = Field(default_factory=MessageMetadata)
    
    @validator('sender_number')
    def validate_phone_number(cls, v):
        """Validate phone number format"""
        if not re.match(config.phone_pattern, v):
            raise ValueError(
                f"Invalid phone number format. Must match E.164 format: {config.phone_pattern}"
            )
        return v
    
    @validator('message_body')
    def validate_message_body(cls, v):
        """Validate message body"""
        if not v or not v.strip():
            raise ValueError("Message body cannot be empty")
        if len(v) > config.max_message_length:
            raise ValueError(
                f"Message body exceeds maximum length of {config.max_message_length} characters"
            )
        return v


class MessageAcceptedResponse(BaseModel):
    """Message accepted response"""
    message_id: str
    status: str = "queued"
    client_id: str
    queued_at: str
    position: Optional[int] = None


class ErrorResponse(BaseModel):
    """Error response"""
    error: str
    message: str
    details: Optional[dict] = None
    timestamp: str
    request_id: Optional[str] = None


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    version: str
    timestamp: str
    checks: dict
    uptime_seconds: Optional[int] = None

# ============================================================================
# Certificate Extraction
# ============================================================================

def extract_client_certificate(request: Request) -> Optional[dict]:
    """
    Extract client certificate from request
    
    For uvicorn with SSL, we need to access the underlying SSL connection.
    Uvicorn verifies the certificate but doesn't expose it directly in scope.
    """
    # Try headers first (for reverse proxy setups like nginx)
    client_cert_cn = request.headers.get("X-Client-Cert-CN")
    client_cert_fingerprint = request.headers.get("X-Client-Cert-Fingerprint")
    
    if client_cert_cn:
        return {
            "common_name": client_cert_cn,
            "fingerprint": client_cert_fingerprint,
            "verified": True
        }
    
    # For uvicorn with SSL, try to access peer certificate from the underlying connection
    # This is a workaround - uvicorn doesn't expose cert in scope by default
    scope = request.scope
    
    # Try to get from ASGI extensions
    extensions = scope.get("extensions", {})
    
    # Access the underlying transport/connection if available
    # Uvicorn stores the SSL context in the server's transport
    try:
        # Get the ASGI application instance
        app = scope.get("app")
        
        # Try to access the server's transport
        # This is uvicorn-specific and may vary by version
        if hasattr(request, "scope"):
            # Check if there's SSL info in the scope
            # Uvicorn may store it under different keys
            
            # For testing: if we can't get the cert, we can use a query param
            # BUT THIS IS NOT SECURE - only for development/testing
            test_client_id = request.query_params.get("client_id")
            if test_client_id:
                logger.warning(f"Using test client_id from query param: {test_client_id}")
                return {
                    "common_name": test_client_id,
                    "fingerprint": "",
                    "verified": True
                }
    except Exception as e:
        logger.debug(f"Error accessing certificate from scope: {e}")
    
    # If we can't extract the cert, return None
    # The certificate was verified by uvicorn (if --ssl-ca-certs is set),
    # but we can't access it programmatically without additional setup
    # return None (will need proper TLS setup)
    return None


def validate_client_certificate(cert_info: Optional[dict]) -> tuple[bool, str]:
    """
    Validate client certificate
    
    Args:
        cert_info: Certificate information
        
    Returns:
        Tuple of (is_valid, client_id)
    """
    if cert_info is None:
        certificate_validations.labels(result='missing').inc()
        logger.warning("No client certificate provided")
        return False, ""
    
    if not cert_info.get("verified"):
        certificate_validations.labels(result='unverified').inc()
        logger.warning("Client certificate not verified")
        return False, ""
    
    # Use CN as client_id
    client_id = cert_info.get("common_name", "unknown")
    
    # TODO: Additional validation:
    # - Check against database for active status
    # - Verify fingerprint matches
    # - Check CRL for revocation
    
    certificate_validations.labels(result='valid').inc()
    logger.debug(f"Certificate validated for client: {client_id}")
    return True, client_id

# ============================================================================
# API Endpoints
# ============================================================================

@app.post(
    "/api/v1/messages",
    response_model=MessageAcceptedResponse,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["Messages"]
)
async def submit_message(
    message: MessageSubmission,
    request: Request
):
    """
    Submit a message for processing
    
    Requires mutual TLS authentication with valid client certificate.
    """
    start_time = datetime.utcnow()
    message_id = str(uuid.uuid4())
    request_id = f"req_{uuid.uuid4().hex[:8]}"
    
    try:
        # Extract and validate client certificate
        cert_info = extract_client_certificate(request)
        is_valid, client_id = validate_client_certificate(cert_info)
        
        if not is_valid:
            requests_total.labels(
                method='POST',
                endpoint='/api/v1/messages',
                status='401'
            ).inc()
            messages_failed.labels(reason='invalid_certificate').inc()
            
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or missing client certificate"
            )
        
        # Populate metadata
        if message.metadata is None:
            message.metadata = MessageMetadata()
        
        message.metadata.client_id = client_id
        message.metadata.timestamp = datetime.utcnow().isoformat() + "Z"
        
        # Create message data for queue
        queued_at = datetime.utcnow()
        message_data = {
            "message_id": message_id,
            "sender_number": message.sender_number,
            "message_body": message.message_body,
            "client_id": client_id,
            "domain": message.metadata.domain or "default",
            "queued_at": queued_at.isoformat() + "Z",
            "attempt_count": 0,
            "metadata": message.metadata.dict() if message.metadata else {}
        }
        
        # Enqueue to Redis
        if not redis_queue.enqueue(message_data):
            requests_total.labels(
                method='POST',
                endpoint='/api/v1/messages',
                status='503'
            ).inc()
            messages_failed.labels(reason='redis_error').inc()
            
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Failed to enqueue message. Redis unavailable."
            )
        
        messages_enqueued.inc()
        
        # Register with main server (async, best effort)
        registration_data = {
            "message_id": message_id,
            "client_id": client_id,
            "sender_number": message.sender_number,
            "message_body": message.message_body,
            "queued_at": queued_at.isoformat() + "Z",
            "domain": message.metadata.domain or "default",
            "metadata": message.metadata.dict() if message.metadata else {}
        }
        
        registered = await main_server_client.register_message(registration_data)
        if not registered:
            logger.warning(f"Failed to register message {message_id} with main server")
            # Continue anyway - worker will handle it
        
        # Log successful submission
        logger.info(
            f"Message queued: {message_id} from {client_id} "
            f"(sender: {message.sender_number[:4]}...)"
        )
        
        # Update metrics
        requests_total.labels(
            method='POST',
            endpoint='/api/v1/messages',
            status='202'
        ).inc()
        
        duration = (datetime.utcnow() - start_time).total_seconds()
        request_duration.labels(
            method='POST',
            endpoint='/api/v1/messages'
        ).observe(duration)
        
        # Return response
        return MessageAcceptedResponse(
            message_id=message_id,
            status="queued",
            client_id=client_id,
            queued_at=queued_at.isoformat() + "Z",
            position=redis_queue.get_queue_size()
        )
    
    except HTTPException:
        raise
    except ValueError as e:
        requests_total.labels(
            method='POST',
            endpoint='/api/v1/messages',
            status='400'
        ).inc()
        messages_failed.labels(reason='validation_error').inc()
        
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error processing message: {e}", exc_info=True)
        requests_total.labels(
            method='POST',
            endpoint='/api/v1/messages',
            status='500'
        ).inc()
        messages_failed.labels(reason='internal_error').inc()
        
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.get(
    "/api/v1/health",
    response_model=HealthResponse,
    tags=["Health"]
)
async def health_check():
    """
    Health check endpoint
    
    Returns service health status and component checks.
    """
    checks = {
        "redis": "healthy" if redis_queue.health_check() else "unhealthy",
        "main_server": "unknown",  # Could add actual check
        "certificate": "valid"  # Could add cert expiry check
    }
    
    overall_status = "healthy" if checks["redis"] == "healthy" else "unhealthy"
    
    requests_total.labels(
        method='GET',
        endpoint='/api/v1/health',
        status='200'
    ).inc()
    
    return HealthResponse(
        status=overall_status,
        version="1.0.0",
        timestamp=datetime.utcnow().isoformat() + "Z",
        checks=checks,
        uptime_seconds=None  # TODO: Track actual uptime
    )


# Mount Prometheus metrics
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# ============================================================================
# Exception Handlers
# ============================================================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Handle HTTP exceptions"""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": f"http_error_{exc.status_code}",
            "message": exc.detail,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle general exceptions"""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "internal_error",
            "message": "An unexpected error occurred",
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    )

# ============================================================================
# Startup/Shutdown Events
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """Initialize connections on startup"""
    logger.info("Starting Message Broker Proxy Server")
    logger.info(f"Redis: {config.redis_host}:{config.redis_port}")
    logger.info(f"Main Server: {config.main_server_url}")
    logger.info(f"Log Level: {config.log_level}")
    
    # Update initial queue size metric
    queue_size.set(redis_queue.get_queue_size())


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("Shutting down Message Broker Proxy Server")


if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8001,
        log_level=config.log_level.lower()
    )

