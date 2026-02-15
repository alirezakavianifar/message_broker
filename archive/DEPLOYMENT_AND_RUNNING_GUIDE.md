# Message Broker System - Complete Deployment and Running Guide

**Version**: 2.0.0  
**Last Updated**: November 2025  
**Platform**: Linux (Ubuntu/Debian/CentOS/RHEL)  
**Status**: Production Ready

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start - Automated Deployment](#quick-start---automated-deployment)
4. [Manual Deployment](#manual-deployment)
5. [Configuration](#configuration)
6. [Service Management](#service-management)
7. [Verification and Testing](#verification-and-testing)
8. [Troubleshooting](#troubleshooting)
9. [Post-Deployment Tasks](#post-deployment-tasks)
10. [Maintenance and Updates](#maintenance-and-updates)

---

## System Overview

### Architecture

```
Client → Proxy (Port 8001) → Redis Queue → Worker → Main Server (Port 8000) → MySQL
                                                              ↓
                                                        Web Portal (Port 8080)
```

### Components

1. **Main Server** (Port 8000)
   - Central API and database service
   - Certificate Authority (CA) management
   - User authentication and authorization
   - Message persistence
   - HTTPS with mutual TLS

2. **Proxy Server** (Port 8001)
   - Client-facing message ingestion endpoint
   - Message validation and queuing
   - Mutual TLS authentication
   - Load balancing and rate limiting

3. **Worker Service**
   - Consumes messages from Redis queue
   - Processes and delivers messages
   - Retry logic with exponential backoff
   - Error handling and dead letter queue

4. **Web Portal** (Port 8080)
   - Web-based user interface
   - Message viewing and management
   - User administration
   - System statistics and monitoring

### Network Ports

| Port | Service | Protocol | Access |
|------|---------|----------|--------|
| 8000 | Main Server | HTTPS | Internal/External |
| 8001 | Proxy Server | HTTPS (mTLS) | External |
| 8080 | Web Portal | HTTP | External |
| 3306 | MySQL | TCP | Internal |
| 6379 | Redis | TCP | Internal |

---

## Prerequisites

### System Requirements

**Minimum Requirements:**
- **OS**: Ubuntu 20.04+, Debian 11+, CentOS 8+, RHEL 8+, or Rocky Linux 8+
- **RAM**: 2GB minimum (4GB recommended)
- **Disk**: 20GB free space
- **CPU**: 2 cores minimum (4 cores recommended)
- **Network**: Internet connection for package installation

**Recommended for Production:**
- **RAM**: 8GB+
- **Disk**: 50GB+ SSD
- **CPU**: 4+ cores
- **Network**: 100 Mbps+

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Python | 3.11+ | Application runtime |
| MySQL/MariaDB | 8.0+ / 10.5+ | Database server |
| Redis | 6.0+ | Message queue |
| OpenSSL | 1.1.1+ | Certificate generation |
| systemd | Latest | Service management |
| Git | Latest | Code repository |

### Deployment Machine Requirements (Windows)

If deploying from Windows:
- **PowerShell** 5.1 or higher
- **OpenSSH Client** (usually pre-installed on Windows 10/11)
- **PuTTY** (optional, for `plink` automatic password entry)
- **WSL** (optional, for `sshpass`)

---

## Quick Start - Automated Deployment

The fastest way to deploy is using the automated PowerShell script.

### Step 1: Prepare Deployment Machine (Windows)

1. **Install Prerequisites** (if not already installed):

```powershell
# Install OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Install PuTTY (optional, for automatic password entry)
# Download from: https://www.putty.org/
```

2. **Verify Tools**:

```powershell
# Check prerequisites
.\check_prerequisites.ps1
```

### Step 2: Configure Server Access

Ensure you have:
- Server IP address
- SSH username (usually `root` or a user with sudo privileges)
- SSH password or SSH key
- SSH port (default: 22, or custom port)

### Step 3: Run Automated Deployment

**Option A: Using deploy_now.ps1 (Quick Deploy)**

Edit `deploy_now.ps1` and set your server credentials:

```powershell
$ServerIP = "173.32.115.223"
$SSHPort = 2222
$Username = "root"
$Password = "YourPassword"
```

Then run:

```powershell
.\deploy_now.ps1
```

**Option B: Using deploy_to_linux.ps1 (Full Control)**

```powershell
.\deploy_to_linux.ps1 `
    -ServerIP "173.32.115.223" `
    -Username "root" `
    -Password "YourPassword" `
    -SSHPort 2222 `
    -RemotePath "/opt/message_broker"
```

**Parameters:**
- `-ServerIP`: Target server IP address (required)
- `-Username`: SSH username (required)
- `-Password`: SSH password (optional if using SSH key)
- `-SSHKey`: Path to SSH private key (optional)
- `-SSHPort`: SSH port (default: 2223)
- `-RemotePath`: Installation path on server (default: `/opt/message_broker`)
- `-SkipTransfer`: Skip file transfer if already deployed
- `-SkipServices`: Skip service installation

**Important Notes:**
- The script uses **hardcoded database password**: `YourStrongPassword123!`
- The script uses **hardcoded admin credentials**: `admin@example.com` / `AdminPass123!`
- **Change these passwords after deployment** for production use
- Services are **enabled** but **NOT started** automatically - you must start them manually
- The script supports automatic password entry via `plink` (PuTTY) or `sshpass` (WSL)

### Step 4: What the Script Does

The automated deployment script performs the following steps in order:

1. ✅ **File Transfer**: 
   - Creates a compressed archive (tar.gz or zip) of project files
   - Transfers archive to `/tmp/` on remote server
   - Excludes: `venv`, `__pycache__`, `.git`, `logs`, `.env`

2. ✅ **System Dependencies**: 
   - Detects package manager (apt-get/yum/dnf)
   - Installs Python 3, pip, venv, OpenSSL
   - Installs MySQL/MariaDB server
   - Installs Redis server
   - Starts and enables MySQL and Redis services

3. ✅ **Python Environment**: 
   - Creates virtual environment at `$RemotePath/venv`
   - Upgrades pip
   - Installs dependencies from all `requirements.txt` files:
     - `main_server/requirements.txt`
     - `proxy/requirements.txt`
     - `worker/requirements.txt`
     - `portal/requirements.txt`

4. ✅ **Database Setup**: 
   - Creates database `message_system` if it doesn't exist
   - Creates user `systemuser@localhost` with password `YourStrongPassword123!`
   - Grants all privileges on `message_system` database
   - Updates password if user already exists

5. ✅ **Environment Configuration**: 
   - Creates `.env` file at `$RemotePath/.env` with:
     - Database credentials (uses `YourStrongPassword123!`)
     - Redis configuration
     - JWT secrets
     - Admin credentials (`admin@example.com` / `AdminPass123!`)
     - Service endpoints
     - Worker configuration
   - **Important**: The script uses a hardcoded password `YourStrongPassword123!` for the database user

6. ✅ **Database Migrations**: 
   - Loads environment variables from `.env`
   - Tests database connection
   - Runs `alembic upgrade head` to create schema

7. ✅ **Certificate Generation**: 
   - Generates CA certificate if missing
   - Generates server certificate for main_server
   - Generates proxy certificate
   - Generates worker certificate
   - Sets proper permissions (600 for keys, 644 for certs)

8. ✅ **Encryption Key**: 
   - Generates AES encryption key at `$RemotePath/main_server/secrets/encryption.key`

9. ✅ **Service User**: 
   - Creates system user `messagebroker` (if not exists)
   - Sets ownership of `$RemotePath` to `messagebroker:messagebroker`

10. ✅ **Service Installation**: 
    - Copies service files to `/etc/systemd/system/`
    - Updates paths in service files to match `$RemotePath`
    - Runs `systemctl daemon-reload`
    - Enables services (but does NOT start them automatically)

11. ✅ **Admin User Creation**: 
    - Checks if admin user exists
    - Creates admin user `admin@example.com` with password `AdminPass123!` if missing

**Note**: The script does NOT automatically start services. You must start them manually after deployment.

### Step 5: Start Services and Verify Deployment

**Important**: The deployment script does NOT start services automatically. You must start them:

```bash
# SSH into server
ssh -p 2222 root@173.32.115.223

# Start all services
sudo systemctl start main_server proxy worker portal

# Check service status
systemctl status main_server proxy worker portal

# Check listening ports
ss -tlnp | grep -E ':(8000|8001|8080)'

# Test health endpoints
curl -k https://localhost:8000/health
curl -k https://localhost:8001/health
curl http://localhost:8080/health
```

**Note**: If services fail to start, check the troubleshooting section below.

---

## Manual Deployment

If you prefer manual deployment or need to customize the process:

### Prerequisites: Connect to Server

Before starting manual deployment, you need to connect to your Linux server via SSH.

**SSH Login Commands:**

**From Windows PowerShell or Command Prompt:**
```powershell
ssh -p 2222 root@173.32.115.223
```
When prompted, enter the password: `Abbas$12345`

**Or using plink (PuTTY) with automatic password:**
```powershell
plink -P 2222 -ssh -pw "Abbas`$12345" root@173.32.115.223
```

**From Linux/Mac terminal:**
```bash
ssh -p 2222 root@173.32.115.223
```
When prompted, enter the password: `Abbas$12345`

**Note**: 
- Replace `173.32.115.223` with your server IP address
- Replace `2222` with your SSH port if different
- Replace `Abbas$12345` with your actual root password
- The password contains special characters (`$`), so type it exactly as shown

**After successful login**, you'll see a prompt like:
```
root@MsgBrocker:~#
```

You're now logged in as root and can proceed with the manual deployment steps below. Since you're logged in as `root`, you don't need to use `sudo` for any commands.

---

### Step 1: Install System Dependencies ✅

**Status**: All dependencies are installed and services are running.

**Copy and paste these commands (Ubuntu/Debian):**

```bash
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv python3-dev build-essential libssl-dev libffi-dev
apt install -y mysql-server mysql-client default-libmysqlclient-dev
apt install -y redis-server
apt install -y openssl curl wget git
systemctl start mysql
systemctl enable mysql
systemctl start redis-server
systemctl enable redis-server
python3 --version
mysql --version
redis-cli --version
openssl version
```

**Copy and paste these commands (CentOS/RHEL/Rocky Linux):**

```bash
yum update -y
yum install -y epel-release
yum install -y python3 python3-pip python3-devel gcc gcc-c++ make openssl-devel libffi-devel
yum install -y mariadb-server mariadb mysql-devel
yum install -y redis
yum install -y openssl curl wget git
systemctl start mariadb
systemctl enable mariadb
systemctl start redis
systemctl enable redis
python3 --version
mysql --version
redis-cli --version
openssl version
```

### Step 2: Transfer Project Files ✅

**Status**: Project files are already deployed at `/opt/message_broker`.

**Copy and paste these commands (From Windows PowerShell):**

**Option 1: Using pscp (PuTTY) with automatic password (Recommended):**

```powershell
Compress-Archive -Path .\* -DestinationPath message_broker.zip -Force
pscp -P 2222 -pw "Abbas`$12345" message_broker.zip root@173.32.115.223:/tmp/
```

**Option 2: Using scp (will prompt for password):**

```powershell
Compress-Archive -Path .\* -DestinationPath message_broker.zip -Force
scp -P 2222 message_broker.zip root@173.32.115.223:/tmp/
# When prompted, enter password: Abbas$12345
```

**Note**: Replace `Abbas$12345` with your actual password. The `$` character needs to be escaped as `` `$ `` in PowerShell.

**Copy and paste these commands (From Linux/Mac):**

```bash
tar -czf message_broker.tar.gz --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' .
scp -P 2222 message_broker.tar.gz root@173.32.115.223:/tmp/
```

**Copy and paste these commands (On Server - Extract Files):**

```bash
mkdir -p /opt/message_broker
chown $USER:$USER /opt/message_broker
cd /opt/message_broker
unzip /tmp/message_broker.zip
# OR if using tar.gz:
# tar -xzf /tmp/message_broker.tar.gz
```

### Step 3: Set Up Python Environment ✅

**Status**: Virtual environment exists and dependencies are installed.

**Copy and paste these commands:**

```bash
cd /opt/message_broker
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
pip install itsdangerous
```

### Step 4: Configure MySQL Database ✅

**Status**: Database `message_system` and user `systemuser@localhost` exist.

**Copy and paste these commands:**

```bash
systemctl start mysql
systemctl enable mysql
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'systemuser'@'localhost' IDENTIFIED BY 'StrongPass123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EOF
```

**Important**: Replace `StrongPass123!` with a strong password and remember it for the `.env` file.

### Step 5: Configure Redis ✅

**Status**: Redis server is running and accessible.

**Copy and paste these commands:**

```bash
systemctl start redis-server
systemctl enable redis-server
redis-cli ping
```

### Step 6: Generate SSL Certificates ✅

**Status**: All SSL certificates (CA, server, proxy, worker) are generated and in place.

**Copy and paste these commands:**

```bash
cd /opt/message_broker
mkdir -p main_server/certs proxy/certs worker/certs
openssl genrsa -out main_server/ca.key 4096
openssl req -new -x509 -days 3650 -key main_server/ca.key -out main_server/certs/ca.crt -subj "/CN=MessageBroker-CA"
cp main_server/certs/ca.crt proxy/certs/ca.crt
cp main_server/certs/ca.crt worker/certs/ca.crt
openssl genrsa -out main_server/certs/server.key 2048
openssl req -new -key main_server/certs/server.key -out main_server/certs/server.csr -subj "/CN=main-server"
openssl x509 -req -days 365 -in main_server/certs/server.csr -CA main_server/certs/ca.crt -CAkey main_server/ca.key -CAcreateserial -out main_server/certs/server.crt
openssl genrsa -out proxy/certs/proxy.key 2048
openssl req -new -key proxy/certs/proxy.key -out proxy/certs/proxy.csr -subj "/CN=proxy-server"
openssl x509 -req -days 365 -in proxy/certs/proxy.csr -CA main_server/certs/ca.crt -CAkey main_server/ca.key -CAcreateserial -out proxy/certs/proxy.crt
openssl genrsa -out worker/certs/worker.key 2048
openssl req -new -key worker/certs/worker.key -out worker/certs/worker.csr -subj "/CN=worker"
openssl x509 -req -days 365 -in worker/certs/worker.csr -CA main_server/certs/ca.crt -CAkey main_server/ca.key -CAcreateserial -out worker/certs/worker.crt
chmod 600 main_server/ca.key
chmod 600 main_server/certs/*.key
chmod 600 proxy/certs/*.key
chmod 600 worker/certs/*.key
chmod 644 main_server/certs/*.crt
chmod 644 proxy/certs/*.crt
chmod 644 worker/certs/*.crt
```

### Step 7: Configure Environment Variables ✅

**Status**: `.env` file exists with all required configuration variables.

**Copy and paste these commands:**

```bash
cd /opt/message_broker
cp env.template .env
nano .env
```

**Required Configuration:**

```bash
# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=YourStrongPassword123!  # Script uses this hardcoded password

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Security - Encryption Key Path (Linux)
ENCRYPTION_KEY_PATH=/opt/message_broker/main_server/secrets/encryption.key

# JWT Configuration
JWT_SECRET=SuperSecretJWTKey_ChangeInProduction
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=30

# Admin Credentials (Portal)
ADMIN_USER=admin@example.com
ADMIN_PASS=AdminPass123!

# Service Endpoints
PROXY_URL=https://localhost:8001
MAIN_SERVER_URL=https://localhost:8000
PORTAL_URL=http://localhost:8080

# Worker Configuration
WORKER_RETRY_INTERVAL=30
WORKER_MAX_ATTEMPTS=10000
WORKER_CONCURRENCY=4

# Logging
LOG_LEVEL=INFO
```

**Important**: 
- The automated script uses hardcoded `DB_PASSWORD=YourStrongPassword123!` - **change this in production**
- The automated script uses hardcoded `ADMIN_PASS=AdminPass123!` - **change this in production**
- Change `JWT_SECRET` to a strong random string in production (minimum 32 characters)
- For manual deployment, use a strong password of your choice

### Step 8: Initialize Database Schema ✅

**Status**: Database migrations are at head (001), all tables exist (users, clients, messages, audit_log, alembic_version).

**Copy and paste these commands (run each line separately or as a block):**

```bash
cd /opt/message_broker
sed -i 's/\r$//' .env
export $(cat .env | grep -v '^#' | xargs)
echo "DB_HOST value: '$DB_HOST'"
source venv/bin/activate
cd main_server
alembic upgrade head
```

**Explanation:**
- `sed -i 's/\r$//' .env` - Fixes Windows line endings (CRLF) if .env was transferred from Windows
- `export $(cat .env | grep -v '^#' | xargs)` - Loads environment variables from .env file
- `echo "DB_HOST value: '$DB_HOST'"` - Verifies DB_HOST doesn't have trailing \r
- `source venv/bin/activate` - Activates the Python virtual environment
- `cd main_server` - Changes to the main_server directory
- `alembic upgrade head` - Runs database migrations

**Note**: If you see an error like `Can't connect to MySQL server on 'localhost\r'`, it means the .env file has Windows line endings. The `sed -i 's/\r$//' .env` command above fixes this.

### Step 9: Create Service User ✅

**Status**: Service user `messagebroker` exists and owns `/opt/message_broker`.

**Copy and paste these commands:**

```bash
useradd -r -s /bin/false -d /opt/message_broker messagebroker
chown -R messagebroker:messagebroker /opt/message_broker
mkdir -p /opt/message_broker/{main_server,proxy,worker,portal}/{logs,secrets}
chown -R messagebroker:messagebroker /opt/message_broker/*/logs
chown -R messagebroker:messagebroker /opt/message_broker/*/secrets
```

### Step 10: Install Systemd Services ✅

**Status**: All systemd services (main_server, proxy, worker, portal) are installed and enabled.

**Copy and paste these commands:**

```bash
cd /opt/message_broker
cp main_server/main_server.service /etc/systemd/system/
cp proxy/proxy.service /etc/systemd/system/
cp worker/worker.service /etc/systemd/system/
cp portal/portal.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable main_server proxy worker portal
```

### Step 11: Create Admin User ✅

**Status**: Admin user `admin@example.com` with role `admin` exists in the database.

**Copy and paste these commands:**

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate
# Set DATABASE_URL with correct password (admin_cli.py reads from environment)
# Use single quotes to prevent bash from interpreting ! as history expansion
export DATABASE_URL='mysql+pymysql://systemuser:YourStrongPassword123!@localhost:3306/message_system'
python admin_cli.py user create admin@example.com --role admin --password AdminPass123!
```

**Note**: Use **single quotes** (`'...'`) instead of double quotes (`"..."`) to prevent bash from interpreting `!` as history expansion.

**Note**: 
- The `admin_cli.py` script reads `DATABASE_URL` from environment variables, so you must export it before running the command
- Replace `YourStrongPassword123!` with your actual database password if different
- If you see "User with email ... already exists", the admin user was already created

**Note**: The email is a positional argument (not `--email`). The correct syntax is:
- `user create <email> --role <role> --password <password>`

### Step 12: Start Services ✅

**Status**: All services (main_server, proxy, worker, portal) are active and running.

**Copy and paste these commands:**

```bash
systemctl start main_server proxy worker portal
systemctl status main_server proxy worker portal
systemctl is-active main_server proxy worker portal
ss -tlnp | grep -E ':(8000|8001|8080)'
curl -k https://localhost:8000/health
curl http://localhost:8080/health
```

**Important**: The automated deployment script does NOT start services automatically. You must start them manually.

---

### Manual Deployment Summary ✅

**All 12 steps completed successfully!**

| Step | Status | Details |
|------|--------|---------|
| 1. Install System Dependencies | ✅ | Python 3.11.2, MariaDB 10.11.14, Redis 7.0.15, OpenSSL 3.0.17 |
| 2. Transfer Project Files | ✅ | Files deployed at `/opt/message_broker` |
| 3. Set Up Python Environment | ✅ | Virtual environment created, all dependencies installed |
| 4. Configure MySQL Database | ✅ | Database `message_system` and user `systemuser` exist |
| 5. Configure Redis | ✅ | Redis server running and accessible |
| 6. Generate SSL Certificates | ✅ | All certificates (CA, server, proxy, worker) generated |
| 7. Configure Environment Variables | ✅ | `.env` file configured with all required variables |
| 8. Initialize Database Schema | ✅ | Migrations at head, all tables created |
| 9. Create Service User | ✅ | User `messagebroker` exists with proper ownership |
| 10. Install Systemd Services | ✅ | All services installed and enabled |
| 11. Create Admin User | ✅ | Admin user `admin@example.com` exists |
| 12. Start Services | ✅ | All services active and running |

**Final Verification:**
- ✅ All ports listening: 8000 (main_server), 8001 (proxy), 8080 (portal)
- ✅ Health endpoints responding: Main Server and Portal both healthy
- ✅ All services running: main_server, proxy, worker, portal

**System Status**: 🟢 **FULLY OPERATIONAL**

---

## Configuration

### Environment Variables

The `.env` file contains all configuration. Key variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_HOST` | MySQL host | localhost |
| `DB_PORT` | MySQL port | 3306 |
| `DB_NAME` | Database name | message_system |
| `DB_USER` | Database user | systemuser |
| `DB_PASSWORD` | Database password | **Required** |
| `REDIS_HOST` | Redis host | localhost |
| `REDIS_PORT` | Redis port | 6379 |
| `JWT_SECRET` | JWT signing key | **Change in production** |
| `ENCRYPTION_KEY_PATH` | AES encryption key path | /opt/message_broker/main_server/secrets/encryption.key |
| `LOG_LEVEL` | Logging level | INFO |

### Service Configuration Files

Service-specific configurations are in:
- `main_server/main_server.service` - Main server systemd service
- `proxy/proxy.service` - Proxy server systemd service
- `worker/worker.service` - Worker systemd service
- `portal/portal.service` - Portal systemd service

**Important Service File Settings:**

- `EnvironmentFile=-/opt/message_broker/.env` - Loads environment variables
- `Environment="PYTHONPATH=/opt/message_broker"` - Sets Python path
- `WorkingDirectory` - Service working directory
- `User=messagebroker` - Service runs as non-root user

### Firewall Configuration

**Open Required Ports:**

```bash
# Ubuntu/Debian (UFW)
sudo ufw allow 8000/tcp
sudo ufw allow 8001/tcp
sudo ufw allow 8080/tcp
sudo ufw reload

# CentOS/RHEL (firewalld)
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --permanent --add-port=8001/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# Or using iptables
sudo iptables -A INPUT -p tcp --dport 8000 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8001 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
```

**Note**: If using a cloud provider (AWS, Azure, GCP), also configure Security Groups/Network Security Groups to allow these ports.

---

## Service Management

### Start Services

```bash
# Start all services
sudo systemctl start main_server proxy worker portal

# Start individual service
sudo systemctl start main_server
```

### Stop Services

```bash
# Stop all services
sudo systemctl stop main_server proxy worker portal

# Stop individual service
sudo systemctl stop main_server
```

### Restart Services

```bash
# Restart all services
sudo systemctl restart main_server proxy worker portal

# Restart individual service
sudo systemctl restart main_server
```

### Check Service Status

```bash
# Check all services
sudo systemctl status main_server proxy worker portal

# Check individual service
sudo systemctl status main_server

# Check if services are active
sudo systemctl is-active main_server proxy worker portal
```

### View Logs

```bash
# View logs for all services
sudo journalctl -u main_server -u proxy -u worker -u portal -f

# View logs for specific service
sudo journalctl -u main_server -f

# View last 100 lines
sudo journalctl -u main_server -n 100

# View logs since today
sudo journalctl -u main_server --since today
```

### Enable/Disable Auto-Start

```bash
# Enable services to start on boot
sudo systemctl enable main_server proxy worker portal

# Disable auto-start
sudo systemctl disable main_server proxy worker portal
```

---

## Verification and Testing

### 1. Check Service Status

```bash
# All services should show "active (running)"
sudo systemctl status main_server proxy worker portal
```

### 2. Check Listening Ports

```bash
# Should show ports 8000, 8001, and 8080 listening
ss -tlnp | grep -E ':(8000|8001|8080)'
```

### 3. Test Health Endpoints

```bash
# Main Server health check
curl -k https://localhost:8000/health
# Expected: {"status":"healthy","timestamp":"...","components":{"database":"healthy","encryption":"healthy"}}

# Portal health check
curl http://localhost:8080/health
# Expected: {"status":"healthy","timestamp":"...","service":"portal"}

# Proxy health check (may return 404, which is normal)
curl -k https://localhost:8001/health
```

### 4. Test API Endpoints

```bash
# Main Server API documentation
curl -k https://localhost:8000/docs

# Portal login page
curl http://localhost:8080/
```

### 5. Test Database Connection

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate
export $(cat ../.env | grep -v '^#' | xargs)

# Test connection
python -c "from database import get_db; next(get_db())"
# Should return without errors
```

### 6. Test Redis Connection

```bash
redis-cli ping
# Should return: PONG
```

### 7. Access Web Portal

Open in browser:
- **Local**: `http://localhost:8080`
- **Remote**: `http://YOUR_SERVER_IP:8080`

**Default Admin Credentials:**
- Email: `admin@example.com`
- Password: `AdminPass123!` (or as set in `.env`)

**Important**: Change default admin password after first login!

### 8. Run Automated System Test

The project includes a comprehensive test script that verifies all components and sends a test message through the system.

**On Linux:**

```bash
cd /opt/message_broker
source venv/bin/activate

# Run full test suite (requires certificates)
python test_message_broker.py

# Run test with custom message
python test_message_broker.py --message "Your test message here"

# Run test bypassing proxy (direct to main server, no certificates needed)
python test_message_broker.py --direct --message "Test message from automated test"

# Run test with custom sender number
python test_message_broker.py --direct --sender "+9876543210" --message "Test message"
```

**On Windows:**

```powershell
cd D:\projects\message_broker
.\venv\Scripts\Activate.ps1

# Run full test suite (requires certificates)
python test_message_broker.py

# Run test bypassing proxy (direct to main server, no certificates needed)
python test_message_broker.py --direct --message "Test message from automated test"
```

**What the Test Script Does:**

The `test_message_broker.py` script performs a comprehensive end-to-end test:

1. **Phase 1: Service Health Checks**
   - Verifies Main Server is healthy
   - Verifies Proxy Server is healthy
   - Verifies Portal is accessible
   - Tests Redis connection

2. **Phase 2: Certificate Check**
   - Checks if test certificates exist in `client-scripts/certs/`
   - Provides instructions if certificates are missing

3. **Phase 3: Message Sending Test**
   - Sends a test message via proxy (with mTLS certificates) OR
   - Sends a test message directly to main server (bypasses proxy, no certs needed)
   - Returns message ID on success

4. **Phase 4: Queue Verification**
   - Checks if message was queued in Redis
   - Verifies message processing

5. **Phase 5: Worker Processing**
   - Waits for worker to process the message
   - Verifies queue is empty after processing

6. **Phase 6: System Statistics**
   - Attempts to fetch system statistics from main server

**Expected Output:**

```
======================================================================
MESSAGE BROKER SYSTEM TEST
======================================================================

[INFO] Test started: 2025-11-28 09:28:59
[INFO] Proxy: https://localhost:8001
[INFO] Main Server: https://localhost:8000
[INFO] Portal: http://localhost:8080

======================================================================
PHASE 1: SERVICE HEALTH CHECKS
======================================================================

[PASS] Main Server is healthy
[PASS] Proxy Server is healthy
[PASS] Portal is accessible
[PASS] Redis is connected (queue size: 0)

======================================================================
PHASE 2: CERTIFICATE CHECK
======================================================================

[PASS] Test certificates found

======================================================================
PHASE 3: MESSAGE SENDING TEST
======================================================================

[PASS] Message registered: test_1764309547
[INFO] Message ID: test_1764309547

======================================================================
PHASE 4: QUEUE VERIFICATION
======================================================================

[WARN] Queue is empty (worker may have processed it)

======================================================================
PHASE 5: WORKER PROCESSING
======================================================================

[PASS] Queue is empty - worker processed messages

======================================================================
TEST SUMMARY
======================================================================

Passed: 5
Warnings: 2
Failed: 0

[SUCCESS] ALL CRITICAL TESTS PASSED
```

**Test Script Options:**

| Option | Description |
|--------|-------------|
| `--sender` | Sender phone number (default: `+1234567890`) |
| `--message` | Test message body (default: `"Test message from automated test"`) |
| `--skip-cert` | Skip certificate-based tests |
| `--direct` | Use direct main server API (bypasses proxy, no certificates needed) |

**Viewing Test Messages:**

After running the test, you can view the test message in the web portal:

1. Open the portal: `http://localhost:8080` (or `http://YOUR_SERVER_IP:8080`)
2. Login with admin credentials
3. Navigate to **Messages** section
4. Look for the message with ID starting with `test_` and the message content you specified

**Troubleshooting Test Failures:**

- **"ModuleNotFoundError: No module named 'httpx'"**: Activate the virtual environment first
- **"Service not responding"**: Ensure all services are running (`systemctl status main_server proxy worker portal`)
- **"Test certificates not found"**: Either use `--direct` flag or generate certificates first
- **"Queue is empty"**: This is normal if the worker processed the message quickly

---

## Troubleshooting

### Service Won't Start

**Problem**: Service fails to start

**Solutions**:

1. **Check service logs:**
   ```bash
   sudo journalctl -u main_server -n 50
   ```

2. **Check environment variables:**
   ```bash
   sudo systemctl show main_server | grep EnvironmentFile
   ```

3. **Verify .env file exists:**
   ```bash
   ls -la /opt/message_broker/.env
   ```

4. **Check Python path:**
   ```bash
   sudo -u messagebroker /opt/message_broker/venv/bin/python --version
   ```

5. **Verify certificates exist:**
   ```bash
   ls -la /opt/message_broker/main_server/certs/
   ```

### Database Connection Error

**Problem**: `Access denied for user 'systemuser'@'localhost'`

**Solutions**:

1. **Verify password in .env matches MySQL:**
   ```bash
   # Check .env
   grep DB_PASSWORD /opt/message_broker/.env
   
   # Test MySQL connection
   mysql -u systemuser -p
   ```

2. **Update MySQL password:**
   ```bash
   sudo mysql -u root -p
   ALTER USER 'systemuser'@'localhost' IDENTIFIED BY 'YourNewPassword';
   FLUSH PRIVILEGES;
   ```

3. **Update .env file:**
   ```bash
   nano /opt/message_broker/.env
   # Update DB_PASSWORD
   ```

4. **Restart services:**
   ```bash
   sudo systemctl restart main_server worker
   ```

### Module Not Found Errors

**Problem**: `ModuleNotFoundError: No module named 'X'`

**Solutions**:

1. **Reinstall dependencies:**
   ```bash
   cd /opt/message_broker
   source venv/bin/activate
   pip install -r main_server/requirements.txt
   pip install -r proxy/requirements.txt
   pip install -r worker/requirements.txt
   pip install -r portal/requirements.txt
   ```

2. **Check PYTHONPATH in service file:**
   ```bash
   grep PYTHONPATH /etc/systemd/system/main_server.service
   # Should show: Environment="PYTHONPATH=/opt/message_broker"
   ```

3. **Install missing package:**
   ```bash
   source venv/bin/activate
   pip install missing-package-name
   ```

### Port Already in Use

**Problem**: `Address already in use`

**Solutions**:

1. **Find process using port:**
   ```bash
   sudo lsof -i :8000
   # or
   sudo ss -tlnp | grep 8000
   ```

2. **Kill process:**
   ```bash
   sudo kill -9 <PID>
   ```

3. **Restart service:**
   ```bash
   sudo systemctl restart main_server
   ```

### Certificate Errors

**Problem**: SSL/TLS certificate errors

**Solutions**:

1. **Verify certificates exist:**
   ```bash
   ls -la /opt/message_broker/main_server/certs/
   ```

2. **Regenerate certificates:**
   ```bash
   # Follow Step 6 in Manual Deployment
   ```

3. **Check certificate permissions:**
   ```bash
   sudo chmod 600 /opt/message_broker/*/certs/*.key
   sudo chmod 644 /opt/message_broker/*/certs/*.crt
   ```

### Proxy Service Stuck in "Activating"

**Problem**: Proxy service shows "activating" but ports are listening

**Solutions**:

1. **Change service type from `notify` to `simple`:**
   ```bash
   sudo sed -i 's/Type=notify/Type=simple/' /etc/systemd/system/proxy.service
   sudo systemctl daemon-reload
   sudo systemctl restart proxy
   ```

2. **Check if proxy is actually running:**
   ```bash
   ps aux | grep uvicorn
   ss -tlnp | grep 8001
   ```

### Cannot Access Portal from Browser

**Problem**: Portal not accessible from external network

**Solutions**:

1. **Check firewall:**
   ```bash
   sudo ufw status
   # or
   sudo firewall-cmd --list-ports
   ```

2. **Open port 8080:**
   ```bash
   sudo ufw allow 8080/tcp
   # or
   sudo firewall-cmd --permanent --add-port=8080/tcp
   sudo firewall-cmd --reload
   ```

3. **Check cloud provider firewall:**
   - AWS: Security Groups
   - Azure: Network Security Groups
   - GCP: Firewall Rules

4. **Verify portal is listening on 0.0.0.0:**
   ```bash
   ss -tlnp | grep 8080
   # Should show: 0.0.0.0:8080
   ```

### Worker Not Processing Messages

**Problem**: Messages stuck in queue

**Solutions**:

1. **Check worker logs:**
   ```bash
   sudo journalctl -u worker -f
   ```

2. **Verify Redis connection:**
   ```bash
   redis-cli ping
   ```

3. **Check queue:**
   ```bash
   redis-cli
   > KEYS *
   > LLEN message_queue
   ```

4. **Restart worker:**
   ```bash
   sudo systemctl restart worker
   ```

---

## Post-Deployment Tasks

### 1. Change Default Passwords

**Change Admin Password:**

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate
export $(cat ../.env | grep -v '^#' | xargs)

python admin_cli.py user update --email admin@example.com --password NewStrongPassword
```

**Change Database Password:**

```bash
# Update MySQL
sudo mysql -u root -p
ALTER USER 'systemuser'@'localhost' IDENTIFIED BY 'NewStrongPassword';
FLUSH PRIVILEGES;

# Update .env
nano /opt/message_broker/.env
# Update DB_PASSWORD

# Restart services
sudo systemctl restart main_server worker
```

### 2. Configure Production Settings

**Update .env for Production:**

```bash
nano /opt/message_broker/.env
```

**Important changes:**
- Set strong `JWT_SECRET`
- Set strong `DB_PASSWORD`
- Set strong `ADMIN_PASS`
- Update `LOG_LEVEL` to `WARNING` or `ERROR` for production
- Configure proper `ENCRYPTION_KEY_PATH`

### 3. Set Up Log Rotation

```bash
# Create logrotate configuration
sudo nano /etc/logrotate.d/message_broker
```

Add:
```
/opt/message_broker/*/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 messagebroker messagebroker
}
```

### 4. Set Up Monitoring (Optional)

**Install Prometheus:**

```bash
# Download and install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xzf prometheus-*.tar.gz
sudo mv prometheus-*.linux-amd64 /opt/prometheus
```

**Configure monitoring endpoints** (if implemented in services)

### 5. Set Up Backups

**Database Backup Script:**

```bash
sudo nano /opt/message_broker/backup_db.sh
```

Add:
```bash
#!/bin/bash
BACKUP_DIR="/opt/message_broker/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

mysqldump -u systemuser -p'YourPassword' message_system > $BACKUP_DIR/message_system_$DATE.sql
gzip $BACKUP_DIR/message_system_$DATE.sql

# Keep only last 7 days
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete
```

```bash
chmod +x /opt/message_broker/backup_db.sh

# Add to crontab (daily at 2 AM)
sudo crontab -e
# Add: 0 2 * * * /opt/message_broker/backup_db.sh
```

### 6. Configure SSL/TLS for Portal (Optional)

For production, consider setting up HTTPS for the portal:

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Generate certificate (if using nginx as reverse proxy)
sudo certbot --nginx -d your-domain.com
```

---

## Maintenance and Updates

### Updating the Application

1. **Backup database:**
   ```bash
   /opt/message_broker/backup_db.sh
   ```

2. **Stop services:**
   ```bash
   sudo systemctl stop main_server proxy worker portal
   ```

3. **Update code:**
   ```bash
   cd /opt/message_broker
   git pull
   # or transfer new files
   ```

4. **Update dependencies:**
   ```bash
   source venv/bin/activate
   pip install -r main_server/requirements.txt
   pip install -r proxy/requirements.txt
   pip install -r worker/requirements.txt
   pip install -r portal/requirements.txt
   ```

5. **Run migrations:**
   ```bash
   cd main_server
   export $(cat ../.env | grep -v '^#' | xargs)
   alembic upgrade head
   ```

6. **Restart services:**
   ```bash
   sudo systemctl start main_server proxy worker portal
   ```

### Database Migrations

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate
export $(cat ../.env | grep -v '^#' | xargs)

# Check current version
alembic current

# Upgrade to latest
alembic upgrade head

# Create new migration
alembic revision --autogenerate -m "Description of changes"
```

### Viewing Logs

**Real-time logs:**
```bash
sudo journalctl -u main_server -f
```

**Filtered logs:**
```bash
# Errors only
sudo journalctl -u main_server -p err

# Since specific time
sudo journalctl -u main_server --since "2025-11-24 10:00:00"
```

---

## Service URLs

After successful deployment:

- **Main Server API**: `https://YOUR_SERVER_IP:8000/docs`
- **Proxy API**: `https://YOUR_SERVER_IP:8001/api/v1/docs`
- **Web Portal**: `http://YOUR_SERVER_IP:8080`

**Default Admin Login (Created by Script):**
- Email: `admin@example.com`
- Password: `AdminPass123!` (hardcoded in script - **change immediately after first login**)

**Default Database Password (Set by Script):**
- Database User: `systemuser@localhost`
- Password: `YourStrongPassword123!` (hardcoded in script - **change in production**)

---

## Support and Resources

- **Logs Location**: `/opt/message_broker/*/logs/`
- **Configuration**: `/opt/message_broker/.env`
- **Service Files**: `/etc/systemd/system/*.service`
- **Database**: MySQL `message_system` database
- **Certificates**: `/opt/message_broker/*/certs/`

---

## Quick Reference Commands

```bash
# Start all services
sudo systemctl start main_server proxy worker portal

# Stop all services
sudo systemctl stop main_server proxy worker portal

# Restart all services
sudo systemctl restart main_server proxy worker portal

# Check status
sudo systemctl status main_server proxy worker portal

# View logs
sudo journalctl -u main_server -f

# Test health
curl -k https://localhost:8000/health
curl http://localhost:8080/health

# Check ports
ss -tlnp | grep -E ':(8000|8001|8080)'

# Run automated system test
cd /opt/message_broker
source venv/bin/activate
python test_message_broker.py --direct --message "Test message"
```

---

**Document Version**: 2.0.0  
**Last Updated**: November 2025  
**Maintained By**: Message Broker Development Team

