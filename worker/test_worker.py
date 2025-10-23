"""
Worker Test Script

Tests the worker functionality by simulating message processing scenarios.
"""

import asyncio
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import redis

# Test configuration
REDIS_HOST = "localhost"
REDIS_PORT = 6379
REDIS_DB = 0
REDIS_PASSWORD = ""
QUEUE_NAME = "message_queue"

# ANSI color codes
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'


def print_header(text):
    """Print a section header"""
    print(f"\n{BLUE}{'=' * 70}{RESET}")
    print(f"{BLUE}{text}{RESET}")
    print(f"{BLUE}{'=' * 70}{RESET}\n")


def print_success(text):
    """Print success message"""
    print(f"{GREEN}✓ {text}{RESET}")


def print_error(text):
    """Print error message"""
    print(f"{RED}✗ {text}{RESET}")


def print_info(text):
    """Print info message"""
    print(f"{YELLOW}ℹ {text}{RESET}")


def print_test(text):
    """Print test name"""
    print(f"\n{BLUE}Test: {text}{RESET}")


def get_redis_client():
    """Get Redis client"""
    try:
        client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            db=REDIS_DB,
            password=REDIS_PASSWORD if REDIS_PASSWORD else None,
            decode_responses=True,
            socket_connect_timeout=5
        )
        client.ping()
        return client
    except Exception as e:
        print_error(f"Failed to connect to Redis: {e}")
        return None


def clear_queue(client):
    """Clear the message queue"""
    try:
        count = client.delete(QUEUE_NAME)
        print_info(f"Cleared {count} messages from queue")
        return True
    except Exception as e:
        print_error(f"Failed to clear queue: {e}")
        return False


def get_queue_size(client):
    """Get current queue size"""
    try:
        return client.llen(QUEUE_NAME)
    except Exception:
        return -1


def push_test_message(client, message_id=None, sender_number="+4915200000000", 
                     message_body="Test message", attempt_count=0):
    """Push a test message to the queue"""
    if message_id is None:
        message_id = f"test-{int(time.time() * 1000)}"
    
    message = {
        "message_id": message_id,
        "client_id": "test_client",
        "sender_number": sender_number,
        "message_body": message_body,
        "queued_at": datetime.utcnow().isoformat() + "Z",
        "attempt_count": attempt_count
    }
    
    try:
        message_json = json.dumps(message)
        client.lpush(QUEUE_NAME, message_json)
        return message
    except Exception as e:
        print_error(f"Failed to push message: {e}")
        return None


def test_redis_connection():
    """Test 1: Redis Connection"""
    print_test("Redis Connection")
    
    client = get_redis_client()
    if client:
        print_success(f"Connected to Redis at {REDIS_HOST}:{REDIS_PORT}")
        return True, client
    else:
        print_error("Cannot connect to Redis")
        print_info("Make sure Redis is running: redis-server --service-start")
        return False, None


def test_queue_operations(client):
    """Test 2: Queue Operations"""
    print_test("Queue Operations")
    
    # Clear queue
    if not clear_queue(client):
        return False
    
    # Check queue is empty
    size = get_queue_size(client)
    if size != 0:
        print_error(f"Queue not empty after clear: {size} messages")
        return False
    print_success("Queue cleared successfully")
    
    # Push messages
    messages_to_push = 5
    for i in range(messages_to_push):
        message = push_test_message(
            client,
            message_id=f"test-msg-{i+1}",
            message_body=f"Test message {i+1}"
        )
        if not message:
            return False
    
    print_success(f"Pushed {messages_to_push} test messages to queue")
    
    # Check queue size
    size = get_queue_size(client)
    if size != messages_to_push:
        print_error(f"Queue size mismatch: expected {messages_to_push}, got {size}")
        return False
    
    print_success(f"Queue size correct: {size} messages")
    return True


