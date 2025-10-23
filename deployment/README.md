# Message Broker System - Deployment Package

**Version**: 1.0.0  
**Platform**: Windows Server 2019/2022  
**Date**: October 2025

---

## 📦 Package Contents

This deployment package contains everything needed to deploy the Message Broker System to Windows Server.

### Directory Structure

```
deployment/
├── README.md                          # This file
├── DEPLOYMENT_GUIDE.md                # Comprehensive deployment guide (50+ pages)
├── services/                          # Windows Service installation scripts
│   ├── install_all_services.ps1      # Install all services at once
│   ├── install_main_server_service.ps1
│   ├── install_proxy_service.ps1
│   ├── install_worker_service.ps1
│   └── install_portal_service.ps1
├── backup/                            # Backup and restore scripts
│   ├── backup.ps1                     # Manual/automated backup script
│   ├── restore.ps1                    # Restore from backup
│   └── install_backup_task.ps1        # Schedule automated backups
├── config/                            # Production configuration templates
│   ├── env.production.template        # Environment variables template
│   ├── redis.conf                     # Redis/Memurai configuration
│   └── mysql.cnf                      # MySQL configuration
├── tests/                             # Post-deployment tests
│   └── smoke_test.ps1                 # Smoke test suite
└── scripts/                           # Utility scripts
    ├── check_ports.ps1                # Port availability checker
    ├── generate_passwords.ps1         # Secure password generator
    └── health_check.ps1               # Continuous health monitoring
```

---

## 🚀 Quick Start

### Prerequisites

1. Windows Server 2019 or 2022
2. Administrator access
3. Internet connection (for initial setup)
4. At least 8 GB RAM, 50 GB disk space

### Installation Steps (Summary)

```powershell
# 1. Install base software
choco install python mysql redis-64 openssl git -y

# 2. Deploy application code
cd C:\
git clone <repo-url> MessageBroker
cd MessageBroker

# 3. Create virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r proxy/requirements.txt -r main_server/requirements.txt -r worker/requirements.txt -r portal/requirements.txt

# 4. Configure environment
copy deployment\config\env.production.template .env
# Edit .env with your configuration

# 5. Initialize database
cd main_server
alembic upgrade head

# 6. Generate certificates
.\init_ca.bat
.\generate_cert.bat server localhost 3650

# 7. Install services
cd ..\deployment\services
.\install_all_services.ps1

# 8. Run smoke test
cd ..\tests
.\smoke_test.ps1
```

**For detailed instructions, see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)**

---

## 📋 Deployment Checklist

Use this checklist to track your deployment progress:

### Pre-Deployment

- [ ] Server meets system requirements
- [ ] Firewall rules configured
- [ ] DNS records configured
- [ ] SSL/TLS certificates obtained (if using public domain)
- [ ] Backup storage configured
- [ ] Service accounts created

### Software Installation

- [ ] Python 3.8+ installed
- [ ] MySQL 8.0+ installed and running
- [ ] Redis/Memurai installed and running
- [ ] OpenSSL installed
- [ ] Application code deployed

### Configuration

- [ ] `.env` file configured
- [ ] MySQL database and user created
- [ ] Database schema initialized (Alembic)
- [ ] Redis configured with AOF persistence
- [ ] Certificate Authority initialized
- [ ] Component certificates generated

### Service Installation

- [ ] Main Server service installed
- [ ] Proxy service installed
- [ ] Worker service installed
- [ ] Portal service installed
- [ ] Service dependencies configured

### Security

- [ ] File permissions set
- [ ] Firewall rules applied
- [ ] Service accounts configured
- [ ] Encryption keys protected
- [ ] Certificate private keys protected

### Testing

- [ ] All services started successfully
- [ ] Smoke test passed
- [ ] Health checks passing
- [ ] Message submission test passed
- [ ] Portal login tested

### Monitoring

- [ ] Prometheus installed (optional)
- [ ] Grafana installed (optional)
- [ ] Metrics endpoints accessible
- [ ] Backup schedule configured
- [ ] Alerts configured (optional)

### Documentation

- [ ] Credentials documented securely
- [ ] Configuration changes documented
- [ ] Operations team briefed
- [ ] Support contacts established

---

## 🔧 Service Management

### Start All Services

```powershell
Get-Service MessageBroker* | Start-Service
```

### Stop All Services

```powershell
Get-Service MessageBroker* | Stop-Service
```

### Check Service Status

```powershell
Get-Service MessageBroker* | Format-Table Name, Status, StartType
```

### View Service Logs

```powershell
# Main Server
Get-Content C:\MessageBroker\logs\main_server.log -Tail 50 -Wait

# Proxy
Get-Content C:\MessageBroker\logs\proxy.log -Tail 50 -Wait

# Worker
Get-Content C:\MessageBroker\logs\worker.log -Tail 50 -Wait

# Portal
Get-Content C:\MessageBroker\logs\portal.log -Tail 50 -Wait
```

### Restart a Service

```powershell
Restart-Service MessageBrokerMainServer
```

---

## 🔒 Security Best Practices

1. **Change Default Passwords**: Update all passwords in `.env` file
2. **Protect Private Keys**: Restrict access to `*.key` files
3. **Enable Firewall**: Only allow required ports
4. **Regular Updates**: Keep Python packages and system updated
5. **Monitor Logs**: Review logs daily for suspicious activity
6. **Backup Regularly**: Ensure automated backups are running
7. **Rotate Certificates**: Plan certificate rotation before expiry
8. **Limit Access**: Use least privilege for service accounts

