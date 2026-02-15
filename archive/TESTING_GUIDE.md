# Message Broker Testing Guide

This guide provides step-by-step instructions for testing the deployed message broker system on your Linux server.

## Prerequisites

- SSH access to the server (IP: `91.92.206.217`, Port: `2223`)
- Admin credentials:
  - Email: `admin@example.com`
  - Password: `AdminPass123!`

### Note for Windows Users

If you're using Windows PowerShell:

- SSH commands work the same way
- For `curl` commands, use `curl.exe` (if available) or `Invoke-WebRequest` with `-SkipCertificateCheck`
- Example: `Invoke-WebRequest -Uri "https://91.92.206.217:8000/health" -SkipCertificateCheck`
- Or use: `curl.exe -k https://91.92.206.217:8000/health`

---

## 1. Verify Services Are Running

### Check Service Status

**Quick Check (All 4 Services):**

```bash
ssh -p 2223 root@91.92.206.217 "systemctl is-active main_server proxy worker portal"
```

**Expected Output:**

```
active
active
active
active
```

**Detailed Status Check:**

```bash
ssh -p 2223 root@91.92.206.217 "systemctl status main_server proxy worker portal --no-pager | grep -E '(●|Active:)'"
```

**Expected Output:**

```
● main_server.service - Active: active (running)
● proxy.service - Active: active (running)
● worker.service - Active: active (running)
● portal.service - Active: active (running)
```

**Note:** The worker service doesn't listen on a network port - it's a background process that polls Redis for messages. Only 3 ports (8000, 8001, 8080) will show in port checks.

### Check Service Logs

```bash
# Main Server logs
ssh -p 2223 root@91.92.206.217 "journalctl -u main_server.service --no-pager -n 20"

# Proxy logs
ssh -p 2223 root@91.92.206.217 "journalctl -u proxy.service --no-pager -n 20"

# Worker logs
ssh -p 2223 root@91.92.206.217 "journalctl -u worker.service --no-pager -n 20"

# Portal logs
ssh -p 2223 root@91.92.206.217 "journalctl -u portal.service --no-pager -n 20"
```

### Verify Ports Are Listening

**Note:** Only 3 services listen on network ports. The worker service is a background process and doesn't expose a network port.

```bash
ssh -p 2223 root@91.92.206.217 "netstat -tlnp | grep -E '(8000|8001|8080)'"
```

**Expected Output:**

```
tcp  0  0  0.0.0.0:8000  LISTEN  <pid>/python3  # Main Server
tcp  0  0  0.0.0.0:8001  LISTEN  <pid>/python3  # Proxy
tcp  0  0  0.0.0.0:8080  LISTEN  <pid>/python3  # Portal
```

**Verify All 4 Services (including worker):**

```bash
# Check all services are active
ssh -p 2223 root@91.92.206.217 "systemctl is-active main_server proxy worker portal"

# Check worker process is running
ssh -p 2223 root@91.92.206.217 "ps aux | grep '[w]orker.py'"
```

---

## 2. Test Portal Login

### Access the Portal

1. **Open your web browser** and navigate to:

   ```
   http://91.92.206.217:8080
   ```
2. **Login with admin credentials:**

   - Email: `admin@example.com`
   - Password: `AdminPass123!`
3. **Expected Result:**

   - You should be redirected to the admin dashboard
   - You should see options for:
     - Users management
     - Messages
     - Certificates
     - System statistics

### Test Portal Features

- **Users Management:**

  - Navigate to "Users" section
  - Create a new user
  - List all users
  - Edit user details
- **Messages:**

  - View message queue
  - Check message status
  - View message history
- **Certificates:**

  - View client certificates
  - Generate new certificates
  - Revoke certificates

---

## 3. Test Main Server API

### Health Check

**Linux/Bash:**

```bash
# Test health endpoint (bypass SSL verification for testing)
curl -k https://91.92.206.217:8000/health
```

**Windows PowerShell:**

```powershell
# Using curl.exe (if available)
curl.exe -k https://91.92.206.217:8000/health

# Or using Invoke-WebRequest
Invoke-WebRequest -Uri "https://91.92.206.217:8000/health" -SkipCertificateCheck
```

