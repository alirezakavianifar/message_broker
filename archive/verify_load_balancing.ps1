# Load Balancing Verification Script
# Verifies that load is properly balanced across workers and components

param(
    [switch]$CheckWorkers,
    [switch]$CheckProxy,
    [switch]$CheckQueue,
    [switch]$All,
    [int]$SampleDuration = 30
)

$ErrorActionPreference = "Continue"

if ($All) {
    $CheckWorkers = $true
    $CheckProxy = $true
    $CheckQueue = $true
}

if (-not ($CheckWorkers -or $CheckProxy -or $CheckQueue)) {
    $CheckWorkers = $true
    $CheckProxy = $true
    $CheckQueue = $true
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  LOAD BALANCING VERIFICATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$results = @{
    workers = @{}
    proxy = @{}
    queue = @{}
}

# ============================================================================
# Check Worker Load Distribution
# ============================================================================

if ($CheckWorkers) {
    Write-Host "--- Worker Load Distribution ---" -ForegroundColor Yellow
    
    # Check if workers are running
    $workerProcesses = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
        $cmdLine -like "*worker.py*" -or $cmdLine -like "*worker\worker*"
    }
    
    if ($workerProcesses.Count -eq 0) {
        Write-Host "[WARN] No worker processes found" -ForegroundColor Yellow
        Write-Host "       Start workers with: cd worker ; .\start_multiple_workers.ps1" -ForegroundColor Gray
    } else {
        Write-Host "[OK] Found $($workerProcesses.Count) worker process(es)" -ForegroundColor Green
        
        # Try to get metrics from each worker
        $basePort = 9100
        $activeWorkers = 0
        
        for ($i = 0; $i -lt 10; $i++) {
            $metricsPort = $basePort + $i
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:$metricsPort/metrics" -TimeoutSec 2 -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    $metrics = $response.Content
                    $activeWorkers++
                    
                    # Extract metrics
                    if ($metrics -match 'worker_messages_processed_total\{worker_id="([^"]+)"\} (\d+)') {
                        $workerId = $matches[1]
                        $processed = [int]$matches[2]
                        $results.workers[$workerId] = $processed
                        Write-Host "  Worker $workerId : $processed messages processed" -ForegroundColor Cyan
                    }
                }
            } catch {
                # Worker not listening on this port
            }
        }
        
        if ($activeWorkers -eq 0) {
            Write-Host "[WARN] No workers responding on metrics ports (9100-9109)" -ForegroundColor Yellow
            Write-Host "       Workers may not have metrics enabled" -ForegroundColor Gray
        } else {
            Write-Host "[OK] $activeWorkers worker(s) reporting metrics" -ForegroundColor Green
        }
    }
    Write-Host ""
}

# ============================================================================
# Check Proxy Load Distribution
# ============================================================================

if ($CheckProxy) {
    Write-Host "--- Proxy Load Distribution ---" -ForegroundColor Yellow
    
    try {
        # Use System.Net.HttpWebRequest to bypass SSL verification for testing
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $proxyMetrics = Invoke-WebRequest -Uri "https://localhost:8001/metrics" -TimeoutSec 5 -ErrorAction Stop
        
        if ($proxyMetrics.StatusCode -eq 200) {
            $metrics = $proxyMetrics.Content
            
            # Extract request metrics
            if ($metrics -match 'http_requests_total\{method="POST",endpoint="/api/v1/messages",status="(\d+)"\} (\d+)') {
                $status = $matches[1]
                $count = [int]$matches[2]
                Write-Host "  POST /api/v1/messages (status $status): $count requests" -ForegroundColor Cyan
            }
            
            # Check queue size
            if ($metrics -match 'redis_queue_size (\d+)') {
                $queueSize = [int]$matches[1]
                $results.queue.current = $queueSize
                Write-Host "  Redis queue size: $queueSize messages" -ForegroundColor Cyan
                
                if ($queueSize -gt 1000) {
                    Write-Host "  [WARN] Queue size is high - workers may be overloaded" -ForegroundColor Yellow
                } elseif ($queueSize -eq 0) {
                    Write-Host "  [OK] Queue is empty - load balanced well" -ForegroundColor Green
                } else {
                    Write-Host "  [OK] Queue size is manageable" -ForegroundColor Green
                }
            }
            
            Write-Host "[OK] Proxy metrics accessible" -ForegroundColor Green
        }
    } catch {
        Write-Host "[WARN] Could not access proxy metrics: $_" -ForegroundColor Yellow
        Write-Host "       Proxy may not be running" -ForegroundColor Gray
    }
    Write-Host ""
}

# ============================================================================
# Check Queue Distribution
# ============================================================================

