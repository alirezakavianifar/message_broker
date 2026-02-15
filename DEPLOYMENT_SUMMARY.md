# Message Broker System - Deployment Summary

## Overview

This document provides a comprehensive guide to the Message Broker system deployment, including service locations, health checks, user management, and message sending.

The Message Broker System is a secure message routing platform that allows clients to send encrypted messages through a proxy server, which are then stored in a database and can be viewed through a web portal.

---

## Prerequisites

Before you begin testing, ensure you have the following:

### Required Tools

**On Windows**:
- **PowerShell** (5.1+ or PowerShell Core) - Usually pre-installed
- **PuTTY/plink** - For SSH access
  - Download from: https://www.chiark.greenend.org.uk/~sgtatham/putty/
  - Or install via: `choco install putty`
- **OpenSSL** - For certificate operations
  - Download from: https://slproweb.com/products/Win32OpenSSL.html
  - Or install via: `choco install openssl`
- **Web Browser** - For accessing the portal (Chrome, Firefox, Edge)

**On Linux/Mac**:
- **SSH client** - Usually pre-installed (`ssh` command)
- **OpenSSL** - Usually pre-installed (`openssl` command)
- **curl** - Usually pre-installed (`curl` command)
- **Web Browser** - For accessing the portal

### Required Access

You need SSH access to the following servers:

1. **Main Server**: `173.32.115.223:2221`
   - Username: `root`
   - Password: `Pc$123456`

2. **Proxy Server**: `91.92.206.217:2221`
   - Username: `root`
   - Password: `Pc$123456`

### Verify Access

**On Windows (PowerShell)**:
```powershell
# Test connection to main server
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "echo 'Connection successful'"

# Test connection to proxy server
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "echo 'Connection successful'"
```

**On Linux/Mac**:
```bash
# Test connection to main server
ssh -p 2221 root@173.32.115.223 "echo 'Connection successful'"

# Test connection to proxy server
ssh -p 2221 root@91.92.206.217 "echo 'Connection successful'"
```

If these commands succeed, you have the required access.

### Verify Tools

**Check OpenSSL**:
```powershell
# Windows PowerShell
openssl version

# Linux/Mac
openssl version
```

**Check plink (Windows only)**:
```powershell
plink -V
```

If any tool is missing, install it before proceeding.

---

## Service Locations

### 1. Main Server (API & Database)
- **Server IP**: `173.32.115.223`
- **SSH Port**: `2221`
- **Service Port**: `8000` (HTTPS)
- **Installation Path**: `/opt/message_broker/`
- **Service Name**: `main_server.service`
- **Database**: MySQL/MariaDB on `localhost:3306`
- **Database Name**: `message_system`
- **Database User**: `systemuser`
- **Access URLs**:
  - API: `https://173.32.115.223:8000`
  - Health: `https://173.32.115.223:8000/health`
  - Portal API: `https://173.32.115.223:8000/portal/*`
  - Admin API: `https://173.32.115.223:8000/admin/*`

**Key Files**:
- Service file: `/etc/systemd/system/main_server.service`
- Environment: `/opt/message_broker/.env`
- Certificates: `/opt/message_broker/main_server/certs/`
- Logs: `journalctl -u main_server.service`

---

### 2. Portal Service (Web Interface)
- **Server IP**: `173.32.115.223` (same as main server)
- **SSH Port**: `2221`
- **Service Port**: `8080` (HTTP)
- **Installation Path**: `/opt/message_broker/portal/`
- **Service Name**: `portal.service`
- **Access URLs**:
  - Portal: `http://173.32.115.223:8080`
  - Portal (Domain): `http://msgportal.samsolutions.ir:8080`
  - Health: `http://173.32.115.223:8080/health`

**Key Files**:
- Service file: `/etc/systemd/system/portal.service`
- Environment: `/opt/message_broker/.env` (shared with main_server)
- Logs: `journalctl -u portal.service`

---

### 3. Proxy Service (Message Ingestion)
- **Server IP**: `91.92.206.217`
- **SSH Port**: `2221`
- **Service Port**: `443` (HTTPS)
- **Installation Path**: `/opt/message_broker_proxy/`
- **Service Name**: `proxy.service`
- **Redis**: `localhost:6379`
- **Access URLs**:
  - API: `https://91.92.206.217:443/api/v1/messages`
  - Health: `https://91.92.206.217:443/api/v1/health`
  - Metrics: `https://91.92.206.217:443/metrics`

**Key Files**:
- Service file: `/etc/systemd/system/proxy.service`
- Environment: `/opt/message_broker_proxy/proxy/.env`
- Certificates: `/opt/message_broker_proxy/proxy/certs/`
- Logs: `journalctl -u proxy.service`

