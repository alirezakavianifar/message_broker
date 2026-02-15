# Message Broker System - Administrator Manual

**Version**: 1.0.0  
**Platform**: Windows Server 2019/2022  
**Last Updated**: October 2025  
**Audience**: System Administrators

---

## Table of Contents

1. [Introduction](#introduction)
2. [Administrative Access](#administrative-access)
3. [User Management](#user-management)
4. [Client Management](#client-management)
5. [Certificate Management](#certificate-management)
6. [Message Management](#message-management)
7. [System Configuration](#system-configuration)
8. [Monitoring & Reports](#monitoring--reports)
9. [Security Administration](#security-administration)
10. [Troubleshooting](#troubleshooting)

---

## Introduction

The Message Broker System provides a secure message routing platform with mutual TLS authentication and encrypted storage. As an administrator, you have full access to manage users, clients, certificates, and system configuration.

### Admin Responsibilities

- User account management
- Client certificate issuance and revocation
- System monitoring and health checks
- Security audit and compliance
- System configuration updates
- Backup verification
- Troubleshooting and support

###  Accessing Admin Tools

1. **Web Portal**: `https://your-server:5000/admin`
2. **Command Line**: `C:\MessageBroker\main_server\admin_cli.py`
3. **Database Direct**: MySQL client (for advanced operations)

---

## Administrative Access

### Web Portal Admin Login

1. Navigate to: `https://your-server:5000`
2. Click "Admin Login"
3. Enter credentials:
   - **Email**: Your admin email
   - **Password**: Your admin password
4. Access admin dashboard

### Command Line Admin Tool

```powershell
cd C:\MessageBroker\main_server
..\venv\Scripts\Activate.ps1
python admin_cli.py

```

**Available Commands**:
```
users create      - Create new user
users list        - List all users
users update      - Update user details
users delete      - Delete user
certs generate    - Generate client certificate
certs revoke      - Revoke client certificate
certs list        - List all certificates
messages list     - View messages
messages stats    - Message statistics
system stats      - System statistics
```

### First-Time Admin Setup

If no admin exists, create one:

```powershell
cd C:\MessageBroker\main_server
python admin_cli.py users create --email admin@yourcompany.com --password SecurePassword123! --role admin
```

---

## User Management

### Create New User

**Via Web Portal**:
1. Login to admin portal
2. Navigate to "Users" → "Add User"
3. Fill in details:
   - Email (unique)
   - Password (min 8 characters)
   - Role (user or admin)
   - Client ID (for regular users)
4. Click "Create User"

**Via Command Line**:
```powershell
python admin_cli.py users create --email user@company.com --password UserPass123! --role user --client-id client_001
```

### List Users

**Via Web Portal**:
- Navigate to "Users" → "All Users"
- View table with email, role, client_id, last login

**Via Command Line**:
```powershell
python admin_cli.py users list
```

### Update User

**Via Web Portal**:
1. Navigate to "Users" → Find user
2. Click "Edit"
3. Update fields (email, password, role)
4. Click "Save"

**Via Command Line**:
```powershell
# Change password
python admin_cli.py users update --email user@company.com --password NewPassword123!

# Change role
python admin_cli.py users update --email user@company.com --role admin

# Change client assignment
python admin_cli.py users update --email user@company.com --client-id new_client_id
```

### Delete User

**Via Web Portal**:
1. Navigate to "Users" → Find user
2. Click "Delete"
3. Confirm deletion

**Via Command Line**:
```powershell
python admin_cli.py users delete --email user@company.com
```

### Reset User Password

**Via Web Portal**:
1. Navigate to "Users" → Find user
2. Click "Reset Password"
3. Enter new password
4. Click "Update"

**Via Command Line**:
```powershell
python admin_cli.py users update --email user@company.com --password NewPassword123!
```

---

## Client Management

### View Clients

**Via Web Portal**:
- Navigate to "Clients"
- View all registered clients with:
  - Client ID
  - Certificate fingerprint
  - Status (active/revoked/expired)
  - Created date
  - Message count

**Via Command Line**:
```powershell
python admin_cli.py certs list
```

**Via Database**:
```sql
mysql -u systemuser -p message_system

SELECT 
    client_id,
    status,
    cert_fingerprint,
    created_at,
    (SELECT COUNT(*) FROM messages WHERE messages.client_id = clients.client_id) as message_count
FROM clients
ORDER BY created_at DESC;
```

### Client Statistics

**Via Web Portal**:
- Navigate to "Clients" → Click client ID
- View statistics:
  - Total messages sent
  - Messages delivered
  - Messages pending
  - Messages failed
  - Last activity

**Via Command Line**:
```powershell
python admin_cli.py messages stats --client-id client_001
```

---

## Certificate Management

### Generate Client Certificate

**Via Web Portal**:
1. Navigate to "Certificates" → "Generate Certificate"
2. Enter details:
   - Client ID (unique)
   - Domain name
   - Validity days (default: 365)
3. Click "Generate"
4. Download certificate bundle:
   - client_id.crt (certificate)
   - client_id.key (private key)
   - ca.crt (CA certificate)

**Via Command Line**:
```powershell
cd C:\MessageBroker\main_server

# Generate certificate
.\generate_cert.bat client_name domain.com 365

# Files created in certs\ directory:
# - client_name.crt
# - client_name.key
```

**Distributing Certificates**:

Send to client securely:
1. `client_name.crt` - Client certificate
2. `client_name.key` - Private key (⚠️ KEEP SECURE)
3. `ca.crt` - CA certificate

### Revoke Client Certificate

**Via Web Portal**:
1. Navigate to "Certificates"
2. Find certificate to revoke
3. Click "Revoke"
4. Confirm revocation
5. Services will automatically reload CRL

**Via Command Line**:
```powershell
cd C:\MessageBroker\main_server

# Revoke certificate
.\revoke_cert.bat client_name

# Restart services to reload CRL
Restart-Service MessageBrokerProxy
Restart-Service MessageBrokerMainServer
```

### Renew Certificate

**Via Command Line**:
```powershell
cd C:\MessageBroker\main_server

# Renew certificate (same client_id, new validity)
.\renew_cert.bat client_name 365

# Distribute new certificate to client
```

### List All Certificates

**Via Web Portal**:
- Navigate to "Certificates"
- View all certificates with status

**Via Command Line**:
```powershell
cd C:\MessageBroker\main_server
.\list_certs.bat
```

### Check Certificate Expiry

```powershell
cd C:\MessageBroker\main_server

# Check specific certificate
openssl x509 -in certs\client_name.crt -noout -dates

# Check all certificates
Get-ChildItem certs\*.crt | ForEach-Object {
    Write-Host "`n$($_.Name):" -ForegroundColor Cyan
    openssl x509 -in $_.FullName -noout -dates
}
```

---

## Message Management

### View All Messages

**Via Web Portal**:
1. Navigate to "Messages"
2. Filter by:
   - Date range
   - Client ID
   - Status (pending/delivered/failed)
   - Sender number (hashed)
3. View message details (body encrypted)

**Via Command Line**:
```powershell
python admin_cli.py messages list --limit 50
```

**Via Database**:
```sql
mysql -u systemuser -p message_system

-- Recent messages
SELECT 
    id,
    message_id,
    client_id,
    status,
    created_at,
    delivered_at
FROM messages 
ORDER BY created_at DESC 
LIMIT 50;

-- Messages by status
SELECT 
    status,
    COUNT(*) as count
FROM messages 
GROUP BY status;
```

### Search Messages

**Via Web Portal**:
1. Navigate to "Messages" → "Search"
2. Enter search criteria:
   - Client ID
   - Date range
   - Status
3. View results

**Via Command Line**:
```powershell
# By client
python admin_cli.py messages list --client-id client_001

# By date
python admin_cli.py messages list --date 2025-10-20

# By status
python admin_cli.py messages list --status delivered
```

### Message Statistics

**Via Web Portal**:
- Navigate to "Dashboard"
- View statistics:
  - Total messages (today/week/month)
  - Delivery rate
  - Average delivery time
  - Error rate

**Via Command Line**:
```powershell
python admin_cli.py messages stats
```

**Via Database**:
```sql
-- Daily statistics
SELECT 
    DATE(created_at) as date,
    COUNT(*) as total,
    SUM(CASE WHEN status='delivered' THEN 1 ELSE 0 END) as delivered,
    SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) as pending,
    SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) as failed
FROM messages 
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

### Delete Old Messages

**⚠️ WARNING**: This permanently deletes messages!

```sql
mysql -u systemuser -p message_system

-- Delete messages older than 90 days
DELETE FROM messages 
WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY);

-- Verify deletion
SELECT COUNT(*) FROM messages;

-- Optimize table to reclaim space
OPTIMIZE TABLE messages;
```

---

## System Configuration

### Update Environment Configuration

**Edit `.env` file**:

```powershell
notepad C:\MessageBroker\.env
```

**Important Settings**:

```env
# Database
DATABASE_URL=mysql+pymysql://systemuser:password@localhost/message_system

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Security
JWT_SECRET=your_secret_key
ENCRYPTION_KEY_PATH=secrets/encryption.key

# Logging
LOG_LEVEL=INFO

# Workers
WORKER_COUNT=4
WORKER_RETRY_INTERVAL_SECONDS=30
```

**After changes**:
```powershell
# Restart services to apply
Get-Service MessageBroker* | Restart-Service
```

### Update Component Configuration

**Proxy Configuration** (`proxy/config.yaml`):
```yaml
redis:
  host: localhost
  port: 6379
  queue_name: message_queue

main_server:
  url: https://localhost:8000
  verify_ssl: true

logging:
  level: INFO
  rotation: daily
```

**Worker Configuration** (`worker/config.yaml`):
```yaml
redis:
  host: localhost
  port: 6379

worker:
  count: 4
  retry_interval: 30
  max_retries: 10000

logging:
  level: INFO
```

**After changes**:
```powershell
Restart-Service MessageBrokerProxy
Restart-Service MessageBrokerWorker
```

### Database Configuration

**MySQL Configuration** (`C:\ProgramData\MySQL\MySQL Server 8.0\my.ini`):

```ini
[mysqld]
# Performance
max_connections = 200
innodb_buffer_pool_size = 2G

# Security
bind-address = 127.0.0.1

# Logging
slow_query_log = 1
long_query_time = 2
```

**After changes**:
```powershell
net stop MySQL
net start MySQL
```

---

## Monitoring & Reports

### System Dashboard

**Via Web Portal**:
- Navigate to "Dashboard"
- View real-time statistics:
  - Service status
  - Message throughput
  - Queue length
  - Error rate
  - System resources

### Generate Reports

**Message Delivery Report**:
```sql
mysql -u systemuser -p message_system

-- Daily delivery report
SELECT 
    DATE(created_at) as date,
    client_id,
    COUNT(*) as total_messages,
    SUM(CASE WHEN status='delivered' THEN 1 ELSE 0 END) as delivered,
    ROUND(SUM(CASE WHEN status='delivered' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) as delivery_rate
FROM messages
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY DATE(created_at), client_id
ORDER BY date DESC, client_id;
```

**Export to CSV**:
```powershell
mysql -u systemuser -p message_system -e "SELECT * FROM messages WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)" > report.csv
```

### Audit Logs

**View Audit Trail**:
```sql
mysql -u systemuser -p message_system

SELECT 
    created_at,
    user_id,
    action,
    details
FROM audit_log 
ORDER BY created_at DESC 
LIMIT 100;
```

---

## Security Administration

### Change Admin Password

**Via Web Portal**:
1. Login to admin portal
2. Navigate to "Profile" → "Change Password"
3. Enter current and new password
4. Click "Update"

**Via Command Line**:
```powershell
python admin_cli.py users update --email admin@company.com --password NewPassword123!
```

### Update JWT Secret

**⚠️ WARNING**: This will invalidate all existing sessions!

1. Generate new secret:
   ```powershell
   python -c "import secrets; print(secrets.token_urlsafe(64))"
   ```

2. Update `.env`:
   ```env
   JWT_SECRET=new_secret_key_here
   ```

3. Restart services:
   ```powershell
   Restart-Service MessageBrokerMainServer
   Restart-Service MessageBrokerPortal
   ```

### Rotate Encryption Key

**⚠️ WARNING**: This requires re-encrypting all messages!

This is an advanced operation - contact development team for assistance.

### Review Security Logs

```powershell
# Failed login attempts
Get-Content C:\MessageBroker\logs\portal.log | Select-String "login failed"

# Certificate errors
Get-Content C:\MessageBroker\logs\proxy.log | Select-String "certificate|SSL"

# Database errors
Get-Content C:\MessageBroker\logs\main_server.log | Select-String "ERROR"
```

---

## Troubleshooting

### User Can't Login

**Check**:
1. User exists in database:
   ```sql
   SELECT * FROM users WHERE email = 'user@company.com';
   ```

2. Password correct (reset if needed)

3. Portal service running:
   ```powershell
   Get-Service MessageBrokerPortal
   ```

### Client Can't Send Messages

**Note**: Clients can use **any HTTP client** - Python is NOT required. Recommend using curl (no dependencies):
```bash
curl -X POST https://your-server:8001/api/v1/messages \
  --cert client.crt --key client.key --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{"sender_number": "+1234567890", "message_body": "Test message"}'
```

**Check**:
1. Certificate valid:
   ```powershell
   openssl x509 -in client.crt -noout -dates
   ```

2. Certificate not revoked:
   ```powershell
   cd C:\MessageBroker\main_server
   Get-Content crl\revoked.pem
   ```

3. Proxy service running:
   ```powershell
   Get-Service MessageBrokerProxy
   ```

4. If client has Python/dependency issues, direct them to use curl instead

### Messages Not Being Delivered

**Check**:
1. Queue length:
   ```powershell
   memurai-cli LLEN message_queue
   ```

2. Worker running:
   ```powershell
   Get-Service MessageBrokerWorker
   ```

3. Main server accessible:
   ```powershell
   curl https://localhost:8000/health -k
   ```

4. Worker logs:
   ```powershell
   Get-Content C:\MessageBroker\logs\worker.log -Tail 50
   ```

---

## Best Practices

### Daily Tasks
- [ ] Check service status
- [ ] Review error logs
- [ ] Monitor queue length
- [ ] Verify backup completed

### Weekly Tasks
- [ ] Review user access
- [ ] Check certificate expiry dates
- [ ] Review system performance
- [ ] Clean up old logs

### Monthly Tasks
- [ ] Review and update users
- [ ] Audit client certificates
- [ ] Review message statistics
- [ ] Update system documentation
- [ ] Test backup restoration

### Security Best Practices
- Use strong passwords (12+ characters, mixed case, numbers, symbols)
- Rotate passwords every 90 days
- Review audit logs regularly
- Keep certificates up to date
- Limit admin access to necessary personnel
- Use principle of least privilege
- Keep system updated and patched

---

## Appendix

### Quick Commands Reference

```powershell
# User management
python admin_cli.py users list
python admin_cli.py users create --email user@test.com --password Pass123!

# Certificate management
.\generate_cert.bat client_name domain.com 365
.\revoke_cert.bat client_name
.\list_certs.bat

# System status
Get-Service MessageBroker*
cd deployment\tests ; .\smoke_test.ps1

# Database queries
mysql -u systemuser -p message_system -e "SELECT COUNT(*) FROM messages"

# Logs
Get-Content C:\MessageBroker\logs\*.log -Tail 50
```

### Support Contacts

**Technical Support**: support@yourcompany.com  
**Security Issues**: security@yourcompany.com  
**Emergency**: [Phone Number]

---

**Document Version**: 1.0.0  
**Last Updated**: October 2025  
**Next Review**: January 2026

