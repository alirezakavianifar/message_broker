# How to Run the Message Broker System

**Complete guide to running all components of the Message Broker System**

---

## 📋 Prerequisites Check

Before starting, ensure you have:

- [x] **Python 3.12+** installed and in PATH
- [x] **MySQL 8.0+** installed and running
- [x] **Redis** installed and running
- [x] **OpenSSL** installed
- [x] **Virtual environment** created (`venv/` directory exists)
- [x] **All dependencies** installed in venv
- [x] **Database** created (`message_system`)
- [x] **Certificates** generated (CA, server, proxy, worker)
- [x] **Environment file** configured (`.env`)
- [x] **Encryption key** generated (`secrets/encryption.key`)

---

## 🚀 Quick Start - Run All Services

### Option 1: Using PowerShell Scripts (Recommended)

**Start all services in one command:**

```powershell
# From project root directory
cd D:\projects\message_broker

# Start all services (each in background)
Start-Process powershell -ArgumentList "-NoExit", "-File", "main_server\start_server.ps1"
Start-Process powershell -ArgumentList "-NoExit", "-File", "proxy\start_proxy.ps1"
Start-Process powershell -ArgumentList "-NoExit", "-File", "worker\start_worker.ps1"
Start-Process powershell -ArgumentList "-NoExit", "-File", "portal\start_portal.ps1"
```

This will open 4 PowerShell windows, one for each service.

**Stop all services:**

Press `Ctrl+C` in each window, or:

```powershell
# Kill all Python processes (nuclear option)
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force
```

---

### Option 2: Manual Start (Step-by-Step)

#### **Step 1: Start Main Server**

Open PowerShell window #1:

```powershell
cd D:\projects\message_broker
.\venv\Scripts\activate
cd main_server
python -m uvicorn api:app --host 0.0.0.0 --port 8000 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt --ssl-ca-certs certs/ca.crt
```

**Expected output:**
```
INFO:     Started server process
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on https://0.0.0.0:8000
```

**Verify:** Open browser to `https://localhost:8000/health` (accept self-signed cert warning)

---

#### **Step 2: Start Proxy Server**

Open PowerShell window #2:

```powershell
cd D:\projects\message_broker
.\venv\Scripts\activate
cd proxy
python -m uvicorn app:app --host 0.0.0.0 --port 8001 --ssl-keyfile certs/proxy.key --ssl-certfile certs/proxy.crt --ssl-ca-certs certs/ca.crt
```

**Expected output:**
```
INFO:     Started server process
INFO:     Uvicorn running on https://0.0.0.0:8001
```

**Verify:** Check logs show no errors

---

#### **Step 3: Start Worker**

Open PowerShell window #3:

```powershell
cd D:\projects\message_broker
.\venv\Scripts\activate
cd worker
python worker.py
```

**Expected output:**
```
[2025-10-28 10:30:00] INFO - Worker starting...
[2025-10-28 10:30:00] INFO - Connected to Redis
[2025-10-28 10:30:00] INFO - Worker ready, waiting for messages...
```

**Verify:** Worker shows "waiting for messages"

---

#### **Step 4: Start Web Portal**

Open PowerShell window #4:

```powershell
cd D:\projects\message_broker
.\venv\Scripts\activate
cd portal
python -m uvicorn app:app --host 0.0.0.0 --port 5000
```

**Expected output:**
```
INFO:     Started server process
INFO:     Uvicorn running on http://0.0.0.0:5000
```

**Verify:** Open browser to `http://localhost:5000`

---

## 🔍 Service Overview

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| **Main Server** | 8000 | https://localhost:8000 | Core API, database, certificate authority |
| **Proxy Server** | 8001 | https://localhost:8001 | Client-facing message ingestion (mTLS) |
| **Worker** | - | - | Background message processor |
| **Web Portal** | 5000 | http://localhost:5000 | User/admin web interface |

---

## 🔗 Startup Order (Important!)

Services **must** start in this order:

1. ✅ **MySQL** (must be running first)
2. ✅ **Redis** (must be running first)
3. 🟢 **Main Server** (start first)
4. 🟡 **Proxy Server** (depends on Main Server)
5. 🟡 **Worker** (depends on Main Server & Redis)
6. 🟡 **Web Portal** (depends on Main Server)

