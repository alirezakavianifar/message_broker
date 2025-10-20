#!/usr/bin/env python3
"""
Mutual TLS Test Script for Message Broker System

This script tests mutual TLS authentication by:
1. Starting a simple HTTPS server with client certificate verification
2. Attempting connections with various certificate scenarios
3. Validating certificate verification behavior

Usage:
    python test_mtls.py [--server-only] [--client-only] [--port PORT]

Requirements:
    pip install httpx uvicorn fastapi
"""

import argparse
import asyncio
import os
import sys
from pathlib import Path
from typing import Optional

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import uvicorn


# Test server application
app = FastAPI(title="mTLS Test Server")


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "mTLS Test Server",
        "status": "running"
    }


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


@app.post("/test")
async def test_endpoint(request: Request):
    """Test endpoint that returns client certificate info"""
    # In a real scenario, certificate info would be in request headers or SSL context
    return {
        "message": "mTLS authentication successful",
        "endpoint": "/test",
        "method": "POST"
    }


class MTLSConfig:
    """Configuration for mTLS testing"""
    
    def __init__(self, base_dir: Optional[str] = None):
        if base_dir is None:
            # Assume script is in main_server directory
            self.base_dir = Path(__file__).parent
        else:
            self.base_dir = Path(base_dir)
        
        self.certs_dir = self.base_dir / "certs"
        self.ca_cert = self.certs_dir / "ca.crt"
        self.server_key = self.certs_dir / "server.key"
        self.server_cert = self.certs_dir / "server.crt"
    
    def validate(self) -> tuple[bool, str]:
        """Validate that required certificates exist"""
        if not self.ca_cert.exists():
            return False, f"CA certificate not found: {self.ca_cert}"
        if not self.server_key.exists():
            return False, f"Server key not found: {self.server_key}"
        if not self.server_cert.exists():
            return False, f"Server certificate not found: {self.server_cert}"
        return True, "All certificates found"


def run_server(config: MTLSConfig, port: int = 8443):
    """Run test HTTPS server with mTLS"""
    print("=" * 70)
    print("mTLS Test Server")
    print("=" * 70)
    print(f"\nStarting server on https://localhost:{port}")
    print(f"CA Certificate: {config.ca_cert}")
    print(f"Server Certificate: {config.server_cert}")
    print(f"Server Key: {config.server_key}")
    print("\nServer requires client certificate for authentication")
    print("\nPress Ctrl+C to stop the server")
    print("=" * 70)
    print()
    
    # Run uvicorn with SSL
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=port,
        ssl_keyfile=str(config.server_key),
        ssl_certfile=str(config.server_cert),
        ssl_ca_certs=str(config.ca_cert),
        ssl_cert_reqs=2,  # Require client certificate
        log_level="info"
    )


async def test_connection(
    url: str,
    cert_path: Optional[str],
    key_path: Optional[str],
    ca_path: Optional[str],
    test_name: str
) -> dict:
    """
    Test connection with specific certificate configuration
    
    Returns:
        dict with test results
    """
    result = {
        "test": test_name,
        "url": url,
        "success": False,
        "status_code": None,
        "error": None,
        "response": None
    }
    
    try:
        # Configure certificate
        cert = None
        if cert_path and key_path:
            cert = (cert_path, key_path)
        
        # Configure CA verification
        verify = ca_path if ca_path else False
        
        # Create client
        async with httpx.AsyncClient(cert=cert, verify=verify, timeout=10.0) as client:
            # Test GET request
            response = await client.get(url)
            result["success"] = True
            result["status_code"] = response.status_code
            result["response"] = response.json()
            
    except httpx.ConnectError as e:
        result["error"] = f"Connection error: {str(e)}"
    except httpx.HTTPStatusError as e:
        result["status_code"] = e.response.status_code
        result["error"] = f"HTTP error: {e.response.status_code}"
    except httpx.SSLError as e:
        result["error"] = f"SSL error: {str(e)}"
    except Exception as e:
        result["error"] = f"Unexpected error: {str(e)}"
    
    return result


