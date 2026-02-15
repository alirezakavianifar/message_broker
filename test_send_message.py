#!/usr/bin/env python3
"""Simple script to test sending a message via the proxy"""

import ssl
import json
import urllib.request
import urllib.error

# Certificate paths
cert_file = r".\client-scripts\certs\my_pc.crt"
key_file = r".\client-scripts\certs\my_pc.key"
ca_cert = r".\client-scripts\certs\ca.crt"

# Message data
url = "https://91.92.206.217:443/api/v1/messages"
data = {
    "sender_number": "+1234567890",
    "message_body": "Test message from my PC on port 443!"
}

# Create SSL context
context = ssl.create_default_context(cafile=ca_cert)
context.load_cert_chain(cert_file, key_file)

# Prepare request
json_data = json.dumps(data).encode('utf-8')
req = urllib.request.Request(url, data=json_data, headers={'Content-Type': 'application/json'})

try:
    print("Sending message...")
    print(f"  URL: {url}")
    print(f"  Sender: {data['sender_number']}")
    print(f"  Message: {data['message_body']}")
    print("-" * 50)
    
    with urllib.request.urlopen(req, context=context) as response:
        result = json.loads(response.read().decode('utf-8'))
        print("\n✓ Message sent successfully!")
        print(f"Status Code: {response.getcode()}")
        print(f"Response: {json.dumps(result, indent=2)}")
except urllib.error.HTTPError as e:
    print(f"\n✗ HTTP Error: {e.code}")
    print(f"Response: {e.read().decode('utf-8')}")
except Exception as e:
    print(f"\n✗ Error: {e}")