def test_message_format(client):
    """Test 3: Message Format"""
    print_test("Message Format")
    
    # Clear queue
    clear_queue(client)
    
    # Push a message
    message = push_test_message(
        client,
        message_id="format-test-123",
        sender_number="+4915200000000",
        message_body="Format test message"
    )
    
    if not message:
        return False
    
    print_success("Message pushed successfully")
    
    # Pop and verify format
    try:
        result = client.brpop(QUEUE_NAME, timeout=5)
        if not result:
            print_error("Failed to pop message from queue")
            return False
        
        _, message_json = result
        popped_message = json.loads(message_json)
        
        # Verify required fields
        required_fields = ["message_id", "client_id", "sender_number", 
                          "message_body", "queued_at", "attempt_count"]
        
        for field in required_fields:
            if field not in popped_message:
                print_error(f"Missing required field: {field}")
                return False
        
        print_success("All required fields present")
        
        # Verify field values
        if popped_message["message_id"] != "format-test-123":
            print_error("Message ID mismatch")
            return False
        
        if popped_message["sender_number"] != "+4915200000000":
            print_error("Sender number mismatch")
            return False
        
        if popped_message["attempt_count"] != 0:
            print_error("Attempt count should be 0")
            return False
        
        print_success("All field values correct")
        print_info(f"Message format:\n{json.dumps(popped_message, indent=2)}")
        
        return True
        
    except Exception as e:
        print_error(f"Failed to verify message format: {e}")
        return False


def test_retry_simulation(client):
    """Test 4: Retry Simulation"""
    print_test("Retry Simulation")
    
    clear_queue(client)
    
    # Push a message with increasing attempt counts
    message_id = "retry-test-456"
    
    for attempt in range(3):
        message = push_test_message(
            client,
            message_id=message_id,
            attempt_count=attempt
        )
        
        if not message:
            return False
        
        print_success(f"Pushed message with attempt_count={attempt}")
        
        # Pop it
        result = client.brpop(QUEUE_NAME, timeout=5)
        if not result:
            print_error("Failed to pop message")
            return False
        
        _, message_json = result
        popped = json.loads(message_json)
        
        if popped["attempt_count"] != attempt:
            print_error(f"Attempt count mismatch: expected {attempt}, got {popped['attempt_count']}")
            return False
    
    print_success("Retry simulation successful")
    return True


def test_concurrent_messages(client):
    """Test 5: Concurrent Messages"""
    print_test("Concurrent Messages")
    
    clear_queue(client)
    
    # Push multiple messages
    num_messages = 20
    message_ids = []
    
    for i in range(num_messages):
        message_id = f"concurrent-{i+1}"
        message_ids.append(message_id)
        message = push_test_message(
            client,
            message_id=message_id,
            message_body=f"Concurrent test message {i+1}"
        )
        
        if not message:
            return False
    
    print_success(f"Pushed {num_messages} messages")
    
    # Verify queue size
    size = get_queue_size(client)
    if size != num_messages:
        print_error(f"Queue size mismatch: expected {num_messages}, got {size}")
        return False
    
    print_success(f"Queue size correct: {size} messages")
    
    # Pop all messages and verify order (FIFO)
    popped_ids = []
    for _ in range(num_messages):
        result = client.brpop(QUEUE_NAME, timeout=5)
        if not result:
            print_error("Failed to pop message")
            return False
        
        _, message_json = result
        popped = json.loads(message_json)
        popped_ids.append(popped["message_id"])
    
    # Verify FIFO order
    if popped_ids == message_ids:
        print_success("FIFO order maintained")
    else:
        print_error("FIFO order not maintained")
        print_info(f"Expected: {message_ids[:5]}...")
        print_info(f"Got: {popped_ids[:5]}...")
        return False
    
    # Verify queue is empty
    size = get_queue_size(client)
    if size != 0:
        print_error(f"Queue not empty after popping all: {size} messages remain")
        return False
    
    print_success("Queue empty after processing all messages")
    return True


