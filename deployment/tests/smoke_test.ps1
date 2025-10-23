#!/usr/bin/env pwsh
# Message Broker System - Smoke Test
# Verifies all components are running and accessible

param(
    [string]$MainServerUrl = "https://localhost:8000",
    [string]$ProxyUrl = "https://localhost:8001",
    [string]$PortalUrl = "https://localhost:5000",
    [string]$WorkerMetricsUrl = "http://localhost:9100",
    [switch]$SkipCertValidation = $true
)

$ErrorActionPreference = "Continue"

if ($SkipCertValidation) {
    # Disable SSL certificate validation for self-signed certs
    add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Message Broker System - Smoke Test" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

$results = @{
    services = @{}
    endpoints = @{}
    database = @{}
    redis = @{}
    passed = 0
    failed = 0
}

# Test 1: Check Windows Services
Write-Host "[1/9] Checking Windows Services..." -ForegroundColor Cyan

$services = @(
    "MySQL",
    "Memurai",
    "MessageBrokerMainServer",
    "MessageBrokerProxy",
    "MessageBrokerWorker",
    "MessageBrokerPortal"
)

foreach ($serviceName in $services) {
    try {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Host "  OK $serviceName is running" -ForegroundColor Green
            $results.services[$serviceName] = "Running"
            $results.passed++
        } else {
            Write-Host "  FAIL $serviceName is not running" -ForegroundColor Red
            $results.services[$serviceName] = "Stopped"
            $results.failed++
        }
    } catch {
        Write-Host "  FAIL $serviceName not found" -ForegroundColor Red
        $results.services[$serviceName] = "NotFound"
        $results.failed++
    }
}

# Test 2: Check MySQL Connectivity
Write-Host "`n[2/9] Testing MySQL connectivity..." -ForegroundColor Cyan
try {
    $testQuery = "SELECT 1 FROM dual"
    $result = mysql -u systemuser -pStrongPass123! message_system -e $testQuery 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK MySQL connection successful" -ForegroundColor Green
        $results.database.Connection = "Success"
        $results.passed++
    } else {
        Write-Host "  FAIL MySQL connection failed" -ForegroundColor Red
        $results.database.Connection = "Failed"
        $results.failed++
    }
    
    # Check table count
    $tables = mysql -u systemuser -pStrongPass123! message_system -e "SHOW TABLES" 2>&1 | Measure-Object -Line
    Write-Host "    Database tables: $($tables.Lines - 1)" -ForegroundColor Gray
    $results.database.Tables = $tables.Lines - 1
} catch {
    Write-Host "  FAIL MySQL test error: $_" -ForegroundColor Red
    $results.database.Connection = "Error"
    $results.failed++
}

# Test 3: Check Redis Connectivity
Write-Host "`n[3/9] Testing Redis connectivity..." -ForegroundColor Cyan
try {
    $pingResult = memurai-cli ping 2>&1
    
    if ($pingResult -match "PONG") {
        Write-Host "  OK Redis connection successful" -ForegroundColor Green
        $results.redis.Connection = "Success"
        $results.passed++
        
        # Check queue size
        $queueSize = memurai-cli LLEN message_queue 2>&1
        Write-Host "    Queue size: $queueSize messages" -ForegroundColor Gray
        $results.redis.QueueSize = $queueSize
    } else {
        Write-Host "  FAIL Redis connection failed" -ForegroundColor Red
        $results.redis.Connection = "Failed"
        $results.failed++
    }
} catch {
    Write-Host "  FAIL Redis test error: $_" -ForegroundColor Red
    $results.redis.Connection = "Error"
    $results.failed++
}

# Test 4: Check Main Server Health
Write-Host "`n[4/9] Testing Main Server health endpoint..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$MainServerUrl/health" -Method Get -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop
    
    if ($response.StatusCode -eq 200) {
        Write-Host "  OK Main Server health check passed" -ForegroundColor Green
        $results.endpoints.MainServer = "Healthy"
        $results.passed++
    } else {
        Write-Host "  FAIL Main Server returned status $($response.StatusCode)" -ForegroundColor Red
        $results.endpoints.MainServer = "Unhealthy"
        $results.failed++
    }
} catch {
    Write-Host "  FAIL Main Server health check failed: $($_.Exception.Message)" -ForegroundColor Red
    $results.endpoints.MainServer = "Unreachable"
    $results.failed++
}