---

### 4. Database (MySQL/MariaDB)
- **Server IP**: `173.32.115.223` (same as main server)
- **Port**: `3306`
- **Database Name**: `message_system`
- **Database User**: `systemuser`
- **Database Password**: `MsgBrckrTnN2025` (stored in `/opt/message_broker/.env`)

**Connection String**:
```
mysql+pymysql://systemuser:MsgBrckrTnN2025@localhost:3306/message_system
```

**Key Tables**:
- `users` - Portal users (admin, user roles)
- `clients` - Client certificates and configurations
- `messages` - Encrypted messages
- `audit_log` - System audit trail

---

## Service Health Checks

### Main Server Health Check

**Via SSH**:
```bash
ssh -p 2221 root@173.32.115.223 "curl -k https://localhost:8000/health"
```

**From Your PC** (using plink):
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "curl -k https://localhost:8000/health"
```

**Expected Response**:
```json
{
  "status": "healthy",
  "timestamp": "2025-12-31T15:30:00.000000",
  "components": {
    "database": "healthy",
    "encryption": "healthy"
  }
}
```

**Unhealthy Response**:
```json
{
  "status": "unhealthy",
  "timestamp": "2025-12-31T15:30:00.000000",
  "components": {
    "database": "unhealthy",
    "encryption": "healthy"
  }
}
```

**Check Service Status**:
```bash
ssh -p 2221 root@173.32.115.223 "systemctl status main_server.service"
```

**View Logs**:
```bash
ssh -p 2221 root@173.32.115.223 "journalctl -u main_server.service -n 50 --no-pager"
```

---

### Portal Service Health Check

**Via SSH**:
```bash
ssh -p 2221 root@173.32.115.223 "curl http://localhost:8080/health"
```

**From Your PC**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "curl http://localhost:8080/health"
```

**Expected Response**:
```json
{
  "status": "healthy",
  "services": {
    "main_server": "connected"
  }
}
```

**Note**: Portal health check verifies connectivity to the main server API.

**Check Service Status**:
```bash
ssh -p 2221 root@173.32.115.223 "systemctl status portal.service"
```

**View Logs**:
```bash
ssh -p 2221 root@173.32.115.223 "journalctl -u portal.service -n 50 --no-pager"
```

---

### Proxy Service Health Check

**Via SSH**:
```bash
ssh -p 2221 root@91.92.206.217 "curl -k https://localhost:443/api/v1/health"
```

**From Your PC**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "curl -k https://localhost:443/api/v1/health"
```

**Expected Response**:
```json
{
  "status": "healthy",
  "redis": "connected",
  "main_server": "reachable"
}
```

**Unhealthy Response**:
```json
{
  "status": "unhealthy",
  "redis": "disconnected",
  "main_server": "unreachable"
}
```

**Check Service Status**:
```bash
ssh -p 2221 root@91.92.206.217 "systemctl status proxy.service"
```

**View Logs**:
```bash
ssh -p 2221 root@91.92.206.217 "journalctl -u proxy.service -n 50 --no-pager"
```

**Check Redis Queue**:
```bash
ssh -p 2221 root@91.92.206.217 "redis-cli LLEN message_queue"
```

---

### Database Health Check

```bash
# Test Database Connection
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' -e 'SELECT 1' message_system"

# Check Database Status
ssh -p 2221 root@173.32.115.223 "systemctl status mysql.service"

# Check Table Counts
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system -e 'SELECT COUNT(*) as messages FROM messages; SELECT COUNT(*) as users FROM users; SELECT COUNT(*) as clients FROM clients;'"
```

---

## User Management

### Create Admin User

**Using PowerShell Script (Recommended)**:
```powershell
.\check_or_create_admin.ps1 -AdminEmail "admin@example.com" -AdminPassword "Admin123!"
```

**Using SSH Directly**:
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create admin@example.com --role admin --password 'Admin123!'"
```

**Using PowerShell with plink**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create admin@example.com --role admin --password 'Admin123!'"
```

### Create Regular User

**Important**: Regular users should be associated with a `client_id` to view messages. Users without a `client_id` will see no messages in the portal.

**Using SSH** (without client_id):
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create user@example.com --role user --password 'UserPass123!'"
```

**Using SSH** (with client_id - recommended):
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create user@example.com --role user --password 'UserPass123!' --client-id my_pc"
```

**Using PowerShell with plink** (without client_id):
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create user@example.com --role user --password 'UserPass123!'"
```

