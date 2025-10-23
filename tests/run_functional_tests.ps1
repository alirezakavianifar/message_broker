#!/usr/bin/env pwsh
# Functional Tests - Tests individual component functionality

Write-Host "Running Functional Tests..." -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test Proxy
Write-Host "Testing Proxy Server..." -ForegroundColor Yellow
cd ..\proxy
try {
    python test_client.py
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  PASS Proxy tests passed" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  FAIL Proxy tests failed" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  FAIL Proxy tests error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test Main Server
Write-Host "Testing Main Server..." -ForegroundColor Yellow
cd ..\main_server
try {
    python test_server.py
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  PASS Main server tests passed" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  FAIL Main server tests failed" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  FAIL Main server tests error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test Worker
Write-Host "Testing Worker..." -ForegroundColor Yellow
cd ..\worker
try {
    python test_worker.py
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  PASS Worker tests passed" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  FAIL Worker tests failed" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  FAIL Worker tests error: $_" -ForegroundColor Red
    $testsFailed++
}

cd ..\tests

Write-Host ""
Write-Host "Functional Tests Complete:" -ForegroundColor Cyan
Write-Host "  Passed: $testsPassed" -ForegroundColor Green
Write-Host "  Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })

if ($testsFailed -gt 0) {
    throw "Functional tests failed"
}
