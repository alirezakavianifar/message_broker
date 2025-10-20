# Message Broker Proxy Server

FastAPI-based proxy server for message ingestion with mutual TLS authentication, Redis queuing, and main server integration.

## Features

- ✅ **Mutual TLS Authentication**: Client certificate verification
- ✅ **Message Validation**: E.164 phone number format, message length limits
- ✅ **Redis Queue Integration**: Persistent message queuing with AOF
- ✅ **Main Server Integration**: Automatic message registration
- ✅ **Logging**: Daily rotating logs with configurable levels
- ✅ **Prometheus Metrics**: Request rates, queue size, error tracking
- ✅ **Health Checks**: Component status monitoring
- ✅ **API Documentation**: Auto-generated Swagger UI

## Quick Start

### Prerequisites

- Python 3.12+
- Redis server running
- Valid SSL/TLS certificates
- Main server accessible

### Installation

```powershell
# Install dependencies
pip install -r requirements.txt

# Copy configuration
copy ..\env.template .env
# Edit .env with your configuration

# Copy certificates
copy ..\main_server\certs\ca.crt certs\
copy ..\main_server\certs\clients\proxy\proxy.crt certs\
copy ..\main_server\certs\clients\proxy\proxy.key certs\
```

### Running

**Windows (Batch):**
```batch
REM Development mode (no TLS)
start_proxy.bat --dev

REM Production mode (with TLS)
start_proxy.bat --prod
```

**Windows (PowerShell):**
```powershell
# Development mode
.\start_proxy.ps1 -Dev

# Production mode
.\start_proxy.ps1 -Port 8001 -Workers 4

# Without TLS (testing only)
.\start_proxy.ps1 -NoTLS
```

**Manual:**
```bash
# Without TLS (development)
uvicorn app:app --host 0.0.0.0 --port 8001 --reload

# With TLS (production)
uvicorn app:app --host 0.0.0.0 --port 8001 \
  --ssl-keyfile certs/proxy.key \
  --ssl-certfile certs/proxy.crt \
  --ssl-ca-certs certs/ca.crt \
  --workers 4
```

### Testing

```bash
# Basic test (no TLS)
python test_client.py --url http://localhost:8001

# With TLS and certificates
python test_client.py \
  --url https://localhost:8001 \
  --cert certs/test_client.crt \
  --key certs/test_client.key \
  --ca certs/ca.crt

# Run full test suite
python test_client.py --test-suite --url http://localhost:8001
```

## API Endpoints

### POST /api/v1/messages

Submit a message for processing.

**Request:**
```json
{
  "sender_number": "+1234567890",
  "message_body": "Your message here",
  "metadata": {
    "timestamp": "2025-10-20T12:34:56Z"
  }
}
```

**Response (202 Accepted):**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "client_id": "client_001",
  "queued_at": "2025-10-20T12:34:56.789Z",
  "position": 5
}
```

**Validation Rules:**
- `sender_number`: E.164 format (`^\+[1-9]\d{1,14}$`)
- `message_body`: 1-1000 characters
- Requires valid client certificate (mutual TLS)

### GET /api/v1/health

Health check endpoint.

**Response (200 OK):**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-10-20T12:34:56.789Z",
  "checks": {
    "redis": "healthy",
    "main_server": "unknown",
    "certificate": "valid"
  }
}
```

### GET /metrics

Prometheus metrics endpoint.

**Metrics Exposed:**
- `proxy_requests_total`: Total requests by method, endpoint, status
- `proxy_request_duration_seconds`: Request latency histogram
- `redis_queue_size`: Current message queue size
- `proxy_messages_enqueued_total`: Total messages enqueued
- `proxy_messages_failed_total`: Failed messages by reason
- `proxy_certificate_validations_total`: Certificate validation results

### GET /docs

Interactive API documentation (Swagger UI).

### GET /redoc

Alternative API documentation (ReDoc).

## Configuration

### Environment Variables

Create `.env` file in proxy directory:

```bash
# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Main Server
MAIN_SERVER_URL=https://localhost:8000

# Certificates
SERVER_CERT_PATH=certs/proxy.crt
SERVER_KEY_PATH=certs/proxy.key
CA_CERT_PATH=certs/ca.crt

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=logs
```

### YAML Configuration

`config.yaml` provides additional settings:

```yaml
server:
  host: "0.0.0.0"
  port: 8001
  workers: 4

redis:
  host: "${REDIS_HOST}"
  port: 6379
  queue_name: "message_queue"

tls:
  enabled: true
  verify_client: true

validation:
  phone_pattern: "^\\+[1-9]\\d{1,14}$"
  max_message_length: 1000

rate_limiting:
  enabled: true
  max_requests: 100
  window_seconds: 60
```

## Architecture

```
Client → [Mutual TLS] → Proxy → [Redis Queue] → Worker → Main Server
                         ↓
                    [Register] → Main Server → MySQL
```

**Flow:**
1. Client sends message with certificate
2. Proxy validates certificate and message
3. Proxy enqueues message to Redis
4. Proxy registers message with main server (async)
5. Proxy returns 202 Accepted
6. Worker processes queue asynchronously

## Logging

Logs are written to `logs/proxy.log` with daily rotation (7-day retention).

**Log Format:**
```
2025-10-20 12:34:56,789 - proxy - INFO - [app.py:123] - Message queued: abc123
```