**Expected Response:**

```json
{
  "status": "healthy",
  "database": "connected",
  "redis": "connected"
}
```

### API Documentation

1. **Open Swagger UI:**

   ```
   https://91.92.206.217:8000/docs
   ```
2. **Open ReDoc:**

   ```
   https://91.92.206.217:8000/redoc
   ```

### Test Authentication

**Linux/Bash:**

```bash
# Login and get JWT token
TOKEN=$(curl -k -X POST "https://91.92.206.217:8000/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"AdminPass123!"}' \
  | jq -r '.access_token')

echo "Token: $TOKEN"
```

**Windows PowerShell:**

```powershell
# Login and get JWT token
$body = @{
    email = "admin@example.com"
    password = "AdminPass123!"
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "https://91.92.206.217:8000/auth/login" `
    -Method POST `
    -Body $body `
    -ContentType "application/json" `
    -SkipCertificateCheck

$TOKEN = $response.access_token
Write-Host "Token: $TOKEN"
```

### Test Admin Endpoints

**Linux/Bash:**

```bash
# List all users (requires authentication)
curl -k -X GET "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer $TOKEN"

# Get system statistics
curl -k -X GET "https://91.92.206.217:8000/admin/stats" \
  -H "Authorization: Bearer $TOKEN"

# List all clients
curl -k -X GET "https://91.92.206.217:8000/admin/clients" \
  -H "Authorization: Bearer $TOKEN"
```

**Windows PowerShell:**

```powershell
# List all users (requires authentication)
$headers = @{
    Authorization = "Bearer $TOKEN"
}
Invoke-RestMethod -Uri "https://91.92.206.217:8000/admin/users" `
    -Method GET `
    -Headers $headers `
    -SkipCertificateCheck

# Get system statistics
Invoke-RestMethod -Uri "https://91.92.206.217:8000/admin/stats" `
    -Method GET `
    -Headers $headers `
    -SkipCertificateCheck

# List all clients
Invoke-RestMethod -Uri "https://91.92.206.217:8000/admin/clients" `
    -Method GET `
    -Headers $headers `
    -SkipCertificateCheck
```

---

## 4. Test Proxy Server API

### Health Check

```bash
curl -k https://91.92.206.217:8001/health
```

### API Documentation

```
https://91.92.206.217:8001/docs
```

### Test Message Submission (with Client Certificate)

**Note:** The proxy requires mutual TLS authentication with a valid client certificate.

```bash
# Test with client certificate (if you have one)
curl -k -X POST "https://91.92.206.217:8001/messages" \
  --cert /path/to/client.crt \
  --key /path/to/client.key \
  --cacert /path/to/ca.crt \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+1234567890",
    "message_body": "Test message"
  }'
```

---

## 5. Test Database Connectivity

### Check Database Connection

```bash
ssh -p 2223 root@91.92.206.217 'mysql -u systemuser -p"MsgBrckr#TnN$2025" -D message_system -e "SELECT COUNT(*) as user_count FROM users;"'
```

### Verify Admin User Exists

```bash
ssh -p 2223 root@91.92.206.217 'mysql -u systemuser -p"MsgBrckr#TnN$2025" -D message_system -e "SELECT id, email, role, is_active FROM users WHERE role=\"ADMIN\";"'
```

**Expected Output:**

```
+----+-------------------+-------+-----------+
| id | email             | role  | is_active |
+----+-------------------+-------+-----------+
|  1 | admin@example.com | admin |         1 |
+----+-------------------+-------+-----------+
```

---

## 6. Test Redis Connectivity

### Check Redis Connection

```bash
ssh -p 2223 root@91.92.206.217 "redis-cli ping"
```

**Expected Output:**

```
PONG
```

### Check Redis Queue

```bash
ssh -p 2223 root@91.92.206.217 "redis-cli LLEN message_queue"
```

---

## 7. Test Worker Service

### Check Worker Status

```bash
ssh -p 2223 root@91.92.206.217 "systemctl status worker.service --no-pager | head -15"
```

### Monitor Worker Logs

```bash
ssh -p 2223 root@91.92.206.217 "journalctl -u worker.service -f"
```

The worker should be continuously polling Redis for messages and processing them.

---

## 8. Test End-to-End Message Flow

### Step 1: Generate Client Certificate

```bash
# SSH into the server
ssh -p 2223 root@91.92.206.217