---

## 📊 Monitoring & Health Checks

### Manual Health Checks

```powershell
# Main Server
curl https://localhost:8000/health

# Proxy
curl https://localhost:8001/api/v1/health

# Portal
curl https://localhost:5000/health

# Worker Metrics
curl http://localhost:9100/metrics
```

### Run Smoke Test

```powershell
cd C:\MessageBroker\deployment\tests
.\smoke_test.ps1
```

The smoke test verifies:
- All services are running
- Database connectivity
- Redis connectivity
- Health endpoints responding
- Certificates present

---

## 💾 Backup & Restore

### Manual Backup

```powershell
cd C:\MessageBroker\deployment\backup
.\backup.ps1
```

Backs up:
- MySQL database
- Redis data (AOF)
- Configuration files
- Certificates
- Encryption keys
- Recent logs

### Automated Backup

```powershell
cd C:\MessageBroker\deployment\backup
.\install_backup_task.ps1
```

Configures daily backup at 2:00 AM with 30-day retention.

### Restore from Backup

```powershell
cd C:\MessageBroker\deployment\backup
.\restore.ps1 -BackupPath "C:\Backups\MessageBroker\backup_20251020_020000"
```

---

## 🐛 Troubleshooting

### Service Won't Start

1. Check Event Viewer for errors
2. Review service log files
3. Verify dependencies (MySQL, Redis)
4. Check port availability
5. Verify certificate files exist

```powershell
# Check Event Viewer
Get-EventLog -LogName Application -Source "Message Broker*" -Newest 20

# Check port usage
netstat -ano | findstr "8000 8001 5000"

# Check dependencies
Get-Service MySQL, Memurai
```

### Database Connection Fails

1. Verify MySQL is running: `Get-Service MySQL`
2. Test connection: `mysql -u systemuser -p message_system`
3. Check credentials in `.env`
4. Review MySQL error log

### Certificate Errors

1. Verify certificate files exist
2. Check file permissions
3. Validate certificate: `openssl x509 -in cert.crt -noout -dates`
4. Check CA trust chain

### Performance Issues

1. Check system resources (CPU, RAM, disk)
2. Review slow query log (MySQL)
3. Check Redis memory usage
4. Monitor worker queue length
5. Review application metrics

---

## 📞 Support

### Log Locations

- **Application Logs**: `C:\MessageBroker\logs\`
- **MySQL Logs**: `C:\ProgramData\MySQL\MySQL Server 8.0\Data\`
- **Redis Logs**: `C:\Program Files\Memurai\`
- **Windows Event Log**: Application log

### Common Commands

```powershell
# View all services
Get-Service MessageBroker*

# Check MySQL database
mysql -u systemuser -p message_system -e "SHOW TABLES;"

# Check Redis queue
memurai-cli LLEN message_queue

# View recent errors
Get-Content C:\MessageBroker\logs\*.log | Select-String "ERROR" | Select-Object -Last 20

# Check disk space
Get-PSDrive C

# Check service uptime
Get-Service MessageBroker* | Select-Object Name, @{Name='Uptime';Expression={(Get-Date) - $_.StartTime}}
```

---

## 📚 Additional Resources

- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Complete deployment documentation
- **[API_SPECIFICATION.md](../API_SPECIFICATION.md)** - API documentation
- **[CERTIFICATES_README.md](../main_server/CERTIFICATES_README.md)** - Certificate management
- **[TEST_PLAN.md](../tests/TEST_PLAN.md)** - Testing documentation

---

## 🔄 Upgrades & Updates

### Application Updates

1. Stop all services
2. Backup current version
3. Update code (`git pull` or copy new files)
4. Update dependencies (`pip install -r requirements.txt --upgrade`)
5. Run database migrations (`alembic upgrade head`)
6. Start services
7. Run smoke test

### Database Migrations

```powershell
cd C:\MessageBroker\main_server
.\venv\Scripts\Activate.ps1
alembic upgrade head
```

### Certificate Renewal

```powershell
cd C:\MessageBroker\main_server
.\renew_cert.bat server
# Restart services to load new certificates
Restart-Service MessageBrokerMainServer
```

---

## 🎯 Performance Tuning

### For High Load (100k+ messages/day)

1. Increase worker count in worker config
2. Increase database connection pool size
3. Add more RAM to Redis
4. Enable MySQL query cache
5. Use SSD storage for database
6. Consider load balancer for multiple instances

### Configuration Adjustments

Edit `.env` file:

```env
# Increase workers
WORKER_COUNT=8
WORKER_THREADS_PER_PROCESS=4

# Increase database pool
DATABASE_POOL_SIZE=20
DATABASE_MAX_OVERFLOW=40

# Increase Redis connections
REDIS_MAX_CONNECTIONS=100
```

---

## ✅ Production Readiness Checklist

Before going live, verify:

- [ ] All smoke tests pass
- [ ] Load testing completed
- [ ] Security audit completed
- [ ] Backups tested and verified
- [ ] Monitoring configured
- [ ] Documentation complete
- [ ] Operations team trained
- [ ] Disaster recovery plan documented
- [ ] Support contacts established
- [ ] Maintenance window scheduled

---

## 📝 License & Support

**Version**: 1.0.0  
**Release Date**: October 2025  
**Support**: See deployment guide for contact information

For issues or questions, refer to the DEPLOYMENT_GUIDE.md or contact your system administrator.

---

**Deployment Package Created**: October 2025  
**Compatible with**: Message Broker System v1.0.0

