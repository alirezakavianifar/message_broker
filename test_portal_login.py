#!/usr/bin/env python3
"""
Test portal login from inside the server
"""
import urllib.request
import urllib.parse
import json
import sys
import ssl

def test_login(email, password):
    """Test login to portal (via main server API)"""
    url = "https://localhost:8000/portal/auth/login"
    
    try:
        # Prepare data
        data = {
            "email": email,
            "password": password
        }
        data_json = json.dumps(data).encode('utf-8')
        
        # Create request
        req = urllib.request.Request(
            url,
            data=data_json,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        
        # Make request (disable SSL verification for localhost)
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
        
        try:
            with urllib.request.urlopen(req, timeout=10, context=ssl_context) as response:
                status_code = response.getcode()
                response_data = response.read().decode('utf-8')
                
                print(f"Status Code: {status_code}")
                print(f"URL: {url}")
                print("")
                
                if status_code == 200:
                    data = json.loads(response_data)
                    print("✓ Login successful!")
                    print("")
                    print("Response:")
                    print(json.dumps(data, indent=2))
                    
                    if "access_token" in data:
                        print("")
                        print(f"Access Token: {data['access_token'][:50]}...")
                        return data.get("access_token")
                else:
                    print("✗ Login failed")
                    print("")
                    print("Response:")
                    try:
                        print(json.dumps(json.loads(response_data), indent=2))
                    except:
                        print(response_data)
                    return None
        except urllib.error.HTTPError as e:
            print(f"Status Code: {e.code}")
            print(f"URL: {url}")
            print("")
            print("✗ Login failed")
            print("")
            print("Response:")
            try:
                error_data = e.read().decode('utf-8')
                print(json.dumps(json.loads(error_data), indent=2))
            except:
                print(e.read().decode('utf-8'))
            return None
            
    except urllib.error.URLError as e:
        print("✗ Connection error: Could not connect to main server")
        print(f"   Error: {e}")
        print("   Make sure the main_server service is running on port 8000")
        return None
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 test_portal_login.py <email> <password>")
        print("")
        print("This tests portal login via the main server API (port 8000)")
        print("")
        print("Example:")
        print("  python3 test_portal_login.py newadmin@example.com 'Admin123!'")
        sys.exit(1)
    
    email = sys.argv[1]
    password = sys.argv[2]
    
    print("Testing portal login (via main server API)...")
    print("=" * 50)
    print("")
    
    token = test_login(email, password)
    
    if token:
        print("")
        print("=" * 50)
        print("✓ Login test successful!")
        print("You can now use this token to access protected endpoints.")
    else:
        print("")
        print("=" * 50)
        print("✗ Login test failed")
        sys.exit(1)