**Shutdown order:** Reverse of startup (Portal → Worker → Proxy → Main Server)

---

## ✅ Health Checks

After starting all services, verify they're running:

### 1. Check Main Server
```powershell
curl https://localhost:8000/health -k
```
Expected: `{"status":"ok","database":"connected","redis":"connected"}`

### 2. Check Proxy Server
```powershell
curl https://localhost:8001/api/v1/health -k
```
Expected: `{"status":"healthy","redis":"connected"}`

### 3. Check Worker
Look at worker terminal output - should show:
```
[INFO] Worker ready, waiting for messages...
```

### 4. Check Web Portal
```powershell
curl http://localhost:5000
```
Expected: HTML response (login page)

### 5. Check All Services (Quick Script)

```powershell
Write-Host "Checking all services..." -ForegroundColor Cyan

# Main Server
try {
    $response = Invoke-WebRequest -Uri "https://localhost:8000/health" -SkipCertificateCheck -ErrorAction Stop
    Write-Host "[OK] Main Server (port 8000)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Main Server (port 8000)" -ForegroundColor Red
}

# Proxy Server
try {
    $response = Invoke-WebRequest -Uri "https://localhost:8001/api/v1/health" -SkipCertificateCheck -ErrorAction Stop
    Write-Host "[OK] Proxy Server (port 8001)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Proxy Server (port 8001)" -ForegroundColor Red
}

# Web Portal
try {
    $response = Invoke-WebRequest -Uri "http://localhost:5000" -ErrorAction Stop
    Write-Host "[OK] Web Portal (port 5000)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Web Portal (port 5000)" -ForegroundColor Red
}

# Worker (check if process is running)
if (Get-Process python -ErrorAction SilentlyContinue | Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -like "*worker.py*" }) {
    Write-Host "[OK] Worker process running" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Worker process not found" -ForegroundColor Red
}
```

---

## 🧪 Testing the System

### 1. Create Admin User (First Time Only)

```powershell
cd main_server
python admin_cli.py users create --email admin@test.com --password Admin123! --role admin
```

### 2. Login to Web Portal

1. Go to: `http://localhost:5000`
2. Login with: `admin@test.com` / `Admin123!`
3. You should see the admin dashboard

### 3. Create a Test Client Certificate

In the portal:
1. Go to: **Admin → Certificates**
2. Click **"Generate New Certificate"**
3. Client ID: `test_client`
4. Download the certificate files (`test_client.crt`, `test_client.key`)

### 4. Send a Test Message

```powershell
cd client-scripts

# Place certificates in certs/ folder
# - test_client.crt
# - test_client.key
# - ca.crt (from main_server/certs/)

python send_message.py --sender "+1234567890" --message "Hello World" --cert certs/test_client.crt --key certs/test_client.key --ca certs/ca.crt
```

### 5. View Message in Portal

1. Go to: `http://localhost:5000/admin/messages`
2. You should see your test message

---

## 🐛 Troubleshooting

### Problem: Port Already in Use

**Symptom:** `OSError: [WinError 10048] Only one usage of each socket address is normally permitted`

**Solution:**
```powershell
# Find process using port
netstat -ano | findstr "8000"  # or 8001, 5000

# Kill the process
taskkill /PID <pid> /F

# Or kill all Python processes
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force
```

---

### Problem: MySQL Connection Failed

**Symptom:** `OperationalError: (2003, "Can't connect to MySQL server")`

**Solution:**
```powershell
# Check if MySQL is running
Get-Service | Where-Object { $_.Name -like "*mysql*" }

# Start MySQL
net start MySQL80  # or MySQL

# Test connection
mysql -u systemuser -p message_system
```

---

### Problem: Redis Connection Failed

**Symptom:** `ConnectionError: Error connecting to Redis`

**Solution:**
```powershell
# Check if Redis is running
redis-cli ping
# Expected: PONG

# If not running, start Redis
redis-server --service-start

# Or install as service
redis-server --service-install
redis-server --service-start
```

---

### Problem: Certificate Errors

**Symptom:** `SSL: CERTIFICATE_VERIFY_FAILED`

**Solution:**
```powershell
# Verify certificate files exist
Get-ChildItem main_server\certs\*.crt
Get-ChildItem main_server\certs\*.key

# Check certificate validity
openssl x509 -in main_server\certs\server.crt -noout -dates

# Regenerate if expired
cd main_server
.\generate_certs.ps1
```