**Using PowerShell with plink** (with client_id - recommended):
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create user@example.com --role user --password 'UserPass123!' --client-id my_pc"
```

**Note**: The `client_id` must exist in the `clients` table. If the client doesn't exist, user creation will fail. See "Client Certificate Management" section for how to register clients.

### List Users

**Using SSH**:
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user list"
```

**Using PowerShell with plink**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user list"
```

### Delete User

**Using SSH**:
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user delete <user_id>"
```

**Using PowerShell with plink**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user delete <user_id>"
```

### Change User Password

**Using SSH**:
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user password <user_id> --password 'NewPassword123!'"
```

**Using PowerShell with plink**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user password <user_id> --password 'NewPassword123!'"
```

### User Roles

- **admin**: Full access to all features, can view all messages, manage users and clients
- **user**: Limited access, can only view messages for their associated client (requires `client_id` to be set). Users without a `client_id` will see no messages.

### Associating Users with Clients

Regular users must be associated with a `client_id` to view messages in the portal. This association links a user account to a specific client (identified by the client certificate's `client_id`).

**How it works**:
- When a user logs into the portal, the system filters messages based on their `client_id`
- Users see only messages where `Message.client_id` matches their `users.client_id`
- Admin users see all messages regardless of `client_id`
- Users without a `client_id` see no messages

**Creating a user with client_id**:
```bash
# The client must exist in the database first
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create user@example.com --role user --password 'Pass123!' --client-id my_pc"
```

**Updating an existing user's client_id** (using SQL):
```bash
# Update user's client_id
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system -e \"UPDATE users SET client_id = 'my_pc' WHERE email = 'user@example.com';\""

# Verify the update
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system -e \"SELECT id, email, role, client_id FROM users WHERE email = 'user@example.com';\""
```

**Important Notes**:
- The `client_id` must exist in the `clients` table before associating it with a user
- You can verify clients exist using: `admin_cli.py cert list`
- Multiple users can be associated with the same `client_id` (useful for team access)
- Changing a user's `client_id` immediately affects which messages they can see

### Default Admin Credentials

- **Email**: `admin@example.com`
- **Password**: `Admin123!`
- **Portal URL**: `http://173.32.115.223:8080` or `http://msgportal.samsolutions.ir:8080`

### Example: Create a New User Workflow

1. **Ensure the client exists** (if associating user with a client):
   ```powershell
   plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py cert list"
   ```
   The client must be registered in the database before you can associate a user with it.

2. **Create the user** (with client_id):
   ```powershell
   plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create newuser@example.com --role user --password 'SecurePass123!' --client-id my_pc"
   ```
   **Note**: Replace `my_pc` with an actual client_id that exists in the database. If you omit `--client-id`, the user will be created but won't see any messages.

3. **Verify user was created**:
   ```powershell
   plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user list"
   ```

4. **Test login** (from server):
   ```bash
   ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && python3 << 'PYEOF'
   import httpx
   response = httpx.post('https://localhost:8000/portal/auth/login', json={'email': 'newuser@example.com', 'password': 'SecurePass123!'}, verify=False)
   print('SUCCESS' if response.status_code == 200 else f'FAILED: {response.status_code}')
   PYEOF
   "
   ```

---

## Client Certificate Management

### Generate Client Certificate

**Using PowerShell Script**:
```powershell
.\generate_client_cert.ps1 -ClientName "my_client" -ServerAddress "173.32.115.223"
```

This will:
1. Download CA certificate from main server
2. Generate client private key
3. Create certificate signing request
4. Sign certificate on main server
5. Download signed certificate
6. Save files to `client-scripts\certs\`

**Generated Files**:
- `client-scripts\certs\my_client.crt` - Client certificate
- `client-scripts\certs\my_client.key` - Private key (KEEP SECRET!)
- `client-scripts\certs\ca.crt` - CA certificate

**Register Client in Database** (Required before sending messages):

After generating the certificate, you need to register the client in the database. Get the certificate fingerprint first:

**On Windows (PowerShell)**:
```powershell
# Get certificate fingerprint (removes colons and "SHA256 Fingerprint=" prefix)
$fingerprint = (openssl x509 -in client-scripts\certs\my_client.crt -noout -fingerprint -sha256) -replace '.*=', '' -replace ':', ''
Write-Host $fingerprint
```

**On Linux/Mac**:
```bash
# Get certificate fingerprint
openssl x509 -in client-scripts/certs/my_client.crt -noout -fingerprint -sha256 | sed 's/.*=//' | tr -d ':'
```

Then register the client using SQL:

```bash
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system -e \"INSERT INTO clients (client_id, cert_fingerprint, domain, status, issued_at, expires_at) VALUES ('my_client', 'FINGERPRINT_HERE', 'default', 'active', NOW(), DATE_ADD(NOW(), INTERVAL 365 DAY)) ON DUPLICATE KEY UPDATE cert_fingerprint='FINGERPRINT_HERE', status='active';\""
```

**Note**: Replace `FINGERPRINT_HERE` with the actual SHA-256 fingerprint from the command above.

**List Registered Clients**:
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py cert list"
```

