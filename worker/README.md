# Message Broker Worker

The worker service is responsible for consuming messages from the Redis queue and delivering them to the main server with retry logic.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Installation](#installation)
- [Usage](#usage)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Production Deployment](#production-deployment)

---

## Overview

The worker is a Python service that:

1. **Consumes messages** from a Redis queue (atomic BRPOP operation)
2. **Delivers messages** to the main server via mutual TLS
3. **Retries failed deliveries** every 30 seconds (configurable)
4. **Updates message status** in the main server database
5. **Exposes Prometheus metrics** for monitoring

### Message Flow

```
Redis Queue → Worker (BRPOP) → Main Server (mTLS) → Status Update → Complete/Retry
```

### Retry Logic

- **Fixed interval**: 30 seconds by default (configurable)
- **Max attempts**: 10,000 by default (configurable)
- **Strategy**: Re-queue message after retry interval
- **Backoff**: None (per requirements - fixed 30s interval)

---

## Features

### Core Features

✅ **Atomic Queue Consumption**: Uses Redis BRPOP for safe concurrent processing
✅ **Mutual TLS Authentication**: Secure communication with main server
✅ **Configurable Concurrency**: Process multiple messages simultaneously
✅ **Fixed Retry Interval**: Reliable retry behavior (30s default)
✅ **Graceful Shutdown**: Handles SIGTERM/SIGINT cleanly
✅ **Comprehensive Logging**: Daily rotating logs with configurable levels
✅ **Prometheus Metrics**: Real-time performance monitoring

### Advanced Features

✅ **Multiple Worker Support**: Run multiple worker processes concurrently
✅ **Health Monitoring**: Tracks queue size, processing time, and failures
✅ **Resource Limits**: Configurable max attempts and concurrency
✅ **Error Recovery**: Automatic reconnection to Redis and main server
✅ **Queue Wait Time Tracking**: Monitors message age in queue

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                         Worker Process                       │
│                                                              │
│  ┌────────────────┐  ┌──────────────────┐  ┌─────────────┐│
│  │ Redis Manager  │  │ Message Processor │  │ Main Server ││
│  │                │  │                   │  │   Client    ││
│  │ - BRPOP queue  │──│ - Validate        │──│ - Deliver   ││
│  │ - Push retry   │  │ - Process         │  │ - Update    ││
│  │ - Get size     │  │ - Retry logic     │  │   status    ││
│  └────────────────┘  └──────────────────┘  └─────────────┘│
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │              Prometheus Metrics Server                  ││
│  │  - Messages processed  - Delivery duration             ││
│  │  - Success/failure     - Queue wait time               ││
│  └────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Message Processing Flow

```
1. Worker starts and connects to Redis
2. BRPOP message from queue (blocking, timeout 5s)
3. Parse message JSON
4. Check attempt count vs max attempts
5. Deliver to main server via mTLS POST
6. On success:
   - Update status to "delivered"
   - Increment success metrics
7. On failure:
   - Increment attempt count
   - Update status to "queued"
   - Wait retry_interval (30s)
   - Re-queue message (LPUSH)
8. Repeat from step 2
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_HOST` | `localhost` | Redis server hostname |
| `REDIS_PORT` | `6379` | Redis server port |
| `REDIS_DB` | `0` | Redis database number |
| `REDIS_PASSWORD` | _(empty)_ | Redis password (optional) |
| `MAIN_SERVER_URL` | `https://localhost:8000` | Main server base URL |
| `WORKER_ID` | `worker-<pid>` | Unique worker identifier |
| `WORKER_CONCURRENCY` | `4` | Number of concurrent message processors |
| `WORKER_RETRY_INTERVAL` | `30` | Retry interval in seconds |
| `WORKER_MAX_ATTEMPTS` | `10000` | Maximum delivery attempts |
| `WORKER_BATCH_SIZE` | `10` | Batch size for processing |
| `WORKER_METRICS_ENABLED` | `true` | Enable Prometheus metrics |
| `WORKER_METRICS_PORT` | `9100` | Prometheus metrics port |
| `WORKER_CERT_PATH` | `certs/worker.crt` | Path to worker certificate |
| `WORKER_KEY_PATH` | `certs/worker.key` | Path to worker private key |
| `CA_CERT_PATH` | `certs/ca.crt` | Path to CA certificate |
| `LOG_LEVEL` | `INFO` | Logging level (DEBUG, INFO, WARNING, ERROR) |
| `LOG_FILE_PATH` | `logs` | Directory for log files |

### Configuration File

The `config.yaml` file provides additional configuration options:

```yaml
redis:
  host: "${REDIS_HOST}"
  port: ${REDIS_PORT}
  queue_name: "message_queue"

worker:
  concurrency: ${WORKER_CONCURRENCY}
  retry_interval: ${WORKER_RETRY_INTERVAL}
  max_attempts: ${WORKER_MAX_ATTEMPTS}

tls:
  enabled: true
  cert_file: "certs/worker.crt"
  key_file: "certs/worker.key"
  ca_file: "certs/ca.crt"

metrics:
  enabled: true
  port: 9100
```

---

## Installation

### Prerequisites

- Python 3.8+
- Redis server running
- Main server running with mutual TLS
- Worker certificate generated by main server CA

### Windows Setup

1. **Create virtual environment**:
   ```powershell
   cd worker
   python -m venv venv
   .\venv\Scripts\Activate.ps1
   ```

2. **Install dependencies**:
   ```powershell
   pip install -r requirements.txt
   ```

3. **Generate worker certificate**:
   ```powershell
   cd ..\main_server
   .\generate_cert.bat worker
   ```

4. **Copy certificates to worker directory**:
   ```powershell
   cd ..\worker
   mkdir certs
   copy ..\main_server\certs\ca.crt certs\
   copy ..\main_server\certs\worker.crt certs\
   copy ..\main_server\certs\worker.key certs\
   ```

5. **Create .env file** (optional):
   ```powershell
   copy ..\.env.template ..\.env
   # Edit .env with your configuration
   ```

### Linux Setup

1. **Create virtual environment**:
   ```bash
   cd worker
   python3 -m venv venv
   source venv/bin/activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Generate worker certificate**:
   ```bash
   cd ../main_server
   ./generate_cert.sh worker
   ```

4. **Copy certificates**:
   ```bash
   cd ../worker
   mkdir -p certs
   cp ../main_server/certs/ca.crt certs/
   cp ../main_server/certs/worker.crt certs/
   cp ../main_server/certs/worker.key certs/
   chmod 600 certs/worker.key
   ```

---

## Usage

### Single Worker

#### Windows (Batch Script)
```cmd
cd worker
start_worker.bat
```

#### Windows (PowerShell)
```powershell
cd worker
.\start_worker.ps1 -WorkerId "worker-1" -Concurrency 4 -RetryInterval 30
```

**PowerShell Parameters**:
- `-WorkerId`: Unique worker identifier
- `-Concurrency`: Number of concurrent processors (default: 4)
- `-RetryInterval`: Retry interval in seconds (default: 30)
- `-MaxAttempts`: Maximum attempts per message (default: 10000)
- `-MetricsPort`: Prometheus metrics port (default: 9100)
- `-LogLevel`: Log level (default: INFO)

#### Linux
```bash
cd worker
python worker.py
```

### Multiple Workers

For high throughput, run multiple worker processes:

#### Windows (PowerShell)
```powershell
cd worker
.\start_multiple_workers.ps1 -NumWorkers 3 -Concurrency 4
```

**Parameters**:
- `-NumWorkers`: Number of worker processes (default: 3)
- `-Concurrency`: Concurrent processors per worker (default: 4)
- `-BaseMetricsPort`: Starting metrics port (default: 9100)

This starts 3 workers with metrics on ports 9100, 9101, 9102.

#### Linux (systemd)

Enable multiple worker instances:

```bash
# Start 3 worker instances
sudo systemctl start worker@1
sudo systemctl start worker@2
sudo systemctl start worker@3

# Enable on boot
sudo systemctl enable worker@1
sudo systemctl enable worker@2
sudo systemctl enable worker@3
```

---

## Monitoring

### Prometheus Metrics

Workers expose Prometheus metrics on port 9100 (configurable):

#### Available Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `worker_messages_processed_total` | Counter | Total messages processed |
| `worker_messages_delivered_total` | Counter | Total messages delivered successfully |
| `worker_messages_failed_total` | Counter | Total failed messages |
| `worker_messages_retried_total` | Counter | Total retry attempts |
| `worker_delivery_duration_seconds` | Histogram | Message delivery time |
| `worker_queue_wait_seconds` | Histogram | Time in queue before processing |
| `worker_active_workers` | Gauge | Number of active workers |
| `worker_processing_messages` | Gauge | Currently processing messages |

#### Accessing Metrics

```bash
# Single worker
curl http://localhost:9100/metrics

# Multiple workers
curl http://localhost:9100/metrics  # Worker 1
curl http://localhost:9101/metrics  # Worker 2
curl http://localhost:9102/metrics  # Worker 3
```

#### Prometheus Configuration

Add to `monitoring/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'workers'
    static_configs:
      - targets: 
        - 'localhost:9100'  # Worker 1
        - 'localhost:9101'  # Worker 2
        - 'localhost:9102'  # Worker 3
```

### Grafana Dashboards

Import the worker dashboard from `monitoring/grafana/dashboards/worker_dashboard.json`.

**Panels**:
- Messages processed per second
- Delivery success rate
- Average delivery duration
- Queue wait time
- Active workers count
- Error rate by reason

### Logging

#### Log Files

- **Location**: `worker/logs/worker.log`
- **Rotation**: Daily at midnight
- **Retention**: 7 days

#### Log Levels

- **DEBUG**: Detailed processing information
- **INFO**: Normal operations (default)
- **WARNING**: Potential issues (e.g., retries)
- **ERROR**: Failures requiring attention

#### Example Log Output

```
2025-01-15 10:30:45,123 - worker - INFO - [worker-1] - Worker worker-1 starting...
2025-01-15 10:30:45,234 - worker - INFO - [worker-1] - Connected to Redis at localhost:6379
2025-01-15 10:30:45,345 - worker - INFO - [worker-1] - Prometheus metrics server started on port 9100
2025-01-15 10:30:50,456 - worker - INFO - [worker-1] - Processing message 123e4567-e89b-12d3-a456-426614174000 (attempt 1/10000)
2025-01-15 10:30:50,567 - worker - INFO - [worker-1] - Message 123e4567-e89b-12d3-a456-426614174000 delivered successfully
```

### Health Checks

#### Redis Queue Size

```bash
# Windows
redis-cli LLEN message_queue

# Linux
redis-cli LLEN message_queue
```

#### Worker Status (systemd)

```bash
# Check worker status
systemctl status worker@1

# View logs
journalctl -u worker@1 -f
```

---

## Troubleshooting

### Common Issues

#### 1. Cannot Connect to Redis

**Symptoms**:
```
ERROR: Cannot connect to Redis at localhost:6379
```

**Solutions**:
- Verify Redis is running: `redis-cli ping`
- Check Redis configuration in `.env`
- Verify firewall allows connection
- Windows: `redis-server --service-start`
- Linux: `sudo systemctl start redis`

#### 2. Certificate Errors

**Symptoms**:
```
ERROR: Worker certificate not found at certs/worker.crt
```

**Solutions**:
```powershell
# Generate worker certificate
cd main_server
.\generate_cert.bat worker

# Copy to worker directory
cd ..\worker
mkdir certs
copy ..\main_server\certs\worker.* certs\
copy ..\main_server\certs\ca.crt certs\
```

#### 3. Main Server Connection Failed

**Symptoms**:
```
ERROR: Failed to connect to main server: Connection refused
```

**Solutions**:
- Verify main server is running
- Check `MAIN_SERVER_URL` in `.env`
- Verify mutual TLS is configured correctly
- Test certificate: `openssl s_client -connect localhost:8000 -cert certs/worker.crt -key certs/worker.key -CAfile certs/ca.crt`

#### 4. Messages Not Being Processed

**Symptoms**:
- Queue size increasing
- No log activity

**Solutions**:
- Check worker is running: `Get-Process python`
- Verify Redis queue has messages: `redis-cli LLEN message_queue`
- Check worker logs: `Get-Content logs\worker.log -Tail 50`
- Verify worker certificates are valid
- Check main server is accepting connections

#### 5. High Memory Usage

**Symptoms**:
- Worker consuming excessive memory
- Out of memory errors

**Solutions**:
- Reduce `WORKER_CONCURRENCY` value
- Lower `WORKER_BATCH_SIZE`
- Restart worker periodically
- Monitor with: `Get-Process python | Select-Object CPU,WorkingSet`

#### 6. Slow Processing

**Symptoms**:
- Messages taking long to process
- Queue backing up

**Solutions**:
- Increase `WORKER_CONCURRENCY`
- Run multiple worker processes
- Check main server performance
- Review delivery duration metrics in Grafana
- Optimize network latency

### Debug Mode

Enable debug logging for detailed information:

```powershell
# Windows
$env:LOG_LEVEL="DEBUG"
.\start_worker.ps1

# Linux
export LOG_LEVEL=DEBUG
python worker.py
```

### Manual Testing

Test worker independently:

```python
# Test Redis connection
import redis
r = redis.Redis(host='localhost', port=6379, db=0)
r.ping()

# Check queue
r.llen('message_queue')

# Pop message manually
message = r.brpop('message_queue', timeout=5)
print(message)
```

---

## Production Deployment

### Windows Production Setup

#### 1. Install as Windows Service

Use NSSM (Non-Sucking Service Manager):

```powershell
# Download NSSM
choco install nssm

# Install worker service
nssm install MessageBrokerWorker1 "C:\message_broker\venv\Scripts\python.exe"
nssm set MessageBrokerWorker1 AppParameters "C:\message_broker\worker\worker.py"
nssm set MessageBrokerWorker1 AppDirectory "C:\message_broker\worker"
nssm set MessageBrokerWorker1 AppEnvironmentExtra "WORKER_ID=worker-1" "WORKER_METRICS_PORT=9100"
nssm set MessageBrokerWorker1 DisplayName "Message Broker Worker 1"
nssm set MessageBrokerWorker1 Description "Message Broker Worker Process 1"
nssm set MessageBrokerWorker1 Start SERVICE_AUTO_START

# Start service
nssm start MessageBrokerWorker1

# View status
nssm status MessageBrokerWorker1
```

#### 2. Install Multiple Workers

```powershell
for ($i=1; $i -le 3; $i++) {
    nssm install "MessageBrokerWorker$i" "C:\message_broker\venv\Scripts\python.exe"
    nssm set "MessageBrokerWorker$i" AppParameters "C:\message_broker\worker\worker.py"
    nssm set "MessageBrokerWorker$i" AppDirectory "C:\message_broker\worker"
    nssm set "MessageBrokerWorker$i" AppEnvironmentExtra "WORKER_ID=worker-$i" "WORKER_METRICS_PORT=$((9100 + $i - 1))"
    nssm start "MessageBrokerWorker$i"
}
```

### Linux Production Setup

#### 1. Install systemd Service

```bash
# Copy service file
sudo cp worker.service /etc/systemd/system/worker@.service

# Reload systemd
sudo systemctl daemon-reload

# Enable and start workers
for i in {1..3}; do
    sudo systemctl enable worker@$i
    sudo systemctl start worker@$i
done

# Check status
sudo systemctl status worker@1
```

#### 2. Configure Service User

```bash
# Create service user
sudo useradd -r -s /bin/false messagebroker

# Set permissions
sudo chown -R messagebroker:messagebroker /opt/message_broker
sudo chmod 700 /opt/message_broker/worker/certs
sudo chmod 600 /opt/message_broker/worker/certs/*.key
```

### Performance Tuning

#### Concurrency Calculation

**Formula**: `Total Throughput = NumWorkers × Concurrency × (1 / AvgDeliveryTime)`

**Example**:
- Target: 100,000 messages/day = ~1.16 messages/second
- Avg delivery time: 200ms (0.2s)
- Configuration:
  - NumWorkers: 2
  - Concurrency: 4
  - Total capacity: 2 × 4 × (1/0.2) = 40 messages/second

**Recommendation**:
- Start with: 2-3 workers, concurrency 4
- Monitor queue size and delivery duration
- Adjust based on actual throughput

#### Resource Limits

**Memory**:
- Each worker: ~100-200MB base
- Each concurrent processor: ~10-20MB
- Total: `NumWorkers × (200MB + Concurrency × 20MB)`

**CPU**:
- Worker processes: CPU-bound during crypto operations
- Recommendation: 1 core per 2 workers

#### Redis Configuration

Optimize Redis for queue workload:

```ini
# redis.conf
maxmemory 2gb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000
```

### Monitoring and Alerts

#### Prometheus Alerts

```yaml
# alerts.yml
groups:
  - name: worker_alerts
    rules:
      - alert: WorkerDown
        expr: up{job="workers"} == 0
        for: 1m
        annotations:
          summary: "Worker {{ $labels.instance }} is down"
      
      - alert: HighErrorRate
        expr: rate(worker_messages_failed_total[5m]) > 0.1
        for: 5m
        annotations:
          summary: "High error rate on {{ $labels.worker_id }}"
      
      - alert: QueueBacklog
        expr: redis_queue_length > 10000
        for: 5m
        annotations:
          summary: "Message queue backlog exceeds 10,000"
```

### Backup and Recovery

#### Worker Configuration Backup

```powershell
# Windows
$backupDir = "C:\backups\worker_$(Get-Date -Format 'yyyyMMdd')"
New-Item -ItemType Directory -Path $backupDir
Copy-Item config.yaml, .env $backupDir\
```

#### Certificate Backup

```powershell
# Backup certificates (encrypted)
$certBackup = "C:\backups\certs_$(Get-Date -Format 'yyyyMMdd').zip"
Compress-Archive -Path certs\* -DestinationPath $certBackup
```

---

## API Reference

### Main Server Endpoints (Called by Worker)

#### POST /internal/messages/deliver

Deliver a message and mark as completed.

**Request**:
```json
{
  "message_id": "123e4567-e89b-12d3-a456-426614174000",
  "worker_id": "worker-1"
}
```

**Response**:
```json
{
  "status": "success",
  "delivered_at": "2025-01-15T10:30:50.567Z"
}
```

#### PUT /internal/messages/{message_id}/status

Update message status.

**Request**:
```json
{
  "status": "queued",
  "attempt_count": 2,
  "error_message": "Connection timeout"
}
```

**Response**:
```json
{
  "status": "updated"
}
```

---

## Development

### Running Tests

```powershell
# Install test dependencies
pip install pytest pytest-asyncio pytest-cov

# Run tests
pytest tests/ -v

# With coverage
pytest tests/ --cov=worker --cov-report=html
```

### Code Quality

```powershell
# Format code
black worker.py

# Lint
flake8 worker.py
pylint worker.py

# Type checking
mypy worker.py
```

---

## License

See root LICENSE file for details.

---

## Support

For issues and questions:
- Check logs: `worker/logs/worker.log`
- View metrics: `http://localhost:9100/metrics`
- Review main documentation: `../README.md`
- Certificate issues: `../main_server/CERTIFICATES_README.md`

