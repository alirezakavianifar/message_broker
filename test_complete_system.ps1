# Complete System Test for Message Broker
# This script performs a comprehensive test of the entire message broker system
# It checks prerequisites, starts services, runs all tests, and generates a report

param(
    [switch]$SkipServices,  # Skip service startup (assume services already running)
    [switch]$SkipLoad,       # Skip load tests
    [switch]$SkipSecurity,   # Skip security tests
    [switch]$Quick,          # Quick test (skip load and security)
    [switch]$KeepServices    # Don't stop services after testing
)

$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$TestsDir = Join-Path $ProjectRoot "tests"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$testReportFile = Join-Path $TestsDir "logs\test_report_$timestamp.html"

# Colors
function Write-Header { param($text) Write-Host "`n$('='*80)" -ForegroundColor Cyan; Write-Host $text -ForegroundColor Cyan; Write-Host "$('='*80)`n" -ForegroundColor Cyan }
function Write-Section { param($text) Write-Host "`n--- $text ---" -ForegroundColor Yellow }
function Write-Success { param($text) Write-Host "[✓] $text" -ForegroundColor Green }
function Write-Error { param($text) Write-Host "[✗] $text" -ForegroundColor Red }
function Write-Info { param($text) Write-Host "[i] $text" -ForegroundColor Cyan }
function Write-Warn { param($text) Write-Host "[!] $text" -ForegroundColor Yellow }

# Test results
$testResults = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    preflight = @{ passed = 0; failed = 0; total = 0 }
    services = @{ started = 0; alreadyRunning = 0; failed = 0 }
    functional = @{ passed = 0; failed = 0; skipped = 0 }
    integration = @{ passed = 0; failed = 0; skipped = 0 }
    load = @{ passed = 0; failed = 0; skipped = 0 }
    security = @{ passed = 0; failed = 0; skipped = 0 }
    overall = "UNKNOWN"
    duration = 0
    issues = @()
}

$startTime = Get-Date

Write-Header "MESSAGE BROKER SYSTEM - COMPLETE TEST SUITE"
Write-Info "Starting comprehensive system test at $($testResults.timestamp)"
Write-Info "Test Report will be saved to: $testReportFile`n"

# ============================================================================
# STEP 1: PREREQUISITE CHECKS
# ============================================================================

Write-Header "STEP 1: PREREQUISITE CHECKS"

function Test-Prerequisite {
    param([string]$Name, [scriptblock]$Test)
    $testResults.preflight.total++
    Write-Host "Checking $Name..." -NoNewline
    try {
        $result = & $Test
        if ($result) {
            Write-Host " OK" -ForegroundColor Green
            $testResults.preflight.passed++
            return $true
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $testResults.preflight.failed++
            $testResults.issues += "Prerequisite check failed: $Name"
            return $false
        }
    } catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
        $testResults.preflight.failed++
        $testResults.issues += "Prerequisite check error: $Name - $_"
        return $false
    }
}

# Check Python
Test-Prerequisite "Python" {
    $pythonPath = Join-Path $ProjectRoot "venv\Scripts\python.exe"
    if (Test-Path $pythonPath) {
        $version = & $pythonPath --version 2>&1
        return $true
    }
    return $false
} | Out-Null

# Check MySQL
Test-Prerequisite "MySQL" {
    try {
        $mysqlService = Get-Service | Where-Object { $_.Name -like "*mysql*" -and $_.Status -eq "Running" }
        return $null -ne $mysqlService
    } catch {
        return $false
    }
} | Out-Null

# Check Redis
Test-Prerequisite "Redis" {
    try {
        $redisCheck = redis-cli ping 2>&1
        if ($null -eq $redisCheck) { return $false }
        return $redisCheck -match "PONG"
    } catch {
        return $false
    }
} | Out-Null

# Check Certificates
Test-Prerequisite "Certificates" {
    $caCert = Join-Path $ProjectRoot "main_server\certs\ca.crt"
    $serverCert = Join-Path $ProjectRoot "main_server\certs\server.crt"
    return (Test-Path $caCert) -and (Test-Path $serverCert)
} | Out-Null

# Check Encryption Key
Test-Prerequisite "Encryption Key" {
    $keyPath = Join-Path $ProjectRoot "main_server\secrets\encryption.key"
    return Test-Path $keyPath
} | Out-Null

Write-Info "Preflight: $($testResults.preflight.passed)/$($testResults.preflight.total) checks passed"