---

## Sending Messages

### Prerequisites

1. **Client Certificate**: Generated and registered (see above)
2. **Proxy Server**: Running and accessible at `https://91.92.206.217:443`
3. **Client Registered**: Client ID must exist in database

### Method 1: PowerShell Script (Windows - Recommended)

```powershell
cd client-scripts
.\send_message.ps1 `
    -Sender "+1234567890" `
    -Message "Hello from my PC!" `
    -CertPath ".\certs\my_client.crt" `
    -KeyPath ".\certs\my_client.key" `
    -CaPath ".\certs\ca.crt" `
    -ProxyUrl "https://91.92.206.217:443"
```

**With Default Paths**:
```powershell
cd client-scripts
.\send_message.ps1 -Sender "+1234567890" -Message "Hello!" -ProxyUrl "https://91.92.206.217:443"
```

### Method 2: curl (Linux/Mac/WSL)

```bash
curl -X POST https://91.92.206.217:443/api/v1/messages \
  --cert client-scripts/certs/my_client.crt \
  --key client-scripts/certs/my_client.key \
  --cacert client-scripts/certs/ca.crt \
  -H "Content-Type: application/json" \
  -d '{
    "sender_number": "+1234567890",
    "message_body": "Hello from curl!"
  }'
```

### Method 3: Python Script

```bash
cd client-scripts
python send_message.py \
    --sender "+1234567890" \
    --message "Hello from Python!" \
    --cert certs/my_client.crt \
    --key certs/my_client.key \
    --ca certs/ca.crt \
    --proxy-url "https://91.92.206.217:443"
```

### Method 4: Using httpx (Python)

```python
import httpx

cert = ('client-scripts/certs/my_client.crt', 'client-scripts/certs/my_client.key')
data = {
    'sender_number': '+1234567890',
    'message_body': 'Hello from Python httpx!'
}

client = httpx.Client(cert=cert, verify='client-scripts/certs/ca.crt', timeout=10.0)
response = client.post('https://91.92.206.217:443/api/v1/messages', json=data)
print(f'Status: {response.status_code}')
print(f'Response: {response.json()}')
```

### Message Format Requirements

**Sender Number (E.164 Format)**:
- Must start with `+`
- Must include country code
- Only digits after the `+`
- Total length: 8-16 characters

**Valid Examples**:
- `+1234567890` ✅
- `+442012345678` ✅
- `+491234567890` ✅

**Invalid Examples**:
- `1234567890` ❌ (missing `+`)
- `+1-234-567-890` ❌ (contains dashes)
- `+1 234 567 890` ❌ (contains spaces)

**Message Body**:
- Required field
- Maximum length: 1000 characters
- Cannot be empty or whitespace-only

### Expected Response

**Success (202 Accepted)**:
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "client_id": "my_client",
  "queued_at": "2025-12-31T15:30:00Z",
  "position": 1
}
```

**Error Responses**:
- `400 Bad Request`: Invalid message format
- `401 Unauthorized`: Invalid or missing client certificate
- `429 Too Many Requests`: Rate limit exceeded (100 requests per 60 seconds)
- `500 Internal Server Error`: Server error
- `503 Service Unavailable`: Redis/main server unavailable

---

## Viewing Messages in Portal

### Access Portal

1. **Open Browser**: Navigate to `http://173.32.115.223:8080` or `http://msgportal.samsolutions.ir:8080`
2. **Login**: Use admin credentials
   - Email: `admin@example.com`
   - Password: `Admin123!`
3. **View Messages**:
   - **Admin View**: Go to `/admin/messages` to see all messages from all clients
   - **User View**: Go to `/dashboard` to see your messages

### Message Visibility Rules

The portal filters messages based on user role and client association:

- **Admin Users**: See all messages from all clients, regardless of any `client_id` association
- **Regular Users with `client_id`**: See only messages where `Message.client_id` matches their `users.client_id`
- **Regular Users without `client_id`**: See no messages (empty message list)

**Example**:
- If user `john@example.com` has `client_id = "my_pc"`, they will see all messages sent with `client_id = "my_pc"`
- If user `jane@example.com` has no `client_id` (NULL), they will see no messages
- Admin user `admin@example.com` will see all messages regardless of `client_id`