# Navigate to main_server directory
cd /opt/message_broker/main_server
source ../venv/bin/activate

# Generate a test client certificate
python3 admin_cli.py cert generate test_client

# The certificate will be created in:
# /opt/message_broker/main_server/certs/clients/test_client/
```

### Step 2: Download Certificate Files

```bash
# From your local machine, download the certificate files
scp -P 2223 root@91.92.206.217:/opt/message_broker/main_server/certs/clients/test_client/test_client.crt ./
scp -P 2223 root@91.92.206.217:/opt/message_broker/main_server/certs/clients/test_client/test_client.key ./
scp -P 2223 root@91.92.206.217:/opt/message_broker/main_server/certs/ca.crt ./
```

### Step 3: Submit Message via Proxy

```bash
curl -k -X POST "https://91.92.206.217:8001/messages" \
  --cert test_client.crt \
  --key test_client.key \
  --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+1234567890",
    "message_body": "Test message from client"
  }'
```

**Expected Response:**

```json
{
  "message_id": "uuid-here",
  "status": "queued",
  "phone_number": "+1234567890",
  "message_body": "Test message from client",
  "created_at": "2025-11-08T..."
}
```

### Step 4: Verify Message Processing

```bash
# Check if message was processed (via API)
curl -k -X GET "https://91.92.206.217:8000/admin/messages" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.'
```

---

## 9. Test User Management

### Create New User via API

```bash
curl -k -X POST "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "testuser@example.com",
    "password": "TestPass123!",
    "role": "user"
  }'
```

### List All Users

```bash
curl -k -X GET "https://91.92.206.217:8000/admin/users" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.'
```

---

## 10. Performance Testing

### Check System Resources

```bash
ssh -p 2223 root@91.92.206.217 "top -bn1 | head -20"
```

### Check Service Resource Usage

```bash
ssh -p 2223 root@91.92.206.217 "systemctl status main_server proxy worker portal --no-pager | grep -E '(Memory:|CPU:)'"
```

### Monitor Log Files

```bash
# Main server logs
ssh -p 2223 root@91.92.206.217 "tail -f /opt/message_broker/logs/main_server.log"

# Proxy logs
ssh -p 2223 root@91.92.206.217 "tail -f /opt/message_broker/logs/proxy.log"

# Worker logs
ssh -p 2223 root@91.92.206.217 "tail -f /opt/message_broker/logs/worker.log"
```

---

## 11. Troubleshooting

### Service Won't Start

```bash
# Check service status
ssh -p 2223 root@91.92.206.217 "systemctl status <service_name>"

# Check detailed logs
ssh -p 2223 root@91.92.206.217 "journalctl -u <service_name> -n 50 --no-pager"

# Restart service
ssh -p 2223 root@91.92.206.217 "systemctl restart <service_name>"
```

### Database Connection Issues

```bash
# Test database connection
ssh -p 2223 root@91.92.206.217 'mysql -u systemuser -p"MsgBrckr#TnN$2025" -D message_system -e "SELECT 1;"'

# Check database status
ssh -p 2223 root@91.92.206.217 "systemctl status mysql"
```

### Redis Connection Issues

```bash
# Test Redis connection
ssh -p 2223 root@91.92.206.217 "redis-cli ping"

# Check Redis status
ssh -p 2223 root@91.92.206.217 "systemctl status redis"
```

### Portal Not Accessible

1. **Check if firewall is blocking port 8080:**

   - Verify cloud provider firewall rules
   - Ensure port 8080 is open for inbound traffic
2. **Check service is running:**

   ```bash
   ssh -p 2223 root@91.92.206.217 "systemctl status portal"
   ```
3. **Check if port is listening:**

   ```bash
   ssh -p 2223 root@91.92.206.217 "netstat -tlnp | grep 8080"
   ```

### Certificate Issues

```bash
# Verify certificates exist
ssh -p 2223 root@91.92.206.217 "ls -la /opt/message_broker/main_server/certs/"

