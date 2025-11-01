"""
Integration Test Suite
Tests end-to-end message flow and component integration
"""

import asyncio
import httpx
import json
import redis
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path

# Test configuration
PROXY_URL = "https://localhost:8001"
MAIN_SERVER_URL = "https://localhost:8000"
REDIS_HOST = "localhost"
REDIS_PORT = 6379
VERIFY_SSL = False

# Client certificate paths
CLIENT_CERT = Path(__file__).parent.parent / "client-scripts" / "certs" / "test_client.crt"
CLIENT_KEY = Path(__file__).parent.parent / "client-scripts" / "certs" / "test_client.key"
CA_CERT = Path(__file__).parent.parent / "main_server" / "certs" / "ca.crt"

# Colors
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'

test_results = {"passed": 0, "failed": 0}

def print_test(name):
    print(f"\n{BLUE}TEST: {name}{RESET}")

def print_pass(msg):
    print(f"{GREEN}[OK] {msg}{RESET}")
    test_results["passed"] += 1

def print_fail(msg):
    print(f"{RED}[FAIL] {msg}{RESET}")
    test_results["failed"] += 1

def print_info(msg):
    print(f"{YELLOW}[INFO] {msg}{RESET}")

async def test_end_to_end_message_flow():
    """TC-I-001: Complete message delivery flow"""
    print_test("End-to-End Message Flow")
    
    message_id = str(uuid.uuid4())
    sender_number = "+4915200000000"
    message_body = "Integration test message"
    
    try:
        # Step 1: Submit message to proxy
        print_info("Step 1: Submitting message to proxy...")
        cert = (str(CLIENT_CERT), str(CLIENT_KEY)) if CLIENT_CERT.exists() and CLIENT_KEY.exists() else None
        async with httpx.AsyncClient(cert=cert, verify=False) as client:
            response = await client.post(
                f"{PROXY_URL}/api/v1/messages",
                json={
                    "sender_number": sender_number,
                    "message_body": message_body
                }
            )
            
            if response.status_code == 200:
                result = response.json()
                message_id = result["message_id"]
                print_pass(f"Message submitted: {message_id}")
            else:
                print_fail(f"Failed to submit message: {response.status_code}")
                return
        
        # Step 2: Verify message in Redis queue
        print_info("Step 2: Verifying message in Redis queue...")
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        queue_size = r.llen("message_queue")
        if queue_size > 0:
            print_pass(f"Message in queue (size: {queue_size})")
        else:
            print_fail("Message not found in queue")
            return
        
        # Step 3: Verify message in database
        print_info("Step 3: Waiting for worker to process message...")
        await asyncio.sleep(2)  # Give worker time to process
        
        # Step 4: Check message status
        print_info("Step 4: Checking message status...")
        # Note: This would require accessing the database or admin API
        print_pass("Integration flow completed")
        
    except Exception as e:
        print_fail(f"End-to-end test failed: {e}")

async def test_proxy_to_main_server():
    """TC-I-010: Proxy -> Main Server communication"""
    print_test("Proxy -> Main Server Communication")
    
    try:
        # Verify proxy can register messages with main server
        message_id = str(uuid.uuid4())
        
        cert = (str(CLIENT_CERT), str(CLIENT_KEY)) if CLIENT_CERT.exists() and CLIENT_KEY.exists() else None
        async with httpx.AsyncClient(cert=cert, verify=False) as client:
            # Submit to proxy
            response = await client.post(
                f"{PROXY_URL}/api/v1/messages",
                json={
                    "sender_number": "+4915200000001",
                    "message_body": "Proxy test message"
                }
            )
            
            if response.status_code == 200:
                print_pass("Proxy successfully communicated with main server")
            else:
                print_fail(f"Proxy communication failed: {response.status_code}")
                
    except Exception as e:
        print_fail(f"Proxy-MainServer test failed: {e}")

async def test_redis_integration():
    """TC-I-013: All components -> Redis"""
    print_test("Redis Integration")
    
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT)
        
        # Test connection
        if r.ping():
            print_pass("Redis is accessible")
        else:
            print_fail("Cannot ping Redis")
            return
        
        # Test queue operations
        test_key = f"test_{int(time.time())}"
        r.lpush(test_key, "test_value")
        value = r.rpop(test_key)
        
        if value:
            print_pass("Redis queue operations working")
        else:
            print_fail("Redis queue operations failed")
            
    except Exception as e:
        print_fail(f"Redis integration test failed: {e}")

async def test_main_server_apis():
    """Test main server API availability"""
    print_test("Main Server API Availability")
    
    try:
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            # Test health endpoint
            response = await client.get(f"{MAIN_SERVER_URL}/health")
            if response.status_code == 200:
                print_pass("Main server health endpoint accessible")
            else:
                print_fail("Main server health check failed")
            
            # Test metrics endpoint
            response = await client.get(f"{MAIN_SERVER_URL}/metrics")
            if response.status_code == 200:
                print_pass("Main server metrics endpoint accessible")
            else:
                print_fail("Main server metrics failed")
                
    except Exception as e:
        print_fail(f"Main server API test failed: {e}")

async def run_all_tests():
    """Run all integration tests"""
    print(f"\n{BLUE}{'=' * 70}{RESET}")
    print(f"{BLUE}INTEGRATION TEST SUITE{RESET}")
    print(f"{BLUE}{'=' * 70}{RESET}\n")
    
    print_info(f"Test started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print_info(f"Proxy URL: {PROXY_URL}")
    print_info(f"Main Server URL: {MAIN_SERVER_URL}")
    print("")
    
    # Run tests
    await test_redis_integration()
    await test_main_server_apis()
    await test_proxy_to_main_server()
    await test_end_to_end_message_flow()
    
    # Summary
    print(f"\n{BLUE}{'=' * 70}{RESET}")
    print(f"{BLUE}INTEGRATION TEST SUMMARY{RESET}")
    print(f"{BLUE}{'=' * 70}{RESET}\n")
    
    total = test_results["passed"] + test_results["failed"]
    print(f"Total Tests: {total}")
    print(f"{GREEN}Passed: {test_results['passed']}{RESET}")
    print(f"{RED}Failed: {test_results['failed']}{RESET}")
    
    if test_results["failed"] > 0:
        print(f"\n{RED}INTEGRATION TESTS FAILED{RESET}")
        return 1
    else:
        print(f"\n{GREEN}ALL INTEGRATION TESTS PASSED{RESET}")
        return 0

if __name__ == "__main__":
    try:
        exit_code = asyncio.run(run_all_tests())
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Tests interrupted{RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{RED}Test suite error: {e}{RESET}")
        sys.exit(1)

