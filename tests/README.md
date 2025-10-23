# Message Broker System - Testing Suite

Comprehensive test suite for Phase 8 - Testing & QA

## Overview

This directory contains all testing artifacts for the Message Broker System, including:
- Test plans and strategies
- Test execution scripts
- Integration, load, and security tests
- Test reports and checklists
- Bug tracking documentation

## Quick Start

### Prerequisites

1. All system components installed and configured
2. Database initialized (run Alembic migrations)
3. Redis running
4. Test certificates generated
5. Virtual environment activated

### Running All Tests

```powershell
cd tests
.\run_all_tests.ps1
```

### Running Specific Test Suites

```powershell
# Functional tests only
.\run_functional_tests.ps1

# Integration tests
.\run_integration_tests.ps1

# Load tests (takes several minutes)
.\run_load_tests.ps1

# Security tests
.\run_security_tests.ps1
```

### Quick Test (Skip Load & Security)

```powershell
.\run_all_tests.ps1 -Quick
```

## Test Documentation

- **`TEST_PLAN.md`** - Comprehensive test plan with all test cases
- **`TEST_REPORT_TEMPLATE.md`** - Template for test execution reports
- **`BUGS.md`** - Bug tracking and resolution log
- **`QA_CHECKLIST.md`** - Final QA verification checklist

## Test Scripts

### Master Test Runner
- `run_all_tests.ps1` - Executes complete test suite

### Individual Test Suites
- `run_functional_tests.ps1` - Runs component functional tests
- `run_integration_tests.ps1` - Runs integration tests
- `run_load_tests.ps1` - Runs performance/load tests
- `run_security_tests.ps1` - Runs security verification tests

### Test Implementations
- `integration_test.py` - End-to-end integration tests
- `load_test.py` - Load and performance tests
- `security_test.py` - Security verification tests

## Test Categories

### 1. Functional Tests
- **Proxy**: 10 test cases (TC-P-001 to TC-P-010)
- **Main Server**: 15 test cases (TC-M-001 to TC-M-015)
- **Worker**: 10 test cases (TC-W-001 to TC-W-010)
- **Portal**: 15 test cases (TC-PT-001 to TC-PT-015)

### 2. Integration Tests
- **End-to-End Flows**: 5 test cases (TC-I-001 to TC-I-005)
- **Authentication**: 4 test cases (TC-I-006 to TC-I-009)
- **Component Integration**: 5 test cases (TC-I-010 to TC-I-014)

### 3. Load Tests
- **Throughput**: 4 test cases (TC-L-001 to TC-L-004)
- **Concurrency**: 4 test cases (TC-L-008 to TC-L-011)
- **Target**: 100,000 messages/day (~1.16 msg/sec)

### 4. Security Tests
- **Authentication**: 8 test cases (TC-S-001 to TC-S-008)
- **Encryption**: 5 test cases (TC-S-009 to TC-S-013)
- **Access Control**: 4 test cases (TC-S-014 to TC-S-017)

## Test Results

Test results are stored in `logs/` directory:
- `test_run_[timestamp].log` - Execution logs
- `test_results_[timestamp].json` - Machine-readable results

## Usage Examples

### Run Full Test Suite

```powershell
# Run all tests with detailed output
.\run_all_tests.ps1

# Run tests, skip load and security (faster)
.\run_all_tests.ps1 -Quick

# Run tests, skip only load tests
.\run_all_tests.ps1 -SkipLoad

# Run tests, skip only security tests
.\run_all_tests.ps1 -SkipSecurity
```

### View Test Results

```powershell
# View latest log
Get-Content logs\*.log | Select-Object -Last 50

# View latest results
Get-Content logs\test_results_*.json | ConvertFrom-Json
```

## Test Configuration

Edit test scripts to modify configuration:

**Integration Tests** (`integration_test.py`):
```python
PROXY_URL = "https://localhost:8001"
MAIN_SERVER_URL = "https://localhost:8000"
REDIS_HOST = "localhost"
REDIS_PORT = 6379
```

**Load Tests** (`load_test.py`):
```python
TARGET_DAILY = 100000  # messages per day
BURST_RATE = 100  # messages per second
TEST_DURATION_SUSTAINED = 60  # seconds
TEST_DURATION_BURST = 30  # seconds
```

**Security Tests** (`security_test.py`):
```python
DB_CONFIG = {
    "host": "localhost",
    "user": "systemuser",
    "password": "StrongPass123!",
    "database": "message_system"
}
```

## Success Criteria

### Functional Testing
- ✅ 100% of critical test cases pass
- ✅ 95%+ of all test cases pass
- ✅ All blocking bugs fixed

### Integration Testing
- ✅ End-to-end message flow works
- ✅ All component integrations verified
- ✅ No data loss in pipeline

### Load Testing
- ✅ System handles 100,000 messages/day
- ✅ No message loss under load
- ✅ Response times < 5 seconds (P99)

### Security Testing
- ✅ Mutual TLS enforced
- ✅ Messages encrypted at rest
- ✅ Role-based access control working

## Troubleshooting

### Tests Fail to Run

**Problem**: Prerequisites not met

**Solution**:
```powershell
# Check Python
python --version

# Check MySQL
mysql --version

# Check Redis
redis-cli ping

# Check services running
.\check_services.ps1  # If available
```

### Database Connection Errors

**Problem**: Cannot connect to MySQL

**Solution**:
```powershell
# Verify MySQL is running
sc query MySQL80  # Windows

# Test connection
mysql -u systemuser -p message_system

# Check DATABASE_URL in .env
```

### Redis Connection Errors

**Problem**: Cannot connect to Redis

**Solution**:
```powershell
# Start Redis (Windows)
redis-server --service-start

# Test Redis
redis-cli ping
```

### Certificate Errors

**Problem**: Missing or invalid certificates

**Solution**:
```powershell
# Generate missing certificates
cd ..\main_server
.\init_ca.bat
.\generate_cert.bat test_client
```

## Test Report

After running tests, generate a test report:

1. Copy `TEST_REPORT_TEMPLATE.md` to `TEST_REPORT_[date].md`
2. Fill in results from `logs/test_results_*.json`
3. Document any bugs in `BUGS.md`
4. Complete `QA_CHECKLIST.md`
5. Get sign-offs from stakeholders

## Continuous Improvement

After each test cycle:

1. Review failed tests and fix issues
2. Update test cases if requirements changed
3. Add new test cases for new features
4. Update documentation
5. Share lessons learned

## Support

For testing issues:
- Check test logs in `logs/` directory
- Review `TEST_PLAN.md` for test details
- Check component-specific test scripts (proxy, main_server, worker)
- Review main documentation in parent directory

## License

See root LICENSE file for details.