# Check certificate validity
ssh -p 2223 root@91.92.206.217 "openssl x509 -in /opt/message_broker/main_server/certs/server.crt -text -noout | head -20"
```

---

## 12. Quick Test Checklist

- [ ] All services are running (`systemctl status`)
- [ ] Ports 8000, 8001, 8080 are listening (`netstat`)
- [ ] Portal is accessible (`http://91.92.206.217:8080`)
- [ ] Can login to portal with admin credentials
- [ ] Main Server API health check passes (`/health`)
- [ ] Proxy API health check passes (`/health`)
- [ ] Database connection works (MySQL)
- [ ] Redis connection works (`redis-cli ping`)
- [ ] Can create users via API
- [ ] Can generate client certificates
- [ ] Can submit messages via proxy (with certificate)
- [ ] Worker processes messages from queue

---

## 13. API Testing Examples

### Complete API Test Script

```bash
#!/bin/bash

SERVER="91.92.206.217"
PORT_MAIN="8000"
PORT_PROXY="8001"
PORTAL="8080"
EMAIL="admin@example.com"
PASSWORD="AdminPass123!"

echo "=== Testing Message Broker System ==="

# 1. Health Checks
echo -e "\n1. Testing Health Endpoints..."
curl -k -s "https://${SERVER}:${PORT_MAIN}/health" | jq '.'
curl -k -s "https://${SERVER}:${PORT_PROXY}/health" | jq '.'

# 2. Login and Get Token
echo -e "\n2. Authenticating..."
TOKEN=$(curl -k -s -X POST "https://${SERVER}:${PORT_MAIN}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}" \
  | jq -r '.access_token')

if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
  echo "✓ Authentication successful"
else
  echo "✗ Authentication failed"
  exit 1
fi

# 3. Get User Info
echo -e "\n3. Getting Current User Info..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/auth/me" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

# 4. List Users
echo -e "\n4. Listing All Users..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/admin/users" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

# 5. Get System Statistics
echo -e "\n5. Getting System Statistics..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/admin/stats" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

# 6. List Clients
echo -e "\n6. Listing Clients..."
curl -k -s -X GET "https://${SERVER}:${PORT_MAIN}/admin/clients" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.'

echo -e "\n=== Testing Complete ==="
```

Save this as `test_api.sh`, make it executable, and run it:

```bash
chmod +x test_api.sh
./test_api.sh
```

---

## 14. Monitoring and Logs

### Real-time Log Monitoring

```bash
# Monitor all services
ssh -p 2223 root@91.92.206.217 "journalctl -f -u main_server -u proxy -u worker -u portal"

# Monitor specific service
ssh -p 2223 root@91.92.206.217 "journalctl -u main_server -f"
```

### Check Log Files

```bash
# List log files
ssh -p 2223 root@91.92.206.217 "ls -lh /opt/message_broker/logs/"

# View recent logs
ssh -p 2223 root@91.92.206.217 "tail -100 /opt/message_broker/logs/main_server.log"
```

---

## 15. Security Testing

### Test SSL/TLS Configuration

```bash
# Test SSL connection
openssl s_client -connect 91.92.206.217:8000 -servername 91.92.206.217

# Check certificate details
echo | openssl s_client -connect 91.92.206.217:8000 2>/dev/null | openssl x509 -noout -text
```

### Test Authentication

- Try accessing protected endpoints without token
- Verify JWT token expiration
- Test with invalid credentials

---

## 16. Load Testing (Optional)

### Simple Load Test with Apache Bench

```bash
# Install ab (Apache Bench) if not available
# On Ubuntu/Debian: sudo apt install apache2-utils

# Test health endpoint
ab -n 100 -c 10 -k https://91.92.206.217:8000/health

# Test authenticated endpoint (requires token)
ab -n 100 -c 10 -k -H "Authorization: Bearer $TOKEN" https://91.92.206.217:8000/admin/stats
```
