# Message Broker System - Deployment Guide

**Version**: 1.0.0  
**Target Platform**: Windows Server 2019/2022  
**Date**: October 2025  
**Status**: Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [System Requirements](#system-requirements)
4. [Pre-Deployment Checklist](#pre-deployment-checklist)
5. [Installation Steps](#installation-steps)
6. [Service Configuration](#service-configuration)
7. [Security Hardening](#security-hardening)
8. [Backup & Restore](#backup--restore)
9. [Monitoring Setup](#monitoring-setup)
10. [Troubleshooting](#troubleshooting)
11. [Post-Deployment Verification](#post-deployment-verification)

---

## Overview

The Message Broker System consists of four main components:

1. **Proxy Server** (Port 8001) - Client-facing message ingestion
2. **Main Server** (Port 8000) - Core API and database management
3. **Worker** (Port 9100) - Message processing and delivery
4. **Web Portal** (Port 5000) - User and admin interfaces

All components communicate via Mutual TLS (mTLS) for secure authentication.

---

## Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| **Windows Server** | 2019/2022 | Operating System |
| **Python** | 3.8+ | Application Runtime |
| **MySQL** | 8.0+ | Database Server |
| **Redis (Memurai)** | 4.1+ | Message Queue |
| **OpenSSL** | 3.0+ | Certificate Management |
| **PowerShell** | 5.1+ | Deployment Scripts |

### Optional Software

| Software | Version | Purpose |
|----------|---------|---------|
| **IIS** | 10.0+ | Web Server (Alternative to uvicorn) |
| **Prometheus** | Latest | Metrics Collection |
| **Grafana** | Latest | Metrics Visualization |

---

## System Requirements

### Minimum Requirements

- **CPU**: 4 cores
- **RAM**: 8 GB
- **Disk**: 50 GB SSD
- **Network**: 100 Mbps

### Recommended Requirements (100k messages/day)

- **CPU**: 8+ cores
- **RAM**: 16 GB
- **Disk**: 200 GB SSD (RAID 1 for database)
- **Network**: 1 Gbps

### Port Requirements

| Port | Component | Protocol | Direction |
|------|-----------|----------|-----------|
| 3306 | MySQL | TCP | Inbound (localhost only) |
| 6379 | Redis | TCP | Inbound (localhost only) |
| 8000 | Main Server | HTTPS | Inbound |
| 8001 | Proxy | HTTPS | Inbound |
| 5000 | Portal | HTTPS | Inbound |
| 9100 | Worker Metrics | HTTP | Inbound (monitoring) |

---

## Pre-Deployment Checklist

### Infrastructure

- [ ] Windows Server installed and patched
- [ ] Firewall rules configured
- [ ] DNS records configured
- [ ] SSL/TLS certificates prepared
- [ ] Backup storage configured

### Software Installation

- [ ] Python installed and in PATH
- [ ] MySQL installed and service running
- [ ] Redis/Memurai installed and service running
- [ ] OpenSSL installed
- [ ] Git installed (for code deployment)

### Security

- [ ] Service accounts created (least privilege)
- [ ] File permissions configured
- [ ] Encryption keys generated
- [ ] Certificate Authority initialized
- [ ] Firewall rules tested

### Network

- [ ] Domain names configured
- [ ] Load balancer configured (if applicable)
- [ ] HTTPS certificates obtained
- [ ] Network connectivity verified

---

## Installation Steps

### Step 1: Install Base Software

```powershell
# Run as Administrator

# Install Chocolatey (if not already installed)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install required software
choco install python --version=3.12.0 -y
choco install mysql -y
choco install redis-64 -y
choco install openssl -y
choco install git -y

# Refresh environment
refreshenv
```

### Step 2: Configure MySQL

```powershell
# Start MySQL service
net start MySQL

# Secure MySQL installation
mysql_secure_installation

# Create database and user
mysql -u root -p << EOF
CREATE DATABASE IF NOT EXISTS message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'systemuser'@'localhost' IDENTIFIED BY 'YourStrongPasswordHere';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EOF
```

**Configure MySQL for Production** (`C:\ProgramData\MySQL\MySQL Server 8.0\my.ini`):

```ini
[mysqld]
# Bind to localhost only for security
bind-address = 127.0.0.1

# Performance settings
max_connections = 200
innodb_buffer_pool_size = 2G
innodb_log_file_size = 512M

# Character set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# Slow query log
slow_query_log = 1
slow_query_log_file = "C:/ProgramData/MySQL/slow-query.log"
long_query_time = 2

# Binary logging (for backups)
log_bin = mysql-bin
binlog_format = ROW
expire_logs_days = 7
```

Restart MySQL after configuration:

```powershell
net stop MySQL
net start MySQL
```

### Step 3: Configure Redis

**Redis Configuration** (Memurai: `C:\Program Files\Memurai\memurai.conf`):

```conf
# Network
bind 127.0.0.1
protected-mode yes
port 6379

# Memory
maxmemory 2gb
maxmemory-policy allkeys-lru

# Persistence (AOF for durability)
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# Performance
tcp-backlog 511
timeout 300
tcp-keepalive 300
```

Restart Redis/Memurai:

```powershell
Restart-Service Memurai
```

### Step 4: Deploy Application Code

```powershell
# Create application directory
$AppRoot = "C:\MessageBroker"
New-Item -ItemType Directory -Path $AppRoot -Force

# Clone repository (or copy files)
cd $AppRoot
git clone <your-repo-url> .

# OR copy files from deployment package
# Copy-Item -Path "\\deployment-share\message-broker\*" -Destination $AppRoot -Recurse
```

### Step 5: Create Python Virtual Environment

```powershell
cd $AppRoot

# Create virtual environment
python -m venv venv

# Activate virtual environment
.\venv\Scripts\Activate.ps1

# Upgrade pip
python -m pip install --upgrade pip

# Install dependencies for all components
pip install -r proxy/requirements.txt
pip install -r main_server/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

### Step 6: Generate Certificates

```powershell
cd $AppRoot\main_server

# Initialize Certificate Authority
.\init_ca.bat

# Generate component certificates
.\generate_cert.bat server localhost 3650
.\generate_cert.bat proxy localhost 3650
.\generate_cert.bat worker localhost 3650

# Copy certificates to component directories
Copy-Item certs\proxy.* ..\proxy\certs\ -Force
Copy-Item certs\worker.* ..\worker\certs\ -Force
Copy-Item certs\ca.crt ..\proxy\certs\ -Force
Copy-Item certs\ca.crt ..\worker\certs\ -Force
Copy-Item certs\ca.crt ..\portal\certs\ -Force
```

### Step 7: Configure Environment Variables

Create `$AppRoot\.env`:

```env
# Database Configuration
DATABASE_URL=mysql+pymysql://systemuser:YourStrongPasswordHere@localhost/message_system

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# Security
JWT_SECRET=YourVeryLongRandomSecretKeyHere
ENCRYPTION_KEY_PATH=secrets/encryption.key

# Application Settings
ENVIRONMENT=production
LOG_LEVEL=INFO
LOG_FILE_PATH=C:\MessageBroker\logs

# Server Settings
MAIN_SERVER_HOST=0.0.0.0
MAIN_SERVER_PORT=8000
PROXY_HOST=0.0.0.0
PROXY_PORT=8001
PORTAL_HOST=0.0.0.0
PORTAL_PORT=5000

# Metrics
METRICS_ENABLED=true
METRICS_PORT=9100

# Domain Configuration
PRIMARY_DOMAIN=yourdomain.com
```

### Step 8: Initialize Database Schema

```powershell
cd $AppRoot\main_server

# Activate virtual environment
& $AppRoot\venv\Scripts\Activate.ps1

# Run Alembic migrations
alembic upgrade head

# Verify tables
mysql -u systemuser -p message_system -e "SHOW TABLES;"
```

### Step 9: Create Admin User

```powershell
cd $AppRoot\main_server

# Use admin CLI to create first admin user
python admin_cli.py users create --email admin@yourdomain.com --password AdminPass123! --role admin
```

---

## Service Configuration

### Install as Windows Services

Use the provided installation scripts in `deployment/services/`:

```powershell
cd $AppRoot\deployment\services

# Install all services
.\install_all_services.ps1

# OR install individually
.\install_main_server_service.ps1
.\install_proxy_service.ps1
.\install_worker_service.ps1
.\install_portal_service.ps1
```

### Service Management Commands

```powershell
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

# Check service status
Get-Service MessageBroker*

# View service logs
Get-Content C:\MessageBroker\logs\main_server.log -Tail 50
Get-Content C:\MessageBroker\logs\proxy.log -Tail 50
Get-Content C:\MessageBroker\logs\worker.log -Tail 50
Get-Content C:\MessageBroker\logs\portal.log -Tail 50
```

### Service Startup Order

**Important**: Services must start in this order:

1. MySQL (dependency)
2. Redis/Memurai (dependency)
3. Main Server (core service)
4. Proxy (depends on Main Server)
5. Worker (depends on Main Server and Redis)
6. Portal (depends on Main Server)

The service installation scripts configure these dependencies automatically.

---

## Security Hardening

### 1. File Permissions

```powershell
# Restrict application directory
$AppRoot = "C:\MessageBroker"
icacls $AppRoot /inheritance:r
icacls $AppRoot /grant:r "Administrators:(OI)(CI)F"
icacls $AppRoot /grant:r "SYSTEM:(OI)(CI)F"
icacls $AppRoot /grant:r "NetworkService:(OI)(CI)RX"

# Protect certificate private keys
icacls "$AppRoot\main_server\certs\*.key" /inheritance:r
icacls "$AppRoot\main_server\certs\*.key" /grant:r "Administrators:F"
icacls "$AppRoot\main_server\certs\ca.key" /grant:r "SYSTEM:F"

# Protect encryption keys
icacls "$AppRoot\secrets" /inheritance:r
icacls "$AppRoot\secrets" /grant:r "Administrators:F"
icacls "$AppRoot\secrets" /grant:r "SYSTEM:R"
```

### 2. Firewall Configuration

```powershell
# Allow HTTPS traffic
New-NetFirewallRule -DisplayName "Message Broker - Main Server" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Message Broker - Proxy" -Direction Inbound -LocalPort 8001 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Message Broker - Portal" -Direction Inbound -LocalPort 5000 -Protocol TCP -Action Allow

# Allow metrics (restrict to monitoring subnet if possible)
New-NetFirewallRule -DisplayName "Message Broker - Metrics" -Direction Inbound -LocalPort 9100 -Protocol TCP -Action Allow

# Block direct access to MySQL and Redis (should already be bound to localhost)
New-NetFirewallRule -DisplayName "Block MySQL External" -Direction Inbound -LocalPort 3306 -Protocol TCP -Action Block
New-NetFirewallRule -DisplayName "Block Redis External" -Direction Inbound -LocalPort 6379 -Protocol TCP -Action Block
```

### 3. Service Account Configuration

**Recommended**: Create dedicated service accounts for each service.

```powershell
# Create service accounts (run as Domain Admin if domain-joined)
net user MessageBrokerService "ComplexPasswordHere" /add
net localgroup Users MessageBrokerService /delete

# Grant "Log on as a service" right
# Use Local Security Policy (secpol.msc) or:
# Computer Configuration > Windows Settings > Security Settings > Local Policies > User Rights Assignment > Log on as a service
```

Update service configuration to use the dedicated account:

```powershell
sc.exe config MessageBrokerMainServer obj= ".\MessageBrokerService" password= "ComplexPasswordHere"
sc.exe config MessageBrokerProxy obj= ".\MessageBrokerService" password= "ComplexPasswordHere"
sc.exe config MessageBrokerWorker obj= ".\MessageBrokerService" password= "ComplexPasswordHere"
sc.exe config MessageBrokerPortal obj= ".\MessageBrokerService" password= "ComplexPasswordHere"
```

### 4. MySQL Security

```sql
-- Restrict systemuser to localhost only
RENAME USER 'systemuser'@'%' TO 'systemuser'@'localhost';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Flush privileges
FLUSH PRIVILEGES;
```

### 5. Certificate Rotation Plan

- **CA Certificate**: Valid 10 years, rotate before expiration
- **Server Certificates**: Valid 1 year, rotate every 6-9 months
- **Client Certificates**: Valid 1 year, rotate on demand

Set calendar reminders for 30 days before expiration.

---

## Backup & Restore

### Automated Backup Configuration

Use the provided backup script: `deployment\backup\automated_backup.ps1`

**Schedule via Task Scheduler**:

```powershell
# Install backup task
cd $AppRoot\deployment\backup
.\install_backup_task.ps1
```

This creates a daily backup at 2 AM to `C:\Backups\MessageBroker\`.

### Manual Backup

```powershell
# Run backup script
cd $AppRoot\deployment\backup
.\backup.ps1
```

### Backup Contents

1. **MySQL Database** (compressed SQL dump)
2. **Redis AOF** (appendonly.aof)
3. **Configuration Files** (.env, config.yaml)
4. **Certificates** (*.crt, *.key)
5. **Application Logs** (last 7 days)

### Restore Procedure

```powershell
# Stop services
net stop MessageBrokerPortal
net stop MessageBrokerWorker
net stop MessageBrokerProxy
net stop MessageBrokerMainServer

# Restore database
mysql -u systemuser -p message_system < backup_YYYYMMDD_HHMMSS\database.sql

# Restore Redis
Copy-Item backup_YYYYMMDD_HHMMSS\appendonly.aof "C:\Program Files\Memurai\appendonly.aof"
Restart-Service Memurai

# Restore configuration
Copy-Item backup_YYYYMMDD_HHMMSS\.env C:\MessageBroker\.env

# Restore certificates (if needed)
Copy-Item backup_YYYYMMDD_HHMMSS\certs\* C:\MessageBroker\main_server\certs\

# Start services
net start MessageBrokerMainServer
net start MessageBrokerProxy
net start MessageBrokerWorker
net start MessageBrokerPortal
```

---

## Monitoring Setup

### Prometheus Configuration

Install Prometheus:

```powershell
choco install prometheus -y
```

Configure `C:\ProgramData\prometheus\prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'main-server'
    scheme: http
    static_configs:
      - targets: ['localhost:8000']

  - job_name: 'proxy'
    scheme: http
    static_configs:
      - targets: ['localhost:8001']

  - job_name: 'worker'
    scheme: http
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'portal'
    scheme: http
    static_configs:
      - targets: ['localhost:5000']
```

Start Prometheus as service:

```powershell
net start prometheus
```

### Grafana Configuration

Install Grafana:

```powershell
choco install grafana -y
net start grafana
```

Access Grafana at `http://localhost:3000` (default: admin/admin).

Import dashboard from `monitoring/grafana/dashboards/system_dashboard.json`.

---

## Troubleshooting

### Service Won't Start

**Check Event Viewer**:

```powershell
Get-EventLog -LogName Application -Source "Message Broker*" -Newest 50
```

**Check Service Logs**:

```powershell
Get-Content C:\MessageBroker\logs\*.log -Tail 100
```

**Common Issues**:

1. **Port Already in Use**:
   ```powershell
   netstat -ano | findstr "8000"
   # Kill process if needed
   taskkill /PID <pid> /F
   ```

2. **Database Connection Failed**:
   - Verify MySQL is running: `net start | findstr MySQL`
   - Test connection: `mysql -u systemuser -p message_system`
   - Check credentials in `.env`

3. **Certificate Errors**:
   - Verify certificate files exist
   - Check file permissions
   - Verify certificate validity: `openssl x509 -in cert.crt -noout -dates`

### Performance Issues

**Check System Resources**:

```powershell
# CPU and Memory
Get-Counter '\Processor(_Total)\% Processor Time','\Memory\Available MBytes'

# Disk I/O
Get-Counter '\PhysicalDisk(_Total)\Disk Transfers/sec'
```

**Check Database Performance**:

```sql
-- Slow queries
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;

-- Connection count
SHOW STATUS LIKE 'Threads_connected';

-- Table locks
SHOW OPEN TABLES WHERE In_use > 0;
```

**Check Redis Performance**:

```powershell
memurai-cli info stats
memurai-cli --latency
```

---

## Post-Deployment Verification

### Verification Checklist

- [ ] All services started successfully
- [ ] Health checks passing
  - Main Server: `curl https://localhost:8000/health`
  - Proxy: `curl https://localhost:8001/api/v1/health`
  - Worker: `curl http://localhost:9100/metrics`
  - Portal: `curl https://localhost:5000/health`

- [ ] Database connectivity confirmed
- [ ] Redis connectivity confirmed
- [ ] Certificates valid and trusted
- [ ] Message submission test successful
- [ ] Message delivery test successful
- [ ] Portal login successful
- [ ] Admin panel accessible
- [ ] Metrics visible in Prometheus/Grafana
- [ ] Logs rotating correctly
- [ ] Backups running on schedule

### Smoke Test Script

```powershell
# Run smoke test
cd $AppRoot\deployment\tests
.\smoke_test.ps1
```

This script verifies:
- All services running
- All endpoints responding
- Database accessible
- Redis accessible
- Can submit and retrieve a test message

---

## Deployment Completion

Once all verification steps pass:

1. Document any configuration changes
2. Update DNS records (if applicable)
3. Configure load balancer (if applicable)
4. Enable monitoring alerts
5. Schedule regular maintenance windows
6. Provide credentials and documentation to operations team

---

## Support & Maintenance

### Log Locations

- **Application Logs**: `C:\MessageBroker\logs\`
- **MySQL Logs**: `C:\ProgramData\MySQL\MySQL Server 8.0\Data\`
- **Redis Logs**: `C:\Program Files\Memurai\`
- **Windows Event Log**: Application log

### Regular Maintenance Tasks

**Daily**:
- Monitor error logs
- Check disk space
- Verify backups completed

**Weekly**:
- Review performance metrics
- Check for security updates
- Rotate logs (automated)

**Monthly**:
- Test backup restoration
- Review and clear old logs
- Update dependencies
- Review user access

**Quarterly**:
- Security audit
- Performance optimization review
- Capacity planning review
- Certificate expiration check

---

## Contact & Escalation

**Level 1 Support**: Check logs, restart services, verify connectivity  
**Level 2 Support**: Database issues, certificate problems, configuration changes  
**Level 3 Support**: Code changes, architecture changes, critical failures

---

**Deployment Guide Version**: 1.0.0  
**Last Updated**: October 2025  
**Next Review**: January 2026

