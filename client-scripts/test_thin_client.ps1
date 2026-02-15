# Test Script for Thin Client Architecture
# This script verifies that the Message Broker can be used with any HTTP client
# (curl, PowerShell, etc.) without requiring Python dependencies

param(
    [string]$ProxyUrl = "http://localhost:8001",
    [string]$Sender = "+1234567890",
    [string]$Message = "Test message from thin client test"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Thin Client Architecture Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This test verifies that clients can use ANY HTTP client" -ForegroundColor Yellow
Write-Host "(curl, PowerShell, etc.) without Python dependencies." -ForegroundColor Yellow
Write-Host ""

# Test 1: Check if curl.exe is available
Write-Host "[TEST 1] Checking for curl.exe..." -ForegroundColor White
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    $curlVersion = curl.exe --version 2>&1 | Select-Object -First 1
    Write-Host "  ✓ curl.exe found: $curlVersion" -ForegroundColor Green
} else {
    Write-Host "  ✗ curl.exe not found" -ForegroundColor Red
    Write-Host "  Note: curl is available on Windows 10+ or can be installed" -ForegroundColor Yellow
}

# Test 2: Check if proxy server is running
Write-Host ""
Write-Host "[TEST 2] Checking if proxy server is running..." -ForegroundColor White
$proxyRunning = $false
try {
    $response = Invoke-WebRequest -Uri "$ProxyUrl/api/v1/health" -Method Get -TimeoutSec 2 -ErrorAction Stop
    Write-Host "  ✓ Proxy server is running (HTTP $($response.StatusCode))" -ForegroundColor Green
    $proxyRunning = $true
} catch {
    Write-Host "  ✗ Proxy server is not running at $ProxyUrl" -ForegroundColor Red
    Write-Host "  To start: cd proxy ; .\start_proxy.ps1 -NoTLS" -ForegroundColor Yellow
}

# Test 3: Test with curl.exe (if available and proxy is running)
if ($proxyRunning -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "[TEST 3] Testing with curl.exe (no Python required)..." -ForegroundColor White
    
    $jsonBody = @{
        sender_number = $Sender
        message_body = $Message
    } | ConvertTo-Json -Compress
    
    Write-Host "  Command: curl.exe -X POST $ProxyUrl/api/v1/messages ..." -ForegroundColor Gray
    Write-Host "  Body: $jsonBody" -ForegroundColor Gray
    
    try {
        $curlOutput = curl.exe -X POST "$ProxyUrl/api/v1/messages" `
            -H "Content-Type: application/json" `
            -d $jsonBody `
            -w "`nHTTP_CODE:%{http_code}" `
            2>&1
        
        $httpCode = ($curlOutput | Select-String "HTTP_CODE:(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value })
        $responseBody = ($curlOutput | Where-Object { $_ -notmatch "HTTP_CODE" }) -join "`n"
        
        if ($httpCode -eq "202") {
            Write-Host "  ✓ SUCCESS! Message sent using curl (HTTP 202)" -ForegroundColor Green
            Write-Host "  Response: $responseBody" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  This proves the thin client architecture works!" -ForegroundColor Green
            Write-Host "  No Python dependencies needed on client machines." -ForegroundColor Green
        } else {
            Write-Host "  ✗ Request failed (HTTP $httpCode)" -ForegroundColor Red
            Write-Host "  Response: $responseBody" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ✗ Error: $_" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "[TEST 3] Skipped (proxy not running or curl not available)" -ForegroundColor Yellow
}

# Test 4: Test with PowerShell Invoke-RestMethod (if proxy is running)
if ($proxyRunning) {
    Write-Host ""
    Write-Host "[TEST 4] Testing with PowerShell Invoke-RestMethod" -ForegroundColor White
    
    $body = @{
        sender_number = $Sender
        message_body = $Message
    } | ConvertTo-Json
    
    try {
        # Note: Without TLS/certificates, this will work in dev mode
        # In production with mTLS, you'd need proper certificate handling
        $response = Invoke-RestMethod -Uri "$ProxyUrl/api/v1/messages" `
            -Method Post `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        Write-Host "  ✓ SUCCESS! Message sent using PowerShell (HTTP 202)" -ForegroundColor Green
        Write-Host "  Message ID: $($response.message_id)" -ForegroundColor Gray
        Write-Host "  Status: $($response.status)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  This proves PowerShell can be used without Python!" -ForegroundColor Green
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        if ($statusCode -eq 401) {
            Write-Host "  ⚠ Expected: Requires client certificate (mTLS)" -ForegroundColor Yellow
            Write-Host "  In production, you'd provide certificates here" -ForegroundColor Yellow
        } else {
            Write-Host "  ✗ Error: $_" -ForegroundColor Red
        }
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The thin client architecture allows:" -ForegroundColor White
Write-Host "  ✓ Using curl.exe (no Python needed)" -ForegroundColor Green
Write-Host "  ✓ Using PowerShell (no Python needed)" -ForegroundColor Green
Write-Host "  ✓ Using any HTTP client in any language" -ForegroundColor Green
Write-Host "  ✓ Python script is just a convenience wrapper" -ForegroundColor Yellow
Write-Host ""
Write-Host "To test with full services:" -ForegroundColor White
Write-Host "  1. Start Redis: redis-server (or memurai on Windows)" -ForegroundColor Gray
Write-Host "  2. Start Main Server: cd main_server ; .\start_server.ps1" -ForegroundColor Gray
Write-Host "  3. Start Proxy: cd proxy ; .\start_proxy.ps1 -NoTLS" -ForegroundColor Gray
Write-Host "  4. Run this test again" -ForegroundColor Gray
Write-Host ""