**To verify a user's client association**:
```bash
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system -e \"SELECT id, email, role, client_id FROM users WHERE email = 'user@example.com';\""
```

### Portal API (Programmatic Access)

**Login and Get Token**:
```bash
curl -k -X POST https://173.32.115.223:8000/portal/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"Admin123!"}'
```

**Get Messages**:
```bash
TOKEN="your_access_token_here"
curl -k -X GET "https://173.32.115.223:8000/portal/messages?skip=0&limit=20" \
  -H "Authorization: Bearer $TOKEN"
```

---

## Service Management

### Start Services

```bash
# Main Server
ssh -p 2221 root@173.32.115.223 "systemctl start main_server.service"

# Portal
ssh -p 2221 root@173.32.115.223 "systemctl start portal.service"

# Proxy
ssh -p 2221 root@91.92.206.217 "systemctl start proxy.service"
```

### Stop Services

```bash
# Main Server
ssh -p 2221 root@173.32.115.223 "systemctl stop main_server.service"

# Portal
ssh -p 2221 root@173.32.115.223 "systemctl stop portal.service"

# Proxy
ssh -p 2221 root@91.92.206.217 "systemctl stop proxy.service"
```

### Restart Services

```bash
# Main Server
ssh -p 2221 root@173.32.115.223 "systemctl restart main_server.service"

# Portal
ssh -p 2221 root@173.32.115.223 "systemctl restart portal.service"

# Proxy
ssh -p 2221 root@91.92.206.217 "systemctl restart proxy.service"
```

### Enable Services (Auto-start on boot)

```bash
ssh -p 2221 root@173.32.115.223 "systemctl enable main_server.service portal.service"
ssh -p 2221 root@91.92.206.217 "systemctl enable proxy.service"
```

---

## Troubleshooting

### Message Not Appearing in Portal

1. **Check Message in Database**:
   ```bash
   ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py message list --limit 10"
   ```

2. **Check Proxy Registration Logs**:
   ```bash
   ssh -p 2221 root@91.92.206.217 "journalctl -u proxy.service -n 50 --no-pager | grep -i 'register\|error'"
   ```

3. **Check Main Server Logs**:
   ```bash
   ssh -p 2221 root@173.32.115.223 "journalctl -u main_server.service -n 50 --no-pager | grep -i 'error\|register'"
   ```

### Certificate Issues

**Problem**: `401 Unauthorized` when sending messages

**Solutions**:
1. Verify client certificate exists and is valid:
   ```bash
   openssl x509 -in client-scripts/certs/my_client.crt -noout -dates
   ```

2. Check client is registered in database:
   ```bash
   ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py cert list"
   ```

3. Verify certificate fingerprint matches database:
   ```bash
   openssl x509 -in client-scripts/certs/my_client.crt -noout -fingerprint -sha256
   ```

### Database Connection Issues

**Problem**: Main server shows "database: unhealthy"

**Solutions**:
1. Check database is running:
   ```bash
   ssh -p 2221 root@173.32.115.223 "systemctl status mysql.service"
   ```

2. Verify database credentials in `.env`:
   ```bash
   ssh -p 2221 root@173.32.115.223 "cat /opt/message_broker/.env | grep DATABASE_URL"
   ```

3. Test database connection:
   ```bash
   ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' -e 'SELECT 1' message_system"
   ```

### Proxy Cannot Register Messages

**Problem**: Messages queued but not appearing in database

**Solutions**:
1. Check proxy can reach main server:
   ```bash
   ssh -p 2221 root@91.92.206.217 "curl -k https://173.32.115.223:8000/health"
   ```

2. Verify `MAIN_SERVER_VERIFY_SSL` setting:
   ```bash
   ssh -p 2221 root@91.92.206.217 "cat /opt/message_broker_proxy/proxy/.env | grep MAIN_SERVER"
   ```

3. Check proxy logs for registration errors:
   ```bash
   ssh -p 2221 root@91.92.206.217 "journalctl -u proxy.service -n 100 --no-pager | grep -i 'register\|main_server'"
   ```

---

## System Architecture

```
┌─────────────┐
│   Client    │
│  (Your PC)  │
└──────┬──────┘
       │ HTTPS + mTLS (Port 443)
       │ Client Certificate
       ▼
┌─────────────────────────────────┐
│      Proxy Server               │
│  91.92.206.217:443              │
│  - Validates client cert        │
│  - Validates message format     │
│  - Enqueues to Redis            │
│  - Registers with Main Server   │
└──────┬──────────────────────────┘
       │
       ├──► Redis Queue (localhost:6379)
       │
       └──► HTTPS (Port 8000)
            Main Server Registration
            ▼
┌─────────────────────────────────┐
│      Main Server                │
│  173.32.115.223:8000            │
│  - Receives registration        │
│  - Encrypts message             │
│  - Stores in MySQL              │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│      MySQL Database             │
│  localhost:3306                 │
│  - messages (encrypted)         │
│  - users                        │
│  - clients                      │
│  - audit_log                    │
└─────────────────────────────────┘
       │
       │ HTTP (Port 8080)
       ▼
┌─────────────────────────────────┐
│      Portal Service             │
│  173.32.115.223:8080            │
│  - Web interface                │
│  - Queries Main Server API      │
│  - Displays messages            │
└─────────────────────────────────┘
```

