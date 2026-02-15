# Message Broker Test Script - User Guide

**Version**: 1.0.0  
**Last Updated**: November 2025  
**Script**: `test_message_broker.py`

---

## Overview

The `test_message_broker.py` script is a comprehensive testing tool that verifies all components of the Message Broker System and sends test messages through the system. It performs end-to-end testing to ensure everything is working correctly.

---

## Prerequisites

### Required Software

- **Python 3.8+** installed and in PATH
- **Virtual environment** activated (if using project's venv)
- **Message Broker services running**:
  - Main Server (port 8000)
  - Proxy Server (port 8001)
  - Worker service
  - Portal (port 5000 or 8080)
- **MySQL** running and accessible
- **Redis** running and accessible

### Required Python Packages

The script requires the following Python packages:

```bash
pip install httpx redis
```

Or install from requirements:

```bash
# If using project's requirements
pip install -r client-scripts/requirements.txt
pip install redis
```

### Optional: Client Certificates

For full mTLS testing (via proxy), you need client certificates:
- `client-scripts/certs/test_client.crt`
- `client-scripts/certs/test_client.key`
- `client-scripts/certs/ca.crt`

**Note**: If certificates are not available, use the `--direct` flag to bypass the proxy and test directly via the main server API.

---

## Quick Start

### Basic Usage (No Certificates Required)

```bash
# Activate virtual environment (if using project's venv)
source venv/bin/activate  # Linux/Mac
# OR
.\venv\Scripts\Activate.ps1  # Windows PowerShell

# Run test with default message
python test_message_broker.py --direct

# Run test with custom message
python test_message_broker.py --direct --message "My test message"
```

### Full Test (With Certificates)

```bash
# Ensure certificates are in client-scripts/certs/
python test_message_broker.py --message "Test message"
```

---

## Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--sender` | Sender phone number in E.164 format | `+1234567890` | No |
| `--message` | Test message body | `"Test message from automated test"` | No |
| `--skip-cert` | Skip certificate-based tests | `False` | No |
| `--direct` | Use direct main server API (bypasses proxy, no certs needed) | `False` | No |

### Examples

**Example 1: Simple test with default settings**
```bash
python test_message_broker.py --direct
```

**Example 2: Custom message and sender**
```bash
python test_message_broker.py --direct \
    --sender "+9876543210" \
    --message "Hello from test script"
```

**Example 3: Full test with certificates**
```bash
python test_message_broker.py \
    --sender "+1234567890" \
    --message "Full mTLS test message"
```

**Example 4: Skip certificate check**
```bash
python test_message_broker.py --skip-cert --direct
```

---

## What the Test Script Does

The script performs a comprehensive 6-phase test:

### Phase 1: Service Health Checks
- ✅ Verifies Main Server is healthy (`https://localhost:8000/health`)
- ✅ Verifies Proxy Server is healthy (`https://localhost:8001/api/v1/health`)
- ✅ Verifies Portal is accessible (`http://localhost:5000` or `http://localhost:8080`)
- ✅ Tests Redis connection and checks queue size

### Phase 2: Certificate Check
- ✅ Checks if test certificates exist in `client-scripts/certs/`
- ⚠️ Provides instructions if certificates are missing

### Phase 3: Message Sending Test
- **With `--direct` flag**: Sends message directly to main server internal API (bypasses proxy, no certificates needed)
- **Without `--direct` flag**: Sends message via proxy with mTLS certificates (requires certificates)
- ✅ Returns message ID on success

### Phase 4: Queue Verification
- ✅ Checks if message was queued in Redis
- ✅ Verifies message processing

### Phase 5: Worker Processing
- ✅ Waits 5 seconds for worker to process the message
- ✅ Verifies queue is empty after processing

### Phase 6: System Statistics
- ✅ Attempts to fetch system statistics from main server

---

## Expected Output

### Successful Test Output

```
======================================================================
MESSAGE BROKER SYSTEM TEST
======================================================================

[INFO] Test started: 2025-11-28 09:28:59
[INFO] Proxy: https://localhost:8001
[INFO] Main Server: https://localhost:8000
[INFO] Portal: http://localhost:5000


======================================================================
PHASE 1: SERVICE HEALTH CHECKS
======================================================================

[TEST] Checking Main Server health...
[PASS] Main Server is healthy
[TEST] Checking Proxy Server health...
[PASS] Proxy Server is healthy
[TEST] Checking portal accessibility...
[PASS] Portal is accessible
[TEST] Testing Redis connection...
[PASS] Redis is connected (queue size: 0)

======================================================================
PHASE 2: CERTIFICATE CHECK
======================================================================

[PASS] Test certificates found

======================================================================
PHASE 3: MESSAGE SENDING TEST
======================================================================

[TEST] Sending message via main server internal API...
[WARN] This bypasses proxy and mTLS - for testing only!
[PASS] Message registered: test_1764309547
[INFO] Message ID: test_1764309547

======================================================================
PHASE 4: QUEUE VERIFICATION
======================================================================

[TEST] Checking message in Redis queue...
[WARN] Queue is empty (worker may have processed it)

======================================================================
PHASE 5: WORKER PROCESSING
======================================================================

[INFO] Waiting 5 seconds for worker to process message...
[TEST] Re-checking queue after processing...
[PASS] Queue is empty - worker processed messages

======================================================================
PHASE 6: SYSTEM STATISTICS
======================================================================

[TEST] Fetching system statistics...
[WARN] Stats endpoint returned 403

======================================================================
TEST SUMMARY
======================================================================

Passed: 5
Warnings: 2
Failed: 0

Total Checks: 7

[SUCCESS] ALL CRITICAL TESTS PASSED

Next Steps:
1. View messages in portal: http://localhost:5000
2. Check logs: Get-Content logs\*.log -Tail 50
3. Monitor metrics: https://localhost:8000/metrics
```

### Exit Codes

- **0**: All critical tests passed
- **1**: One or more critical tests failed

---

## Viewing Test Messages

After running the test, you can view the test message in the web portal:

1. **Open the portal**:
   - Local: `http://localhost:5000` or `http://localhost:8080`
   - Remote: `http://YOUR_SERVER_IP:5000` or `http://YOUR_SERVER_IP:8080`

2. **Login** with admin credentials:
   - Email: `admin@example.com`
   - Password: `AdminPass123!` (or as configured)

3. **Navigate to Messages** section

4. **Look for the test message**:
   - Message ID will start with `test_` followed by a timestamp
   - Message content will match what you specified with `--message`
   - Client will be `test_client`
   - Status should be `Delivered` (green checkmark)

---

## Troubleshooting

### Problem: "ModuleNotFoundError: No module named 'httpx'"

**Solution:**
```bash
# Install required packages
pip install httpx redis

# Or activate virtual environment first
source venv/bin/activate  # Linux/Mac
.\venv\Scripts\Activate.ps1  # Windows
```

---

### Problem: "Service not responding"

**Symptoms:**
- `[FAIL] Main Server is not responding`
- `[FAIL] Proxy Server is not responding`
- `[FAIL] Portal not accessible`

**Solutions:**

1. **Check if services are running:**
   ```bash
   # Linux
   sudo systemctl status main_server proxy worker portal
   
   # Windows
   Get-Process python | Where-Object { ... }
   ```

2. **Start services if not running:**
   ```bash
   # Linux
   sudo systemctl start main_server proxy worker portal
   
   # Windows
   .\start_all_services.ps1
   ```

3. **Check ports are listening:**
   ```bash
   # Linux
   ss -tlnp | grep -E ':(8000|8001|5000|8080)'
   
   # Windows
   netstat -ano | findstr "8000 8001 5000 8080"
   ```

---

### Problem: "Test certificates not found"

**Symptoms:**
- `[WARN] Test certificates not found`

**Solutions:**

1. **Use `--direct` flag** (bypasses proxy, no certificates needed):
   ```bash
   python test_message_broker.py --direct
   ```

2. **Generate certificates** (if you need full mTLS testing):
   ```bash
   cd main_server
   python admin_cli.py cert generate test_client
   # Then copy certificates to client-scripts/certs/
   ```

3. **Skip certificate check:**
   ```bash
   python test_message_broker.py --skip-cert --direct
   ```

---

### Problem: "Redis connection failed"

**Symptoms:**
- `[FAIL] Redis connection failed`

**Solutions:**

1. **Check if Redis is running:**
   ```bash
   # Linux
   sudo systemctl status redis-server
   # or
   sudo systemctl status redis
   
   # Windows
   redis-cli ping
   # Should return: PONG
   ```

2. **Start Redis:**
   ```bash
   # Linux
   sudo systemctl start redis-server
   
   # Windows
   redis-server --service-start
   ```

3. **Check Redis configuration:**
   - Default host: `localhost`
   - Default port: `6379`
   - Ensure Redis is accessible from the test machine

---

### Problem: "Queue is empty" (but message not delivered)

**Symptoms:**
- Queue shows empty
- But message status is still "Queued" in portal

**Solutions:**

1. **Check worker is running:**
   ```bash
   # Linux
   sudo systemctl status worker
   
   # Windows
   Get-Process python | Where-Object { ... }
   ```

2. **Check worker logs:**
   ```bash
   # Linux
   sudo journalctl -u worker -f
   
   # Windows
   Get-Content logs\worker.log -Tail 50
   ```

3. **Wait longer** - Worker may need more time to process

---

### Problem: "Database connection error"

**Symptoms:**
- Tests pass but message doesn't appear in portal
- Database-related errors in logs

**Solutions:**

1. **Verify database is running:**
   ```bash
   # Linux
   sudo systemctl status mysql
   # or
   sudo systemctl status mariadb
   
   # Windows
   Get-Service | Where-Object { $_.Name -like "*mysql*" }
   ```

2. **Check database credentials** in `.env` file

3. **Test database connection:**
   ```bash
   mysql -u systemuser -p message_system
   ```

---

## Configuration

### Changing Default URLs

If your services run on different ports or hosts, edit the configuration in `test_message_broker.py`:

```python
# Configuration (lines 23-28)
PROXY_URL = "https://localhost:8001"
MAIN_SERVER_URL = "https://localhost:8000"
PORTAL_URL = "http://localhost:5000"  # or http://localhost:8080
REDIS_HOST = "localhost"
REDIS_PORT = 6379
```

### Testing Remote Servers

To test a remote server, modify the URLs:

```python
PROXY_URL = "https://your-server-ip:8001"
MAIN_SERVER_URL = "https://your-server-ip:8000"
PORTAL_URL = "http://your-server-ip:8080"
REDIS_HOST = "your-server-ip"  # If Redis is accessible remotely
```

**Note**: Ensure firewall rules allow connections to these ports.

---

## Advanced Usage

### Running Multiple Tests

```bash
# Test 1: Basic functionality
python test_message_broker.py --direct --message "Test 1"

# Test 2: Different sender
python test_message_broker.py --direct --sender "+9999999999" --message "Test 2"

# Test 3: Full mTLS flow
python test_message_broker.py --message "Test 3"
```

### Integration with CI/CD

```bash
#!/bin/bash
# Example CI/CD script

cd /opt/message_broker
source venv/bin/activate

# Run test
python test_message_broker.py --direct --message "CI/CD test"

# Check exit code
if [ $? -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Tests failed!"
    exit 1
fi
```

### Automated Testing Script

```bash
#!/bin/bash
# Run tests every 5 minutes

while true; do
    python test_message_broker.py --direct --message "Automated test at $(date)"
    sleep 300  # 5 minutes
done
```

---

## Best Practices

1. **Always use `--direct` flag for quick testing** (no certificates needed)

2. **Use full mTLS test** (`--direct` flag removed) for production verification

3. **Check service status before running tests** to avoid false failures

4. **Review test output carefully** - warnings may indicate configuration issues

5. **View messages in portal** after each test to verify end-to-end flow

6. **Keep test messages unique** by including timestamps or unique identifiers

---

## Support

For issues or questions:

1. **Check service logs:**
   ```bash
   # Linux
   sudo journalctl -u main_server -n 50
   
   # Windows
   Get-Content logs\*.log -Tail 50
   ```

2. **Verify all services are running**

3. **Check network connectivity** to services

4. **Review this guide** for common issues

---

## Quick Reference

**Basic test (no certificates):**
```bash
python test_message_broker.py --direct
```

**Custom message:**
```bash
python test_message_broker.py --direct --message "Your message"
```

**Full test with certificates:**
```bash
python test_message_broker.py --message "Test message"
```

**View test results:**
- Portal: `http://localhost:5000` or `http://localhost:8080`
- Look for messages with ID starting with `test_`

---

**Document Version**: 1.0.0  
**Last Updated**: November 2025  
**Maintained By**: Message Broker Development Team

