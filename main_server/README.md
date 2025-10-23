

# Message Broker Main Server

The main server is the central component of the message broker system, providing:
- **Internal API** for proxy and worker communication (mutual TLS)
- **Admin API** for certificate and user management
- **Portal API** for web interface authentication and message viewing
- **Database management** with MySQL and SQLAlchemy
- **Message encryption** at rest with AES-256

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [API Endpoints](#api-endpoints)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Admin CLI](#admin-cli)
- [Database Management](#database-management)
- [Security](#security)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Production Deployment](#production-deployment)

---

## Overview

The main server acts as the central hub for:

1. **Message Registration**: Proxy calls `/internal/messages/register` when messages are enqueued
2. **Message Delivery Tracking**: Workers call `/internal/messages/deliver` when messages are delivered
3. **Status Updates**: Workers update message status during retry cycles
4. **Certificate Management**: Admin generates and revokes client certificates
5. **User Management**: Admin creates and manages portal users
6. **Portal Authentication**: JWT-based authentication for web portal
7. **Statistics and Monitoring**: Prometheus metrics and health checks

### Data Flow

```
Proxy ──mutual TLS──> Main Server ──> MySQL (encrypted storage)
                            ↑
Worker ──mutual TLS──────────┘
                            
Portal ──JWT Auth──> Main Server ──> Message decryption (admin only)
```

---

## Features

### Core Features

✅ **Internal API (Mutual TLS)**
- Message registration from proxy
- Message delivery confirmation from worker
- Status updates during retry cycles
- Certificate-based authentication

✅ **Portal API (JWT Authentication)**
- User login with email/password
- Token refresh mechanism
- Message viewing (encrypted bodies)
- User profile management

✅ **Admin API (Role-Based Access)**
- User creation and management
- Certificate generation and revocation
- System statistics
- Audit logging

✅ **Database Management**
- MySQL with SQLAlchemy ORM
- Connection pooling
- Migration support with Alembic
- Health checks and monitoring

✅ **Security**
- AES-256 message encryption at rest
- SHA-256 phone number hashing
- JWT tokens with configurable expiration
- Password hashing with bcrypt
- Mutual TLS for internal communication

✅ **Monitoring**
- Prometheus metrics
- Health check endpoint
- Request tracking
- Database connection monitoring
- Audit log for all operations

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Main Server (FastAPI)                    │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │ Internal API │  │  Portal API  │  │   Admin API      │ │
│  │ (mTLS)       │  │ (JWT)        │  │   (JWT + Role)   │ │
│  │              │  │              │  │                  │ │
│  │ - Register   │  │ - Login      │  │ - Users          │ │
│  │ - Deliver    │  │ - Messages   │  │ - Certificates   │ │
│  │ - Status     │  │ - Profile    │  │ - Statistics     │ │
│  └──────────────┘  └──────────────┘  └──────────────────┘ │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Database Layer (SQLAlchemy)              │  │
│  │  - Connection pooling  - Session management          │  │
│  │  - ORM models          - Health checks               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Encryption Layer (Fernet/SHA-256)           │  │
│  │  - AES-256 encryption  - Phone number hashing        │  │
│  │  - Key management      - Masked display              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Monitoring (Prometheus)                  │  │
│  │  - Request metrics     - Message metrics             │  │
│  │  - DB metrics          - Certificate metrics         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                        ↓
            ┌───────────────────────┐
            │   MySQL Database      │
            │                       │
            │ - messages (encrypted)│
            │ - users               │
            │ - clients             │
            │ - audit_log           │
            └───────────────────────┘
```

---

## API Endpoints

### Internal API (Mutual TLS Required)

| Method | Endpoint | Description | Called By |
|--------|----------|-------------|-----------|
| POST | `/internal/messages/register` | Register new message | Proxy |
| POST | `/internal/messages/deliver` | Mark message as delivered | Worker |
| PUT | `/internal/messages/{id}/status` | Update message status | Worker |

### Portal API (JWT Authentication Required)

| Method | Endpoint | Description | Access |
|--------|----------|-------------|--------|
| POST | `/portal/auth/login` | User login | Public |
| POST | `/portal/auth/refresh` | Refresh access token | Authenticated |
| GET | `/portal/messages` | List messages | User/Admin |
| GET | `/portal/profile` | Get user profile | Authenticated |

### Admin API (Admin Role Required)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/admin/certificates/generate` | Generate client certificate |
| POST | `/admin/certificates/revoke` | Revoke client certificate |
| POST | `/admin/users` | Create new user |
| GET | `/admin/users` | List all users |
| GET | `/admin/stats` | System statistics |

### Monitoring

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/metrics` | Prometheus metrics |
| GET | `/` | Server info |
| GET | `/docs` | Swagger UI |
| GET | `/redoc` | ReDoc UI |

---

## Installation

### Prerequisites

- Python 3.8+
- MySQL 8.0+
- OpenSSL for certificate management

### Windows Setup

1. **Create virtual environment**:
   ```powershell
   cd main_server
   python -m venv venv
   .\venv\Scripts\Activate.ps1
   ```

2. **Install dependencies**:
   ```powershell
   pip install -r requirements.txt
   ```

3. **Setup MySQL database**:
   ```sql
   CREATE DATABASE message_system CHARACTER SET utf8mb4;
   CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'StrongPass123!';
   GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
   FLUSH PRIVILEGES;
   ```

4. **Run database migrations**:
   ```powershell
   alembic upgrade head
   ```

5. **Initialize Certificate Authority**:
   ```powershell
   .\init_ca.bat
   ```

6. **Generate server certificate**:
   ```powershell
   .\generate_cert.bat server
   ```

7. **Create encryption key**:
   ```powershell
   mkdir secrets
   python -c "from cryptography.fernet import Fernet; open('secrets/encryption.key', 'wb').write(Fernet.generate_key())"
   ```

8. **Create admin user**:
   ```powershell
   python admin_cli.py user create admin@example.com --role admin
   ```

### Linux Setup

1. **Create virtual environment**:
   ```bash
   cd main_server
   python3 -m venv venv
   source venv/bin/activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Setup MySQL** (same as Windows)

4. **Run migrations**:
   ```bash
   alembic upgrade head
   ```

5. **Initialize CA and generate certificates**:
   ```bash
   ./init_ca.sh
   ./generate_cert.sh server
   ```

6. **Create encryption key**:
   ```bash
   mkdir -p secrets
   python3 -c "from cryptography.fernet import Fernet; open('secrets/encryption.key', 'wb').write(Fernet.generate_key())"
   chmod 600 secrets/encryption.key
   ```

7. **Create admin user**:
   ```bash
   python3 admin_cli.py user create admin@example.com --role admin
   ```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `mysql+pymysql://...` | MySQL connection string |
| `MAIN_SERVER_HOST` | `0.0.0.0` | Server bind address |
| `MAIN_SERVER_PORT` | `8000` | Server port |
| `JWT_SECRET` | _(required)_ | JWT signing secret |
| `JWT_EXPIRATION_HOURS` | `24` | Access token expiration |
| `ENCRYPTION_KEY_PATH` | `secrets/encryption.key` | Encryption key file |
| `HASH_SALT` | _(required)_ | Salt for phone number hashing |
| `CA_CERT_PATH` | `certs/ca.crt` | CA certificate |
| `SERVER_CERT_PATH` | `certs/server.crt` | Server certificate |
| `SERVER_KEY_PATH` | `certs/server.key` | Server private key |
| `CRL_PATH` | `crl/revoked.pem` | Certificate Revocation List |
| `LOG_LEVEL` | `INFO` | Logging level |
| `LOG_FILE_PATH` | `logs` | Log directory |
| `METRICS_ENABLED` | `true` | Enable Prometheus metrics |

### .env File Example

```env
# Database
DATABASE_URL=mysql+pymysql://systemuser:StrongPass123!@localhost/message_system

# Server
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000

# Security
JWT_SECRET=your-secret-key-change-in-production
HASH_SALT=your-salt-change-in-production

# Paths
ENCRYPTION_KEY_PATH=secrets/encryption.key
CA_CERT_PATH=certs/ca.crt
SERVER_CERT_PATH=certs/server.crt
SERVER_KEY_PATH=certs/server.key

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=logs
```

---

## Usage

### Starting the Server

#### Windows (Batch)
```cmd
cd main_server
start_server.bat
```

#### Windows (PowerShell)
```powershell
cd main_server
.\start_server.ps1 -Port 8000 -LogLevel INFO
```

**PowerShell Parameters**:
- `-Host`: Bind address (default: 0.0.0.0)
- `-Port`: Port number (default: 8000)
- `-LogLevel`: Log level (default: INFO)
- `-NoTLS`: Disable TLS (development only)
- `-Reload`: Enable auto-reload (development only)

#### Linux
```bash
cd main_server
python3 api.py
```

Or with systemd:
```bash
sudo systemctl start main_server
```

### Accessing the Server

- **API Documentation**: https://localhost:8000/docs
- **ReDoc**: https://localhost:8000/redoc
- **Health Check**: https://localhost:8000/health
- **Metrics**: https://localhost:8000/metrics

---

## Admin CLI

The admin CLI (`admin_cli.py`) provides command-line management:

### User Management

```powershell
# List users
python admin_cli.py user list

# Create user
python admin_cli.py user create user@example.com --role user
python admin_cli.py user create admin@example.com --role admin

# Delete user
python admin_cli.py user delete 1 --force

# Change password
python admin_cli.py user password 1
```

### Certificate Management

```powershell
# List certificates
python admin_cli.py cert list
python admin_cli.py cert list --status active

# Revoke certificate
python admin_cli.py cert revoke client_123 --reason "Compromised" --force
```

### Message Management

```powershell
# List messages
python admin_cli.py message list
python admin_cli.py message list --client test_client
python admin_cli.py message list --status delivered --limit 50

# View message details
python admin_cli.py message view <message_uuid>
python admin_cli.py message view <message_uuid> --decrypt
```

### System Statistics

```powershell
# Show statistics
python admin_cli.py stats
```

**Output**:
```
System Statistics
==================================================

Messages:
  Total: 12,345
  Queued: 234
  Delivered: 12,000
  Failed: 111
  Last 24 hours: 1,456
  Last 7 days: 9,876

Clients:
  Total: 45
  Active: 42
  Revoked: 3

Users:
  Total: 8
```

---

## Database Management

### Migrations

The project uses Alembic for database migrations:

```powershell
# Apply migrations
alembic upgrade head

# Create new migration
alembic revision --autogenerate -m "Add new column"

# Rollback
alembic downgrade -1

# Show current version
alembic current

# Show migration history
alembic history
```

### Direct SQL Access

```powershell
# Connect to database
mysql -u systemuser -p message_system

# Useful queries
SELECT COUNT(*) FROM messages WHERE status = 'delivered';
SELECT client_id, COUNT(*) as total FROM messages GROUP BY client_id;
SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 10;
```

### Backup and Restore

```powershell
# Backup database
mysqldump -u systemuser -p message_system > backup_$(date +%Y%m%d).sql

# Restore database
mysql -u systemuser -p message_system < backup_20250115.sql
```

---

## Security

### Message Encryption

All message bodies are encrypted at rest using AES-256 (Fernet):

```python
# Encryption happens automatically
encrypted_body = encryption_manager.encrypt("Message text")

# Decryption (admin only)
message_text = encryption_manager.decrypt(encrypted_body)
```

### Phone Number Privacy

Phone numbers are hashed with SHA-256:

```python
# Hash for storage
hashed = encryption_manager.hash_phone_number("+4915200000000")

# Display masked version
masked = encryption_manager.mask_phone_number(hashed)  # "+4915****0000"
```

### Password Security

- Passwords hashed with bcrypt
- Minimum 8 characters
- Stored as irreversible hash

### JWT Tokens

```python
# Token payload
{
  "sub": "user_id",
  "email": "user@example.com",
  "role": "admin",
  "exp": 1705334400  # Expiration timestamp
}
```

**Token Expiration**:
- Access tokens: 24 hours (configurable)
- Refresh tokens: 30 days (configurable)

### Certificate Management

- Mutual TLS for internal API
- Certificate revocation list (CRL)
- Per-client certificates
- Automatic expiration checking

---

## Monitoring

### Prometheus Metrics

```
# Request metrics
main_server_requests_total{method,endpoint,status}
main_server_request_duration_seconds{method,endpoint}

# Message metrics
main_server_messages_registered_total{client_id}
main_server_messages_delivered_total{client_id}
main_server_messages_failed_total{client_id,reason}

# Database metrics
main_server_db_connections

# Certificate metrics
main_server_certificates_issued_total
main_server_certificates_revoked_total
```

### Health Checks

```bash
# Check health
curl -k https://localhost:8000/health

# Response
{
  "status": "healthy",
  "timestamp": "2025-01-15T10:30:00Z",
  "components": {
    "database": "healthy",
    "encryption": "healthy"
  }
}
```

### Logging

**Log Files**:
- Location: `logs/main_server.log`
- Rotation: Daily at midnight
- Retention: 7 days
- Format: Timestamp - Level - [File:Line] - Message

**Log Levels**:
- **DEBUG**: Detailed processing information
- **INFO**: Normal operations (default)
- **WARNING**: Potential issues
- **ERROR**: Failures requiring attention

**Example Logs**:
```
2025-01-15 10:30:00 - main_server - INFO - Message registered: msg-123 for client test_client
2025-01-15 10:30:01 - main_server - INFO - User logged in: admin@example.com
2025-01-15 10:30:02 - main_server - WARNING - Token expired for user 5
```

---

## Troubleshooting

### Common Issues

#### 1. Cannot Connect to Database

**Symptoms**:
```
ERROR: Failed to connect to database
sqlalchemy.exc.OperationalError: (pymysql.err.OperationalError) (2003, "Can't connect to MySQL server...")
```

**Solutions**:
- Verify MySQL is running: `sc query mysql` (Windows) or `systemctl status mysql` (Linux)
- Check DATABASE_URL in `.env`
- Verify credentials: `mysql -u systemuser -p`
- Check firewall allows port 3306

#### 2. Certificate Errors

**Symptoms**:
```
ERROR: Server certificate not found at certs/server.crt
```

**Solutions**:
```powershell
# Initialize CA
.\init_ca.bat

# Generate server certificate
.\generate_cert.bat server

# Verify files exist
dir certs\*.crt
dir certs\*.key
```

#### 3. JWT Secret Not Set

**Symptoms**:
```
WARNING: Using default JWT secret
```

**Solution**:
Set `JWT_SECRET` in `.env`:
```env
JWT_SECRET=your-very-secure-random-secret-key
```

Generate a secure secret:
```powershell
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

#### 4. Encryption Key Missing

**Symptoms**:
```
ERROR: Failed to initialize encryption: [Errno 2] No such file or directory: 'secrets/encryption.key'
```

**Solution**:
```powershell
mkdir secrets
python -c "from cryptography.fernet import Fernet; open('secrets/encryption.key', 'wb').write(Fernet.generate_key())"
```

#### 5. Port Already in Use

**Symptoms**:
```
ERROR: [Errno 10048] Only one usage of each socket address is normally permitted
```

**Solutions**:
- Stop other service on port 8000
- Use different port: `.\start_server.ps1 -Port 8001`
- Find process: `netstat -ano | findstr :8000`

#### 6. Migration Errors

**Symptoms**:
```
alembic.util.exc.CommandError: Can't locate revision identified by '...'
```

**Solutions**:
```powershell
# Check current version
alembic current

# Show history
alembic history

# Stamp as current (if fresh database)
alembic stamp head

# Or start fresh
alembic downgrade base
alembic upgrade head
```

---

## Production Deployment

### Windows Production Setup

#### 1. Install as Windows Service (NSSM)

```powershell
# Install NSSM
choco install nssm

# Install service
nssm install MessageBrokerServer "C:\message_broker\venv\Scripts\python.exe"
nssm set MessageBrokerServer AppParameters "C:\message_broker\main_server\api.py"
nssm set MessageBrokerServer AppDirectory "C:\message_broker\main_server"
nssm set MessageBrokerServer DisplayName "Message Broker Main Server"
nssm set MessageBrokerServer Description "Central API and database service for message broker"
nssm set MessageBrokerServer Start SERVICE_AUTO_START

# Set environment
nssm set MessageBrokerServer AppEnvironmentExtra ^
  DATABASE_URL=mysql+pymysql://systemuser:password@localhost/message_system ^
  JWT_SECRET=your-production-secret ^
  LOG_LEVEL=INFO

# Start service
nssm start MessageBrokerServer

# Check status
nssm status MessageBrokerServer
```

### Linux Production Setup

#### 1. Install systemd Service

```bash
# Copy service file
sudo cp main_server.service /etc/systemd/system/

# Create service user
sudo useradd -r -s /bin/false messagebroker
sudo chown -R messagebroker:messagebroker /opt/message_broker

# Set permissions
sudo chmod 700 /opt/message_broker/main_server/certs
sudo chmod 600 /opt/message_broker/main_server/certs/*.key
sudo chmod 600 /opt/message_broker/main_server/secrets/*

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable main_server
sudo systemctl start main_server

# Check status
sudo systemctl status main_server

# View logs
sudo journalctl -u main_server -f
```

### Performance Tuning

#### Database Optimization

```ini
# MySQL configuration (/etc/mysql/my.cnf)
[mysqld]
innodb_buffer_pool_size = 2G
max_connections = 200
innodb_log_file_size = 256M
query_cache_size = 64M
```

#### Connection Pool Tuning

Adjust in `api.py`:
```python
db_manager = DatabaseManager(
    config.DATABASE_URL,
    pool_size=20,          # For high load
    max_overflow=40,       # Total 60 connections
    pool_recycle=3600,     # Recycle every hour
)
```

#### Uvicorn Workers

For production, use multiple workers:

```bash
uvicorn main_server.api:app \
  --host 0.0.0.0 \
  --port 8000 \
  --workers 4 \
  --ssl-keyfile certs/server.key \
  --ssl-certfile certs/server.crt \
  --ssl-ca-certs certs/ca.crt
```

### Reverse Proxy (Nginx)

```nginx
upstream main_server {
    server localhost:8000;
    server localhost:8001;  # Multiple instances
}

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # Pass client certificate to backend
    ssl_client_certificate /path/to/ca.crt;
    ssl_verify_client optional;
    
    location / {
        proxy_pass https://main_server;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-SSL-Client-Subject-DN $ssl_client_s_dn;
        proxy_set_header X-SSL-Client-Cert $ssl_client_cert;
    }
}
```

### Backup Strategy

#### Automated Backups

```bash
#!/bin/bash
# backup.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/message_broker"

# Database backup
mysqldump -u systemuser -p${DB_PASSWORD} message_system | \
  gzip > ${BACKUP_DIR}/db_${DATE}.sql.gz

# Encryption keys
tar -czf ${BACKUP_DIR}/secrets_${DATE}.tar.gz secrets/

# Certificates
tar -czf ${BACKUP_DIR}/certs_${DATE}.tar.gz certs/

# Logs
tar -czf ${BACKUP_DIR}/logs_${DATE}.tar.gz logs/

# Cleanup old backups (keep 30 days)
find ${BACKUP_DIR} -name "*.gz" -mtime +30 -delete
```

Add to crontab:
```bash
0 2 * * * /opt/message_broker/backup.sh
```

---

## License

See root LICENSE file for details.

---

## Support

For issues and questions:
- Check logs: `main_server/logs/main_server.log`
- View metrics: `https://localhost:8000/metrics`
- Health check: `https://localhost:8000/health`
- API docs: `https://localhost:8000/docs`
- Review main documentation: `../README.md`