---

## Quick Start Guide

If you're new to the system, follow these steps in order:

1. **Verify Prerequisites** (see Prerequisites section above)
2. **Check All Services Are Running** (Step 1 below)
3. **Test Health Endpoints** (Step 2 below)
4. **Verify Database Connectivity** (Step 3 below)
5. **Test Portal Login** (Step 4 below)
6. **Test User Management** (Step 5 below)
7. **Send a Test Message** (Step 6 below)
8. **Verify Message in Database** (Step 7 below)

**Expected Time**: 15-30 minutes for complete testing

**Automated Testing**: You can also use the automated test script:
```powershell
.\test_deployment.ps1
```

This script runs all 7 steps automatically and provides a summary report.

**If a Step Fails**:
- Check the "Expected Result" for that step to see what should happen
- Review the "Troubleshooting" section below for common issues
- Check service logs using the commands in the "Service Management" section
- Verify prerequisites are met (tools installed, access working)

---

## Complete Testing Workflow

Follow these steps in order to verify the entire system is working correctly.

### Step 1: Verify All Services Are Running

**Purpose**: Ensure all required services are active before testing.

**Expected Result**: All services should show "RUNNING" or "active"

```bash
# Check Main Server
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "systemctl is-active main_server.service && echo 'Main Server: RUNNING' || echo 'Main Server: STOPPED'"

# Check Portal
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "systemctl is-active portal.service && echo 'Portal: RUNNING' || echo 'Portal: STOPPED'"

# Check Proxy
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "systemctl is-active proxy.service && echo 'Proxy: RUNNING' || echo 'Proxy: STOPPED'"

# Check Database
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "systemctl is-active mysql.service && echo 'Database: RUNNING' || echo 'Database: STOPPED'"
```

### Step 2: Test Health Endpoints

**Purpose**: Verify that all services are responding correctly to health check requests.

**Expected Result**: All health endpoints should return `"status": "healthy"`

```bash
# Main Server Health
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "curl -k -s https://localhost:8000/health | python3 -m json.tool"

# Portal Health
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "curl -s http://localhost:8080/health | python3 -m json.tool"

# Proxy Health
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "curl -k -s https://localhost:443/api/v1/health | python3 -m json.tool"
```

### Step 3: Verify Database Connectivity

**Purpose**: Confirm that the database is accessible and contains data.

**Expected Result**: Should show "Database: CONNECTED" with message, user, and client counts

```bash
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 << 'PYEOF'
import os
from dotenv import load_dotenv
load_dotenv('../.env')
from main_server.database import DatabaseManager
from sqlalchemy import text

db = DatabaseManager(os.getenv('DATABASE_URL'))
with db.get_session() as session:
    result = session.execute(text('SELECT COUNT(*) as count FROM messages'))
    count = result.fetchone()[0]
    print(f'Database: CONNECTED')
    print(f'Messages in database: {count}')
PYEOF
"
```

### Step 4: Test Portal Login

**Purpose**: Verify that the portal authentication system is working.

**Expected Result**: Should show "Login: SUCCESS" with user email, role, and token length

```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && python3 << 'PYEOF'
import httpx

response = httpx.post(
    'https://localhost:8000/portal/auth/login',
    json={'email': 'admin@example.com', 'password': 'Admin123!'},
    verify=False,
    timeout=10.0
)

if response.status_code == 200:
    data = response.json()
    print('Login: SUCCESS')
    user_data = data.get('user', {})
    print('User: ' + str(user_data.get('email')))
    print('Role: ' + str(user_data.get('role')))
    token = data.get('access_token', '')
    print('Token received: ' + str(len(token)) + ' characters')
else:
    print('Login: FAILED (Status: ' + str(response.status_code) + ')')
    print('Response: ' + response.text[:200])
PYEOF
"
```

### Step 5: Test User Management

**Purpose**: Verify that user creation, listing, and authentication work correctly.

**Expected Result**: Should successfully list users, create a test user, and allow login