# Test 5: Check Proxy Health
Write-Host "`n[5/9] Testing Proxy health endpoint..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$ProxyUrl/api/v1/health" -Method Get -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop
    
    if ($response.StatusCode -eq 200) {
        Write-Host "  OK Proxy health check passed" -ForegroundColor Green
        $results.endpoints.Proxy = "Healthy"
        $results.passed++
    } else {
        Write-Host "  FAIL Proxy returned status $($response.StatusCode)" -ForegroundColor Red
        $results.endpoints.Proxy = "Unhealthy"
        $results.failed++
    }
} catch {
    Write-Host "  FAIL Proxy health check failed: $($_.Exception.Message)" -ForegroundColor Red
    $results.endpoints.Proxy = "Unreachable"
    $results.failed++
}

# Test 6: Check Portal Health
Write-Host "`n[6/9] Testing Portal health endpoint..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$PortalUrl/health" -Method Get -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop
    
    if ($response.StatusCode -eq 200) {
        Write-Host "  OK Portal health check passed" -ForegroundColor Green
        $results.endpoints.Portal = "Healthy"
        $results.passed++
    } else {
        Write-Host "  FAIL Portal returned status $($response.StatusCode)" -ForegroundColor Red
        $results.endpoints.Portal = "Unhealthy"
        $results.failed++
    }
} catch {
    Write-Host "  FAIL Portal health check failed: $($_.Exception.Message)" -ForegroundColor Red
    $results.endpoints.Portal = "Unreachable"
    $results.failed++
}

# Test 7: Check Worker Metrics
Write-Host "`n[7/9] Testing Worker metrics endpoint..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$WorkerMetricsUrl/metrics" -Method Get -TimeoutSec 5 -ErrorAction Stop
    
    if ($response.StatusCode -eq 200) {
        Write-Host "  OK Worker metrics accessible" -ForegroundColor Green
        $results.endpoints.WorkerMetrics = "Accessible"
        $results.passed++
    } else {
        Write-Host "  FAIL Worker metrics returned status $($response.StatusCode)" -ForegroundColor Red
        $results.endpoints.WorkerMetrics = "Inaccessible"
        $results.failed++
    }
} catch {
    Write-Host "  WARN Worker metrics not accessible: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    (Worker may be running without metrics endpoint)" -ForegroundColor Gray
    $results.endpoints.WorkerMetrics = "Unavailable"
}

# Test 8: Check Certificate Files
Write-Host "`n[8/9] Checking certificate files..." -ForegroundColor Cyan
$certPaths = @(
    "C:\MessageBroker\main_server\certs\ca.crt",
    "C:\MessageBroker\main_server\certs\server.crt",
    "C:\MessageBroker\main_server\certs\server.key",
    "C:\MessageBroker\proxy\certs\proxy.crt",
    "C:\MessageBroker\proxy\certs\proxy.key",
    "C:\MessageBroker\worker\certs\worker.crt",
    "C:\MessageBroker\worker\certs\worker.key"
)

$certsFound = 0
$certsMissing = 0

foreach ($certPath in $certPaths) {
    if (Test-Path $certPath) {
        $certsFound++
    } else {
        $certsMissing++
        Write-Host "  WARN Certificate missing: $certPath" -ForegroundColor Yellow
    }
}

if ($certsMissing -eq 0) {
    Write-Host "  OK All $certsFound certificates found" -ForegroundColor Green
    $results.passed++
} else {
    Write-Host "  WARN $certsMissing certificate(s) missing" -ForegroundColor Yellow
    $results.failed++
}

# Test 9: Check Log Files
Write-Host "`n[9/9] Checking log files..." -ForegroundColor Cyan
$logDir = "C:\MessageBroker\logs"

if (Test-Path $logDir) {
    $logFiles = Get-ChildItem $logDir -File
    Write-Host "  OK Log directory exists ($($logFiles.Count) files)" -ForegroundColor Green
    $results.passed++
} else {
    Write-Host "  WARN Log directory not found" -ForegroundColor Yellow
    $results.failed++
}

# Summary
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Smoke Test Summary" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

Write-Host "Results:" -ForegroundColor Yellow
Write-Host "  Passed: $($results.passed)" -ForegroundColor Green
Write-Host "  Failed: $($results.failed)" -ForegroundColor $(if ($results.failed -gt 0) { "Red" } else { "Gray" })
Write-Host ""

if ($results.failed -eq 0) {
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "ALL TESTS PASSED - System is operational" -ForegroundColor Green
    Write-Host "================================================================`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "SOME TESTS FAILED - Check logs and service status" -ForegroundColor Red
    Write-Host "================================================================`n" -ForegroundColor Red
    
    Write-Host "Troubleshooting commands:" -ForegroundColor Yellow
    Write-Host "  Get-Service MessageBroker*" -ForegroundColor White
    Write-Host "  Get-EventLog -LogName Application -Source 'Message Broker*' -Newest 10" -ForegroundColor White
    Write-Host "  Get-Content C:\MessageBroker\logs\*.log -Tail 50" -ForegroundColor White
    Write-Host ""
    
    exit 1
}

