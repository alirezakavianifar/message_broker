# Linux Setup Guide - Message Broker System

Complete step-by-step instructions for getting the Message Broker application up and running on Linux.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Dependencies Installation](#system-dependencies-installation)
3. [Project Setup](#project-setup)
4. [Database Configuration](#database-configuration)
5. [Redis Configuration](#redis-configuration)
6. [Python Environment Setup](#python-environment-setup)
7. [Certificate Generation](#certificate-generation)
8. [Environment Configuration](#environment-configuration)
9. [Database Schema Initialization](#database-schema-initialization)
10. [Service User Creation](#service-user-creation)
11. [Systemd Service Installation](#systemd-service-installation)
12. [Starting Services](#starting-services)
13. [Verification and Testing](#verification-and-testing)
14. [Creating Admin User](#creating-admin-user)
15. [Firewall Configuration](#firewall-configuration)
16. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- **Linux Server**: Ubuntu 20.04+ / Debian 11+ / CentOS 8+ / RHEL 8+
- **Root or sudo access** to the server
- **SSH access** to the server
- **Internet connection** for package downloads
- **Minimum 2GB RAM** and **10GB disk space**

---

## System Dependencies Installation

### Step 1: Update System Packages

```bash
# Ubuntu/Debian
sudo apt update
sudo apt upgrade -y

# CentOS/RHEL
sudo yum update -y
# or for newer versions
sudo dnf update -y
```

### Step 2: Install Required System Packages

**For Ubuntu/Debian:**
```bash
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    mysql-server \
    redis-server \
    openssl \
    git \
    curl \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev
```

**For CentOS/RHEL:**
```bash
sudo yum install -y \
    python3 \
    python3-pip \
    mysql-server \
    redis \
    openssl \
    git \
    curl \
    gcc \
    openssl-devel \
    libffi-devel \
    python3-devel

# Enable and start MySQL
sudo systemctl enable mysqld
sudo systemctl start mysqld

# Enable and start Redis
sudo systemctl enable redis
sudo systemctl start redis
```

### Step 3: Verify Installations

```bash
# Check Python version (should be 3.8+)
python3 --version

# Check MySQL
mysql --version
sudo systemctl status mysql  # or mysqld on CentOS

# Check Redis
redis-cli --version
sudo systemctl status redis
```

---

## Project Setup

### Step 4: Clone or Transfer Project Files

**Option A: If using Git:**
```bash
cd /opt
sudo git clone <repository-url> message_broker
sudo chown -R $USER:$USER /opt/message_broker
cd /opt/message_broker
```

**Option B: If transferring files:**
```bash
# Create directory
sudo mkdir -p /opt/message_broker
sudo chown -R $USER:$USER /opt/message_broker

# Transfer files (from your local machine)
# scp -r message_broker/* user@server:/opt/message_broker/

# Or extract from archive
cd /opt/message_broker
# Extract your archive here
```

### Step 5: Verify Project Structure

```bash
cd /opt/message_broker
ls -la

# You should see:
# - main_server/
# - proxy/
# - worker/
# - portal/
# - client-scripts/
# - env.template
```

---

## Database Configuration

### Step 6: Secure MySQL Installation

**For Ubuntu/Debian (first-time setup):**
```bash
sudo mysql_secure_installation
```

Follow the prompts:
- Set root password (or leave blank for socket authentication)
- Remove anonymous users: **Y**
- Disallow root login remotely: **Y** (or N if needed)
- Remove test database: **Y**
- Reload privilege tables: **Y**

### Step 7: Create Database and User

```bash
# Login to MySQL
sudo mysql -u root -p
```

In the MySQL prompt, execute:

```sql
-- Create database
CREATE DATABASE message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create user (replace 'StrongPass123!' with a strong password)
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'StrongPass123!';

-- Grant privileges
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';

-- Flush privileges
FLUSH PRIVILEGES;

-- Verify
SHOW DATABASES;
EXIT;
```

### Step 8: Test Database Connection

```bash
mysql -u systemuser -p message_system
# Enter password when prompted
# Type EXIT; to leave
```

---

## Redis Configuration

### Step 9: Configure Redis

**For Ubuntu/Debian:**
```bash
# Redis should already be running
sudo systemctl status redis

# Test connection
redis-cli ping
# Should return: PONG
```

**For CentOS/RHEL:**
```bash
# Start Redis if not running
sudo systemctl start redis
sudo systemctl enable redis

# Test connection
redis-cli ping
# Should return: PONG
```

### Step 10: Configure Redis Persistence (Optional but Recommended)

Edit Redis config:
```bash
sudo nano /etc/redis/redis.conf
# or on CentOS: sudo nano /etc/redis.conf
```

Find and ensure these settings:
```
save 900 1
save 300 10
save 60 10000
appendonly yes
```

Restart Redis:
```bash
sudo systemctl restart redis
```

---

## Python Environment Setup

### Step 11: Create Virtual Environment

```bash
cd /opt/message_broker

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Verify activation (prompt should show (venv))
which python
```

### Step 12: Upgrade pip

```bash
pip install --upgrade pip setuptools wheel
```

### Step 13: Install Python Dependencies

```bash
# Make sure venv is activated
source venv/bin/activate

# Install all requirements
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt

# Verify installations
pip list | grep -E "(fastapi|uvicorn|sqlalchemy|redis|pymysql)"
```

---

## Certificate Generation

### Step 14: Create Certificate Directories

```bash
cd /opt/message_broker

# Create necessary directories
mkdir -p main_server/certs/clients
mkdir -p proxy/certs
mkdir -p worker/certs
mkdir -p portal/certs
mkdir -p client-scripts/certs
```

### Step 15: Generate Certificate Authority (CA)

```bash
cd /opt/message_broker/main_server/certs

# Generate CA private key
openssl genrsa -out ca.key 4096

# Generate CA certificate (valid for 10 years)
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
    -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"

# Set secure permissions
chmod 600 ca.key
chmod 644 ca.crt
```

### Step 16: Generate Server Certificate

```bash
cd /opt/message_broker/main_server/certs

# Generate server private key
openssl genrsa -out server.key 2048

# Generate certificate signing request
openssl req -new -key server.key -out server.csr \
    -subj "/CN=localhost/O=MessageBroker/C=US"

# Sign certificate with CA (valid for 1 year)
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out server.crt -days 365 -sha256

# Set permissions
chmod 600 server.key
chmod 644 server.crt

# Clean up CSR
rm server.csr
```

### Step 17: Generate Proxy Certificate

```bash
cd /opt/message_broker/main_server/certs

# Generate proxy private key
openssl genrsa -out proxy.key 2048

# Generate CSR
openssl req -new -key proxy.key -out proxy.csr \
    -subj "/CN=proxy/O=MessageBroker/C=US"

# Sign certificate
openssl x509 -req -in proxy.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out proxy.crt -days 365 -sha256

# Copy to proxy directory
cp proxy.crt proxy.key ../proxy/certs/
cp ca.crt ../proxy/certs/

# Set permissions
chmod 600 proxy.key ../proxy/certs/proxy.key
chmod 644 proxy.crt ../proxy/certs/proxy.crt

# Clean up
rm proxy.csr
```

### Step 18: Generate Worker Certificate

```bash
cd /opt/message_broker/main_server/certs

# Generate worker private key
openssl genrsa -out worker.key 2048

# Generate CSR
openssl req -new -key worker.key -out worker.csr \
    -subj "/CN=worker/O=MessageBroker/C=US"

# Sign certificate
openssl x509 -req -in worker.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out worker.crt -days 365 -sha256

# Copy to worker directory
cp worker.crt worker.key ../worker/certs/
cp ca.crt ../worker/certs/

# Set permissions
chmod 600 worker.key ../worker/certs/worker.key
chmod 644 worker.crt ../worker/certs/worker.crt

# Clean up
rm worker.csr
```

### Step 19: Copy CA Certificate to Client Scripts

```bash
cp /opt/message_broker/main_server/certs/ca.crt /opt/message_broker/client-scripts/certs/
```

---

## Environment Configuration

### Step 20: Create Environment File

```bash
cd /opt/message_broker

# Copy template
cp env.template .env

# Edit the .env file
nano .env
```

### Step 21: Configure Environment Variables

Edit `.env` with your settings:

```bash
# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=StrongPass123!  # Change this!
DATABASE_URL=mysql+pymysql://systemuser:StrongPass123!@localhost:3306/message_system

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Security - AES Encryption Key Path
AES_KEY_PATH=/opt/message_broker/main_server/secrets/aes.key

# JWT Configuration (CHANGE THESE IN PRODUCTION!)
JWT_SECRET=SuperSecretJWTKey_ChangeInProduction_Minimum32Characters
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=30

# Admin Credentials (Portal)
ADMIN_USER=admin@example.com
ADMIN_PASS=AdminPass123!  # Change this!

# TLS/Certificate Paths
CA_CERT_PATH=/opt/message_broker/main_server/certs/ca.crt
SERVER_KEY_PATH=/opt/message_broker/main_server/certs/server.key
SERVER_CERT_PATH=/opt/message_broker/main_server/certs/server.crt

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
LOG_FILE_PATH=/opt/message_broker/logs
LOG_ROTATION_DAYS=7

# Monitoring (Optional)
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
```

**Important:** Change all default passwords and secrets before production use!

### Step 22: Generate AES Encryption Key

```bash
# Create secrets directory
mkdir -p /opt/message_broker/main_server/secrets

# Generate AES key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" > /opt/message_broker/main_server/secrets/aes.key

# Set secure permissions
chmod 600 /opt/message_broker/main_server/secrets/aes.key
```

---

## Database Schema Initialization

### Step 23: Create Logs Directory

```bash
mkdir -p /opt/message_broker/logs
mkdir -p /opt/message_broker/main_server/logs
mkdir -p /opt/message_broker/proxy/logs
mkdir -p /opt/message_broker/worker/logs
mkdir -p /opt/message_broker/portal/logs
```

### Step 24: Run Database Migrations

```bash
cd /opt/message_broker

# Activate virtual environment
source venv/bin/activate

# Load .env file (IMPORTANT: This loads DB_PASSWORD and other variables)
export $(cat .env | grep -v '^#' | xargs)

# Verify DB_PASSWORD is set (should show your password)
echo "DB_PASSWORD is set: $([ -n "$DB_PASSWORD" ] && echo 'YES' || echo 'NO')"

# Set PYTHONPATH
export PYTHONPATH=/opt/message_broker

# Navigate to main_server
cd main_server

# Run migrations
alembic upgrade head
```

**Important:** If you get a database connection error, make sure:
1. `DB_PASSWORD` is set in your `.env` file
2. The password in `.env` matches your actual MySQL/MariaDB password
3. You've loaded the `.env` file with `export $(cat .env | grep -v '^#' | xargs)`

**Expected output:**
```
INFO  [alembic.runtime.migration] Context impl MySQLImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade -> <revision>, <message>
```

### Step 25: Verify Database Tables

```bash
mysql -u systemuser -p message_system -e "SHOW TABLES;"
```

You should see tables like: `users`, `messages`, `clients`, `certificates`, etc.

---

## Service User Creation

### Step 26: Create Service User

```bash
# Create system user for running services
sudo useradd -r -s /bin/false -d /opt/message_broker messagebroker

# Set ownership
sudo chown -R messagebroker:messagebroker /opt/message_broker

# Set directory permissions
sudo chmod 755 /opt/message_broker
sudo chmod -R 700 /opt/message_broker/main_server/certs
sudo chmod -R 600 /opt/message_broker/main_server/certs/*.key
sudo chmod -R 600 /opt/message_broker/main_server/secrets
sudo chmod -R 755 /opt/message_broker/logs
```

---

## Systemd Service Installation

### Step 27: Update Service Files (if needed)

Check and update service files to match your installation path:

```bash
# Verify service files exist
ls -la /opt/message_broker/main_server/main_server.service
ls -la /opt/message_broker/proxy/proxy.service
ls -la /opt/message_broker/worker/worker.service
ls -la /opt/message_broker/portal/portal.service
```

### Step 28: Install Systemd Services

```bash
# Copy service files
sudo cp /opt/message_broker/main_server/main_server.service /etc/systemd/system/
sudo cp /opt/message_broker/proxy/proxy.service /etc/systemd/system/
sudo cp /opt/message_broker/worker/worker.service /etc/systemd/system/
sudo cp /opt/message_broker/portal/portal.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services (auto-start on boot)
sudo systemctl enable main_server
sudo systemctl enable proxy
sudo systemctl enable worker
sudo systemctl enable portal
```

---

## Starting Services

### Step 29: Start Services in Order

**Important:** Start services in this order:

```bash
# 1. Start Main Server (must be first)
sudo systemctl start main_server

# Wait a few seconds, then check status
sudo systemctl status main_server

# 2. Start Proxy Server
sudo systemctl start proxy
sudo systemctl status proxy

# 3. Start Worker
sudo systemctl start worker
sudo systemctl status worker

# 4. Start Portal
sudo systemctl start portal
sudo systemctl status portal
```

### Step 30: Check All Service Status

```bash
# Check all services at once
sudo systemctl status main_server proxy worker portal

# Or individually
sudo systemctl is-active main_server
sudo systemctl is-active proxy
sudo systemctl is-active worker
sudo systemctl is-active portal
```

All should show `active (running)`.

---

## Verification and Testing

### Step 31: Check Service Logs

```bash
# View logs for each service
sudo journalctl -u main_server -f
sudo journalctl -u proxy -f
sudo journalctl -u worker -f
sudo journalctl -u portal -f

# View last 50 lines
sudo journalctl -u main_server -n 50
```

### Step 32: Test Health Endpoints

```bash
# Test Main Server (HTTPS)
curl -k https://localhost:8000/health

# Expected: {"status":"ok","database":"connected","redis":"connected"}

# Test Proxy Server (HTTPS)
curl -k https://localhost:8001/api/v1/health

# Expected: {"status":"healthy","redis":"connected"}

# Test Portal (HTTP)
curl http://localhost:8080/

# Expected: HTML response (login page)
```

### Step 33: Verify Ports are Listening

```bash
# Check if services are listening on expected ports
sudo netstat -tlnp | grep -E "(8000|8001|8080)"
# or
sudo ss -tlnp | grep -E "(8000|8001|8080)"
```

You should see:
- Port 8000 (Main Server)
- Port 8001 (Proxy)
- Port 8080 (Portal)

---

## Creating Admin User

### Step 34: Create First Admin User

**Option A: Using admin_cli.py (Recommended)**

```bash
cd /opt/message_broker
source venv/bin/activate
cd main_server

# Create admin user
python3 admin_cli.py user create admin@example.com --role admin --password "YourSecurePassword123!"
```

**Option B: Using create_admin.sh script**

```bash
cd /opt/message_broker
chmod +x create_admin.sh
./create_admin.sh admin@example.com "YourSecurePassword123!"
```

**Option C: Using create_admin_user.py**

```bash
cd /opt/message_broker
source venv/bin/activate
python3 create_admin_user.py admin@example.com "YourSecurePassword123!"
```

### Step 35: Verify Admin User

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate

# List users
python3 admin_cli.py user list
```

You should see your admin user listed.

---

## Firewall Configuration

### Step 36: Configure Firewall

**For Ubuntu/Debian (UFW):**
```bash
# Allow required ports
sudo ufw allow 8000/tcp  # Main Server
sudo ufw allow 8001/tcp  # Proxy
sudo ufw allow 8080/tcp  # Portal
sudo ufw allow 22/tcp    # SSH (if not already allowed)

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status
```

**For CentOS/RHEL (firewalld):**
```bash
# Allow required ports
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --permanent --add-port=8001/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=22/tcp

# Reload firewall
sudo firewall-cmd --reload

# Check status
sudo firewall-cmd --list-all
```

---

## Accessing the Services

After successful setup, you can access:

- **Web Portal**: `http://<SERVER_IP>:8080`
  - Login with the admin credentials you created

- **Main Server API Docs**: `https://<SERVER_IP>:8000/docs`
  - Note: You'll need to accept the self-signed certificate warning

- **Proxy API Docs**: `https://<SERVER_IP>:8001/api/v1/docs`
  - Note: Requires client certificate for full access

---

## Service Management Commands

### Start Services
```bash
sudo systemctl start main_server proxy worker portal
```

### Stop Services
```bash
sudo systemctl stop portal worker proxy main_server
```

### Restart Services
```bash
sudo systemctl restart main_server
sudo systemctl restart proxy
sudo systemctl restart worker
sudo systemctl restart portal
```

### Check Service Status
```bash
sudo systemctl status main_server
sudo systemctl status proxy
sudo systemctl status worker
sudo systemctl status portal
```

### View Service Logs
```bash
# Real-time logs
sudo journalctl -u main_server -f
sudo journalctl -u proxy -f
sudo journalctl -u worker -f
sudo journalctl -u portal -f

# Last 100 lines
sudo journalctl -u main_server -n 100

# Logs since boot
sudo journalctl -u main_server -b
```

### Enable/Disable Auto-start
```bash
# Enable auto-start on boot
sudo systemctl enable main_server proxy worker portal

# Disable auto-start
sudo systemctl disable main_server proxy worker portal
```

---

## Troubleshooting

### Problem: Service Won't Start

**Check service status:**
```bash
sudo systemctl status <service_name>
```

**View detailed logs:**
```bash
sudo journalctl -u <service_name> -n 50
```

**Common issues:**
- Certificate files missing or wrong permissions
- Database connection failed (check MySQL is running)
- Redis connection failed (check Redis is running)
- Port already in use

### Problem: Database Connection Error

```bash
# Check MySQL is running
sudo systemctl status mysql  # or mysqld

# Test connection
mysql -u systemuser -p message_system

# Check database exists
mysql -u root -p -e "SHOW DATABASES;"

# Verify user permissions
mysql -u root -p -e "SHOW GRANTS FOR 'systemuser'@'localhost';"
```

### Problem: Missing DB_PASSWORD Environment Variable

**Symptom:** Database connection fails even though user exists and other variables are set.

**Solution:**

```bash
# 1. Check if DB_PASSWORD is set
echo $DB_PASSWORD
# If empty, you need to set it

# 2. Load .env file
cd /opt/message_broker
export $(cat .env | grep -v '^#' | xargs)

# 3. Verify DB_PASSWORD is now set
echo "DB_PASSWORD: $DB_PASSWORD"

# 4. Make sure password in .env matches your actual MySQL password
# Edit .env if needed
nano .env
# Update: DB_PASSWORD=YourActualPasswordHere

# 5. Test connection with the password
mysql -u systemuser -p message_system
# Enter the password from .env

# 6. Now run migrations
cd main_server
export PYTHONPATH=/opt/message_broker
alembic upgrade head
```

**See also:** `FIX_DB_PASSWORD_ERROR.md` for detailed troubleshooting.

### Problem: Redis Connection Error

```bash
# Check Redis is running
sudo systemctl status redis

# Test connection
redis-cli ping
# Should return: PONG

# Check Redis is listening
sudo netstat -tlnp | grep 6379
```

### Problem: Certificate Errors

```bash
# Verify certificates exist
ls -la /opt/message_broker/main_server/certs/

# Check certificate validity
openssl x509 -in /opt/message_broker/main_server/certs/server.crt -text -noout

# Verify permissions
ls -l /opt/message_broker/main_server/certs/*.key
# Should show 600 permissions
```

### Problem: Port Already in Use

```bash
# Find process using port
sudo lsof -i :8000
sudo lsof -i :8001
sudo lsof -i :8080

# Kill process (replace PID)
sudo kill -9 <PID>
```

### Problem: Permission Denied

```bash
# Fix ownership
sudo chown -R messagebroker:messagebroker /opt/message_broker

# Fix certificate permissions
sudo chmod 600 /opt/message_broker/main_server/certs/*.key
sudo chmod 644 /opt/message_broker/main_server/certs/*.crt
```

### Problem: Import Errors / Module Not Found

```bash
# Ensure virtual environment is activated
source /opt/message_broker/venv/bin/activate

# Reinstall dependencies
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

### Problem: Database Schema Missing

```bash
cd /opt/message_broker
source venv/bin/activate

# Load .env file (IMPORTANT!)
export $(cat .env | grep -v '^#' | xargs)

# Set PYTHONPATH
export PYTHONPATH=/opt/message_broker

# Navigate to main_server
cd main_server

# Run migrations
alembic upgrade head

# Verify tables
mysql -u systemuser -p message_system -e "SHOW TABLES;"
```

---

## Quick Reference

### Essential Commands

```bash
# Start all services
sudo systemctl start main_server proxy worker portal

# Stop all services
sudo systemctl stop portal worker proxy main_server

# Check status
sudo systemctl status main_server proxy worker portal

# View logs
sudo journalctl -u main_server -f

# Restart a service
sudo systemctl restart main_server

# Test health
curl -k https://localhost:8000/health
curl -k https://localhost:8001/api/v1/health
curl http://localhost:8080/
```

### File Locations

- **Project Root**: `/opt/message_broker`
- **Environment File**: `/opt/message_broker/.env`
- **Certificates**: `/opt/message_broker/main_server/certs/`
- **Logs**: `/opt/message_broker/logs/`
- **Service Files**: `/etc/systemd/system/*.service`

### Default Ports

- **Main Server**: 8000 (HTTPS)
- **Proxy Server**: 8001 (HTTPS)
- **Portal**: 8080 (HTTP)
- **MySQL**: 3306
- **Redis**: 6379

---

## Next Steps

After successful setup:

1. **Change Default Passwords**: Update all default passwords in `.env`
2. **Generate Production Certificates**: Don't use test certificates in production
3. **Configure SSL/TLS**: Set up proper domain certificates if needed
4. **Set Up Monitoring**: Configure Prometheus and Grafana (optional)
5. **Set Up Backups**: Configure database and certificate backups
6. **Review Security**: Harden firewall rules and review file permissions
7. **Create Client Certificates**: Generate certificates for your clients
8. **Test Message Flow**: Send test messages to verify end-to-end functionality

---

## Additional Resources

- **Main README**: See `README.md` for project overview
- **Deployment Guide**: See `DEPLOYMENT_GUIDE.md` for production deployment
- **User Manual**: See `docs/USER_MANUAL.md` for portal usage
- **Admin Manual**: See `docs/ADMIN_MANUAL.md` for administration
- **Troubleshooting**: See `TROUBLESHOOTING_MYSQL.md` for MySQL-specific issues

---

## Support

If you encounter issues:

1. Check service logs: `sudo journalctl -u <service_name> -n 100`
2. Verify all prerequisites are met
3. Review the troubleshooting section above
4. Check service status: `sudo systemctl status <service_name>`
5. Verify configuration files and environment variables

---

**Setup Complete!** 🎉

Your Message Broker system should now be running on Linux. Access the web portal at `http://<SERVER_IP>:8080` and log in with your admin credentials.