**List Existing Users**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user list"
```

**Create a Test User** (with client_id):
```powershell
# First, verify a client exists (e.g., "my_pc")
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py cert list"

# Create user with client_id association
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create testuser@example.com --role user --password 'TestPass123!' --client-id my_pc"
```

**Note**: Replace `my_pc` with an actual client_id from the cert list. If you omit `--client-id`, the user will be created but won't see any messages.

**Test User Login** (from server):
```bash
ssh -p 2221 root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && python3 << 'PYEOF'
import httpx
response = httpx.post('https://localhost:8000/portal/auth/login', json={'email': 'testuser@example.com', 'password': 'TestPass123!'}, verify=False, timeout=10.0)
if response.status_code == 200:
    print('SUCCESS: User can login')
    data = response.json()
    print(f'User: {data.get(\"user\", {}).get(\"email\")}')
    print(f'Role: {data.get(\"user\", {}).get(\"role\")}')
    token = data.get('access_token')
    
    # Verify user can see messages for their client
    msg_response = httpx.get('https://localhost:8000/portal/messages?limit=10', headers={'Authorization': f'Bearer {token}'}, verify=False, timeout=10.0)
    if msg_response.status_code == 200:
        messages = msg_response.json()
        print(f'Messages visible to user: {len(messages)}')
        if messages:
            print(f'First message client_id: {messages[0].get(\"client_id\")}')
    else:
        print(f'Failed to fetch messages: {msg_response.status_code}')
else:
    print(f'FAILED: {response.status_code}')
PYEOF
"
```

**Verify User-Client Association**:
```bash
# Check user's client_id in database
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system -e \"SELECT id, email, role, client_id FROM users WHERE email = 'testuser@example.com';\""
```

### Step 6: Send Test Message

**Purpose**: Test the complete message sending workflow from client to proxy to database.

**Expected Result**: Should return status 202 with a message_id

**From Your PC (PowerShell)**:
```powershell
cd client-scripts
.\send_message.ps1 -Sender "+1234567890" -Message "Test message for health check" -ProxyUrl "https://91.92.206.217:443"
```

**Note**: If you encounter SSL errors on Windows, you can test from the server instead using Python:
```bash
# Test from proxy server (using query param for client_id)
ssh -p 2221 root@91.92.206.217 "cd /opt/message_broker_proxy && source venv/bin/activate && python3 << 'PYEOF'
import httpx
data = {'sender_number': '+1234567890', 'message_body': 'Test message'}
url = 'https://localhost:443/api/v1/messages?client_id=my_pc'
response = httpx.post(url, json=data, verify=False, timeout=10.0)
print(f'Status: {response.status_code}')
if response.status_code == 202:
    print('SUCCESS:', response.json().get('message_id'))
else:
    print('Error:', response.text[:200])
PYEOF
"
```

**Important**: The proxy currently uses a query parameter workaround (`?client_id=my_pc`) for client identification when client certificates cannot be extracted from the SSL connection. This is a temporary solution for testing. In production, proper mTLS with certificate extraction should be configured.

### Step 7: Verify Message in Database

**Purpose**: Confirm that the message sent in Step 6 was successfully stored in the database.

**Expected Result**: Should show recent messages including the one sent in Step 6

```bash
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 << 'PYEOF'
import os
from dotenv import load_dotenv
load_dotenv('../.env')
from main_server.database import DatabaseManager
from main_server.models import Message

db = DatabaseManager(os.getenv('DATABASE_URL'))
with db.get_session() as session:
    messages = session.query(Message).order_by(Message.created_at.desc()).limit(5).all()
    print(f'Recent messages ({len(messages)}):')
    for msg in messages:
        print(f'  - {msg.message_id[:12]}... | {msg.client_id} | {msg.status.value} | {msg.created_at}')
PYEOF
"
```

---

## Quick Reference

### Service URLs

| Service | URL | Port | Protocol |
|---------|-----|------|----------|
| Main Server API | `https://173.32.115.223:8000` | 8000 | HTTPS |
| Portal Web UI | `http://173.32.115.223:8080` | 8080 | HTTP |
| Proxy API | `https://91.92.206.217:443` | 443 | HTTPS |
| Database | `localhost:3306` | 3306 | MySQL |

### Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| Portal Admin | `admin@example.com` | `Admin123!` |
| Database | `systemuser` | `MsgBrckrTnN2025` |
| SSH (Main) | `root` | `Pc$123456` |
| SSH (Proxy) | `root` | `Pc$123456` |

### Important Paths

| Component | Path |
|-----------|------|
| Main Server | `/opt/message_broker/main_server/` |
| Portal | `/opt/message_broker/portal/` |
| Proxy | `/opt/message_broker_proxy/proxy/` |
| Shared .env | `/opt/message_broker/.env` |
| Proxy .env | `/opt/message_broker_proxy/proxy/.env` |
| Client Certs | `./client-scripts/certs/` |