if ($CheckQueue) {
    Write-Host "--- Queue Load Analysis ---" -ForegroundColor Yellow
    
    try {
        $redisCheck = redis-cli ping 2>&1
        if ($redisCheck -match "PONG") {
            Write-Host "[OK] Redis is accessible" -ForegroundColor Green
            
            # Get queue length
            $queueLength = redis-cli LLEN message_queue 2>&1
            
            if ($queueLength -match "^\d+$") {
                $queueSize = [int]$queueLength
                Write-Host "  Queue length: $queueSize messages" -ForegroundColor Cyan
                
                if ($queueSize -eq 0) {
                    Write-Host "  [OK] Queue is empty - all messages processed" -ForegroundColor Green
                } elseif ($queueSize -lt 100) {
                    Write-Host "  [OK] Queue size is low - load balanced well" -ForegroundColor Green
                } elseif ($queueSize -lt 1000) {
                    Write-Host "  [WARN] Queue is growing - consider adding workers" -ForegroundColor Yellow
                } else {
                    Write-Host "  [ERROR] Queue is very large - workers may be overloaded" -ForegroundColor Red
                }
                
                # Sample queue growth over time
                Write-Host "`n  Sampling queue growth over $SampleDuration seconds..." -ForegroundColor Cyan
                $startSize = $queueSize
                $samples = @($queueSize)
                
                for ($i = 1; $i -le $SampleDuration; $i++) {
                    Start-Sleep -Seconds 1
                    $currentSize = [int](redis-cli LLEN message_queue 2>&1)
                    if ($currentSize -match "^\d+$") {
                        $samples += [int]$currentSize
                    }
                    
                    if ($i % 10 -eq 0) {
                        Write-Host "    After $i seconds: $currentSize messages" -ForegroundColor Gray
                    }
                }
                
                $endSize = $samples[-1]
                $change = $endSize - $startSize
                
                Write-Host "`n  Queue Analysis:" -ForegroundColor Cyan
                Write-Host "    Start size: $startSize messages" -ForegroundColor White
                Write-Host "    End size: $endSize messages" -ForegroundColor White
                Write-Host "    Change: $change messages" -ForegroundColor $(if ($change -gt 0) { "Yellow" } elseif ($change -lt 0) { "Green" } else { "White" })
                
                if ($change -gt 0) {
                    $growthRate = $change / $SampleDuration
                    Write-Host "    Growth rate: $growthRate messages/second" -ForegroundColor Yellow
                    Write-Host "    [WARN] Queue is growing - workers cannot keep up" -ForegroundColor Yellow
                } elseif ($change -lt 0) {
                    $processingRate = [math]::Abs($change) / $SampleDuration
                    Write-Host "    Processing rate: $processingRate messages/second" -ForegroundColor Green
                    Write-Host "    [OK] Workers are processing messages faster than they arrive" -ForegroundColor Green
                } else {
                    Write-Host "    [OK] Queue is stable - load balanced" -ForegroundColor Green
                }
            } else {
                Write-Host "[WARN] Could not read queue length" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[WARN] Redis is not responding" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[ERROR] Could not check Redis: $_" -ForegroundColor Red
    }
    Write-Host ""
}

# ============================================================================
# Load Balancing Recommendations
# ============================================================================

Write-Host "--- Load Balancing Recommendations ---" -ForegroundColor Yellow

$recommendations = @()

# Check worker count
$workerCount = ($results.workers.Keys | Measure-Object).Count
if ($workerCount -eq 0) {
    $recommendations += "Start at least 2-3 worker processes for load balancing"
} elseif ($workerCount -eq 1) {
    $recommendations += "Consider running multiple workers: cd worker ; .\start_multiple_workers.ps1 -NumWorkers 3"
} else {
    Write-Host "[OK] Multiple workers running ($workerCount workers)" -ForegroundColor Green
}

# Check worker message distribution
if ($results.workers.Count -gt 1) {
    $processed = $results.workers.Values | ForEach-Object { [int]$_ }
    $min = ($processed | Measure-Object -Minimum).Minimum
    $max = ($processed | Measure-Object -Maximum).Maximum
    
    if ($max -gt 0) {
        $balance = (1 - ($max - $min) / $max) * 100
        Write-Host "  Worker load balance: $([math]::Round($balance, 1))% balanced" -ForegroundColor $(if ($balance -gt 80) { "Green" } elseif ($balance -gt 60) { "Yellow" } else { "Red" })
        
        if ($balance -lt 80) {
            $recommendations += "Worker load is not well balanced - check for bottlenecks"
        }
    }
}

# Check queue
if ($results.queue.current -gt 1000) {
    $recommendations += "Queue size is high - add more workers or increase worker concurrency"
}

if ($recommendations.Count -gt 0) {
    Write-Host "`nRecommendations:" -ForegroundColor Yellow
    foreach ($rec in $recommendations) {
        Write-Host "  • $rec" -ForegroundColor White
    }
} else {
    Write-Host "[OK] Load balancing appears optimal" -ForegroundColor Green
}

# ============================================================================
# Summary
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  VERIFICATION COMPLETE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "For production load balancing:" -ForegroundColor Yellow
Write-Host "1. Run multiple workers: cd worker ; .\start_multiple_workers.ps1 -NumWorkers 3" -ForegroundColor White
Write-Host "2. Use multiple proxy instances behind a load balancer (e.g., nginx)" -ForegroundColor White
Write-Host "3. Monitor queue size: redis-cli LLEN message_queue" -ForegroundColor White
Write-Host "4. Check worker metrics: curl http://localhost:9100/metrics" -ForegroundColor White
Write-Host "5. Scale workers based on queue growth rate`n" -ForegroundColor White
