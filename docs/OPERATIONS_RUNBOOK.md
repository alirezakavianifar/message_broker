# Message Broker System - Operations Runbook

**Version**: 1.0.0  
**Platform**: Windows Server 2019/2022  
**Last Updated**: October 2025  
**Audience**: Operations Team, System Administrators

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Daily Operations](#daily-operations)
3. [Service Management](#service-management)
4. [Monitoring & Health Checks](#monitoring--health-checks)
5. [Backup & Recovery](#backup--recovery)
6. [Troubleshooting](#troubleshooting)
7. [Common Tasks](#common-tasks)
8. [Emergency Procedures](#emergency-procedures)
9. [Maintenance Windows](#maintenance-windows)
10. [Escalation Procedures](#escalation-procedures)

---

## System Overview

### Architecture

The Message Broker System consists of four main components:

```
┌─────────────┐        ┌──────────────┐        ┌──────────────┐
│   Clients   │───────▶│    Proxy     │───────▶│ Main Server  │
│  (mTLS)     │        │  Port 8001   │        │  Port 8000   │
└─────────────┘        └──────────────┘        └──────────────┘
                               │                        │
                               ▼                        │
                       ┌──────────────┐                │
                       │    Redis     │◀───────────────┘
                       │  Port 6379   │
                       └──────────────┘
                               │
                               ▼
                       ┌──────────────┐        ┌──────────────┐
                       │    Worker    │───────▶│    MySQL     │
                       │  Port 9100   │        │  Port 3306   │
                       └──────────────┘        └──────────────┘
                                                       │
                                                       ▼
                                               ┌──────────────┐
                                               │   Portal     │
                                               │  Port 5000   │
                                               └──────────────┘
```

### Components

| Component | Port | Purpose | Critical |
|-----------|------|---------|----------|
| **Proxy** | 8001 | Client-facing API (mTLS) | Yes |
| **Main Server** | 8000 | Core API & database | Yes |
| **Worker** | 9100 | Message processing | Yes |
| **Portal** | 5000 | Web UI (admin + user) | No |
| **MySQL** | 3306 | Database | Yes |
| **Redis** | 6379 | Message queue | Yes |

### Service Dependencies

```
MySQL (must start first)
  └─> Main Server
       ├─> Proxy
       ├─> Worker
       └─> Portal

Redis (must start first)
  └─> Worker
```

### File Locations

| Item | Location |
|------|----------|
| Application Root | `C:\MessageBroker` |
| Configuration | `C:\MessageBroker\.env` |
| Logs | `C:\MessageBroker\logs\` |
| Certificates | `C:\MessageBroker\*\certs\` |
| Backups | `C:\Backups\MessageBroker\` |
| Database | MySQL data directory |

---

## Daily Operations

### Morning Health Check (Start of Business)

Run these commands every morning:

```powershell
# 1. Check all services
Get-Service MessageBroker* | Format-Table Name, Status, StartType

# 2. Check dependencies
Get-Service MySQL, Memurai | Format-Table Name, Status

# 3. Quick health check
cd C:\MessageBroker\deployment\tests
.\smoke_test.ps1

# 4. Check queue length
memurai-cli LLEN message_queue

# 5. Check disk space
Get-PSDrive C

# 6. Review error logs (last hour)
$cutoff = (Get-Date).AddHours(-1)
Get-ChildItem C:\MessageBroker\logs\*.log | ForEach-Object {
    Get-Content $_ | Select-String "ERROR" | Where-Object { $_.Line -match $cutoff.ToString("yyyy-MM-dd") }
}
```

### Expected Results

- All services: **Running**
- Health checks: **All passing**
- Queue length: **< 100** (normal operations)
- Disk space: **> 20% free**
- Recent errors: **0-5 errors/hour** (investigate if more)

### Evening Check (End of Business)

```powershell
# 1. Verify services still running
Get-Service MessageBroker* | Where-Object {$_.Status -ne 'Running'}

# 2. Check daily metrics
# Queue processed today
# Messages delivered today
# Error count today

# 3. Verify backup completed
Get-ChildItem C:\Backups\MessageBroker\backup_$(Get-Date -Format 'yyyyMMdd')*.zip
```

---

## Service Management

### Start All Services

**Correct startup order**:

```powershell
# 1. Verify dependencies
net start MySQL
net start Memurai

# 2. Wait for dependencies
Start-Sleep -Seconds 5

# 3. Start Main Server first
net start MessageBrokerMainServer
Start-Sleep -Seconds 5

# 4. Start Proxy
net start MessageBrokerProxy
Start-Sleep -Seconds 3

# 5. Start Worker
net start MessageBrokerWorker
Start-Sleep -Seconds 3

# 6. Start Portal
net start MessageBrokerPortal

# 7. Verify all started
Get-Service MessageBroker* | Format-Table Name, Status
```

### Stop All Services

**Correct shutdown order** (reverse of startup):

```powershell
# 1. Stop Portal (least critical)
net stop MessageBrokerPortal

# 2. Stop Worker (let it finish current tasks)
Write-Host "Stopping worker (may take 30-60 seconds)..."
net stop MessageBrokerWorker

# 3. Stop Proxy (stop accepting new messages)
net stop MessageBrokerProxy

# 4. Stop Main Server
net stop MessageBrokerMainServer

# 5. Optionally stop dependencies
# net stop Memurai
# net stop MySQL
```

### Restart a Single Service

```powershell
# Example: Restart Main Server
Write-Host "Restarting Main Server..." -ForegroundColor Yellow

# Stop dependent services first
net stop MessageBrokerPortal
net stop MessageBrokerWorker
net stop MessageBrokerProxy

# Restart main server
Restart-Service MessageBrokerMainServer
Start-Sleep -Seconds 10

# Verify it's running
if ((Get-Service MessageBrokerMainServer).Status -eq 'Running') {
    Write-Host "Main Server restarted successfully" -ForegroundColor Green
    
    # Restart dependencies
    net start MessageBrokerProxy
    Start-Sleep -Seconds 5
    net start MessageBrokerWorker
    Start-Sleep -Seconds 5
    net start MessageBrokerPortal
} else {
    Write-Host "ERROR: Main Server failed to start!" -ForegroundColor Red
    # Check logs immediately
    Get-Content C:\MessageBroker\logs\main_server.log -Tail 50
}
```

### Check Service Status

```powershell
# Quick status
Get-Service MessageBroker*

# Detailed status
Get-Service MessageBroker* | Select-Object Name, Status, StartType, DisplayName | Format-Table -AutoSize

# Check service uptime
Get-CimInstance -ClassName Win32_Service | Where-Object {$_.Name -like "MessageBroker*"} | Select-Object Name, State, Started

# Check service logs
Get-EventLog -LogName Application -Source "MessageBroker*" -Newest 20
```

---

## Monitoring & Health Checks

### Manual Health Checks

```powershell
# Main Server
curl https://localhost:8000/health -k

# Proxy
curl https://localhost:8001/api/v1/health -k

# Portal
curl https://localhost:5000/health -k

# Worker Metrics
curl http://localhost:9100/metrics

# MySQL
mysql -u systemuser -p message_system -e "SELECT 1"

# Redis
memurai-cli ping
```

### Automated Monitoring Script

Save as `C:\MessageBroker\scripts\monitor.ps1`:

```powershell
# Continuous monitoring script
while ($true) {
    Clear-Host
    Write-Host "=== Message Broker System Monitor ===" -ForegroundColor Cyan
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
    
    # Services
    Write-Host "Services:" -ForegroundColor Yellow
    Get-Service MessageBroker* | ForEach-Object {
        $color = if ($_.Status -eq 'Running') { 'Green' } else { 'Red' }
        Write-Host "  $($_.Name): $($_.Status)" -ForegroundColor $color
    }
    
    # Queue
    Write-Host "`nQueue:" -ForegroundColor Yellow
    $queueLen = memurai-cli LLEN message_queue 2>&1
    Write-Host "  Messages: $queueLen"
    
    # Disk
    Write-Host "`nDisk:" -ForegroundColor Yellow
    $disk = Get-PSDrive C
    $percentFree = [math]::Round(($disk.Free / $disk.Used) * 100, 1)
    Write-Host "  Free: $([math]::Round($disk.Free/1GB, 1)) GB ($percentFree%)"
    
    Start-Sleep -Seconds 30
}
```

Run: `powershell -ExecutionPolicy Bypass -File C:\MessageBroker\scripts\monitor.ps1`

### Key Performance Indicators (KPIs)

Monitor these metrics daily:

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Queue Length | < 50 | 50-500 | > 500 |
| Message Delivery Rate | > 90% | 80-90% | < 80% |
| Service Uptime | 100% | 99%+ | < 99% |
| Disk Free Space | > 30% | 10-30% | < 10% |
| Error Rate | < 1% | 1-5% | > 5% |
| Response Time (API) | < 500ms | 500ms-2s | > 2s |

---

## Backup & Recovery

### Daily Backup Verification

```powershell
# Check last backup
$lastBackup = Get-ChildItem C:\Backups\MessageBroker\ -Filter "backup_*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($lastBackup) {
    $age = (Get-Date) - $lastBackup.LastWriteTime
    Write-Host "Last backup: $($lastBackup.Name)" -ForegroundColor Green
    Write-Host "Age: $($age.Hours) hours ago"
    Write-Host "Size: $([math]::Round($lastBackup.Length/1MB, 2)) MB"
    
    if ($age.Hours -gt 25) {
        Write-Host "WARNING: Backup is over 24 hours old!" -ForegroundColor Yellow
    }
} else {
    Write-Host "ERROR: No backups found!" -ForegroundColor Red
}
```

### Manual Backup

```powershell
# Run backup script
cd C:\MessageBroker\deployment\backup
.\backup.ps1

# Verify backup created
Get-ChildItem C:\Backups\MessageBroker\ -Filter "backup_$(Get-Date -Format 'yyyyMMdd')*.zip"
```

### Restore from Backup

⚠️ **WARNING**: This will overwrite current data!

```powershell
# 1. Stop all services
Get-Service MessageBroker* | Stop-Service -Force

# 2. Run restore
cd C:\MessageBroker\deployment\backup
.\restore.ps1 -BackupPath "C:\Backups\MessageBroker\backup_YYYYMMDD_HHMMSS.zip"

# 3. Restart services
Get-Service MessageBroker* | Start-Service

# 4. Verify
cd ..\tests
.\smoke_test.ps1
```

---

## Troubleshooting

### Service Won't Start

#### Checklist:

1. **Check dependencies**:
   ```powershell
   Get-Service MySQL, Memurai
   ```

2. **Check port availability**:
   ```powershell
   netstat -ano | findstr "8000 8001 5000 9100"
   ```

3. **Check logs**:
   ```powershell
   Get-Content C:\MessageBroker\logs\<service>.log -Tail 50
   ```

4. **Check Event Viewer**:
   ```powershell
   Get-EventLog -LogName Application -Source "MessageBroker*" -Newest 10
   ```

5. **Verify configuration**:
   ```powershell
   Get-Content C:\MessageBroker\.env | Select-String "ERROR"
   ```

### High Queue Length

**Symptoms**: Redis queue growing, messages not being delivered

**Investigation**:

```powershell
# 1. Check queue length
memurai-cli LLEN message_queue

# 2. Check worker status
Get-Service MessageBrokerWorker

# 3. Check worker logs
Get-Content C:\MessageBroker\logs\worker.log -Tail 100 | Select-String "ERROR|WARN"

# 4. Check main server connectivity
curl https://localhost:8000/health -k
```

**Solutions**:

1. **Worker not running**: `net start MessageBrokerWorker`
2. **Main server down**: `net start MessageBrokerMainServer`
3. **Database issues**: Check MySQL status and logs
4. **Need more workers**: Increase `WORKER_COUNT` in `.env`, restart worker service

### Database Connection Errors

**Symptoms**: "Can't connect to MySQL server", "Access denied"

**Investigation**:

```powershell
# 1. Check MySQL service
Get-Service MySQL

# 2. Test connection
mysql -u systemuser -p message_system -e "SELECT 1"

# 3. Check connection string
Get-Content C:\MessageBroker\.env | Select-String "DATABASE_URL"

# 4. Check MySQL error log
Get-Content "C:\ProgramData\MySQL\MySQL Server 8.0\Data\*.err" -Tail 50
```

**Solutions**:

1. **MySQL not running**: `net start MySQL`
2. **Wrong password**: Update `.env` with correct password
3. **User doesn't exist**: Recreate user in MySQL
4. **Too many connections**: Check `max_connections` in MySQL config

### Certificate Errors

**Symptoms**: "SSL: CERTIFICATE_VERIFY_FAILED", "Client cert required"

**Investigation**:

```powershell
# 1. Check certificate files exist
Get-ChildItem C:\MessageBroker\*\certs\ -Recurse -Include *.crt, *.key

# 2. Verify certificate validity
cd C:\MessageBroker\main_server
openssl x509 -in certs\ca.crt -noout -dates
openssl x509 -in certs\server.crt -noout -dates

# 3. Check certificate permissions
icacls C:\MessageBroker\main_server\certs\*.key
```

**Solutions**:

1. **Expired certificate**: Regenerate certificates
2. **Missing certificate**: Copy from backup or regenerate
3. **Wrong permissions**: Reset using deployment scripts
4. **CA mismatch**: Ensure all components use same CA

---

## Common Tasks

### Add New Client Certificate

```powershell
cd C:\MessageBroker\main_server

# Generate certificate
.\generate_cert.bat client_name domain.com 365

# Distribute to client
# Files to send:
# - certs\client_name.crt
# - certs\client_name.key
# - certs\ca.crt
```

### Revoke Client Certificate

```powershell
cd C:\MessageBroker\main_server

# Revoke certificate
.\revoke_cert.bat client_name

# Restart services to reload CRL
Restart-Service MessageBrokerProxy
Restart-Service MessageBrokerMainServer
```

### Clear Old Messages

```powershell
# Connect to MySQL
mysql -u systemuser -p message_system

# Delete messages older than 90 days
DELETE FROM messages WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY);

# Check space freed
SELECT 
    table_name,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS "Size (MB)"
FROM information_schema.TABLES
WHERE table_schema = "message_system";

# Optimize table
OPTIMIZE TABLE messages;
```

### View System Statistics

```powershell
# Message statistics (today)
mysql -u systemuser -p message_system -e "
SELECT 
    COUNT(*) as total_messages,
    SUM(CASE WHEN status='delivered' THEN 1 ELSE 0 END) as delivered,
    SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) as pending,
    SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) as failed
FROM messages 
WHERE DATE(created_at) = CURDATE();
"

# Queue statistics
memurai-cli INFO stats | Select-String "total_commands_processed|instantaneous_ops_per_sec"

# Service uptime
Get-Service MessageBroker* | Select-Object Name, Status, @{Name='StartTime';Expression={(Get-CimInstance Win32_Service -Filter "Name='$($_.Name)'").Started}}
```

---

## Emergency Procedures

### Complete System Failure

**Steps**:

1. **Stop all services**:
   ```powershell
   Get-Service MessageBroker* | Stop-Service -Force
   ```

2. **Check dependencies**:
   ```powershell
   Get-Service MySQL, Memurai | Restart-Service
   ```

3. **Review all logs**:
   ```powershell
   Get-ChildItem C:\MessageBroker\logs\*.log | ForEach-Object {
       Write-Host "`n=== $($_.Name) ===" -ForegroundColor Cyan
       Get-Content $_ -Tail 20
   }
   ```

4. **Restore from last backup** (if needed):
   ```powershell
   cd C:\MessageBroker\deployment\backup
   .\restore.ps1 -BackupPath <latest_backup>
   ```

5. **Start services**:
   ```powershell
   # Start in order
   net start MessageBrokerMainServer
   Start-Sleep -Seconds 10
   net start MessageBrokerProxy
   Start-Sleep -Seconds 5
   net start MessageBrokerWorker
   Start-Sleep -Seconds 5
   net start MessageBrokerPortal
   ```

6. **Verify**:
   ```powershell
   cd C:\MessageBroker\deployment\tests
   .\smoke_test.ps1
   ```

### Data Loss / Corruption

1. Stop all services
2. Restore from most recent backup
3. Replay any transactions from MySQL binary logs (if enabled)
4. Restart services
5. Verify data integrity

### Security Breach

1. **Immediately disconnect from network** (if confirmed breach)
2. **Stop all services**
3. **Review audit logs**:
   ```sql
   SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 100;
   ```
4. **Revoke all client certificates**:
   ```powershell
   cd C:\MessageBroker\main_server
   # Revoke each certificate
   ```
5. **Change all passwords**:
   - Database passwords
   - JWT secrets
   - Admin portal passwords
6. **Review and patch system**
7. **Generate new certificates**
8. **Restore from clean backup** (if compromised)
9. **Contact security team**

---

## Maintenance Windows

### Planned Maintenance Procedure

**Preparation** (1 week before):
- [ ] Schedule maintenance window (off-peak hours)
- [ ] Notify users via portal announcement
- [ ] Prepare rollback plan
- [ ] Full system backup

**During Maintenance**:

```powershell
# 1. Set maintenance mode (if implemented)
# Update .env: MAINTENANCE_MODE=true

# 2. Stop accepting new messages
net stop MessageBrokerProxy

# 3. Wait for queue to drain
Write-Host "Waiting for queue to drain..."
while ((memurai-cli LLEN message_queue) -gt 0) {
    Write-Host "Queue length: $(memurai-cli LLEN message_queue)"
    Start-Sleep -Seconds 30
}

# 4. Stop remaining services
Get-Service MessageBroker* | Stop-Service

# 5. Perform maintenance tasks
# - Update code
# - Run database migrations
# - Update certificates
# - System updates

# 6. Test in maintenance mode
cd C:\MessageBroker\deployment\tests
.\smoke_test.ps1

# 7. Restart services
# (See startup procedure above)

# 8. Verify production
# Test message flow end-to-end

# 9. Disable maintenance mode
# Update .env: MAINTENANCE_MODE=false
# Restart services
```

**Post-Maintenance**:
- [ ] Verify all services running
- [ ] Monitor for 1-2 hours
- [ ] Check error logs
- [ ] Notify users maintenance complete

---

## Escalation Procedures

### Escalation Levels

#### Level 1: Operations Team
- Service restarts
- Log review
- Basic troubleshooting
- Backup/restore operations

#### Level 2: System Administrators  
- Configuration changes
- Database issues
- Certificate problems
- Performance optimization

#### Level 3: Development Team
- Code bugs
- Architecture changes
- Critical failures requiring code fixes
- Data corruption issues

### When to Escalate

| Issue | Timeframe | Escalate To |
|-------|-----------|-------------|
| Service won't start after 3 restart attempts | Immediate | Level 2 |
| Queue > 1000 messages | 30 minutes | Level 2 |
| Error rate > 10% | 15 minutes | Level 2 |
| Database corruption | Immediate | Level 3 |
| Security breach (suspected) | Immediate | Security Team |
| Complete system failure | Immediate | Level 3 |

### Contact Information

**Level 1 Support**: operations@company.com  
**Level 2 Support**: sysadmin@company.com  
**Level 3 Support**: dev-team@company.com  
**Security Team**: security@company.com  

**Emergency Hotline**: [Phone Number]

---

## Appendix

### Quick Reference Commands

```powershell
# Health check
.\deployment\tests\smoke_test.ps1

# View logs
Get-Content C:\MessageBroker\logs\*.log -Tail 50

# Service status
Get-Service MessageBroker*

# Queue length
memurai-cli LLEN message_queue

# Database stats
mysql -u systemuser -p message_system -e "SELECT COUNT(*) FROM messages"

# Disk space
Get-PSDrive C

# Backup
.\deployment\backup\backup.ps1

# Restart all services
Get-Service MessageBroker* | Restart-Service
```

### Log Files

| Component | Log File |
|-----------|----------|
| Main Server | `C:\MessageBroker\logs\main_server.log` |
| Proxy | `C:\MessageBroker\logs\proxy.log` |
| Worker | `C:\MessageBroker\logs\worker.log` |
| Portal | `C:\MessageBroker\logs\portal.log` |
| MySQL | `C:\ProgramData\MySQL\MySQL Server 8.0\Data\*.err` |
| Redis | `C:\Program Files\Memurai\memurai.log` |

---

**Document Version**: 1.0.0  
**Last Updated**: October 2025  
**Next Review**: January 2026

