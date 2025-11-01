# Message Broker System - Testing Guide

This guide explains how to test the message broker system before delivering it to end users.

## Quick Test

The fastest way to test the system:

```powershell
.\run_system_test.ps1 -Quick
```

This will:
- Check all prerequisites (Python, MySQL, Redis, Certificates)
- Verify services are running
- Run basic functional tests
- Generate a summary report

## Comprehensive Test

For a full test suite:

```powershell
.\run_system_test.ps1
```

This includes all tests plus integration tests.

## Complete Test Suite

For the most comprehensive testing (includes load and security tests):

```powershell
.\test_complete_system.ps1 -Quick
```

Or without the Quick flag for full load and security testing:

```powershell
.\test_complete_system.ps1
```

## Before Testing

### 1. Start All Services

```powershell
.\start_all_services.ps1
```

Wait for all services to start (about 10-15 seconds). The script will verify they're running.

### 2. Verify Services

Check that services are running:

- **Main Server**: https://localhost:8000/health
- **Proxy Server**: https://localhost:8001/api/v1/health  
- **Web Portal**: http://localhost:5000

### 3. Check Prerequisites

```powershell
cd tests
python preflight_check.py
```

This verifies:
- Python version and dependencies
- MySQL connection
- Redis connection
- Certificate files
- Database schema

## Test Categories

### 1. Prerequisites Test
- ✅ Python installed and accessible
- ✅ MySQL service running
- ✅ Redis service running
- ✅ Certificates generated
- ✅ Encryption key exists

### 2. Service Health Tests
- ✅ Main Server responding
- ✅ Proxy Server responding
- ✅ Web Portal accessible
- ✅ Worker process running (checked automatically)

### 3. Functional Tests
- ✅ Message submission via proxy
- ✅ Message queuing in Redis
- ✅ Message processing by worker
- ✅ Message storage in database
- ✅ Portal message viewing

### 4. Integration Tests
- ✅ End-to-end message flow
- ✅ Certificate authentication
- ✅ Database persistence
- ✅ Status updates

### 5. Load Tests (Optional)
- ✅ Throughput testing
- ✅ Concurrent processing
- ✅ Queue management under load

### 6. Security Tests (Optional)
- ✅ Mutual TLS enforcement
- ✅ Message encryption
- ✅ Access control

## Understanding Test Results

### Success Criteria

The system passes testing if:

1. ✅ All prerequisites are met
2. ✅ All services are running
3. ✅ At least basic functional tests pass
4. ✅ No critical errors in logs

### Common Issues

#### Services Not Running
**Solution**: Start services with `.\start_all_services.ps1`

#### MySQL Not Running
**Solution**: 
```powershell
net start MySQL80
```

#### Redis Not Running
**Solution**:
```powershell
redis-server --service-start
```

#### Certificates Missing
**Solution**: Generate certificates
```powershell
cd main_server
.\init_ca.bat
.\generate_cert.bat test_client
```

#### Health Checks Failing
**Solution**: 
- Check service logs: `Get-Content logs\*.log -Tail 50`
- Verify ports are not blocked
- Wait a few seconds for services to fully initialize

## Manual Testing Checklist

After automated tests pass, verify manually:

### Portal Testing
- [ ] Access portal at http://localhost:5000
- [ ] Login with admin credentials
- [ ] View messages list
- [ ] Check message details
- [ ] Test user management (admin only)
- [ ] Test certificate management (admin only)

### API Testing
- [ ] Send message via proxy with client certificate
- [ ] Verify message appears in portal
- [ ] Check message status transitions
- [ ] Verify message encryption

### System Testing
- [ ] Restart services - verify they recover
- [ ] Send multiple messages concurrently
- [ ] Stop and start worker - verify queue processing resumes
- [ ] Check logs for errors

## Test Output Files

Test results are saved in:
- `tests/logs/test_run_[timestamp].log` - Detailed execution log
- `tests/logs/test_results_[timestamp].json` - Machine-readable results
- `tests/logs/test_report_[timestamp].html` - HTML report (if using complete test)

## Stopping Services After Testing

```powershell
.\stop_all_services.ps1
```

## Troubleshooting

### Tests Fail to Run
1. Check Python is in venv: `.\venv\Scripts\python.exe --version`
2. Verify MySQL is running: `Get-Service | Where-Object { $_.Name -like "*mysql*" }`
3. Verify Redis is running: `redis-cli ping`
4. Check certificates exist: `Test-Path main_server\certs\ca.crt`

### Services Won't Start
1. Check if ports are in use: `Get-NetTCPConnection -LocalPort 8000`
2. Review service logs in `logs\` directory
3. Verify database connection: Check `.env` file for DATABASE_URL

### Tests Pass But System Doesn't Work
1. Check service logs for runtime errors
2. Verify database schema is up to date (run Alembic migrations)
3. Check Redis queue: `redis-cli LLEN message_queue`
4. Verify certificates are valid and not expired

## Next Steps After Testing

Once all tests pass:

1. ✅ Review test report
2. ✅ Fix any warnings or issues found
3. ✅ Verify all features manually
4. ✅ Check logs for errors
5. ✅ Document any known limitations
6. ✅ Prepare deployment package
7. ✅ Create user documentation

## Support

If you encounter issues during testing:
1. Check the logs in `logs\` directory
2. Review component-specific READMEs
3. Check `docs/OPERATIONS_RUNBOOK.md` for operational guidance
4. Review `PRODUCTION_READINESS_TESTS.md` for production checklist