if ($testResults.preflight.failed -gt 0) {
    Write-Error "Some prerequisites are missing. Please fix them before continuing."
    Write-Info "Run: cd tests ; python preflight_check.py"
    exit 1
}

# ============================================================================
# STEP 2: SERVICE MANAGEMENT
# ============================================================================

Write-Header "STEP 2: SERVICE MANAGEMENT"

function Test-ServiceRunning {
    param([int]$Port)
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        return $null -ne $connection
    } catch {
        return $false
    }
}

function Test-HealthEndpoint {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -SkipCertificateCheck -TimeoutSec 3 -ErrorAction SilentlyContinue
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

$servicesToCheck = @(
    @{ Name = "Main Server"; Port = 8000; HealthUrl = "https://localhost:8000/health" }
    @{ Name = "Proxy Server"; Port = 8001; HealthUrl = "https://localhost:8001/api/v1/health" }
    @{ Name = "Web Portal"; Port = 5000; HealthUrl = "http://localhost:5000" }
)

$servicesRunning = 0
$servicesNeeded = @()

foreach ($service in $servicesToCheck) {
    $isRunning = Test-ServiceRunning -Port $service.Port
    $isHealthy = $false
    
    if ($isRunning) {
        $isHealthy = Test-HealthEndpoint -Url $service.HealthUrl
        if ($isHealthy) {
            Write-Success "$($service.Name) is running and healthy"
            $servicesRunning++
            $testResults.services.alreadyRunning++
        } else {
            Write-Warn "$($service.Name) is running but not responding"
            $servicesNeeded += $service
        }
    } else {
        Write-Warn "$($service.Name) is not running"
        $servicesNeeded += $service
    }
}

# Start services if needed
if (-not $SkipServices -and $servicesNeeded.Count -gt 0) {
    Write-Section "Starting Required Services"
    
    if ($servicesRunning -eq 0) {
        Write-Info "No services running. Starting all services..."
        & "$ProjectRoot\start_all_services.ps1" -Silent
        
        Write-Info "Waiting for services to start..."
        Start-Sleep -Seconds 10
        
        # Verify services started
        foreach ($service in $servicesToCheck) {
            $maxAttempts = 12
            $attempt = 0
            $healthy = $false
            
            while ($attempt -lt $maxAttempts -and -not $healthy) {
                $attempt++
                $healthy = Test-HealthEndpoint -Url $service.HealthUrl
                if (-not $healthy) {
                    Write-Info "  Waiting for $($service.Name)... (attempt $attempt/$maxAttempts)"
                    Start-Sleep -Seconds 5
                }
            }
            
            if ($healthy) {
                Write-Success "$($service.Name) is now healthy"
                $testResults.services.started++
            } else {
                Write-Error "$($service.Name) failed to start"
                $testResults.services.failed++
                $testResults.issues += "Service failed to start: $($service.Name)"
            }
        }
    } else {
        Write-Info "Some services are already running. Starting only required services..."
        # Could implement selective startup here if needed
    }
} elseif ($SkipServices) {
    Write-Info "Skipping service startup (assuming services are running)"
}

# Final service check
Write-Section "Final Service Health Check"
$allServicesHealthy = $true

foreach ($service in $servicesToCheck) {
    $healthy = Test-HealthEndpoint -Url $service.HealthUrl
    if ($healthy) {
        Write-Success "$($service.Name): Healthy"
    } else {
        Write-Error "$($service.Name): Not responding"
        $allServicesHealthy = $false
        $testResults.issues += "Service not healthy: $($service.Name)"
    }
}

if (-not $allServicesHealthy) {
    Write-Error "Not all services are healthy. Some tests may fail."
}

# ============================================================================
# STEP 3: RUN PREFLIGHT TEST SUITE
# ============================================================================

Write-Header "STEP 3: PREFLIGHT TEST SUITE"

Set-Location $TestsDir
try {
    Write-Info "Running preflight checks..."
    & "$ProjectRoot\venv\Scripts\python.exe" preflight_check.py
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Preflight checks passed"
        $testResults.functional.passed++
    } else {
        Write-Error "Preflight checks failed"
        $testResults.functional.failed++
    }
} catch {
    Write-Error "Preflight test error: $_"
    $testResults.functional.failed++
}

Set-Location $ProjectRoot

# ============================================================================
# STEP 4: FUNCTIONAL TESTS
# ============================================================================

Write-Header "STEP 4: FUNCTIONAL TESTS"

