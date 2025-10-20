#!/usr/bin/env python3
"""
Test Client for Message Broker Proxy

Sends test messages to the proxy server to validate functionality.

Usage:
    python test_client.py [--url URL] [--cert CERT] [--key KEY] [--ca CA]
    
Examples:
    # Without TLS (development)
    python test_client.py --url http://localhost:8001
    
    # With TLS and client certificate
    python test_client.py --url https://localhost:8001 \
        --cert certs/test_client.crt \
        --key certs/test_client.key \
        --ca certs/ca.crt
"""

import argparse
import json
import sys
from datetime import datetime
from typing import Optional

import httpx
from pydantic import BaseModel, Field


class MessageSubmission(BaseModel):
    """Message submission model"""
    sender_number: str = Field(..., description="Phone number in E.164 format")
    message_body: str = Field(..., description="Message content")
    metadata: Optional[dict] = Field(default_factory=dict)


def send_message(
    url: str,
    sender: str,
    message: str,
    cert: Optional[tuple] = None,
    verify: Optional[str] = None
) -> dict:
    """
    Send a test message to the proxy
    
    Args:
        url: Proxy server URL
        sender: Sender phone number
        message: Message content
        cert: Tuple of (cert_file, key_file) for client certificate
        verify: Path to CA certificate for verification
        
    Returns:
        Response dictionary
    """
    # Prepare message
    msg = MessageSubmission(
        sender_number=sender,
        message_body=message,
        metadata={
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "test": True
        }
    )
    
    endpoint = f"{url}/api/v1/messages"
    
    print(f"\n{'='*70}")
    print("Sending Test Message")
    print(f"{'='*70}")
    print(f"URL:          {endpoint}")
    print(f"Sender:       {sender}")
    print(f"Message:      {message[:50]}...")
    print(f"Client Cert:  {cert[0] if cert else 'None (no TLS)'}")
    print(f"CA Cert:      {verify if verify else 'None'}")
    print(f"{'='*70}\n")
    
    try:
        # Create client with optional TLS config
        with httpx.Client(cert=cert, verify=verify or False, timeout=30.0) as client:
            response = client.post(
                endpoint,
                json=msg.dict(),
                headers={"Content-Type": "application/json"}
            )
            
            print(f"✓ Response Status: {response.status_code}")
            print(f"{'='*70}")
            
            if response.status_code == 202:
                result = response.json()
                print("\n✓ SUCCESS - Message Accepted")
                print(f"{'='*70}")
                print(f"Message ID:   {result.get('message_id')}")
                print(f"Client ID:    {result.get('client_id')}")
                print(f"Status:       {result.get('status')}")
                print(f"Queued At:    {result.get('queued_at')}")
                print(f"Queue Pos:    {result.get('position', 'N/A')}")
                print(f"{'='*70}\n")
                return result
            else:
                print(f"\n✗ FAILED - Status {response.status_code}")
                print(f"{'='*70}")
                print(f"Response: {response.text}")
                print(f"{'='*70}\n")
                return {"error": response.text, "status_code": response.status_code}
                
    except httpx.ConnectError as e:
        print(f"\n✗ CONNECTION ERROR")
        print(f"{'='*70}")
        print(f"Could not connect to {url}")
        print(f"Error: {e}")
        print(f"\nTroubleshooting:")
        print(f"  1. Is the proxy server running?")
        print(f"  2. Is the URL correct?")
        print(f"  3. Check firewall settings")
        print(f"{'='*70}\n")
        return {"error": str(e)}
    
    except httpx.HTTPStatusError as e:
        print(f"\n✗ HTTP ERROR {e.response.status_code}")
        print(f"{'='*70}")
        print(f"Response: {e.response.text}")
        print(f"{'='*70}\n")
        return {"error": e.response.text, "status_code": e.response.status_code}
    
    except httpx.SSLError as e:
        print(f"\n✗ SSL/TLS ERROR")
        print(f"{'='*70}")
        print(f"Error: {e}")
        print(f"\nTroubleshooting:")
        print(f"  1. Check certificate paths are correct")
        print(f"  2. Ensure certificates are not expired")
        print(f"  3. Verify CA certificate matches server")
        print(f"{'='*70}\n")
        return {"error": str(e)}
    
    except Exception as e:
        print(f"\n✗ UNEXPECTED ERROR")
        print(f"{'='*70}")
        print(f"Error: {e}")
        print(f"{'='*70}\n")
        return {"error": str(e)}