async def run_client_tests(config: MTLSConfig, port: int = 8443):
    """Run comprehensive mTLS client tests"""
    print("=" * 70)
    print("mTLS Client Tests")
    print("=" * 70)
    print(f"\nServer: https://localhost:{port}")
    print(f"CA Certificate: {config.ca_cert}\n")
    
    base_url = f"https://localhost:{port}"
    
    # Find a valid client certificate for testing
    clients_dir = config.certs_dir / "clients"
    test_client = None
    test_client_key = None
    test_client_cert = None
    
    if clients_dir.exists():
        for client_dir in clients_dir.iterdir():
            if client_dir.is_dir():
                cert_file = client_dir / f"{client_dir.name}.crt"
                key_file = client_dir / f"{client_dir.name}.key"
                if cert_file.exists() and key_file.exists():
                    test_client = client_dir.name
                    test_client_cert = str(cert_file)
                    test_client_key = str(key_file)
                    break
    
    tests = [
        {
            "name": "Test 1: Valid Certificate",
            "cert": test_client_cert,
            "key": test_client_key,
            "ca": str(config.ca_cert),
            "expected": "SUCCESS"
        },
        {
            "name": "Test 2: No Client Certificate",
            "cert": None,
            "key": None,
            "ca": str(config.ca_cert),
            "expected": "FAIL (client cert required)"
        },
        {
            "name": "Test 3: Wrong CA Certificate",
            "cert": test_client_cert,
            "key": test_client_key,
            "ca": None,  # Don't verify CA
            "expected": "FAIL or WARNING"
        }
    ]
    
    if test_client is None:
        print("⚠ WARNING: No client certificates found for testing")
        print(f"   Please generate a client certificate first:")
        print(f"   generate_cert.bat test_client")
        print()
        return
    
    print(f"Using test client: {test_client}\n")
    
    results = []
    for test in tests:
        print(f"Running: {test['name']}")
        print(f"Expected: {test['expected']}")
        
        result = await test_connection(
            url=base_url,
            cert_path=test['cert'],
            key_path=test['key'],
            ca_path=test['ca'],
            test_name=test['name']
        )
        
        results.append(result)
        
        # Display result
        if result['success']:
            print(f"✓ PASS - Status: {result['status_code']}")
            print(f"  Response: {result['response']}")
        else:
            print(f"✗ FAIL - {result['error']}")
        
        print()
    
    # Summary
    print("=" * 70)
    print("Test Summary")
    print("=" * 70)
    passed = sum(1 for r in results if r['success'])
    failed = sum(1 for r in results if not r['success'])
    print(f"Total Tests: {len(results)}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print()


async def run_validation_tests(config: MTLSConfig):
    """Run certificate validation tests"""
    print("=" * 70)
    print("Certificate Validation Tests")
    print("=" * 70)
    print()
    
    tests = []
    
    # Test 1: CA certificate validation
    print("Test 1: CA Certificate Validation")
    ca_valid = config.ca_cert.exists()
    print(f"  CA Certificate: {config.ca_cert}")
    print(f"  Status: {'✓ EXISTS' if ca_valid else '✗ NOT FOUND'}")
    tests.append(("CA Certificate", ca_valid))
    print()
    
    # Test 2: Server certificate validation
    print("Test 2: Server Certificate Validation")
    server_valid = config.server_cert.exists() and config.server_key.exists()
    print(f"  Server Certificate: {config.server_cert}")
    print(f"  Server Key: {config.server_key}")
    print(f"  Status: {'✓ EXISTS' if server_valid else '✗ NOT FOUND'}")
    tests.append(("Server Certificate", server_valid))
    print()
    
    # Test 3: Client certificates
    print("Test 3: Client Certificates")
    clients_dir = config.certs_dir / "clients"
    if clients_dir.exists():
        client_count = 0
        for client_dir in clients_dir.iterdir():
            if client_dir.is_dir():
                cert_file = client_dir / f"{client_dir.name}.crt"
                key_file = client_dir / f"{client_dir.name}.key"
                if cert_file.exists() and key_file.exists():
                    print(f"  ✓ {client_dir.name}")
                    client_count += 1
        
        print(f"  Total: {client_count} client(s)")
        tests.append(("Client Certificates", client_count > 0))
    else:
        print("  ✗ No clients directory")
        tests.append(("Client Certificates", False))
    print()
    
    # Summary
    print("=" * 70)
    print("Validation Summary")
    print("=" * 70)
    passed = sum(1 for _, valid in tests if valid)
    failed = sum(1 for _, valid in tests if not valid)
    print(f"Total Tests: {len(tests)}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print()
    
    if failed > 0:
        print("⚠ Some validation tests failed. Please check certificate setup.")
        print("   Run: init_ca.bat")
        print("   Run: generate_cert.bat server")
        print("   Run: generate_cert.bat test_client")
    else:
        print("✓ All validation tests passed!")
    print()


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="mTLS Test Script for Message Broker System"
    )
    parser.add_argument(
        "--server-only",
        action="store_true",
        help="Only run the test server"
    )
    parser.add_argument(
        "--client-only",
        action="store_true",
        help="Only run client tests (requires running server)"
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Only run certificate validation"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8443,
        help="Server port (default: 8443)"
    )
    parser.add_argument(
        "--base-dir",
        type=str,
        help="Base directory for certificates (default: script directory)"
    )
    
    args = parser.parse_args()
    
    # Initialize configuration
    config = MTLSConfig(args.base_dir)
    
    # Validate certificates exist
    valid, message = config.validate()
    if not valid and not args.validate_only:
        print(f"ERROR: {message}")
        print("\nPlease ensure certificates are generated:")
        print("  1. Run: init_ca.bat")
        print("  2. Run: generate_cert.bat server")
        print("  3. Run: generate_cert.bat test_client")
        sys.exit(1)
    
    # Run appropriate mode
    if args.validate_only:
        asyncio.run(run_validation_tests(config))
    elif args.server_only:
        run_server(config, args.port)
    elif args.client_only:
        asyncio.run(run_client_tests(config, args.port))
    else:
        # Default: Run validation and provide instructions
        print("mTLS Test Script")
        print("=" * 70)
        print()
        asyncio.run(run_validation_tests(config))
        print("\nUsage Options:")
        print("  --validate-only  : Run certificate validation")
        print("  --server-only    : Start test HTTPS server")
        print("  --client-only    : Run client tests (requires running server)")
        print()
        print("Example Workflow:")
        print("  Terminal 1: python test_mtls.py --server-only")
        print("  Terminal 2: python test_mtls.py --client-only")
        print()


if __name__ == "__main__":
    main()

