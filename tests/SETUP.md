# Test Environment Setup Guide

## Prerequisites

Before running tests, you need to set up the complete test environment.

## 1. Install Test Dependencies

```powershell
# Activate virtual environment
cd ..
.\venv\Scripts\Activate.ps1

# Install test dependencies
cd tests
pip install -r requirements.txt
```

## 2. Install and Configure MySQL

### Windows:
```powershell
# Download and install MySQL 8.0
# Or use Chocolatey:
choco install mysql

# Start MySQL service
net start MySQL80

# Create database and user
mysql -u root -p
```

```sql
CREATE DATABASE message_system CHARACTER SET utf8mb4;
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY 'StrongPass123!';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

## 3. Install and Configure Redis

### Windows:
```powershell
# Download Redis for Windows or use Memurai (Redis-compatible)
# Or use Chocolatey:
choco install redis-64

# Start Redis service
redis-server --service-start

# Or run Redis in a terminal:
redis-server
```

## 4. Initialize Database Schema

```powershell
cd ..\main_server

# Run Alembic migrations
alembic upgrade head

# Or run schema directly
mysql -u systemuser -p message_system < schema.sql
```

## 5. Generate Certificates

```powershell
cd ..\main_server

# Initialize CA
.\init_ca.bat

# Generate test client certificate
.\generate_cert.bat test_client
```

## 6. Create Test Users

```powershell
cd ..\main_server

# Create admin user
python admin_cli.py user create admin@example.com --role admin

# Create regular users
python admin_cli.py user create user1@example.com --role user
python admin_cli.py user create user2@example.com --role user
```

## 7. Start All Services

Open 4 separate PowerShell terminals:

### Terminal 1 - Main Server:
```powershell
cd main_server
.\start_server.ps1
```

### Terminal 2 - Proxy:
```powershell
cd proxy
.\start_proxy.ps1
```

### Terminal 3 - Worker:
```powershell
cd worker
.\start_worker.ps1
```

### Terminal 4 - Portal:
```powershell
cd portal
.\start_portal.ps1
```

## 8. Verify Services

```powershell
# Check Main Server
curl -k https://localhost:8000/health

# Check Proxy
curl -k https://localhost:8001/api/v1/health

# Check Portal
curl http://localhost:8080/health
```

## 9. Run Tests

```powershell
cd tests

# Run all tests
.\run_all_tests.ps1

# Or run specific test suites
.\run_integration_tests.ps1
.\run_load_tests.ps1 -SkipLoad:$false
.\run_security_tests.ps1
```

## Quick Setup (Development)

If you just want to verify the test framework works:

```powershell
# 1. Install dependencies
pip install httpx redis pymysql

# 2. Start Redis (if available)
redis-server

# 3. Start MySQL (if available)
net start MySQL80

# 4. Run integration tests (will show what's needed)
python integration_test.py
```

## Troubleshooting

### "Module not found" errors
```powershell
pip install -r requirements.txt
```

### "Connection refused" errors
- Verify MySQL is running: `sc query MySQL80`
- Verify Redis is running: `redis-cli ping`
- Check services are listening on correct ports

### Certificate errors
- Run `cd main_server; .\init_ca.bat`
- Generate client certs: `.\generate_cert.bat test_client`

### Database errors
- Verify database exists: `mysql -u systemuser -p -e "SHOW DATABASES;"`
- Run migrations: `cd main_server; alembic upgrade head`

## Test Execution Order

For first-time testing:

1. ✅ Setup environment (Steps 1-6)
2. ✅ Start services (Step 7)
3. ✅ Verify services (Step 8)
4. ✅ Run smoke test (quick verification)
5. ✅ Run functional tests
6. ✅ Run integration tests
7. ✅ Run load tests (optional, takes time)
8. ✅ Run security tests
9. ✅ Generate test report

## Expected Test Results

With all services running:
- **Functional Tests**: Should pass if components are implemented correctly
- **Integration Tests**: Should pass if all services communicate properly
- **Load Tests**: Should pass if system meets performance targets
- **Security Tests**: Should pass if security features are implemented

Without services running:
- Tests will fail with connection errors (expected)
- This demonstrates what infrastructure is needed