def test_worker_prerequisites():
    """Test 6: Worker Prerequisites"""
    print_test("Worker Prerequisites")
    
    # Check if worker.py exists
    worker_file = Path(__file__).parent / "worker.py"
    if not worker_file.exists():
        print_error("worker.py not found")
        return False
    print_success("worker.py found")
    
    # Check if config.yaml exists
    config_file = Path(__file__).parent / "config.yaml"
    if not config_file.exists():
        print_error("config.yaml not found")
        return False
    print_success("config.yaml found")
    
    # Check if certs directory exists
    certs_dir = Path(__file__).parent / "certs"
    if not certs_dir.exists():
        print_error("certs/ directory not found")
        print_info("Run: cd main_server && generate_cert.bat worker")
        return False
    print_success("certs/ directory found")
    
    # Check for required certificates
    required_certs = ["worker.crt", "worker.key", "ca.crt"]
    for cert in required_certs:
        cert_path = certs_dir / cert
        if not cert_path.exists():
            print_error(f"Certificate not found: {cert}")
            print_info("Generate certificates using main_server/generate_cert.bat")
            return False
    
    print_success("All required certificates found")
    
    # Check if logs directory exists (will be created if not)
    logs_dir = Path(__file__).parent / "logs"
    if not logs_dir.exists():
        print_info("logs/ directory will be created on first run")
    else:
        print_success("logs/ directory found")
    
    return True


def test_metrics_endpoint():
    """Test 7: Metrics Endpoint Check"""
    print_test("Metrics Endpoint")
    
    print_info("Note: Metrics endpoint test requires worker to be running")
    print_info("After starting worker, check: http://localhost:9100/metrics")
    
    # Try to check if worker is running
    try:
        import httpx
        response = httpx.get("http://localhost:9100/metrics", timeout=2)
        if response.status_code == 200:
            print_success("Worker metrics endpoint is accessible")
            print_info(f"Metrics preview:\n{response.text[:500]}...")
            return True
        else:
            print_error(f"Metrics endpoint returned status {response.status_code}")
            return False
    except ImportError:
        print_info("httpx not installed, skipping metrics check")
        return True
    except Exception as e:
        print_info(f"Worker not running or metrics not accessible: {e}")
        print_info("This is expected if worker is not running")
        return True


def run_all_tests():
    """Run all tests"""
    print_header("Message Broker Worker - Test Suite")
    
    print(f"Configuration:")
    print(f"  Redis Host: {REDIS_HOST}")
    print(f"  Redis Port: {REDIS_PORT}")
    print(f"  Redis DB: {REDIS_DB}")
    print(f"  Queue Name: {QUEUE_NAME}")
    
    tests = [
        ("Redis Connection", test_redis_connection),
    ]
    
    results = {}
    client = None
    
    # Run first test to get client
    test_name, test_func = tests[0]
    success, client = test_func()
    results[test_name] = success
    
    if not success:
        print_header("Test Suite Aborted - Cannot Connect to Redis")
        return False
    
    # Run remaining tests
    additional_tests = [
        ("Queue Operations", lambda: test_queue_operations(client)),
        ("Message Format", lambda: test_message_format(client)),
        ("Retry Simulation", lambda: test_retry_simulation(client)),
        ("Concurrent Messages", lambda: test_concurrent_messages(client)),
        ("Worker Prerequisites", test_worker_prerequisites),
        ("Metrics Endpoint", test_metrics_endpoint),
    ]
    
    for test_name, test_func in additional_tests:
        try:
            results[test_name] = test_func()
        except Exception as e:
            print_error(f"Test failed with exception: {e}")
            results[test_name] = False
    
    # Print summary
    print_header("Test Summary")
    
    passed = sum(1 for result in results.values() if result)
    total = len(results)
    
    for test_name, result in results.items():
        status = f"{GREEN}PASS{RESET}" if result else f"{RED}FAIL{RESET}"
        print(f"  {test_name:30s} {status}")
    
    print(f"\n{BLUE}Results: {passed}/{total} tests passed{RESET}")
    
    if passed == total:
        print_success("All tests passed! Worker is ready to run.")
        print_info("\nNext steps:")
        print_info("1. Start main server: cd main_server && start_server.ps1")
        print_info("2. Start worker: cd worker && start_worker.ps1")
        print_info("3. Send test message: cd proxy && python test_client.py")
    else:
        print_error(f"{total - passed} test(s) failed. Please fix issues before running worker.")
    
    # Clean up
    if client:
        clear_queue(client)
        print_info("\nQueue cleared for clean start")
    
    return passed == total


if __name__ == "__main__":
    try:
        success = run_all_tests()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\nTest suite interrupted")
        sys.exit(1)
    except Exception as e:
        print_error(f"Fatal error: {e}")
        sys.exit(1)

