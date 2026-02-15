# Linux Deployment Guide - Message Broker System

This guide explains how to deploy the message broker system on Linux. **Good news**: The Python source code works on Linux without modifications! Only the startup scripts need Linux alternatives.

## Overview

✅ **Python Source Code**: Works on Linux as-is (uses cross-platform `pathlib.Path`)  
✅ **Systemd Service Files**: Already included (`.service` files)  
⚠️ **Startup Scripts**: Need Linux bash alternatives for PowerShell/Batch scripts  
⚠️ **Certificate Scripts**: Need bash alternatives for `.bat` files  

## What Works Without Changes

### Python Source Code
All Python files (`*.py`) are **100% cross-platform** and work on Linux without modifications:
- `proxy/app.py`
- `main_server/api.py`
- `worker/worker.py`
- `portal/app.py`
- All other Python modules

The code uses:
- `pathlib.Path` for file paths (cross-platform)
- Standard Python libraries (os, sys, etc.)
- FastAPI, SQLAlchemy, Redis - all cross-platform

### Systemd Service Files
Linux systemd service files are **already included**:
- `main_server/main_server.service`
- `proxy/proxy.service`
- `worker/worker.service`
- `portal/portal.service`

## What Needs Linux Alternatives

### 1. Startup Scripts
**Windows**: PowerShell scripts (`.ps1`) and Batch files (`.bat`)  
**Linux Needed**: Bash scripts (`.sh`)

Replacements needed:
- `start_all_services.ps1` → `start_all_services.sh`
- `stop_all_services.ps1` → `stop_all_services.sh`
- `proxy/start_proxy.ps1` → `proxy/start_proxy.sh`
- `main_server/start_server.ps1` → `main_server/start_server.sh`
- `worker/start_worker.ps1` → `worker/start_worker.sh`
- `portal/start_portal.ps1` → `portal/start_portal.sh`

### 2. Certificate Generation Scripts
**Windows**: Batch files (`.bat`)  
**Linux Needed**: Bash scripts (`.sh`)

Replacements needed:
- `main_server/init_ca.bat` → `main_server/init_ca.sh`
- `main_server/generate_cert.bat` → `main_server/generate_cert.sh`
- `main_server/revoke_cert.bat` → `main_server/revoke_cert.sh`
- `main_server/renew_cert.bat` → `main_server/renew_cert.sh`
- `main_server/list_certs.bat` → `main_server/list_certs.sh`
- `main_server/verify_cert.bat` → `main_server/verify_cert.sh`

### 3. Deployment Scripts
**Windows**: PowerShell installation scripts  
**Linux Needed**: Bash equivalents

Not critical for basic usage - you can install services manually using systemd.

## Quick Start on Linux

### 1. Install Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y python3 python3-pip python3-venv mysql-server redis-server openssl

# Or CentOS/RHEL
sudo yum install -y python3 python3-pip mysql-server redis openssl
```

### 2. Setup Python Environment

```bash
cd /opt/message_broker
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Initialize Database

```bash
cd main_server
alembic upgrade head
```

### 4. Generate Certificates

**On Linux, you can either:**
- Use OpenSSL commands directly
- Use the admin CLI: `python admin_cli.py certificates generate <client_name>`

### 5. Start Services Manually (Development)

```bash
# Terminal 1 - Main Server
cd main_server
source ../venv/bin/activate
uvicorn main_server.api:app --host 0.0.0.0 --port 8000 \
    --ssl-keyfile certs/server.key \
    --ssl-certfile certs/server.crt \
    --ssl-ca-certs certs/ca.crt

# Terminal 2 - Proxy
cd proxy
source ../venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 8001 \
    --ssl-keyfile certs/proxy.key \
    --ssl-certfile certs/proxy.crt \
    --ssl-ca-certs certs/ca.crt \
    --workers 4

# Terminal 3 - Worker
cd worker
source ../venv/bin/activate
python worker.py

# Terminal 4 - Portal
cd portal
source ../venv/bin/activate
uvicorn app:app --host 0.0.0.0 --port 5000
```

### 6. Install as Systemd Services (Production)

```bash
# Copy service files
sudo cp main_server/main_server.service /etc/systemd/system/
sudo cp proxy/proxy.service /etc/systemd/system/
sudo cp worker/worker.service /etc/systemd/system/
sudo cp portal/portal.service /etc/systemd/system/

# Create service user
sudo useradd -r -s /bin/false messagebroker
sudo chown -R messagebroker:messagebroker /opt/message_broker

# Set proper permissions
sudo chmod 700 /opt/message_broker/main_server/certs
sudo chmod 600 /opt/message_broker/main_server/certs/*.key
sudo chmod 600 /opt/message_broker/main_server/secrets/*

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable main_server proxy worker portal
sudo systemctl start main_server proxy worker portal

# Check status
sudo systemctl status main_server
sudo systemctl status proxy
sudo systemctl status worker
sudo systemctl status portal
```

## Certificate Generation on Linux

### Initialize CA

```bash
cd main_server/certs

# Generate CA private key
openssl genrsa -out ca.key 4096

# Generate CA certificate
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
    -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"

# Set permissions
chmod 600 ca.key
chmod 644 ca.crt
```

### Generate Client Certificate

```bash
cd main_server/certs/clients
mkdir -p test_client

# Generate client private key
openssl genrsa -out test_client/test_client.key 2048

# Generate CSR
openssl req -new -key test_client/test_client.key \
    -out test_client/test_client.csr \
    -subj "/CN=test_client/O=MessageBroker/OU=default"

# Sign with CA
openssl x509 -req -in test_client/test_client.csr \
    -CA ../ca.crt -CAkey ../ca.key -CAcreateserial \
    -out test_client/test_client.crt -days 365 -sha256

# Copy CA cert
cp ../ca.crt test_client/

# Set permissions
chmod 600 test_client/test_client.key
chmod 644 test_client/test_client.crt
```

## Path Differences

The main difference is virtual environment paths:

**Windows**: `venv\Scripts\python.exe`  
**Linux**: `venv/bin/python`

This is already handled correctly in the Python code using `pathlib.Path` and environment detection.

## Environment Variables

Create `/opt/message_broker/.env`:

```bash
# Database
DATABASE_URL=mysql+pymysql://systemuser:password@localhost/message_system

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Secrets (CHANGE THESE!)
JWT_SECRET=your-production-secret-key-here
HASH_SALT=your-production-salt-here

# Main Server
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=/opt/message_broker/logs
```

## Service Management

```bash
# Start all services
sudo systemctl start main_server proxy worker portal

# Stop all services
sudo systemctl stop portal worker proxy main_server

# Restart a service
sudo systemctl restart main_server

# Check status
sudo systemctl status main_server

# View logs
sudo journalctl -u main_server -f
sudo journalctl -u proxy -f
sudo journalctl -u worker -f
sudo journalctl -u portal -f
```

## Summary

### ✅ No Source Code Changes Needed
- All Python code is cross-platform
- Uses `pathlib.Path` for paths
- No Windows-specific dependencies

### ⚠️ Script Replacements Needed
- PowerShell scripts → Bash scripts
- Batch files → Bash scripts
- Windows service scripts → systemd (already included!)

### 📝 Quick Answer
**You can use the Python source code on Linux without changes.** You just need:
1. Linux bash scripts instead of PowerShell/Batch
2. Use systemd service files (already included)
3. Use OpenSSL commands directly for certificates

The core application logic, API endpoints, database models, encryption, and all Python modules work identically on Linux!