### Common Commands

**Check All Services Status**:
```powershell
# Main Server & Portal
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "systemctl status main_server.service portal.service --no-pager | head -20"

# Proxy
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "systemctl status proxy.service --no-pager | head -20"
```

**View Recent Logs**:
```powershell
# Main Server
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "journalctl -u main_server.service -n 20 --no-pager"

# Portal
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "journalctl -u portal.service -n 20 --no-pager"

# Proxy
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "journalctl -u proxy.service -n 20 --no-pager"
```

**Check Database**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system -e 'SELECT COUNT(*) as messages FROM messages; SELECT COUNT(*) as users FROM users; SELECT COUNT(*) as clients FROM clients;'"
```

**Check Redis Queue**:
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "redis-cli LLEN message_queue"
```

**View Queue Contents** (for debugging):
```powershell
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "redis-cli LRANGE message_queue 0 4"
```

---

## Security Notes

⚠️ **Important Security Reminders**:

- ⚠️ **Never commit certificates to version control**
- ⚠️ **Keep private keys secure** - Never share `*.key` files
- ⚠️ **Use secure networks** when sending messages
- ⚠️ **Rotate certificates periodically** (as per organization policy)
- ⚠️ **Change default passwords** in production
- ⚠️ **Use strong passwords** for database and admin accounts
- ⚠️ **Enable firewall rules** to restrict access to service ports
- ⚠️ **Monitor audit logs** regularly for suspicious activity

---

## Monitoring & Metrics

### Prometheus Metrics

**Main Server Metrics**:
- Endpoint: `https://173.32.115.223:8000/metrics`
- Metrics include: request counts, database connections, message counts

**Proxy Metrics**:
- Endpoint: `https://91.92.206.217:443/metrics`
- Metrics include: request rates, queue size, certificate validations, error counts

### Key Metrics to Monitor

1. **Queue Size**: Should remain low (< 100 messages typically)
   ```bash
   plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "redis-cli LLEN message_queue"
   ```

2. **Message Registration Success Rate**: Check proxy logs for registration failures
   ```bash
   plink -P 2221 -ssh -batch -pw "Pc`$123456" root@91.92.206.217 "journalctl -u proxy.service --since '1 hour ago' --no-pager | grep -c 'Failed to register'"
   ```

3. **Database Connection Pool**: Monitor main server logs for connection errors
   ```bash
   plink -P 2221 -ssh -batch -pw "Pc`$123456" root@173.32.115.223 "journalctl -u main_server.service --since '1 hour ago' --no-pager | grep -i 'database.*error'"
   ```

---

## Backup & Recovery

### Database Backup

```bash
# Create backup
ssh -p 2221 root@173.32.115.223 "mysqldump -u systemuser -p'MsgBrckrTnN2025' message_system > /tmp/message_system_backup_$(date +%Y%m%d).sql"

# Restore from backup
ssh -p 2221 root@173.32.115.223 "mysql -u systemuser -p'MsgBrckrTnN2025' message_system < /tmp/message_system_backup_YYYYMMDD.sql"
```

### Certificate Backup

```bash
# Backup CA and server certificates
ssh -p 2221 root@173.32.115.223 "tar -czf /tmp/certs_backup_$(date +%Y%m%d).tar.gz /opt/message_broker/main_server/certs/"
ssh -p 2221 root@91.92.206.217 "tar -czf /tmp/proxy_certs_backup_$(date +%Y%m%d).tar.gz /opt/message_broker_proxy/proxy/certs/"
```

---

## Support

For issues or questions:
1. Check service logs using `journalctl`
2. Verify service health using health check endpoints
3. Review this documentation
4. Check troubleshooting section above
5. Contact system administrator

---

## Appendix: Service Dependencies

### Service Startup Order

1. **Database** (MySQL) - Must start first
2. **Main Server** - Depends on database
3. **Portal** - Depends on main server
4. **Proxy** - Independent, but needs main server for registration

### Port Requirements

| Port | Service | Protocol | Access |
|------|---------|----------|--------|
| 2221 | SSH | TCP | Remote management |
| 3306 | MySQL | TCP | Local only |
| 6379 | Redis | TCP | Local only (proxy server) |
| 8000 | Main Server API | HTTPS | Internal + External |
| 8080 | Portal Web UI | HTTP | Internal + External |
| 443 | Proxy API | HTTPS | External (clients) |

---

**Last Updated**: December 31, 2025  
**Version**: 1.0

