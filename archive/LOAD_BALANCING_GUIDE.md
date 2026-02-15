# Load Balancing Guide - Message Broker System

This guide explains how to ensure proper load balancing across all components of the message broker system.

## Overview

The message broker system has three main areas where load balancing is critical:

1. **Worker Load Balancing**: Multiple workers processing messages from Redis queue
2. **Proxy Load Balancing**: Multiple proxy instances handling incoming requests
3. **Queue Distribution**: Ensuring messages are evenly distributed across workers

## Worker Load Balancing

### How It Works

Workers use Redis's `BRPOP` command which is **atomic and automatically distributes** messages across all workers. When multiple workers are running, they compete for messages from the queue, ensuring automatic load balancing.

### Running Multiple Workers

#### Quick Start

```powershell
cd worker
.\start_multiple_workers.ps1 -NumWorkers 3
```

This starts 3 worker processes that automatically share the load.

#### Configuration Options

```powershell
.\start_multiple_workers.ps1 `
    -NumWorkers 3 `          # Number of worker processes
    -Concurrency 4 `         # Concurrent messages per worker
    -RetryInterval 30 `       # Retry interval in seconds
    -MaxAttempts 10000 `     # Max retry attempts
    -BaseMetricsPort 9100 `  # Starting metrics port
    -LogLevel INFO           # Log level
```

#### Environment Variables

Set per-worker configuration via environment variables:

```powershell
$env:WORKER_CONCURRENCY = "4"      # Messages per worker
$env:WORKER_RETRY_INTERVAL = "30"
$env:WORKER_MAX_ATTEMPTS = "10000"
$env:WORKER_ID = "worker-1"        # Unique worker ID
```

### Verifying Worker Load Balance

#### Check Active Workers

```powershell
Get-Process python | Where-Object {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
    $cmd -like "*worker.py*"
}
```

#### Check Worker Metrics

Each worker exposes metrics on its own port (starting at 9100):

```powershell
# Worker 1 metrics
curl http://localhost:9100/metrics

# Worker 2 metrics  
curl http://localhost:9101/metrics

# Worker 3 metrics
curl http://localhost:9102/metrics
```

Look for:
- `worker_messages_processed_total{worker_id="..."}` - Messages processed per worker
- `worker_messages_failed_total{worker_id="..."}` - Failed messages per worker
- `worker_active_tasks{worker_id="..."}` - Currently processing tasks

#### Using Verification Script

```powershell
.\verify_load_balancing.ps1 -CheckWorkers
```

This will:
- Detect all running workers
- Check metrics from each worker
- Show message distribution
- Recommend optimal worker count

### Optimal Worker Count

**Rule of Thumb:**
- **CPU-bound tasks**: Number of CPU cores
- **I/O-bound tasks**: 2-4x number of CPU cores
- **Mixed workload**: Start with 2-3 workers, scale based on queue growth

**For 100,000 messages/day:**
- Average rate: ~1.16 messages/second
- Peak rate: ~10-100 messages/second (bursts)
- **Recommended**: 2-3 workers with 4 concurrency each

## Proxy Load Balancing

### Single Instance with Multiple Workers

The proxy uses uvicorn's `--workers` flag for internal load balancing:

```powershell
cd proxy
.\start_proxy.ps1 -Workers 4
```

This runs 4 worker processes within a single proxy instance.

### Multiple Proxy Instances (Production)

For true horizontal scaling, run multiple proxy instances behind a load balancer:

#### Option 1: Nginx Load Balancer

```nginx
upstream proxy_backend {
    least_conn;  # Use least connections algorithm
    server localhost:8001;
    server localhost:8002;
    server localhost:8003;
}

server {
    listen 443 ssl;
    server_name proxy.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass https://proxy_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Start multiple proxy instances:
```powershell
# Proxy instance 1
$env:PROXY_PORT = "8001"
cd proxy
.\start_proxy.ps1

# Proxy instance 2 (new terminal)
$env:PROXY_PORT = "8002"
cd proxy
.\start_proxy.ps1