**Log Levels:**
- `DEBUG`: Detailed diagnostic information
- `INFO`: General informational messages
- `WARNING`: Warning messages
- `ERROR`: Error messages
- `CRITICAL`: Critical errors

## Metrics & Monitoring

### Prometheus Integration

Metrics available at `/metrics`:

```prometheus
# Request metrics
proxy_requests_total{method="POST",endpoint="/api/v1/messages",status="202"} 1234

# Queue metrics
redis_queue_size 42

# Error metrics
proxy_messages_failed_total{reason="validation_error"} 5
```

### Grafana Dashboard

Import the dashboard from `../monitoring/grafana/dashboards/` for:
- Request rate per endpoint
- Response time percentiles
- Queue size over time
- Error rate tracking
- Certificate validation stats

## Security

### Mutual TLS

**Client Authentication:**
1. Client presents certificate during TLS handshake
2. Proxy validates certificate against CA
3. Proxy extracts Common Name (CN) as client_id
4. Proxy checks certificate status (not revoked)

**Certificate Requirements:**
- Signed by Message Broker CA
- Not expired
- Not in CRL (Certificate Revocation List)
- CN matches registered client

### Input Validation

**Phone Number:**
- E.164 international format
- Must start with `+`
- 8-16 characters total
- Pattern: `^\+[1-9]\d{1,14}$`

**Message Body:**
- Minimum: 1 character
- Maximum: 1000 characters
- Must not be empty or whitespace-only

### Rate Limiting

- 100 requests per 60 seconds per client
- Based on client certificate CN
- Returns 429 Too Many Requests when exceeded

## Troubleshooting

### Redis Connection Failed

**Symptoms:** `Failed to connect to Redis` in logs

**Solutions:**
1. Check Redis is running: `redis-cli ping`
2. Verify Redis host/port in `.env`
3. Check Redis password if configured
4. Ensure Redis is accessible from proxy server

### Certificate Validation Failed

**Symptoms:** `401 Unauthorized` or `Invalid client certificate`

**Solutions:**
1. Verify certificate files exist in `certs/`
2. Check certificate not expired: `openssl x509 -in cert.crt -noout -dates`
3. Verify CA certificate matches: `openssl verify -CAfile ca.crt proxy.crt`
4. Check certificate not revoked
5. Ensure certificate CN matches expected client_id

### Message Registration Failed

**Symptoms:** `Failed to register message with main server` in logs

**Solutions:**
1. Check main server is running and accessible
2. Verify `MAIN_SERVER_URL` in `.env`
3. Check proxy certificate for main server access
4. Review main server logs for errors
5. Verify network connectivity

### Queue Size Growing

**Symptoms:** `redis_queue_size` metric continuously increasing

**Solutions:**
1. Check workers are running and processing messages
2. Verify main server is accepting deliveries
3. Check for worker errors in logs
4. Consider scaling up worker count
5. Review Redis memory usage

## Performance

### Capacity

**Single Instance:**
- **Requests**: 1,000+ req/sec
- **Latency**: <100ms (p95)
- **Queue**: Limited by Redis memory
- **Connections**: 100+ concurrent

**Scaling:**
- **Horizontal**: Multiple proxy instances behind load balancer
- **Vertical**: Increase workers (4-16 recommended)
- **Redis**: Cluster mode for high throughput

### Optimization Tips

1. **Use multiple workers**: `--workers 4` (CPU count)
2. **Enable connection pooling**: Redis keepalive enabled
3. **Tune logging**: Reduce to INFO in production
4. **Monitor queue size**: Alert if >1000 messages
5. **Use SSD for logs**: Improves I/O performance

## Development

### Running in Dev Mode

```powershell
# Hot-reload enabled
.\start_proxy.ps1 -Dev

# Or manually
uvicorn app:app --reload --log-level debug
```

### Testing

```python
# Run test suite
python test_client.py --test-suite

# Single message test
python test_client.py --sender "+1234567890" --message "Test"

# Load testing with hey
hey -n 1000 -c 10 -m POST -H "Content-Type: application/json" \
  -d '{"sender_number":"+1234567890","message_body":"Load test"}' \
  http://localhost:8001/api/v1/messages
```

### Code Structure

```
proxy/
├── app.py              # Main FastAPI application
├── config.yaml         # YAML configuration
├── requirements.txt    # Python dependencies
├── start_proxy.bat     # Windows startup (batch)
├── start_proxy.ps1     # Windows startup (PowerShell)
├── test_client.py      # Test client script
├── proxy.service       # Systemd service file (Linux)
├── certs/              # TLS certificates
│   ├── proxy.crt
│   ├── proxy.key
│   └── ca.crt
└── logs/               # Application logs
    └── proxy.log
```

## Production Deployment

### Linux (systemd)

```bash
# Copy service file
sudo cp proxy.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start service
sudo systemctl enable proxy
sudo systemctl start proxy

# Check status
sudo systemctl status proxy

# View logs
sudo journalctl -u proxy -f
```

### Windows (NSSM)

```powershell
# Install NSSM
choco install nssm

# Install service
nssm install MessageBrokerProxy "C:\path\to\venv\Scripts\python.exe" ^
  "C:\path\to\proxy\app.py"

# Start service
nssm start MessageBrokerProxy
```

## Support

- **Documentation**: See `/docs` endpoint when running
- **Logs**: Check `logs/proxy.log`
- **Metrics**: Monitor `/metrics` endpoint
- **Issues**: Create issue in repository

---

**Version**: 1.0.0  
**Last Updated**: October 2025

