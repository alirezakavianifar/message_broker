# Simple System Test Script
# Tests the message broker system comprehensively

param(
    [switch]$Quick,
    [switch]$SkipServices
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MESSAGE BROKER SYSTEM TEST" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$ProjectRoot = $PSScriptRoot
$TestsDir = Join-Path $ProjectRoot "tests"

# Track results
$passed = 0
$failed = 0
$issues = @()

# Function to test a service
function Test-Service {
    param([string]$Name, [int]$Port, [string]$HealthUrl)
    
    Write-Host "Testing $Name..." -NoNewline
    
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($connection) {
            try {
                $response = Invoke-WebRequest -Uri $HealthUrl -SkipCertificateCheck -TimeoutSec 3 -ErrorAction Stop
                Write-Host " OK" -ForegroundColor Green
                $script:passed++
                return $true
            } catch {
                Write-Host " RUNNING BUT NOT RESPONDING" -ForegroundColor Yellow
                $script:issues += "$Name is running but health check failed"
                return $false
            }
        } else {
            Write-Host " NOT RUNNING" -ForegroundColor Red
            $script:failed++
            $script:issues += "$Name is not running on port $Port"
            return $false
        }
    } catch {
        Write-Host " ERROR" -ForegroundColor Red
        $script:failed++
        $script:issues += "Error checking $Name : $_"
        return $false
    }
}

# Test prerequisites
Write-Host "`n--- Prerequisites ---" -ForegroundColor Yellow

# Check Python
Write-Host "Checking Python..." -NoNewline
$pythonPath = Join-Path $ProjectRoot "venv\Scripts\python.exe"
if (Test-Path $pythonPath) {
    Write-Host " OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host " NOT FOUND" -ForegroundColor Red
    $failed++
    $issues += "Python not found in venv"
}

# Check MySQL
Write-Host "Checking MySQL..." -NoNewline
try {
    $mysqlService = Get-Service | Where-Object { $_.Name -like "*mysql*" -and $_.Status -eq "Running" }
    if ($mysqlService) {
        Write-Host " OK" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " NOT RUNNING" -ForegroundColor Yellow
        $issues += "MySQL service may not be running"
    }
} catch {
    Write-Host " ERROR" -ForegroundColor Yellow
    $issues += "Could not check MySQL status"
}

# Check Redis
Write-Host "Checking Redis..." -NoNewline
try {
    $redisCheck = redis-cli ping 2>&1
    if ($redisCheck -match "PONG") {
        Write-Host " OK" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " NOT RESPONDING" -ForegroundColor Red
        $failed++
        $issues += "Redis is not responding"
    }
} catch {
    Write-Host " NOT FOUND" -ForegroundColor Red
    $failed++
    $issues += "Redis-cli not found or Redis not running"
}

# Check Certificates
Write-Host "Checking Certificates..." -NoNewline
$caCert = Join-Path $ProjectRoot "main_server\certs\ca.crt"
$serverCert = Join-Path $ProjectRoot "main_server\certs\server.crt"
if ((Test-Path $caCert) -and (Test-Path $serverCert)) {
    Write-Host " OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host " MISSING" -ForegroundColor Red
    $failed++
    $issues += "Certificates not found"
}

# Test services
Write-Host "`n--- Service Health Checks ---" -ForegroundColor Yellow

$serviceHealthy = $true

Test-Service -Name "Main Server" -Port 8000 -HealthUrl "https://localhost:8000/health" | Out-Null
Test-Service -Name "Proxy Server" -Port 8001 -HealthUrl "https://localhost:8001/api/v1/health" | Out-Null
Test-Service -Name "Web Portal" -Port 5000 -HealthUrl "http://localhost:5000" | Out-Null

# Run Python tests if services are available
Write-Host "`n--- Running Test Suites ---" -ForegroundColor Yellow

if ($serviceHealthy) {
    # Preflight check
    Write-Host "Running preflight checks..." -NoNewline
    Set-Location $TestsDir
    try {
        & "$pythonPath" preflight_check.py 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host " PASSED" -ForegroundColor Green
            $passed++
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $failed++
        }
    } catch {
        Write-Host " ERROR" -ForegroundColor Red
        $failed++
        $issues += "Preflight check error: $_"
    }
    Set-Location $ProjectRoot
    
    # Basic functional test
    Write-Host "Running basic functional test..." -NoNewline
    try {
        & "$pythonPath" "$ProjectRoot\test_message_broker.py" --direct 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host " PASSED" -ForegroundColor Green
            $passed++
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $failed++
        }
    } catch {
        Write-Host " ERROR" -ForegroundColor Red
        $failed++
    }
    
    if (-not $Quick) {
        # Integration test
        Write-Host "Running integration tests..." -NoNewline
        Set-Location $TestsDir
        try {
            & "$pythonPath" integration_test.py 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host " PASSED" -ForegroundColor Green
                $passed++
            } else {
                Write-Host " FAILED" -ForegroundColor Red
                $failed++
            }
        } catch {
            Write-Host " ERROR" -ForegroundColor Red
            $failed++
        }
        Set-Location $ProjectRoot
    }
} else {
    Write-Host "Skipping Python tests - services not healthy" -ForegroundColor Yellow
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Tests Passed: $passed" -ForegroundColor Green
Write-Host "Tests Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Gray" })

if ($issues.Count -gt 0) {
    Write-Host "`nIssues Found:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
}

Write-Host "`n========================================`n" -ForegroundColor Cyan

if ($failed -eq 0 -and $passed -gt 0) {
    Write-Host "SUCCESS: All critical tests passed!" -ForegroundColor Green
    Write-Host "`nThe message broker system is ready for delivery.`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAILURE: Some tests failed. Please review and fix issues.`n" -ForegroundColor Red
    exit 1
}