# Proxy instance 3 (new terminal)
$env:PROXY_PORT = "8003"
cd proxy
.\start_proxy.ps1
```

#### Option 2: Windows Network Load Balancing (NLB)

For Windows Server environments, use NLB for proxy load balancing.

#### Option 3: Reverse Proxy with SSL Termination

Place a reverse proxy (nginx, HAProxy) in front of proxy instances to:
- Handle SSL/TLS termination
- Distribute load across instances
- Provide health checks and failover

### Proxy Load Balancing Algorithm

**Recommended:** Least Connections
- Distributes requests to proxy with fewest active connections
- Works well for variable processing times

**Alternatives:**
- Round Robin: Simple but doesn't account for load
- IP Hash: Sticky sessions based on client IP
- Weighted: Assign different capacity to instances

## Queue Load Balancing

### How Redis Queue Works

Redis lists (`LPUSH`/`BRPOP`) provide **automatic load distribution**:

1. Proxy enqueues messages with `LPUSH` (adds to left/head)
2. Workers use `BRPOP` (blocking pop from right/tail)
3. First worker to call `BRPOP` gets the message
4. Multiple workers compete fairly for messages

### Verifying Queue Balance

#### Check Queue Size

```powershell
redis-cli LLEN message_queue
```

**Healthy indicators:**
- Queue size < 100: Well balanced
- Queue size 100-1000: Monitor closely
- Queue size > 1000: Need more workers

#### Monitor Queue Growth

```powershell
# Watch queue size in real-time
while ($true) {
    $size = redis-cli LLEN message_queue
    Write-Host "$(Get-Date -Format 'HH:mm:ss'): Queue size = $size"
    Start-Sleep -Seconds 5
}
```

#### Using Verification Script

```powershell
.\verify_load_balancing.ps1 -CheckQueue -SampleDuration 60
```

This samples queue growth over 60 seconds and calculates:
- Queue growth rate
- Processing rate
- Load balance status

### When Queue is Growing

If queue size keeps increasing:

1. **Add more workers:**
   ```powershell
   cd worker
   .\start_multiple_workers.ps1 -NumWorkers 5
   ```

2. **Increase worker concurrency:**
   ```powershell
   $env:WORKER_CONCURRENCY = "8"
   # Restart workers
   ```

3. **Check for bottlenecks:**
   - Main server response time
   - Database connection pool
   - Network latency

## Load Balancing Best Practices

### 1. Start with Baseline

Run with default settings and monitor:
- Queue growth rate
- Worker CPU/memory usage
- Response times

### 2. Scale Based on Metrics

**Scale up when:**
- Queue size > 1000 messages
- Worker CPU > 80%
- Response time p95 > 5 seconds

**Scale down when:**
- Queue size consistently 0
- Worker CPU < 30%
- Excess capacity unused

### 3. Monitor Key Metrics

**Per Worker:**
- `worker_messages_processed_total` - Total processed
- `worker_messages_failed_total` - Total failed
- `worker_active_tasks` - Currently processing
- `worker_retry_attempts` - Retry count

**System-wide:**
- `redis_queue_size` - Current queue size
- `proxy_requests_total` - Total requests
- `proxy_requests_duration_seconds` - Response times

### 4. Health Checks

Ensure load balancers perform health checks:

```powershell
# Health check endpoint
curl https://localhost:8001/api/v1/health

# Metrics endpoint
curl https://localhost:8001/metrics
```

### 5. Graceful Scaling

**Adding Workers:**
1. Start new worker processes
2. They automatically join the queue
3. No service interruption

**Removing Workers:**
1. Stop accepting new tasks (SIGTERM)
2. Wait for current tasks to complete
3. Shut down gracefully

## Troubleshooting Load Balancing

### Problem: Uneven Worker Load

**Symptoms:**
- One worker processing all messages
- Other workers idle

**Solutions:**
- Check worker metrics ports (9100-9109)
- Verify all workers are connected to Redis
- Check for worker errors in logs
- Ensure workers use same queue name

### Problem: Queue Growing Continuously

**Symptoms:**
- Queue size keeps increasing
- Workers can't keep up

**Solutions:**
- Add more workers
- Increase worker concurrency
- Check main server response times
- Verify database connection pool
- Check for network issues

### Problem: Messages Stuck in Queue

**Symptoms:**
- Messages in queue but not processing
- Workers running but idle

**Solutions:**
- Check worker logs for errors
- Verify main server is accessible
- Check certificate validity
- Verify Redis connection

### Problem: Proxy Overload

**Symptoms:**
- High response times
- Connection errors
- 503 Service Unavailable

**Solutions:**
- Add proxy instances
- Increase proxy workers (`--workers 8`)
- Use load balancer to distribute
- Check proxy logs for errors

## Production Recommendations

### Small Deployment (< 10k messages/day)

- **Workers**: 2 workers, 4 concurrency each
- **Proxy**: 1 instance, 4 workers
- **Load Balancer**: Not needed

### Medium Deployment (10k-100k messages/day)

- **Workers**: 3-5 workers, 4-8 concurrency each
- **Proxy**: 2 instances, 4 workers each
- **Load Balancer**: Simple round-robin

### Large Deployment (100k+ messages/day)

- **Workers**: 5-10 workers, 8-16 concurrency each
- **Proxy**: 3+ instances, 8 workers each
- **Load Balancer**: Nginx/HAProxy with least-connections
- **Monitoring**: Prometheus + Grafana
- **Auto-scaling**: Scale workers based on queue size

## Verification Checklist

Run this checklist to verify load balancing:

```powershell
# 1. Check workers
.\verify_load_balancing.ps1 -CheckWorkers

# 2. Check queue
.\verify_load_balancing.ps1 -CheckQueue

# 3. Check proxy
.\verify_load_balancing.ps1 -CheckProxy

# 4. Full check
.\verify_load_balancing.ps1 -All -SampleDuration 60
```

**Expected Results:**
- ✅ Multiple workers running
- ✅ Workers processing messages evenly
- ✅ Queue size stable or decreasing
- ✅ No single worker overloaded
- ✅ Proxy response times < 1 second

## Summary

Load balancing in the message broker is achieved through:

1. **Worker level**: Redis BRPOP automatically distributes messages
2. **Proxy level**: Multiple instances + load balancer
3. **Queue level**: Redis list provides fair distribution

The system is designed for horizontal scaling - simply add more workers or proxy instances as needed!
