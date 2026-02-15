#!/usr/bin/env python3
"""
Message Broker Client - Python Convenience Script (Optional)

This script is a convenience wrapper around HTTP requests. You don't need Python
to send messages - you can use curl, Postman, or any HTTP client!

The Message Broker uses a thin client architecture:
- No Python required - use any HTTP client
- No virtual environments needed on client machines
- Just send HTTP POST requests with mutual TLS certificates

See README.md for examples using curl, PowerShell, JavaScript, Go, etc.

Usage: python send_message.py --sender "+1234567890" --message "Your message here"
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import httpx
from pydantic import BaseModel, Field, validator


class Message(BaseModel):
    """Message model matching the system's expected format."""
    
    sender_number: str = Field(..., description="Phone number in E.164 format")
    message_body: str = Field(..., description="Message content")
    metadata: dict = Field(default_factory=dict)
    
    @validator('sender_number')
    def validate_phone(cls, v):
        """Validate phone number format (E.164)."""
        if not v.startswith('+'):
            raise ValueError('Phone number must start with +')
        if not v[1:].isdigit():
            raise ValueError('Phone number must contain only digits after +')
        if len(v) < 8 or len(v) > 16:
            raise ValueError('Phone number must be between 8-16 characters')
        return v
    
    @validator('message_body')
    def validate_message(cls, v):
        """Validate message body."""
        if not v or not v.strip():
            raise ValueError('Message body cannot be empty')
        if len(v) > 1000:
            raise ValueError('Message body cannot exceed 1000 characters')
        return v


def send_message(
    sender: str,
    message: str,
    proxy_url: str = "https://localhost:8001",
    cert_file: str = None,
    key_file: str = None,
    ca_file: str = None,
    client_id: str = "default_client"
) -> dict:
    """
    Send a message to the proxy server.
    
    Args:
        sender: Phone number in E.164 format
        message: Message content
        proxy_url: Proxy server URL
        cert_file: Path to client certificate
        key_file: Path to client private key
        ca_file: Path to CA certificate
        client_id: Client identifier
        
    Returns:
        Response from the proxy server
    """
    # Create message payload
    msg = Message(
        sender_number=sender,
        message_body=message,
        metadata={
            "client_id": client_id,
            "timestamp": datetime.utcnow().isoformat()
        }
    )
    
    # Prepare TLS configuration
    cert = None
    if cert_file and key_file:
        cert = (cert_file, key_file)
    
    verify = ca_file if ca_file else False
    
    # Send request
    try:
        with httpx.Client(cert=cert, verify=verify, timeout=30.0) as client:
            response = client.post(
                f"{proxy_url}/api/v1/messages",
                json=msg.dict(),
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            return response.json()
    except httpx.HTTPStatusError as e:
        print(f"HTTP Error: {e.response.status_code}")
        print(f"Response: {e.response.text}")
        sys.exit(1)
    except httpx.RequestError as e:
        print(f"Request Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected Error: {e}")
        sys.exit(1)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Send a message to the message broker system"
    )
    parser.add_argument(
        "--sender",
        required=True,
        help="Sender phone number in E.164 format (e.g., +1234567890)"
    )
    parser.add_argument(
        "--message",
        required=True,
        help="Message body (max 1000 characters)"
    )
    parser.add_argument(
        "--proxy-url",
        default="https://localhost:8001",
        help="Proxy server URL (default: https://localhost:8001)"
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
        "--client-id",
        default="default_client",
        help="Client identifier (default: default_client)"
    )
    
    args = parser.parse_args()
    
    print(f"Sending message...")
    print(f"Sender: {args.sender}")
    print(f"Message: {args.message}")
    print(f"Proxy: {args.proxy_url}")
    print("-" * 50)
    
    result = send_message(
        sender=args.sender,
        message=args.message,
        proxy_url=args.proxy_url,
        cert_file=args.cert,
        key_file=args.key,
        ca_file=args.ca,
        client_id=args.client_id
    )
    
    print("✓ Message sent successfully!")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