def test_health_check(url: str, verify: Optional[str] = None) -> bool:
    """
    Test the health check endpoint
    
    Args:
        url: Proxy server URL
        verify: Path to CA certificate
        
    Returns:
        True if healthy, False otherwise
    """
    endpoint = f"{url}/api/v1/health"
    
    print(f"\n{'='*70}")
    print("Testing Health Check")
    print(f"{'='*70}")
    print(f"URL: {endpoint}")
    print(f"{'='*70}\n")
    
    try:
        with httpx.Client(verify=verify or False, timeout=10.0) as client:
            response = client.get(endpoint)
            
            if response.status_code == 200:
                result = response.json()
                print("✓ Health Check: PASSED")
                print(f"{'='*70}")
                print(f"Status:    {result.get('status')}")
                print(f"Version:   {result.get('version')}")
                print(f"Timestamp: {result.get('timestamp')}")
                print("\nComponent Health:")
                for component, status in result.get('checks', {}).items():
                    print(f"  {component:15} {status}")
                print(f"{'='*70}\n")
                return True
            else:
                print(f"✗ Health Check: FAILED (Status {response.status_code})")
                print(f"Response: {response.text}\n")
                return False
                
    except Exception as e:
        print(f"✗ Health Check: FAILED")
        print(f"Error: {e}\n")
        return False


def run_test_suite(
    url: str,
    cert: Optional[tuple] = None,
    verify: Optional[str] = None
):
    """
    Run a complete test suite
    
    Args:
        url: Proxy server URL
        cert: Client certificate tuple
        verify: CA certificate path
    """
    print("\n" + "="*70)
    print("MESSAGE BROKER PROXY - TEST SUITE")
    print("="*70 + "\n")
    
    # Test 1: Health Check
    print("Test 1: Health Check")
    print("-" * 70)
    health_ok = test_health_check(url, verify)
    
    if not health_ok:
        print("\n⚠ WARNING: Health check failed. Some tests may not work.\n")
    
    # Test 2: Valid Message
    print("\nTest 2: Valid Message Submission")
    print("-" * 70)
    result1 = send_message(
        url=url,
        sender="+1234567890",
        message="This is a test message from the test suite.",
        cert=cert,
        verify=verify
    )
    
    # Test 3: Different Phone Format
    print("\nTest 3: International Phone Number")
    print("-" * 70)
    result2 = send_message(
        url=url,
        sender="+44123456789",
        message="Test message from UK number.",
        cert=cert,
        verify=verify
    )
    
    # Test 4: Long Message
    print("\nTest 4: Long Message (near limit)")
    print("-" * 70)
    long_message = "Test " * 195  # ~975 characters
    result3 = send_message(
        url=url,
        sender="+19876543210",
        message=long_message,
        cert=cert,
        verify=verify
    )
    
    # Test 5: Invalid Phone Number (should fail)
    print("\nTest 5: Invalid Phone Number (Expected to Fail)")
    print("-" * 70)
    result4 = send_message(
        url=url,
        sender="1234567890",  # Missing + prefix
        message="This should fail validation.",
        cert=cert,
        verify=verify
    )
    
    # Test 6: Empty Message (should fail)
    print("\nTest 6: Empty Message (Expected to Fail)")
    print("-" * 70)
    result5 = send_message(
        url=url,
        sender="+1234567890",
        message="",  # Empty message
        cert=cert,
        verify=verify
    )
    
    # Summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)
    
    results = [
        ("Health Check", health_ok),
        ("Valid Message #1", "message_id" in result1),
        ("Valid Message #2", "message_id" in result2),
        ("Long Message", "message_id" in result3),
        ("Invalid Phone (should fail)", "error" in result4),
        ("Empty Message (should fail)", "error" in result5),
    ]
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, passed_test in results:
        status = "✓ PASS" if passed_test else "✗ FAIL"
        print(f"  {status:8} - {test_name}")
    
    print(f"\nTotal: {passed}/{total} tests passed")
    print("="*70 + "\n")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Test client for Message Broker Proxy"
    )
    parser.add_argument(
        "--url",
        default="http://localhost:8001",
        help="Proxy server URL (default: http://localhost:8001)"
    )
    parser.add_argument(
        "--cert",
        help="Path to client certificate file"
    )
    parser.add_argument(
        "--key",
        help="Path to client private key file"
    )
    parser.add_argument(
        "--ca",
        help="Path to CA certificate file"
    )
    parser.add_argument(
        "--sender",
        default="+1234567890",
        help="Sender phone number (default: +1234567890)"
    )
    parser.add_argument(
        "--message",
        default="Test message from test client",
        help="Message content"
    )
    parser.add_argument(
        "--test-suite",
        action="store_true",
        help="Run complete test suite"
    )
    
    args = parser.parse_args()
    
    # Prepare certificate tuple
    cert = None
    if args.cert and args.key:
        cert = (args.cert, args.key)
    
    # Run tests
    if args.test_suite:
        run_test_suite(args.url, cert, args.ca)
    else:
        # Single message test
        test_health_check(args.url, args.ca)
        send_message(args.url, args.sender, args.message, cert, args.ca)


if __name__ == "__main__":
    main()

