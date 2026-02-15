# Message Broker System - Deployment and Running Guide

**Version**: 1.0.0  
**Platform**: Windows Server/Linux  
**Date**: November 2025

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Prerequisites](#prerequisites)
3. [Windows Deployment](#windows-deployment)
4. [Linux Deployment](#linux-deployment)
5. [Configuration](#configuration)
6. [Certificate Management](#certificate-management)
7. [Running the System](#running-the-system)
8. [Service Management](#service-management)
9. [Troubleshooting](#troubleshooting)

---

## System Overview

The Message Broker System consists of 4 main components:

- **Main Server** (Port 8000): Central API, database, authentication
- **Proxy Server** (Port 8001): Client-facing API with mutual TLS
- **Worker**: Processes messages from Redis queue
- **Web Portal** (Port 5000): Web interface for viewing messages

### Architecture

```
Client → Proxy (8001) → Redis Queue → Worker → Main Server (8000) → MySQL
                                                        ↓
                                                   Web Portal (5000)
```

---

## Prerequisites

### Required Software

**Both Platforms:**
- Python 3.8 or higher
- MySQL 8.0 or higher
- Redis 6.0 or higher (or Memurai on Windows)
- OpenSSL 3.0 or higher

**Windows Additional:**
- PowerShell 5.1 or higher

**Linux Additional:**
- systemd (for service management)

### Network Ports

- **8000**: Main Server (HTTPS)
- **8001**: Proxy Server (HTTPS with mutual TLS)
- **5000**: Web Portal (HTTP)
- **3306**: MySQL
- **6379**: Redis
- **9100+**: Worker metrics (optional)

---

## Windows Deployment

### Step 1: Install Dependencies

#### Option A: Using Chocolatey (Recommended)

```powershell
# Install Chocolatey if not already installed
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install dependencies
choco install mysql redis-64 openssl python3 -y
```

#### Option B: Manual Installation

1. Download and install MySQL 8.0 from mysql.com
2. Download and install Memurai (Redis-compatible) from memurai.com
3. Download and install OpenSSL from slproweb.com/products/Win32OpenSSL.html
4. Download and install Python 3.8+ from python.org

### Step 2: Setup Database

```powershell
# Start MySQL
net start MySQL80

# Create database
mysql -u root -p
```

```sql
CREATE DATABASE message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'YourStrongPassword123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### Step 3: Setup Python Environment

```powershell
# Navigate to project directory
cd C:\MessageBroker

# Create virtual environment
python -m venv venv

# Activate virtual environment
.\venv\Scripts\Activate.ps1

# Install dependencies
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

### Step 4: Initialize Database Schema

```powershell
cd main_server
alembic upgrade head
```

### Step 5: Generate Certificates

```powershell
cd main_server

# Initialize Certificate Authority
.\init_ca.bat

# Generate server certificates
.\generate_cert.bat server
.\generate_cert.bat proxy
.\generate_cert.bat worker

# Generate test client certificate
.\generate_cert.bat test_client
```

Copy certificates to appropriate directories:
- `proxy.crt` and `proxy.key` → `proxy/certs/`
- `worker.crt` and `worker.key` → `worker/certs/`
- Copy `ca.crt` to `proxy/certs/` and `worker/certs/`

### Step 6: Create Admin User

```powershell
cd main_server
python admin_cli.py users create --email admin@example.com --password AdminPass123! --role admin
```

### Step 7: Configure Environment

Create `.env` file in project root:

```env
# Database
DATABASE_URL=mysql+pymysql://systemuser:YourStrongPassword123!@localhost/message_system

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Secrets (CHANGE THESE IN PRODUCTION!)
JWT_SECRET=your-production-secret-key-min-32-chars
HASH_SALT=your-production-salt-change-this

# Main Server
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=logs
```

---

## Linux Deployment

### Step 1: Install Dependencies

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv mysql-server redis-server openssl
```

**CentOS/RHEL:**
```bash
sudo yum install -y python3 python3-pip mysql-server redis openssl
```

### Step 2: Setup Database

```bash
# Start MySQL
sudo systemctl start mysql
sudo systemctl enable mysql

# Secure MySQL installation
sudo mysql_secure_installation

# Create database
sudo mysql -u root -p
```

```sql
CREATE DATABASE message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'YourStrongPassword123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### Step 3: Setup Python Environment

```bash
# Navigate to project directory
cd /opt/message_broker

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install dependencies
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

### Step 4: Initialize Database Schema

```bash
cd main_server
alembic upgrade head
```

### Step 5: Generate Certificates

```bash
cd main_server/certs

# Generate CA private key
openssl genrsa -out ca.key 4096
chmod 600 ca.key

# Generate CA certificate
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
    -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"
chmod 644 ca.crt

# Generate server certificate
mkdir -p ../certs
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
    -subj "/CN=server/O=MessageBroker/C=US"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out server.crt -days 365 -sha256
chmod 600 server.key
chmod 644 server.crt

# Generate proxy certificate
cd ../proxy/certs
openssl genrsa -out proxy.key 2048
openssl req -new -key proxy.key -out proxy.csr \
    -subj "/CN=proxy/O=MessageBroker/C=US"
openssl x509 -req -in proxy.csr -CA ../../main_server/certs/ca.crt \
    -CAkey ../../main_server/certs/ca.key -CAcreateserial \
    -out proxy.crt -days 365 -sha256
chmod 600 proxy.key
chmod 644 proxy.crt

# Copy CA cert to proxy
cp ../../main_server/certs/ca.crt .

# Generate worker certificate
cd ../../worker/certs
openssl genrsa -out worker.key 2048
openssl req -new -key worker.key -out worker.csr \
    -subj "/CN=worker/O=MessageBroker/C=US"
openssl x509 -req -in worker.csr -CA ../../main_server/certs/ca.crt \
    -CAkey ../../main_server/certs/ca.key -CAcreateserial \
    -out worker.crt -days 365 -sha256
chmod 600 worker.key
chmod 644 worker.crt

# Copy CA cert to worker
cp ../../main_server/certs/ca.crt .
```

**Or use the admin CLI:**
```bash
cd main_server
source ../venv/bin/activate
python admin_cli.py certificates generate server
python admin_cli.py certificates generate proxy
python admin_cli.py certificates generate worker
python admin_cli.py certificates generate test_client
```

### Step 6: Create Admin User

```bash
cd main_server
source ../venv/bin/activate
python admin_cli.py users create --email admin@example.com --password AdminPass123! --role admin
```

### Step 7: Configure Environment

Create `.env` file in project root (`/opt/message_broker/.env`):

```env
# Database
DATABASE_URL=mysql+pymysql://systemuser:YourStrongPassword123!@localhost/message_system

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Secrets (CHANGE THESE IN PRODUCTION!)
JWT_SECRET=your-production-secret-key-min-32-chars
HASH_SALT=your-production-salt-change-this

# Main Server
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=/opt/message_broker/logs
```

---

## Running the System

### Windows - Manual Start

#### Option 1: Use Startup Script (Easiest)

```powershell
# Start all services at once
.\start_all_services.ps1

# Or start in silent mode (background)
.\start_all_services.ps1 -Silent
```

#### Option 2: Start Individually

Open 4 separate PowerShell windows:

**Terminal 1 - Main Server:**
```powershell
cd main_server
..\venv\Scripts\Activate.ps1
.\start_server.ps1
```

**Terminal 2 - Proxy:**
```powershell
cd proxy
..\venv\Scripts\Activate.ps1
.\start_proxy.ps1
```

**Terminal 3 - Worker:**
```powershell
cd worker
..\venv\Scripts\Activate.ps1
.\start_worker.ps1
```

**Terminal 4 - Portal:**
```powershell
cd portal
..\venv\Scripts\Activate.ps1
.\start_portal.ps1
```

### Linux - Manual Start

Open 4 separate terminal windows:

**Terminal 1 - Main Server:**
```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate
uvicorn main_server.api:app --host 0.0.0.0 --port 8000 \
    --ssl-keyfile certs/server.key \
    --ssl-certfile certs/server.crt \
    --ssl-ca-certs certs/ca.crt
```

**Terminal 2 - Proxy:**
```bash
cd /opt/message_broker/proxy
source ../venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 8001 \
    --ssl-keyfile certs/proxy.key \
    --ssl-certfile certs/proxy.crt \
    --ssl-ca-certs certs/ca.crt \
    --workers 4
```

**Terminal 3 - Worker:**
```bash
cd /opt/message_broker/worker
source ../venv/bin/activate
python worker.py
```

**Terminal 4 - Portal:**
```bash
cd /opt/message_broker/portal
source ../venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 5000
```

### Verify Services are Running

**Windows:**
```powershell
# Check ports
Get-NetTCPConnection -LocalPort 8000,8001,5000

# Check health endpoints
Invoke-WebRequest -Uri https://localhost:8000/health -SkipCertificateCheck
Invoke-WebRequest -Uri https://localhost:8001/api/v1/health -SkipCertificateCheck
Invoke-WebRequest -Uri http://localhost:5000
```

**Linux:**
```bash
# Check ports
sudo netstat -tlnp | grep -E '8000|8001|5000'

# Check health endpoints
curl -k https://localhost:8000/health
curl -k https://localhost:8001/api/v1/health
curl http://localhost:5000
```

---

## Service Management

### Windows - Install as Services

```powershell
# Install all services
cd deployment/services
.\install_all_services.ps1

# Start services
net start MessageBrokerMainServer
net start MessageBrokerProxy
net start MessageBrokerWorker
net start MessageBrokerPortal

# Stop services
net stop MessageBrokerPortal
net stop MessageBrokerWorker
net stop MessageBrokerProxy
net stop MessageBrokerMainServer

# Check status
Get-Service MessageBroker*
```

### Linux - Install as systemd Services

```bash
# Copy service files
sudo cp main_server/main_server.service /etc/systemd/system/
sudo cp proxy/proxy.service /etc/systemd/system/
sudo cp worker/worker.service /etc/systemd/system/
sudo cp portal/portal.service /etc/systemd/system/

# Create service user
sudo useradd -r -s /bin/false messagebroker
sudo chown -R messagebroker:messagebroker /opt/message_broker

# Set permissions
sudo chmod 700 /opt/message_broker/main_server/certs
sudo chmod 600 /opt/message_broker/main_server/certs/*.key
sudo chmod 600 /opt/message_broker/main_server/secrets/*

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable main_server proxy worker portal
sudo systemctl start main_server proxy worker portal

# Check status
sudo systemctl status main_server
sudo systemctl status proxy
sudo systemctl status worker
sudo systemctl status portal

# View logs
sudo journalctl -u main_server -f
sudo journalctl -u proxy -f
sudo journalctl -u worker -f
sudo journalctl -u portal -f
```

---

## Certificate Management

### Generate Client Certificate

**Windows:**
```powershell
cd main_server
.\generate_cert.bat client_name
```

**Linux:**
```bash
cd main_server
mkdir -p certs/clients/client_name
cd certs/clients/client_name

# Generate private key
openssl genrsa -out client_name.key 2048

# Generate CSR
openssl req -new -key client_name.key -out client_name.csr \
    -subj "/CN=client_name/O=MessageBroker/C=US"

# Sign with CA
openssl x509 -req -in client_name.csr \
    -CA ../../ca.crt -CAkey ../../ca.key -CAcreateserial \
    -out client_name.crt -days 365 -sha256

# Copy CA cert
cp ../../ca.crt .
```

### Revoke Certificate

**Windows:**
```powershell
cd main_server
.\revoke_cert.bat client_name
```

**Linux:**
```bash
cd main_server
openssl ca -revoke certs/clients/client_name/client_name.crt \
    -keyfile certs/ca.key -cert certs/ca.crt
openssl ca -gencrl -out crl/revoked.pem -keyfile certs/ca.key -cert certs/ca.crt
```

### List Certificates

**Windows:**
```powershell
cd main_server
.\list_certs.bat
```

**Linux:**
```bash
cd main_server/certs/clients
for dir in */; do
    echo "Client: $dir"
    openssl x509 -in ${dir}${dir%/}.crt -noout -subject -dates
done
```

---

## Testing the System

### 1. Access Web Portal

Open browser: `http://localhost:5000`

Login with admin credentials created earlier.

### 2. Send Test Message

**Using Python Client:**

```python
import httpx

cert = ("client-scripts/certs/test_client.crt", "client-scripts/certs/test_client.key")
ca = "client-scripts/certs/ca.crt"

response = httpx.post(
    "https://localhost:8001/api/v1/messages",
    json={
        "sender_number": "+1234567890",
        "message_body": "Test message"
    },
    cert=cert,
    verify=ca
)

print(response.json())
```

**Using curl (if certificate is in PEM format):**

```bash
curl -k --cert client-scripts/certs/test_client.crt \
     --key client-scripts/certs/test_client.key \
     --cacert client-scripts/certs/ca.crt \
     -X POST https://localhost:8001/api/v1/messages \
     -H "Content-Type: application/json" \
     -d '{"sender_number": "+1234567890", "message_body": "Test message"}'
```

### 3. View Message in Portal

1. Login to portal at `http://localhost:5000`
2. Navigate to Messages section
3. Your test message should appear

---

## Troubleshooting

### Services Won't Start

**Check logs:**
- Windows: `Get-Content logs\*.log -Tail 50`
- Linux: `sudo journalctl -u <service_name> -n 50`

**Common issues:**
- Port already in use: `netstat -ano | findstr :8000` (Windows) or `sudo lsof -i :8000` (Linux)
- Database connection failed: Verify MySQL is running and credentials are correct
- Redis connection failed: Verify Redis is running (`redis-cli ping`)
- Certificate errors: Regenerate certificates

### Certificate Errors

**Error**: "Certificate verify failed"
- Solution: Regenerate certificates using `init_ca.bat` (Windows) or OpenSSL commands (Linux)
- Ensure CA certificate matches across all components

**Error**: "Invalid or missing client certificate"
- Solution: Ensure client certificate is valid and signed by the CA
- Check certificate hasn't expired: `openssl x509 -in cert.crt -noout -dates`

### Database Connection Errors

**Error**: "Can't connect to MySQL"
- Verify MySQL is running: `net start MySQL80` (Windows) or `sudo systemctl status mysql` (Linux)
- Check credentials in `.env` file
- Verify database exists: `mysql -u systemuser -p -e "SHOW DATABASES;"`

### Redis Connection Errors

**Error**: "Connection refused"
- Start Redis: `redis-server --service-start` (Windows) or `sudo systemctl start redis` (Linux)
- Verify Redis is listening: `redis-cli ping` (should return PONG)

### Worker Not Processing Messages

**Check:**
1. Worker is running
2. Redis queue has messages: `redis-cli LLEN message_queue`
3. Main server is accessible from worker
4. Worker certificate is valid

### Portal Login Issues

**Error**: "Invalid credentials"
- Create admin user: `python admin_cli.py users create --email admin@example.com --password AdminPass123! --role admin`
- Verify user exists: `python admin_cli.py users list`

---

## Production Checklist

Before deploying to production:

- [ ] Change all default passwords (JWT_SECRET, HASH_SALT, database passwords)
- [ ] Generate new CA and certificates (don't use test certificates)
- [ ] Configure firewall rules (allow ports 8000, 8001, 5000)
- [ ] Set up SSL/TLS certificates for production domain
- [ ] Configure log rotation
- [ ] Set up backup procedures for database
- [ ] Configure Redis persistence (AOF enabled)
- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Configure failover and redundancy
- [ ] Review and harden security settings
- [ ] Test backup and restore procedures
- [ ] Document production credentials securely

---

## Support and Documentation

### API Documentation

- Main Server API: `https://localhost:8000/docs`
- Proxy API: `https://localhost:8001/api/v1/docs`

### Health Checks

- Main Server: `https://localhost:8000/health`
- Proxy: `https://localhost:8001/api/v1/health`
- Metrics: `https://localhost:8000/metrics`

### Log Locations

**Windows:**
- Main Server: `logs/main_server.log`
- Proxy: `logs/proxy.log`
- Worker: `logs/worker.log`
- Portal: `logs/portal.log`

**Linux:**
- Systemd logs: `sudo journalctl -u <service_name>`
- Application logs: `/opt/message_broker/logs/*.log`

---

## Quick Reference Commands

### Windows

```powershell
# Start all services
.\start_all_services.ps1

# Stop all services
.\stop_all_services.ps1

# Check service status
Get-Service MessageBroker*

# View logs
Get-Content logs\*.log -Tail 50
```

### Linux

```bash
# Start all services
sudo systemctl start main_server proxy worker portal

# Stop all services
sudo systemctl stop portal worker proxy main_server

# Check status
sudo systemctl status main_server proxy worker portal

# View logs
sudo journalctl -u main_server -f
```

---

**End of Deployment Guide**
