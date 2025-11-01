"""
Load Test Suite
Tests system performance under load (~100k messages/day target)
"""

import asyncio
import httpx
import json
import redis
import sys
import time
import uuid
from datetime import datetime, timedelta
from typing import List

# Test configuration
PROXY_URL = "https://localhost:8001"
REDIS_HOST = "localhost"
REDIS_PORT = 6379
VERIFY_SSL = False

# Load test parameters
TARGET_DAILY = 100000  # 100k messages per day
TARGET_PER_SECOND = TARGET_DAILY / (24 * 3600)  # ~1.16 msg/sec
BURST_RATE = 100  # messages per second for burst test
TEST_DURATION_SUSTAINED = 60  # seconds for sustained test
TEST_DURATION_BURST = 30  # seconds for burst test

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

class LoadTestMetrics:
    """Track load test metrics"""
    def __init__(self):
        self.total_sent = 0
        self.total_success = 0
        self.total_failed = 0
        self.response_times = []
        self.start_time = None
        self.end_time = None
    
    def record_request(self, success: bool, response_time: float):
        self.total_sent += 1
        if success:
            self.total_success += 1
        else:
            self.total_failed += 1
        self.response_times.append(response_time)
    
    def get_summary(self):
        if not self.response_times:
            return {}
        
        duration = (self.end_time - self.start_time).total_seconds()
        throughput = self.total_success / duration if duration > 0 else 0
        
        sorted_times = sorted(self.response_times)
        return {
            "total_sent": self.total_sent,
            "total_success": self.total_success,
            "total_failed": self.total_failed,
            "duration_seconds": round(duration, 2),
            "throughput_msg_per_sec": round(throughput, 2),
            "avg_response_time": round(sum(self.response_times) / len(self.response_times), 3),
            "min_response_time": round(min(self.response_times), 3),
            "max_response_time": round(max(self.response_times), 3),
            "p50_response_time": round(sorted_times[len(sorted_times)//2], 3),
            "p95_response_time": round(sorted_times[int(len(sorted_times)*0.95)], 3),
            "p99_response_time": round(sorted_times[int(len(sorted_times)*0.99)], 3),
        }

async def send_message(client: httpx.AsyncClient, message_num: int) -> tuple:
    """Send a single message"""
    start_time = time.time()
    try:
        response = await client.post(
            f"{PROXY_URL}/api/v1/messages",
            json={
                "sender_number": f"+49152{str(message_num).zfill(8)}",
                "message_body": f"Load test message {message_num}"
            },
            headers={"X-Client-ID": "load_test_client"},
            timeout=30.0
        )
        response_time = time.time() - start_time
        return (response.status_code == 200, response_time)
    except Exception as e:
        response_time = time.time() - start_time
        return (False, response_time)

async def test_sustained_load():
    """TC-L-001: Sustained load test (1-2 msg/sec)"""
    print_test(f"Sustained Load Test ({TARGET_PER_SECOND:.2f} msg/sec for {TEST_DURATION_SUSTAINED}s)")
    
    metrics = LoadTestMetrics()
    metrics.start_time = datetime.now()
    
    target_count = int(TARGET_PER_SECOND * TEST_DURATION_SUSTAINED)
    interval = 1.0 / TARGET_PER_SECOND
    
    print_info(f"Target: {target_count} messages in {TEST_DURATION_SUSTAINED} seconds")
    print_info(f"Rate: {TARGET_PER_SECOND:.2f} messages/second")
    print_info("Sending messages...")
    
    async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
        for i in range(target_count):
            success, response_time = await send_message(client, i)
            metrics.record_request(success, response_time)
            
            # Progress indicator
            if (i + 1) % 10 == 0:
                print(f"  Sent: {i+1}/{target_count} ({metrics.total_success} success, {metrics.total_failed} failed)", end='\r')
            
            # Rate limiting
            await asyncio.sleep(interval)
    
    print()  # New line after progress
    metrics.end_time = datetime.now()
    
    # Results
    summary = metrics.get_summary()
    print_info(f"Results:")
    print_info(f"  Total: {summary['total_sent']}")
    print_info(f"  Success: {summary['total_success']}")
    print_info(f"  Failed: {summary['total_failed']}")
    print_info(f"  Duration: {summary['duration_seconds']}s")
    print_info(f"  Throughput: {summary['throughput_msg_per_sec']:.2f} msg/s")
    print_info(f"  Avg Response: {summary['avg_response_time']}s")
    print_info(f"  P95 Response: {summary['p95_response_time']}s")
    
    # Check success criteria
    success_rate = metrics.total_success / metrics.total_sent if metrics.total_sent > 0 else 0
    
    if success_rate >= 0.95:  # 95% success rate
        print_pass(f"Sustained load test passed (success rate: {success_rate*100:.1f}%)")
    else:
        print_fail(f"Sustained load test failed (success rate: {success_rate*100:.1f}%)")

async def test_burst_load():
    """TC-L-003: Burst load test (100 msg/sec for short duration)"""
    print_test(f"Burst Load Test ({BURST_RATE} msg/sec for {TEST_DURATION_BURST}s)")
    
    metrics = LoadTestMetrics()
    metrics.start_time = datetime.now()
    
    target_count = BURST_RATE * TEST_DURATION_BURST
    
    print_info(f"Target: {target_count} messages in {TEST_DURATION_BURST} seconds")
    print_info(f"Rate: {BURST_RATE} messages/second")
    print_info("Sending messages...")
    
    async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
        tasks = []
        for i in range(target_count):
            task = send_message(client, i + 10000)
            tasks.append(task)
            
            # Send in batches
            if len(tasks) >= BURST_RATE:
                results = await asyncio.gather(*tasks)
                for success, response_time in results:
                    metrics.record_request(success, response_time)
                
                print(f"  Sent: {metrics.total_sent}/{target_count} ({metrics.total_success} success)", end='\r')
                tasks = []
                await asyncio.sleep(1.0)  # One batch per second
        
        # Send remaining
        if tasks:
            results = await asyncio.gather(*tasks)
            for success, response_time in results:
                metrics.record_request(success, response_time)
    
    print()  # New line
    metrics.end_time = datetime.now()
    
    # Results
    summary = metrics.get_summary()
    print_info(f"Results:")
    print_info(f"  Total: {summary['total_sent']}")
    print_info(f"  Success: {summary['total_success']}")
    print_info(f"  Failed: {summary['total_failed']}")
    print_info(f"  Duration: {summary['duration_seconds']}s")
    print_info(f"  Throughput: {summary['throughput_msg_per_sec']:.2f} msg/s")
    print_info(f"  Max Response: {summary['max_response_time']}s")
    print_info(f"  P99 Response: {summary['p99_response_time']}s")
    
    # Check success criteria
    success_rate = metrics.total_success / metrics.total_sent if metrics.total_sent > 0 else 0
    
    if success_rate >= 0.90:  # 90% success rate for burst (more lenient)
        print_pass(f"Burst load test passed (success rate: {success_rate*100:.1f}%)")
    else:
        print_fail(f"Burst load test failed (success rate: {success_rate*100:.1f}%)")

async def test_queue_under_load():
    """TC-L-005: Queue growth under load"""
    print_test("Queue Management Under Load")
    
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT)
        
        # Check queue size before
        size_before = r.llen("message_queue")
        print_info(f"Queue size before: {size_before}")
        
        # Send some messages quickly
        async with httpx.AsyncClient(verify=VERIFY_SSL) as client:
            tasks = [send_message(client, i + 20000) for i in range(50)]
            await asyncio.gather(*tasks)
        
        # Check queue size after
        await asyncio.sleep(1)
        size_after = r.llen("message_queue")
        print_info(f"Queue size after: {size_after}")
        
        # Queue should grow but not excessively
        if size_after >= size_before:
            print_pass("Queue is accepting messages under load")
        else:
            print_fail("Queue size issues detected")
            
    except Exception as e:
        print_fail(f"Queue test failed: {e}")

async def run_all_tests():
    """Run all load tests"""
    print(f"\n{BLUE}{'=' * 70}{RESET}")
    print(f"{BLUE}LOAD TEST SUITE{RESET}")
    print(f"{BLUE}{'=' * 70}{RESET}\n")
    
    print_info(f"Test started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print_info(f"Target: {TARGET_DAILY:,} messages/day ({TARGET_PER_SECOND:.2f} msg/sec)")
    print_info(f"Proxy URL: {PROXY_URL}")
    print("")
    
    # Run tests
    await test_queue_under_load()
    await test_sustained_load()
    await test_burst_load()
    
    # Summary
    print(f"\n{BLUE}{'=' * 70}{RESET}")
    print(f"{BLUE}LOAD TEST SUMMARY{RESET}")
    print(f"{BLUE}{'=' * 70}{RESET}\n")
    
    total = test_results["passed"] + test_results["failed"]
    print(f"Total Tests: {total}")
    print(f"{GREEN}Passed: {test_results['passed']}{RESET}")
    print(f"{RED}Failed: {test_results['failed']}{RESET}")
    
    if test_results["failed"] > 0:
        print(f"\n{RED}LOAD TESTS FAILED{RESET}")
        return 1
    else:
        print(f"\n{GREEN}ALL LOAD TESTS PASSED{RESET}")
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

