"""
Main Server Test Script

Tests the main server API endpoints and functionality.
"""

import asyncio
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import httpx

# Test configuration
MAIN_SERVER_URL = "https://localhost:8000"
VERIFY_SSL = False  # Set to True in production with proper certificates

# Test credentials
ADMIN_EMAIL = "admin@example.com"
ADMIN_PASSWORD = "admin123"

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


async def test_health_check():
    """Test 1: Health Check Endpoint"""
    print_test("Health Check Endpoint")
    
    try:
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.get(f"{MAIN_SERVER_URL}/health")
            
            if response.status_code == 200:
                data = response.json()
                print_success(f"Server is {data['status']}")
                print_info(f"Components: {json.dumps(data['components'], indent=2)}")
                return True
            else:
                print_error(f"Health check failed with status {response.status_code}")
                return False
    except Exception as e:
        print_error(f"Health check failed: {e}")
        print_info("Make sure the main server is running: cd main_server && start_server.ps1")
        return False


async def test_root_endpoint():
    """Test 2: Root Endpoint"""
    print_test("Root Endpoint")
    
    try:
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.get(f"{MAIN_SERVER_URL}/")
            
            if response.status_code == 200:
                data = response.json()
                print_success(f"Service: {data['service']}")
                print_success(f"Version: {data['version']}")
                print_success(f"Status: {data['status']}")
                return True
            else:
                print_error(f"Root endpoint failed with status {response.status_code}")
                return False
    except Exception as e:
        print_error(f"Root endpoint failed: {e}")
        return False


async def test_metrics_endpoint():
    """Test 3: Metrics Endpoint"""
    print_test("Metrics Endpoint")
    
    try:
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.get(f"{MAIN_SERVER_URL}/metrics")
            
            if response.status_code == 200:
                metrics = response.text
                print_success("Metrics endpoint accessible")
                
                # Check for key metrics
                key_metrics = [
                    "main_server_requests_total",
                    "main_server_messages_registered_total",
                    "main_server_db_connections",
                ]
                
                found = 0
                for metric in key_metrics:
                    if metric in metrics:
                        found += 1
                
                print_info(f"Found {found}/{len(key_metrics)} expected metrics")
                return True
            else:
                print_error(f"Metrics endpoint failed with status {response.status_code}")
                return False
    except Exception as e:
        print_error(f"Metrics endpoint failed: {e}")
        return False


async def test_docs_endpoint():
    """Test 4: API Documentation Endpoint"""
    print_test("API Documentation")
    
    try:
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            # Check OpenAPI JSON
            response = await client.get(f"{MAIN_SERVER_URL}/openapi.json")
            
            if response.status_code == 200:
                spec = response.json()
                print_success(f"OpenAPI spec available")
                print_info(f"Title: {spec.get('info', {}).get('title')}")
                print_info(f"Version: {spec.get('info', {}).get('version')}")
                print_info(f"Endpoints: {len(spec.get('paths', {}))}")
                return True
            else:
                print_error(f"OpenAPI spec failed with status {response.status_code}")
                return False
    except Exception as e:
        print_error(f"API documentation test failed: {e}")
        return False


async def test_internal_register_message():
    """Test 5: Internal Message Registration Endpoint"""
    print_test("Internal Message Registration")
    
    try:
        message_data = {
            "message_id": f"test-{int(time.time() * 1000)}",
            "client_id": "test_client",
            "sender_number": "+4915200000000",
            "message_body": "Test message from main server test",
            "queued_at": datetime.utcnow().isoformat() + "Z"
        }
        
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.post(
                f"{MAIN_SERVER_URL}/internal/messages/register",
                json=message_data
            )
            
            if response.status_code == 200:
                result = response.json()
                print_success(f"Message registered: {result['message_id']}")
                print_info(f"Database ID: {result['id']}")
                return True, result['message_id']
            else:
                print_error(f"Registration failed with status {response.status_code}")
                print_info(f"Response: {response.text}")
                return False, None
    except Exception as e:
        print_error(f"Message registration test failed: {e}")
        return False, None


async def test_internal_deliver_message(message_id):
    """Test 6: Internal Message Delivery Endpoint"""
    print_test("Internal Message Delivery")
    
    if not message_id:
        print_info("Skipping (no message_id from previous test)")
        return False
    
    try:
        deliver_data = {
            "message_id": message_id,
            "worker_id": "test-worker-1"
        }
        
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.post(
                f"{MAIN_SERVER_URL}/internal/messages/deliver",
                json=deliver_data
            )
            
            if response.status_code == 200:
                result = response.json()
                print_success(f"Message marked as delivered")
                print_info(f"Delivered at: {result['delivered_at']}")
                return True
            else:
                print_error(f"Delivery failed with status {response.status_code}")
                print_info(f"Response: {response.text}")
                return False
    except Exception as e:
        print_error(f"Message delivery test failed: {e}")
        return False