---

### Problem: Import Errors

**Symptom:** `ModuleNotFoundError: No module named 'fastapi'`

**Solution:**
```powershell
# Ensure venv is activated
.\venv\Scripts\activate

# Reinstall dependencies
pip install -r main_server/requirements.txt
pip install -r proxy/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
```

---

### Problem: Database Schema Missing

**Symptom:** `OperationalError: (1146, "Table 'message_system.messages' doesn't exist")`

**Solution:**
```powershell
cd main_server

# Run migrations
alembic upgrade head

# Verify tables exist
mysql -u systemuser -p message_system -e "SHOW TABLES;"
```

---

## 📊 Monitoring

### View Logs

**Main Server:**
```powershell
Get-Content logs\main_server.log -Tail 50 -Wait
```

**Proxy:**
```powershell
Get-Content logs\proxy.log -Tail 50 -Wait
```

**Worker:**
```powershell
Get-Content logs\worker.log -Tail 50 -Wait
```

**Portal:**
```powershell
Get-Content logs\portal.log -Tail 50 -Wait
```

### Check Database

```sql
-- Connect to MySQL
mysql -u systemuser -p message_system

-- View recent messages
SELECT id, client_id, status, created_at 
FROM messages 
ORDER BY created_at DESC 
LIMIT 10;

-- Count by status
SELECT status, COUNT(*) 
FROM messages 
GROUP BY status;
```

### Check Redis Queue

```powershell
redis-cli

# View queue length
LLEN message_queue

# View messages in queue
LRANGE message_queue 0 -1

# Monitor in real-time
MONITOR
```

---

## 🔧 Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `.env` | Environment variables | Project root |
| `proxy/config.yaml` | Proxy settings | `proxy/` |
| `worker/config.yaml` | Worker settings | `worker/` |
| `secrets/encryption.key` | AES encryption key | `secrets/` |
| `main_server/certs/*` | SSL/TLS certificates | `main_server/certs/` |

---

## 🎯 Common Tasks

### Add a New User

```powershell
cd main_server
python admin_cli.py users create --email user@test.com --password User123! --role user
```

### Generate Client Certificate

Via Web Portal: `http://localhost:5000/admin/certificates`

Or via CLI:
```powershell
cd main_server
.\generate_cert.bat client_name localhost 365
```

### Backup Database

```powershell
mysqldump -u systemuser -p message_system > backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql
```

### Clear Message Queue

```powershell
redis-cli DEL message_queue
```

---

## 📚 Additional Documentation

- **[QUICK_START_GUIDE.md](QUICK_START_GUIDE.md)** - Understanding the system and sending messages
- **[deployment/DEPLOYMENT_GUIDE.md](deployment/DEPLOYMENT_GUIDE.md)** - Full production deployment
- **[docs/USER_MANUAL.md](docs/USER_MANUAL.md)** - Web portal user guide
- **[docs/ADMIN_MANUAL.md](docs/ADMIN_MANUAL.md)** - Administrator guide
- **[README.md](README.md)** - Project overview

---

## 🆘 Getting Help

If you encounter issues not covered here:

1. **Check the logs** - Most errors are logged with details
2. **Review health checks** - Identify which component is failing
3. **Verify prerequisites** - Ensure MySQL, Redis, certificates are properly configured
4. **Consult detailed guides** - See deployment guide for in-depth troubleshooting

---

## ✅ Quick Reference

**Start all services:**
```powershell
# Terminal 1
cd main_server; python -m uvicorn api:app --host 0.0.0.0 --port 8000 --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt --ssl-ca-certs certs/ca.crt

# Terminal 2
cd proxy; python -m uvicorn app:app --host 0.0.0.0 --port 8001 --ssl-keyfile certs/proxy.key --ssl-certfile certs/proxy.crt --ssl-ca-certs certs/ca.crt

# Terminal 3
cd worker; python worker.py

# Terminal 4
cd portal; python -m uvicorn app:app --host 0.0.0.0 --port 5000
```

**Access points:**
- Web Portal: `http://localhost:5000`
- Main Server API: `https://localhost:8000/docs`
- Proxy API: `https://localhost:8001/api/v1/docs`
- Health Checks: `/health` on each service

---

**Happy messaging! 🚀**