Set-Location $TestsDir
try {
    Write-Info "Running basic message broker test..."
    & "$ProjectRoot\venv\Scripts\python.exe" "$ProjectRoot\test_message_broker.py" --direct
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Basic functional test passed"
        $testResults.functional.passed++
    } else {
        Write-Error "Basic functional test failed"
        $testResults.functional.failed++
    }
} catch {
    Write-Error "Functional test error: $_"
    $testResults.functional.failed++
}

Set-Location $ProjectRoot

# ============================================================================
# STEP 5: INTEGRATION TESTS
# ============================================================================

Write-Header "STEP 5: INTEGRATION TESTS"

Set-Location $TestsDir
try {
    Write-Info "Running integration tests..."
    & "$ProjectRoot\venv\Scripts\python.exe" integration_test.py
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Integration tests passed"
        $testResults.integration.passed++
    } else {
        Write-Error "Integration tests failed"
        $testResults.integration.failed++
    }
} catch {
    Write-Error "Integration test error: $_"
    $testResults.integration.failed++
}

Set-Location $ProjectRoot

# ============================================================================
# STEP 6: LOAD TESTS (Optional)
# ============================================================================

if (-not $SkipLoad -and -not $Quick) {
    Write-Header "STEP 6: LOAD TESTS"
    
    Set-Location $TestsDir
    try {
        Write-Info "Running load tests (this may take several minutes)..."
        & "$ProjectRoot\venv\Scripts\python.exe" load_test.py
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Load tests passed"
            $testResults.load.passed++
        } else {
            Write-Error "Load tests failed"
            $testResults.load.failed++
        }
    } catch {
        Write-Error "Load test error: $_"
        $testResults.load.failed++
    }
    
    Set-Location $ProjectRoot
} else {
    Write-Info "Load tests skipped"
    $testResults.load.skipped++
}

# ============================================================================
# STEP 7: SECURITY TESTS (Optional)
# ============================================================================

if (-not $SkipSecurity -and -not $Quick) {
    Write-Header "STEP 7: SECURITY TESTS"
    
    Set-Location $TestsDir
    try {
        Write-Info "Running security tests..."
        & "$ProjectRoot\venv\Scripts\python.exe" security_test.py
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Security tests passed"
            $testResults.security.passed++
        } else {
            Write-Error "Security tests failed"
            $testResults.security.failed++
        }
    } catch {
        Write-Error "Security test error: $_"
        $testResults.security.failed++
    }
    
    Set-Location $ProjectRoot
} else {
    Write-Info "Security tests skipped"
    $testResults.security.skipped++
}

# ============================================================================
# STEP 8: GENERATE REPORT
# ============================================================================

$endTime = Get-Date
$testResults.duration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)

$totalPassed = $testResults.functional.passed + $testResults.integration.passed + $testResults.load.passed + $testResults.security.passed
$totalFailed = $testResults.functional.failed + $testResults.integration.failed + $testResults.load.failed + $testResults.security.failed

if ($totalFailed -eq 0 -and $totalPassed -gt 0) {
    $testResults.overall = "PASSED"
} elseif ($totalFailed -gt 0) {
    $testResults.overall = "FAILED"
} else {
    $testResults.overall = "INCOMPLETE"
}