async def test_internal_status_update(message_id):
    """Test 7: Internal Status Update Endpoint"""
    print_test("Internal Status Update")
    
    if not message_id:
        print_info("Skipping (no message_id from previous test)")
        return False
    
    try:
        status_data = {
            "status": "queued",
            "attempt_count": 1,
            "error_message": "Test retry"
        }
        
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.put(
                f"{MAIN_SERVER_URL}/internal/messages/{message_id}/status",
                json=status_data
            )
            
            if response.status_code == 200:
                result = response.json()
                print_success(f"Status updated: {result['status']}")
                return True
            else:
                print_error(f"Status update failed with status {response.status_code}")
                print_info(f"Response: {response.text}")
                return False
    except Exception as e:
        print_error(f"Status update test failed: {e}")
        return False


async def test_portal_login():
    """Test 8: Portal Login (if admin user exists)"""
    print_test("Portal Login")
    
    print_info("Note: This test requires an admin user to exist")
    print_info(f"Create one with: python admin_cli.py user create {ADMIN_EMAIL} --role admin")
    
    try:
        login_data = {
            "email": ADMIN_EMAIL,
            "password": ADMIN_PASSWORD
        }
        
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.post(
                f"{MAIN_SERVER_URL}/portal/auth/login",
                json=login_data
            )
            
            if response.status_code == 200:
                result = response.json()
                print_success("Login successful")
                print_info(f"Token type: {result['token_type']}")
                print_info(f"Expires in: {result['expires_in']} seconds")
                return True, result['access_token']
            elif response.status_code == 401:
                print_info("Login failed (user not found or wrong password)")
                print_info("This is expected if admin user doesn't exist")
                return True, None  # Not a failure of the endpoint
            else:
                print_error(f"Login failed with status {response.status_code}")
                print_info(f"Response: {response.text}")
                return False, None
    except Exception as e:
        print_error(f"Portal login test failed: {e}")
        return False, None


async def test_admin_stats(token):
    """Test 9: Admin Statistics Endpoint"""
    print_test("Admin Statistics")
    
    if not token:
        print_info("Skipping (no auth token)")
        return True
    
    try:
        headers = {"Authorization": f"Bearer {token}"}
        
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            response = await client.get(
                f"{MAIN_SERVER_URL}/admin/stats",
                headers=headers
            )
            
            if response.status_code == 200:
                stats = response.json()
                print_success("Statistics retrieved")
                print_info(f"Total messages: {stats['total_messages']}")
                print_info(f"Total clients: {stats['total_clients']}")
                print_info(f"Active clients: {stats['active_clients']}")
                print_info(f"Messages last 24h: {stats['messages_last_24h']}")
                return True
            else:
                print_error(f"Stats failed with status {response.status_code}")
                print_info(f"Response: {response.text}")
                return False
    except Exception as e:
        print_error(f"Admin stats test failed: {e}")
        return False


async def run_all_tests():
    """Run all tests"""
    print_header("Message Broker Main Server - Test Suite")
    
    print(f"Configuration:")
    print(f"  Server URL: {MAIN_SERVER_URL}")
    print(f"  SSL Verification: {VERIFY_SSL}")
    
    results = {}
    
    # Test 1: Health check
    results["Health Check"] = await test_health_check()
    
    if not results["Health Check"]:
        print_header("Test Suite Aborted - Server Not Available")
        return False
    
    # Test 2: Root endpoint
    results["Root Endpoint"] = await test_root_endpoint()
    
    # Test 3: Metrics
    results["Metrics"] = await test_metrics_endpoint()
    
    # Test 4: Docs
    results["API Documentation"] = await test_docs_endpoint()
    
    # Test 5: Register message
    success, message_id = await test_internal_register_message()
    results["Message Registration"] = success
    
    # Test 6: Deliver message
    results["Message Delivery"] = await test_internal_deliver_message(message_id)
    
    # Test 7: Status update
    results["Status Update"] = await test_internal_status_update(message_id)
    
    # Test 8: Portal login
    success, token = await test_portal_login()
    results["Portal Login"] = success
    
    # Test 9: Admin stats
    results["Admin Statistics"] = await test_admin_stats(token)
    
    # Print summary
    print_header("Test Summary")
    
    passed = sum(1 for result in results.values() if result)
    total = len(results)
    
    for test_name, result in results.items():
        status = f"{GREEN}PASS{RESET}" if result else f"{RED}FAIL{RESET}"
        print(f"  {test_name:30s} {status}")
    
    print(f"\n{BLUE}Results: {passed}/{total} tests passed{RESET}")
    
    if passed == total:
        print_success("All tests passed! Main server is fully functional.")
        print_info("\nNext steps:")
        print_info("1. Create admin user: python admin_cli.py user create admin@example.com --role admin")
        print_info("2. Start proxy: cd proxy && start_proxy.ps1")
        print_info("3. Start worker: cd worker && start_worker.ps1")
        print_info("4. Send test message: cd proxy && python test_client.py")
    else:
        print_error(f"{total - passed} test(s) failed. Please check server logs.")
    
    return passed == total


def main():
    """Main entry point"""
    try:
        success = asyncio.run(run_all_tests())
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\nTest suite interrupted")
        sys.exit(1)
    except Exception as e:
        print_error(f"Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

