# Complete Linux Deployment Guide - Message Broker System

This comprehensive guide will help you deploy the Message Broker System on a fresh Linux distribution.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Prerequisites Installation](#prerequisites-installation)
3. [Project Setup](#project-setup)
4. [Database Configuration](#database-configuration)
5. [Certificate Setup](#certificate-setup)
6. [Environment Configuration](#environment-configuration)
7. [Running Migrations](#running-migrations)
8. [Service Installation](#service-installation)
9. [Verification and Testing](#verification-and-testing)
10. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Minimum Requirements
- **OS**: Ubuntu 20.04+, Debian 11+, CentOS 8+, or RHEL 8+
- **RAM**: 2GB minimum (4GB recommended)
- **Disk**: 10GB free space
- **CPU**: 2 cores minimum

### Required Software
- Python 3.11 or higher
- MySQL 8.0+ or MariaDB 10.5+
- Redis 6.0+
- OpenSSL 1.1.1+
- systemd (usually pre-installed)

---

## Prerequisites Installation

### Ubuntu/Debian

```bash
# Update package list
sudo apt update && sudo apt upgrade -y

# Install Python and build tools
sudo apt install -y python3 python3-pip python3-venv python3-dev build-essential

# Install MySQL
sudo apt install -y mysql-server mysql-client

# Install Redis
sudo apt install -y redis-server

# Install OpenSSL and other utilities
sudo apt install -y openssl curl wget git

# Install MySQL client library for Python
sudo apt install -y default-libmysqlclient-dev pkg-config
```

### CentOS/RHEL/Rocky Linux

```bash
# Update package list
sudo yum update -y

# Install EPEL repository (for some packages)
sudo yum install -y epel-release

# Install Python and build tools
sudo yum install -y python3 python3-pip python3-devel gcc gcc-c++ make

# Install MySQL
sudo yum install -y mysql-server mysql

# Install Redis
sudo yum install -y redis

# Install OpenSSL and utilities
sudo yum install -y openssl curl wget git

# Install MySQL client library
sudo yum install -y mysql-devel pkgconfig
```

### Start Required Services

```bash
# Start and enable MySQL
sudo systemctl start mysql
sudo systemctl enable mysql

# Start and enable Redis
sudo systemctl start redis
sudo systemctl enable redis

# Verify services are running
sudo systemctl status mysql
sudo systemctl status redis
```

---

## Project Setup

### 1. Extract and Prepare Project

```bash
# Create application directory
sudo mkdir -p /opt/message_broker
sudo chown $USER:$USER /opt/message_broker

# Extract the zip file (adjust path as needed)
cd /opt
unzip message_broker.zip -d message_broker
# OR if you have the files already:
# cd /opt/message_broker

# Verify structure
ls -la /opt/message_broker
```

Expected directory structure:
```
/opt/message_broker/
├── main_server/
├── proxy/
├── worker/
├── portal/
├── client-scripts/
├── tests/
└── requirements files
```

### 2. Create Virtual Environment

```bash
cd /opt/message_broker

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel
```

### 3. Install Python Dependencies

```bash
# Install all requirements
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt

# If you have a root requirements.txt, install it too
# pip install -r requirements.txt
```

**Note**: If you encounter issues with `mysqlclient`, you can use `pymysql` instead:
```bash
pip install pymysql
```

---

## Database Configuration

### 1. Secure MySQL Installation

```bash
# Run MySQL secure installation (set root password)
sudo mysql_secure_installation
```

### 2. Create Database and User

```bash
# Login to MySQL as root
sudo mysql -u root -p
```

In MySQL prompt:
```sql
-- Create database
CREATE DATABASE message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create user (replace 'StrongPass123!' with a strong password)
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'StrongPass123!';

-- Grant privileges
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;

-- Verify
SHOW DATABASES;
SELECT user, host FROM mysql.user WHERE user = 'systemuser';

-- Exit
EXIT;
```

### 3. Test Database Connection

```bash
# Test connection
mysql -u systemuser -p message_system
# Enter password when prompted
# Type EXIT; to leave
```

---

## Certificate Setup

### 1. Initialize Certificate Authority

```bash
cd /opt/message_broker/main_server/certs

# Create CA private key
openssl genrsa -out ca.key 4096

# Create CA certificate (valid for 10 years)
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
    -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"

# Set secure permissions
chmod 600 ca.key
chmod 644 ca.crt
```

### 2. Generate Server Certificate

```bash
# Generate server private key
openssl genrsa -out server.key 2048

# Create certificate signing request
openssl req -new -key server.key -out server.csr \
    -subj "/CN=main-server/O=MessageBroker/C=US"

# Sign certificate with CA (valid for 1 year)
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out server.crt -days 365 -sha256

# Clean up CSR
rm server.csr

# Set permissions
chmod 600 server.key
chmod 644 server.crt
```

### 3. Generate Proxy Certificate

```bash
cd /opt/message_broker/proxy/certs

# Generate proxy private key
openssl genrsa -out proxy.key 2048

# Create CSR
openssl req -new -key proxy.key -out proxy.csr \
    -subj "/CN=proxy-server/O=MessageBroker/C=US"

# Sign with CA
openssl x509 -req -in proxy.csr -CA ../main_server/certs/ca.crt \
    -CAkey ../main_server/certs/ca.key -CAcreateserial \
    -out proxy.crt -days 365 -sha256

# Clean up
rm proxy.csr

# Set permissions
chmod 600 proxy.key
chmod 644 proxy.crt
```

### 4. Create Certificate Revocation List (CRL)

```bash
cd /opt/message_broker/main_server/crl

# Create empty CRL
openssl ca -gencrl -keyfile ../certs/ca.key -cert ../certs/ca.crt \
    -out revoked.pem -config <(echo '[ca]'; echo 'default_ca=CA_default'; echo '[CA_default]'; echo 'dir=.')

# If the above doesn't work, create an empty CRL file
touch revoked.pem
chmod 644 revoked.pem
```

### 5. Generate Test Client Certificate

```bash
cd /opt/message_broker/main_server/certs/clients
mkdir -p test_client

# Generate client key
openssl genrsa -out test_client/test_client.key 2048

# Create CSR
openssl req -new -key test_client/test_client.key \
    -out test_client/test_client.csr \
    -subj "/CN=test_client/O=MessageBroker/OU=default"

# Sign with CA
openssl x509 -req -in test_client/test_client.csr \
    -CA ../ca.crt -CAkey ../ca.key -CAcreateserial \
    -out test_client/test_client.crt -days 365 -sha256

# Copy CA cert for client
cp ../ca.crt test_client/

# Set permissions
chmod 600 test_client/test_client.key
chmod 644 test_client/test_client.crt
chmod 644 test_client/ca.crt
```

---

## Environment Configuration

### 1. Create .env File

```bash
cd /opt/message_broker

# Create .env file
cat > .env << 'EOF'
# Database Configuration
DATABASE_URL=mysql+pymysql://systemuser:StrongPass123!@localhost:3306/message_system
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=StrongPass123!

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Security - Encryption Key Path
ENCRYPTION_KEY_PATH=/opt/message_broker/main_server/secrets/encryption.key
HASH_SALT=message_broker_salt_change_in_production

# JWT Configuration
JWT_SECRET=change_this_secret_in_production_use_random_string
JWT_ALGORITHM=HS256
JWT_EXPIRATION_HOURS=24
JWT_REFRESH_EXPIRATION_DAYS=30

# Main Server Configuration
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000

# Proxy Configuration
PROXY_URL=https://localhost:8001
PROXY_HOST=0.0.0.0
PROXY_PORT=8001

# Portal Configuration
PORTAL_URL=http://localhost:8080
PORTAL_HOST=0.0.0.0
PORTAL_PORT=8080

# Worker Configuration
WORKER_RETRY_INTERVAL=30
WORKER_MAX_ATTEMPTS=10000
WORKER_CONCURRENCY=4

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=/opt/message_broker/logs

# Monitoring
METRICS_ENABLED=true
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
EOF

# Set secure permissions
chmod 600 .env
```

**⚠️ IMPORTANT**: Change the following in production:
- `DB_PASSWORD`: Use a strong database password
- `JWT_SECRET`: Generate a random secret (use `openssl rand -hex 32`)
- `HASH_SALT`: Generate a random salt

### 2. Generate Encryption Key

```bash
# Create secrets directory
mkdir -p /opt/message_broker/main_server/secrets

# Generate encryption key
openssl rand -base64 32 > /opt/message_broker/main_server/secrets/encryption.key

# Set secure permissions
chmod 600 /opt/message_broker/main_server/secrets/encryption.key
```

### 3. Create Logs Directory

```bash
mkdir -p /opt/message_broker/logs
mkdir -p /opt/message_broker/main_server/logs
mkdir -p /opt/message_broker/proxy/logs
mkdir -p /opt/message_broker/worker/logs
mkdir -p /opt/message_broker/portal/logs
```

---

## Running Migrations

### 1. Set PYTHONPATH

```bash
export PYTHONPATH=/opt/message_broker
```

To make it permanent, add to `~/.bashrc`:
```bash
echo 'export PYTHONPATH=/opt/message_broker' >> ~/.bashrc
source ~/.bashrc
```

### 2. Run Database Migrations

**⚠️ IMPORTANT**: Before running migrations, ensure:
1. MySQL user `systemuser` exists (see Database Configuration section above)
2. The password in `.env` matches the MySQL user password
3. Environment variables are set correctly

**Option 1: Using Migration Script (Recommended)**

The `run_migrations.sh` script automatically loads credentials from `.env`:

```bash
cd /opt/message_broker
source venv/bin/activate
export PYTHONPATH=/opt/message_broker
bash run_migrations.sh
```

**Option 2: Manual Migration with Environment Variables**

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate

# Set PYTHONPATH
export PYTHONPATH=/opt/message_broker

# Set environment variables for Alembic
# ⚠️ Replace 'StrongPass123!' with your actual database password!
export DB_HOST=localhost
export DB_PORT=3306
export DB_NAME=message_system
export DB_USER=systemuser
export DB_PASSWORD=StrongPass123!  # Use your actual password!

# Run migrations
alembic upgrade head
```

**If you get "Access denied" error**, see `TROUBLESHOOTING_MYSQL.md` for detailed fix instructions.

### 3. Verify Database Tables

```bash
mysql -u systemuser -p message_system -e "SHOW TABLES;"
```

You should see tables like: `users`, `clients`, `messages`, `audit_logs`, etc.

---

## Service Installation

### 1. Create Service User

```bash
# Create dedicated user for running services
sudo useradd -r -s /bin/false -d /opt/message_broker messagebroker

# Set ownership
sudo chown -R messagebroker:messagebroker /opt/message_broker

# Set directory permissions
sudo chmod 755 /opt/message_broker
```

### 2. Update Service Files

Edit the service files to match your installation path. Check each service file:

```bash
# Main Server
cat /opt/message_broker/main_server/main_server.service

# Proxy
cat /opt/message_broker/proxy/proxy.service

# Worker
cat /opt/message_broker/worker/worker.service

# Portal
cat /opt/message_broker/portal/portal.service
```

Ensure they point to:
- WorkingDirectory: `/opt/message_broker/main_server` (or respective directory)
- ExecStart: `/opt/message_broker/venv/bin/python ...`
- User: `messagebroker`

### 3. Install Systemd Services

```bash
# Copy service files
sudo cp /opt/message_broker/main_server/main_server.service /etc/systemd/system/
sudo cp /opt/message_broker/proxy/proxy.service /etc/systemd/system/
sudo cp /opt/message_broker/worker/worker.service /etc/systemd/system/
sudo cp /opt/message_broker/portal/portal.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services (start on boot)
sudo systemctl enable main_server
sudo systemctl enable proxy
sudo systemctl enable worker
sudo systemctl enable portal
```

### 4. Set Proper Permissions

```bash
# Certificate directories
sudo chmod 700 /opt/message_broker/main_server/certs
sudo chmod 700 /opt/message_broker/proxy/certs
sudo chmod 600 /opt/message_broker/main_server/certs/*.key
sudo chmod 600 /opt/message_broker/proxy/certs/*.key

# Secrets directory
sudo chmod 700 /opt/message_broker/main_server/secrets
sudo chmod 600 /opt/message_broker/main_server/secrets/*

# Logs (service user needs write access)
sudo chmod 755 /opt/message_broker/logs
sudo chown -R messagebroker:messagebroker /opt/message_broker/logs
```

### 5. Start Services

```bash
# Start services in order
sudo systemctl start main_server
sleep 2
sudo systemctl start proxy
sleep 2
sudo systemctl start worker
sleep 2
sudo systemctl start portal

# Check status
sudo systemctl status main_server
sudo systemctl status proxy
sudo systemctl status worker
sudo systemctl status portal
```

### 6. View Logs

```bash
# View service logs
sudo journalctl -u main_server -f
sudo journalctl -u proxy -f
sudo journalctl -u worker -f
sudo journalctl -u portal -f

# View application logs
tail -f /opt/message_broker/logs/main_server.log
tail -f /opt/message_broker/logs/proxy.log
tail -f /opt/message_broker/logs/worker.log
tail -f /opt/message_broker/logs/portal.log
```

---

## Verification and Testing

### 1. Check Service Health

```bash
# Check if services are running
sudo systemctl is-active main_server proxy worker portal

# Check ports
sudo netstat -tlnp | grep -E '8000|8001|8080'
# OR
sudo ss -tlnp | grep -E '8000|8001|8080'
```

### 2. Test API Endpoints

```bash
# Test Main Server (should return 401 or similar - means server is up)
curl -k https://localhost:8000/health

# Test Proxy
curl -k https://localhost:8001/health

# Test Portal
curl http://localhost:8080/
```

### 3. Create Admin User

```bash
cd /opt/message_broker
source venv/bin/activate

# Use the admin creation script
python create_admin_user.py

# Or use the admin CLI
cd main_server
python admin_cli.py users create \
    --username admin@example.com \
    --password AdminPass123! \
    --role admin
```

### 4. Test Portal Login

```bash
# Open in browser
http://your-server-ip:8080

# Or test with curl
curl -X POST http://localhost:8080/login \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin@example.com&password=AdminPass123!"
```

### 5. Test Message Sending

```bash
cd /opt/message_broker/client-scripts

# Activate venv
source ../../venv/bin/activate

# Send a test message
python send_message.py \
    --proxy-url https://localhost:8001 \
    --cert test_client/test_client.crt \
    --key test_client/test_client.key \
    --ca-cert test_client/ca.crt \
    --recipient "+1234567890" \
    --message "Test message from Linux deployment"
```

---

## Troubleshooting

### Common Issues

#### 1. ModuleNotFoundError: No module named 'main_server.models'

**Solution**: Ensure PYTHONPATH is set:
```bash
export PYTHONPATH=/opt/message_broker
```

This has been fixed in `main_server/database.py`, but ensure the path is set when running migrations.

#### 2. Database Connection Errors

**Most Common**: "Access denied for user 'systemuser'@'localhost'"

**See**: `TROUBLESHOOTING_MYSQL.md` for complete step-by-step fix.

**Quick Check**:
- MySQL is running: `sudo systemctl status mysql`
- Database exists: `mysql -u systemuser -p -e "SHOW DATABASES;"`
- Credentials in `.env` are correct
- MySQL user exists: `sudo mysql -u root -p -e "SELECT user, host FROM mysql.user WHERE user = 'systemuser';"`
- Firewall allows MySQL connections

#### 3. Certificate Errors

**Check**:
- Certificates exist in correct directories
- Permissions are correct (600 for keys, 644 for certs)
- CA certificate is properly signed
- Certificate paths in service files are correct

#### 4. Service Won't Start

**Check logs**:
```bash
sudo journalctl -u main_server -n 50
```

**Common fixes**:
- Verify Python path in service file
- Check file permissions
- Ensure virtual environment is accessible
- Verify .env file exists and is readable

#### 5. Port Already in Use

**Find process using port**:
```bash
sudo lsof -i :8000
sudo lsof -i :8001
sudo lsof -i :8080
```

**Kill process** (if needed):
```bash
sudo kill -9 <PID>
```

#### 6. Permission Denied Errors

**Fix permissions**:
```bash
sudo chown -R messagebroker:messagebroker /opt/message_broker
sudo chmod 755 /opt/message_broker
sudo chmod -R 755 /opt/message_broker/logs
```

### Debug Mode

Run services manually for debugging:

```bash
cd /opt/message_broker/main_server
source ../venv/bin/activate
export PYTHONPATH=/opt/message_broker
python -m uvicorn api:app --host 0.0.0.0 --port 8000 \
    --ssl-keyfile certs/server.key \
    --ssl-certfile certs/server.crt \
    --ssl-ca-certs certs/ca.crt \
    --log-level debug
```

---

## Firewall Configuration

If you have a firewall enabled, open required ports:

### UFW (Ubuntu/Debian)

```bash
sudo ufw allow 8000/tcp   # Main Server
sudo ufw allow 8001/tcp   # Proxy
sudo ufw allow 8080/tcp   # Portal
sudo ufw allow 3306/tcp   # MySQL (if remote access needed)
sudo ufw allow 6379/tcp   # Redis (if remote access needed)
sudo ufw reload
```

### firewalld (CentOS/RHEL)

```bash
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --permanent --add-port=8001/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=3306/tcp
sudo firewall-cmd --permanent --add-port=6379/tcp
sudo firewall-cmd --reload
```

---

## Maintenance

### Update Services

```bash
# Stop services
sudo systemctl stop portal worker proxy main_server

# Update code (if using git)
cd /opt/message_broker
git pull  # or extract new zip

# Update dependencies
source venv/bin/activate
pip install -r main_server/requirements.txt --upgrade

# Run migrations if needed
cd main_server
alembic upgrade head

# Start services
sudo systemctl start main_server proxy worker portal
```

### Backup

```bash
# Backup database
mysqldump -u systemuser -p message_system > backup_$(date +%Y%m%d).sql

# Backup certificates and secrets
tar -czf backup_certs_$(date +%Y%m%d).tar.gz \
    main_server/certs main_server/secrets proxy/certs

# Backup configuration
tar -czf backup_config_$(date +%Y%m%d).tar.gz .env
```

### Log Rotation

Logs are automatically rotated by the application. To manually clean old logs:

```bash
find /opt/message_broker/logs -name "*.log.*" -mtime +30 -delete
```

---

## Security Checklist

- [ ] Changed default database password
- [ ] Changed JWT_SECRET to a random value
- [ ] Changed HASH_SALT to a random value
- [ ] Set proper file permissions (600 for keys, 644 for certs)
- [ ] Created dedicated service user
- [ ] Configured firewall rules
- [ ] Enabled SSL/TLS for all services
- [ ] Restricted database access (localhost only if possible)
- [ ] Set up log monitoring
- [ ] Configured automatic backups
- [ ] Updated system packages regularly

---

## Support

For issues or questions:
1. Check logs: `sudo journalctl -u <service-name> -f`
2. Review this guide's troubleshooting section
3. Check application logs in `/opt/message_broker/logs/`
4. Verify all prerequisites are installed and running

---

## Quick Reference Commands

```bash
# Service management
sudo systemctl start|stop|restart|status main_server
sudo systemctl start|stop|restart|status proxy
sudo systemctl start|stop|restart|status worker
sudo systemctl start|stop|restart|status portal

# View logs
sudo journalctl -u main_server -f
tail -f /opt/message_broker/logs/main_server.log

# Database
mysql -u systemuser -p message_system
alembic upgrade head  # Run migrations

# Activate virtual environment
source /opt/message_broker/venv/bin/activate
```

---

**Last Updated**: 2025-01-31  
**Version**: 1.0.0