# Generate HTML Report
$htmlReport = @'
<!DOCTYPE html>
<html>
<head>
    <title>Message Broker Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .section { background: white; margin: 20px 0; padding: 20px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .passed { color: #27ae60; font-weight: bold; }
        .failed { color: #e74c3c; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #ecf0f1; }
        .summary { font-size: 1.2em; padding: 15px; border-radius: 5px; }
        .summary.passed { background: #d5f4e6; }
        .summary.failed { background: #fadbd8; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Message Broker System - Test Report</h1>
        <p>Generated: TIMESTAMP_PLACEHOLDER</p>
        <p>Duration: DURATION_PLACEHOLDER seconds</p>
    </div>
    
    <div class="section summary OVERALL_CLASS_PLACEHOLDER">
        <h2>Overall Result: <span class="OVERALL_CLASS_PLACEHOLDER">OVERALL_TEXT_PLACEHOLDER</span></h2>
        <p>Tests Passed: <span class="passed">TOTAL_PASSED_PLACEHOLDER</span> | Tests Failed: <span class="failed">TOTAL_FAILED_PLACEHOLDER</span></p>
    </div>
    
    <div class="section">
        <h2>Test Results Summary</h2>
        <table>
            <tr><th>Test Category</th><th>Passed</th><th>Failed</th><th>Skipped</th></tr>
            <tr><td>Functional Tests</td><td class="passed">FUNC_PASSED_PLACEHOLDER</td><td class="failed">FUNC_FAILED_PLACEHOLDER</td><td>FUNC_SKIPPED_PLACEHOLDER</td></tr>
            <tr><td>Integration Tests</td><td class="passed">INT_PASSED_PLACEHOLDER</td><td class="failed">INT_FAILED_PLACEHOLDER</td><td>INT_SKIPPED_PLACEHOLDER</td></tr>
            <tr><td>Load Tests</td><td class="passed">LOAD_PASSED_PLACEHOLDER</td><td class="failed">LOAD_FAILED_PLACEHOLDER</td><td>LOAD_SKIPPED_PLACEHOLDER</td></tr>
            <tr><td>Security Tests</td><td class="passed">SEC_PASSED_PLACEHOLDER</td><td class="failed">SEC_FAILED_PLACEHOLDER</td><td>SEC_SKIPPED_PLACEHOLDER</td></tr>
        </table>
    </div>
    
    <div class="section">
        <h2>Service Status</h2>
        <ul>
            <li>Services Started: SERVICES_STARTED_PLACEHOLDER</li>
            <li>Services Already Running: SERVICES_RUNNING_PLACEHOLDER</li>
            <li>Services Failed: SERVICES_FAILED_PLACEHOLDER</li>
        </ul>
    </div>
    
    <div class="section">
        <h2>Preflight Checks</h2>
        <p>Passed: PREFLIGHT_PASSED_PLACEHOLDER/PREFLIGHT_TOTAL_PLACEHOLDER</p>
    </div>
    
    ISSUES_PLACEHOLDER
    
    <div class="section">
        <h2>Next Steps</h2>
        <ul>
            NEXT_STEPS_PLACEHOLDER
        </ul>
    </div>
</body>
</html>
'@

# Replace placeholders
$htmlReport = $htmlReport -replace 'TIMESTAMP_PLACEHOLDER', $testResults.timestamp
$htmlReport = $htmlReport -replace 'DURATION_PLACEHOLDER', $testResults.duration
$overallLower = $testResults.overall.ToLower()
$htmlReport = $htmlReport -replace 'OVERALL_TEXT_PLACEHOLDER', $testResults.overall
$htmlReport = $htmlReport -replace 'OVERALL_CLASS_PLACEHOLDER', $overallLower
$htmlReport = $htmlReport -replace 'TOTAL_PASSED_PLACEHOLDER', $totalPassed
$htmlReport = $htmlReport -replace 'TOTAL_FAILED_PLACEHOLDER', $totalFailed
$htmlReport = $htmlReport -replace 'FUNC_PASSED_PLACEHOLDER', $testResults.functional.passed
$htmlReport = $htmlReport -replace 'FUNC_FAILED_PLACEHOLDER', $testResults.functional.failed
$htmlReport = $htmlReport -replace 'FUNC_SKIPPED_PLACEHOLDER', $testResults.functional.skipped
$htmlReport = $htmlReport -replace 'INT_PASSED_PLACEHOLDER', $testResults.integration.passed
$htmlReport = $htmlReport -replace 'INT_FAILED_PLACEHOLDER', $testResults.integration.failed
$htmlReport = $htmlReport -replace 'INT_SKIPPED_PLACEHOLDER', $testResults.integration.skipped
$htmlReport = $htmlReport -replace 'LOAD_PASSED_PLACEHOLDER', $testResults.load.passed
$htmlReport = $htmlReport -replace 'LOAD_FAILED_PLACEHOLDER', $testResults.load.failed
$htmlReport = $htmlReport -replace 'LOAD_SKIPPED_PLACEHOLDER', $testResults.load.skipped
$htmlReport = $htmlReport -replace 'SEC_PASSED_PLACEHOLDER', $testResults.security.passed
$htmlReport = $htmlReport -replace 'SEC_FAILED_PLACEHOLDER', $testResults.security.failed
$htmlReport = $htmlReport -replace 'SEC_SKIPPED_PLACEHOLDER', $testResults.security.skipped
$htmlReport = $htmlReport -replace 'SERVICES_STARTED_PLACEHOLDER', $testResults.services.started
$htmlReport = $htmlReport -replace 'SERVICES_RUNNING_PLACEHOLDER', $testResults.services.alreadyRunning
$htmlReport = $htmlReport -replace 'SERVICES_FAILED_PLACEHOLDER', $testResults.services.failed
$htmlReport = $htmlReport -replace 'PREFLIGHT_PASSED_PLACEHOLDER', $testResults.preflight.passed
$htmlReport = $htmlReport -replace 'PREFLIGHT_TOTAL_PLACEHOLDER', $testResults.preflight.total

# Build issues section
if ($testResults.issues.Count -gt 0) {
    $issuesHtml = "<div class='section'><h2 class='failed'>Issues Found</h2><ul>"
    foreach ($issue in $testResults.issues) {
        $issuesHtml += "<li>$issue</li>"
    }
    $issuesHtml += "</ul></div>"
    $htmlReport = $htmlReport -replace 'ISSUES_PLACEHOLDER', $issuesHtml
} else {
    $htmlReport = $htmlReport -replace 'ISSUES_PLACEHOLDER', ''
}

# Build next steps section
$nextSteps = @()
if ($testResults.overall -eq "PASSED") {
    $nextSteps += "<li class='passed'>✓ System is ready for production</li>"
    $nextSteps += "<li>Review logs for any warnings</li>"
    $nextSteps += "<li>Verify all features in the web portal</li>"
} else {
    $nextSteps += "<li class='failed'>✗ Please review and fix failed tests</li>"
    $nextSteps += "<li>Check service logs for errors</li>"
    $nextSteps += "<li>Run individual test suites to debug</li>"
}
$htmlReport = $htmlReport -replace 'NEXT_STEPS_PLACEHOLDER', ($nextSteps -join '')

# Ensure logs directory exists
$logsDir = Join-Path $TestsDir "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$htmlReport | Out-File -FilePath $testReportFile -Encoding UTF8

# Also save JSON results
$jsonFile = Join-Path $TestsDir "logs\test_results_$timestamp.json"
$testResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -Encoding UTF8

# ============================================================================
# FINAL SUMMARY
# ============================================================================

Write-Header "TEST EXECUTION SUMMARY"

Write-Host "Functional Tests:" -ForegroundColor Yellow
Write-Host "  Passed:  $($testResults.functional.passed)" -ForegroundColor Green
Write-Host "  Failed:  $($testResults.functional.failed)" -ForegroundColor $(if ($testResults.functional.failed -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped: $($testResults.functional.skipped)" -ForegroundColor Gray
Write-Host ""

Write-Host "Integration Tests:" -ForegroundColor Yellow
Write-Host "  Passed:  $($testResults.integration.passed)" -ForegroundColor Green
Write-Host "  Failed:  $($testResults.integration.failed)" -ForegroundColor $(if ($testResults.integration.failed -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped: $($testResults.integration.skipped)" -ForegroundColor Gray
Write-Host ""

Write-Host "Load Tests:" -ForegroundColor Yellow
Write-Host "  Passed:  $($testResults.load.passed)" -ForegroundColor Green
Write-Host "  Failed:  $($testResults.load.failed)" -ForegroundColor $(if ($testResults.load.failed -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped: $($testResults.load.skipped)" -ForegroundColor Gray
Write-Host ""

Write-Host "Security Tests:" -ForegroundColor Yellow
Write-Host "  Passed:  $($testResults.security.passed)" -ForegroundColor Green
Write-Host "  Failed:  $($testResults.security.failed)" -ForegroundColor $(if ($testResults.security.failed -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped: $($testResults.security.skipped)" -ForegroundColor Gray
Write-Host ""

Write-Host "$('='*80)" -ForegroundColor Cyan
Write-Host "OVERALL RESULT: $($testResults.overall)" -ForegroundColor $(if ($testResults.overall -eq "PASSED") { "Green" } else { "Red" })
Write-Host "$('='*80)" -ForegroundColor Cyan
Write-Host ""

Write-Info "Total Duration: $($testResults.duration) seconds"
Write-Info "Test Report: $testReportFile"
Write-Info "JSON Results: $jsonFile"

if ($testResults.issues.Count -gt 0) {
    Write-Host "`nIssues Found:" -ForegroundColor Yellow
    foreach ($issue in $testResults.issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
}

# Cleanup services if not keeping them
if (-not $KeepServices -and -not $SkipServices) {
    Write-Header "CLEANUP"
    Write-Info "Stopping test services..."
    & "$ProjectRoot\stop_all_services.ps1" | Out-Null
}

Write-Header "TEST COMPLETE"

if ($testResults.overall -eq "PASSED") {
    Write-Success "All tests passed! System is ready for delivery."
    Write-Info "Open the test report: $testReportFile"
    exit 0
} else {
    Write-Error "Some tests failed. Please review the report and fix issues."
    Write-Info "Open the test report: $testReportFile"
    exit 1
}
