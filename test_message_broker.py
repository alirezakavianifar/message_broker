#!/usr/bin/env python3
"""
Comprehensive Message Broker Test Script
Tests all components and message flow end-to-end
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any

import httpx
import redis

# Add project root to path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

# Configuration
PROXY_URL = "https://localhost:8001"
MAIN_SERVER_URL = "https://localhost:8000"
PORTAL_URL = "http://localhost:5000"
REDIS_HOST = "localhost"
REDIS_PORT = 6379

# Colors for output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_header(text: str):
    print(f"\n{Colors.CYAN}{'='*70}{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}{text}{Colors.RESET}")
    print(f"{Colors.CYAN}{'='*70}{Colors.RESET}\n")

def print_test(text: str):
    print(f"{Colors.BLUE}[TEST] {text}...{Colors.RESET}")

def print_pass(text: str):
    print(f"{Colors.GREEN}[PASS] {text}{Colors.RESET}")

def print_fail(text: str):
    print(f"{Colors.RED}[FAIL] {text}{Colors.RESET}")

def print_warn(text: str):
    print(f"{Colors.YELLOW}[WARN] {text}{Colors.RESET}")

def print_info(text: str):
    print(f"{Colors.YELLOW}[INFO] {text}{Colors.RESET}")

# Test results tracking
test_results = {
    "passed": 0,
    "failed": 0,
    "warnings": 0
}

def test_service_health(name: str, url: str, verify: bool = False) -> bool:
    """Test if a service health endpoint is responding"""
    print_test(f"Checking {name} health")
    try:
        with httpx.Client(verify=verify, timeout=5.0) as client:
            response = client.get(url)
            if response.status_code == 200:
                print_pass(f"{name} is healthy")
                test_results["passed"] += 1
                return True
            else:
                print_fail(f"{name} returned status {response.status_code}")
                test_results["failed"] += 1
                return False
    except Exception as e:
        print_fail(f"{name} is not responding: {str(e)}")
        test_results["failed"] += 1
        return False

def test_redis_connection() -> bool:
    """Test Redis connection and basic operations"""
    print_test("Testing Redis connection")
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        if r.ping():
            queue_size = r.llen("message_queue")
            print_pass(f"Redis is connected (queue size: {queue_size})")
            test_results["passed"] += 1
            return True
        else:
            print_fail("Redis ping failed")
            test_results["failed"] += 1
            return False
    except Exception as e:
        print_fail(f"Redis connection failed: {str(e)}")
        test_results["failed"] += 1
        return False

def check_certificates() -> Optional[Dict[str, str]]:
    """Check if test certificates exist"""
    certs_dir = project_root / "client-scripts" / "certs"
    ca_cert = certs_dir / "ca.crt"
    client_cert = certs_dir / "test_client.crt"
    client_key = certs_dir / "test_client.key"
    
    if all([ca_cert.exists(), client_cert.exists(), client_key.exists()]):
        print_pass("Test certificates found")
        return {
            "cert": str(client_cert),
            "key": str(client_key),
            "ca": str(ca_cert)
        }
    else:
        print_warn("Test certificates not found")
        print_info("You can generate certificates using:")
        print_info("  cd main_server && .\\generate_cert.bat test_client")
        print_info("Then copy files to client-scripts/certs/")
        test_results["warnings"] += 1
        return None

def send_message_with_cert(certs: Dict[str, str], sender: str, message: str) -> Optional[Dict]:
    """Send a message via proxy with client certificate"""
    print_test(f"Sending message via proxy (with mTLS)")
    
    try:
        with httpx.Client(
            cert=(certs["cert"], certs["key"]),
            verify=certs["ca"],
            timeout=30.0
        ) as client:
            payload = {
                "sender_number": sender,
                "message_body": message,
                "metadata": {
                    "client_id": "test_client",
                    "timestamp": datetime.utcnow().isoformat(),
                    "test": True
                }
            }
            
            response = client.post(
                f"{PROXY_URL}/api/v1/messages",
                json=payload,
                headers={"Content-Type": "application/json"}
            )
            
            if response.status_code == 202:
                result = response.json()
                print_pass(f"Message sent successfully: {result.get('message_id', 'N/A')}")
                test_results["passed"] += 1
                return result
            else:
                print_fail(f"Message send failed: {response.status_code} - {response.text}")
                test_results["failed"] += 1
                return None
                
    except Exception as e:
        print_fail(f"Failed to send message: {str(e)}")
        test_results["failed"] += 1
        return None

def send_message_direct(sender: str, message: str) -> Optional[Dict]:
    """Send message directly to main server internal API (for testing without certs)"""
    print_test("Sending message via main server internal API")
    print_warn("This bypasses proxy and mTLS - for testing only!")
    
    try:
        message_id = f"test_{int(time.time())}"
        payload = {
            "message_id": message_id,
            "sender_number": sender,
            "message_body": message,
            "client_id": "test_client",
            "domain": "test",
            "queued_at": datetime.utcnow().isoformat() + "Z"
        }
        
        with httpx.Client(verify=False, timeout=10.0) as client:
            response = client.post(
                f"{MAIN_SERVER_URL}/internal/messages/register",
                json=payload,
                headers={"Content-Type": "application/json"}
            )
            
            if response.status_code == 200:
                result = response.json()
                print_pass(f"Message registered: {message_id}")
                test_results["passed"] += 1
                return result
            else:
                print_fail(f"Registration failed: {response.status_code} - {response.text}")
                test_results["failed"] += 1
                return None
                
    except Exception as e:
        print_fail(f"Failed to register message: {str(e)}")
        test_results["failed"] += 1
        return None

def check_message_in_queue(message_id: Optional[str] = None) -> bool:
    """Check if message is in Redis queue"""
    print_test("Checking message in Redis queue")
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        queue_size = r.llen("message_queue")
        if queue_size > 0:
            print_pass(f"Queue has {queue_size} message(s)")
            test_results["passed"] += 1
            return True
        else:
            print_warn("Queue is empty (worker may have processed it)")
            test_results["warnings"] += 1
            return False
    except Exception as e:
        print_fail(f"Failed to check queue: {str(e)}")
        test_results["failed"] += 1
        return False

def check_portal_accessible() -> bool:
    """Check if portal is accessible"""
    print_test("Checking portal accessibility")
    try:
        with httpx.Client(timeout=5.0) as client:
            response = client.get(PORTAL_URL)
            if response.status_code == 200:
                print_pass("Portal is accessible")
                test_results["passed"] += 1
                return True
            else:
                print_warn(f"Portal returned status {response.status_code}")
                test_results["warnings"] += 1
                return False
    except Exception as e:
        print_fail(f"Portal not accessible: {str(e)}")
        test_results["failed"] += 1
        return False

def get_main_server_stats() -> Optional[Dict]:
    """Get statistics from main server"""
    print_test("Fetching system statistics")
    try:
        with httpx.Client(verify=False, timeout=5.0) as client:
            response = client.get(f"{MAIN_SERVER_URL}/admin/stats")
            if response.status_code == 200:
                stats = response.json()
                print_pass("Statistics retrieved")
                print_info(f"Total messages: {stats.get('total_messages', 0)}")
                print_info(f"Messages last 24h: {stats.get('messages_last_24h', 0)}")
                test_results["passed"] += 1
                return stats
            else:
                print_warn(f"Stats endpoint returned {response.status_code}")
                test_results["warnings"] += 1
                return None
    except Exception as e:
        print_warn(f"Could not fetch stats: {str(e)}")
        test_results["warnings"] += 1
        return None

def main():
    parser = argparse.ArgumentParser(description="Test Message Broker System")
    parser.add_argument("--sender", default="+1234567890", help="Test sender phone number")
    parser.add_argument("--message", default="Test message from automated test", help="Test message body")
    parser.add_argument("--skip-cert", action="store_true", help="Skip certificate-based tests")
    parser.add_argument("--direct", action="store_true", help="Use direct main server API (bypasses proxy)")
    
    args = parser.parse_args()
    
    print_header("MESSAGE BROKER SYSTEM TEST")
    print_info(f"Test started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print_info(f"Proxy: {PROXY_URL}")
    print_info(f"Main Server: {MAIN_SERVER_URL}")
    print_info(f"Portal: {PORTAL_URL}\n")
    
    # Phase 1: Service Health Checks
    print_header("PHASE 1: SERVICE HEALTH CHECKS")
    
    health_main = test_service_health("Main Server", f"{MAIN_SERVER_URL}/health", verify=False)
    health_proxy = test_service_health("Proxy Server", f"{PROXY_URL}/api/v1/health", verify=False)
    health_portal = check_portal_accessible()
    redis_ok = test_redis_connection()
    
    if not all([health_main, health_proxy, redis_ok]):
        print_fail("\nBasic services are not healthy. Please check service status.")
        print_info("Run: .\\start_all_services.ps1 -Silent")
        return 1
    
    # Phase 2: Certificate Check
    print_header("PHASE 2: CERTIFICATE CHECK")
    certs = None
    if not args.skip_cert:
        certs = check_certificates()
    
    # Phase 3: Message Sending
    print_header("PHASE 3: MESSAGE SENDING TEST")
    
    message_result = None
    if args.direct:
        # Direct registration via main server
        message_result = send_message_direct(args.sender, args.message)
    elif certs:
        # Full flow via proxy with certificates
        message_result = send_message_with_cert(certs, args.sender, args.message)
    else:
        print_warn("Skipping message send test (no certificates available)")
        print_info("Use --direct to test via main server API")
        print_info("Or generate certificates and run again")
    
    if message_result:
        message_id = message_result.get("message_id") or message_result.get("id")
        print_info(f"Message ID: {message_id}")
    
    # Phase 4: Queue Verification
    print_header("PHASE 4: QUEUE VERIFICATION")
    if message_result:
        time.sleep(2)  # Give proxy time to enqueue
        check_message_in_queue()
    
    # Phase 5: Worker Processing Check
    print_header("PHASE 5: WORKER PROCESSING")
    print_info("Waiting 5 seconds for worker to process message...")
    time.sleep(5)
    
    # Check queue again (should be empty or smaller)
    print_test("Re-checking queue after processing")
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        queue_size = r.llen("message_queue")
        if queue_size == 0:
            print_pass("Queue is empty - worker processed messages")
        else:
            print_warn(f"Queue still has {queue_size} message(s)")
    except Exception as e:
        print_warn(f"Could not re-check queue: {str(e)}")
    
    # Phase 6: System Statistics
    print_header("PHASE 6: SYSTEM STATISTICS")
    stats = get_main_server_stats()
    
    # Final Summary
    print_header("TEST SUMMARY")
    
    total = test_results["passed"] + test_results["failed"] + test_results["warnings"]
    print(f"{Colors.GREEN}Passed: {test_results['passed']}{Colors.RESET}")
    print(f"{Colors.YELLOW}Warnings: {test_results['warnings']}{Colors.RESET}")
    print(f"{Colors.RED}Failed: {test_results['failed']}{Colors.RESET}")
    print(f"\nTotal Checks: {total}")
    
    if test_results["failed"] == 0:
        print(f"\n{Colors.GREEN}{Colors.BOLD}[SUCCESS] ALL CRITICAL TESTS PASSED{Colors.RESET}")
        print(f"\n{Colors.CYAN}Next Steps:{Colors.RESET}")
        print("1. View messages in portal: http://localhost:5000")
        print("2. Check logs: Get-Content logs\\*.log -Tail 50")
        print("3. Monitor metrics: https://localhost:8000/metrics")
        return 0
    else:
        print(f"\n{Colors.RED}{Colors.BOLD}[FAILURE] SOME TESTS FAILED{Colors.RESET}")
        return 1

if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Test interrupted by user{Colors.RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.RED}Test suite error: {e}{Colors.RESET}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

