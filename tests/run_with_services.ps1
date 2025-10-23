#!/usr/bin/env pwsh
# Integration Test Runner with Service Management
# Starts services, runs tests, and cleans up

param(
    [switch]$SkipCleanup,
    [int]$Timeout = 300
)

$ErrorActionPreference = "Stop"

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "     INTEGRATION TEST RUNNER WITH SERVICE MANAGEMENT" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# Service management
$services = @()
$testsPassed = $false

function Start-Service-Process {
    param(
        [string]$Name,
        [string]$Directory,
        [string]$Command,
        [int]$Port,
        [string]$HealthUrl = $null
    )
    
    Write-Host "Starting $Name..." -ForegroundColor Cyan
    
    try {
        # Navigate to directory
        Push-Location "$PSScriptRoot\..\$Directory"
        
        # Start process in background
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoExit", "-Command", "& { $Command }" `
            -WindowStyle Minimized `
            -PassThru
        
        if ($process) {
            $serviceInfo = @{
                Name = $Name
                Process = $process
                Port = $Port
                Directory = $Directory
            }
            $script:services += $serviceInfo
            
            Write-Host "  ✓ $Name started (PID: $($process.Id))" -ForegroundColor Green
            
            # Wait for service to be ready
            if ($HealthUrl) {
                Write-Host "  Waiting for $Name to be ready..." -ForegroundColor Yellow
                $maxAttempts = 30
                $attempt = 0
                $ready = $false
                
                while ($attempt -lt $maxAttempts -and -not $ready) {
                    Start-Sleep -Seconds 2
                    try {
                        $response = Invoke-WebRequest -Uri $HealthUrl -SkipCertificateCheck -TimeoutSec 2 -ErrorAction SilentlyContinue
                        if ($response.StatusCode -eq 200) {
                            $ready = $true
                            Write-Host "  ✓ $Name is ready!" -ForegroundColor Green
                        }
                    } catch {
                        $attempt++
                    }
                }
                
                if (-not $ready) {
                    Write-Host "  ⚠ $Name health check timeout, continuing anyway..." -ForegroundColor Yellow
                }
            } else {
                # Just wait a bit for service to start
                Write-Host "  Waiting 5 seconds for $Name to initialize..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                Write-Host "  ✓ Initialization wait complete" -ForegroundColor Green
            }
            
            Pop-Location
            return $true
        } else {
            Write-Host "  ✗ Failed to start $Name" -ForegroundColor Red
            Pop-Location
            return $false
        }
    } catch {
        Write-Host "  ✗ Error starting $Name : $_" -ForegroundColor Red
        Pop-Location
        return $false
    }
}

function Stop-All-Services {
    Write-Host "`nStopping services..." -ForegroundColor Cyan
    
    foreach ($service in $script:services) {
        try {
            if (-not $service.Process.HasExited) {
                Write-Host "  Stopping $($service.Name)..." -ForegroundColor Yellow
                Stop-Process -Id $service.Process.Id -Force -ErrorAction SilentlyContinue
                Write-Host "  ✓ $($service.Name) stopped" -ForegroundColor Green
            } else {
                Write-Host "  ✓ $($service.Name) already stopped" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  ⚠ Error stopping $($service.Name): $_" -ForegroundColor Yellow
        }
    }
}

try {
    # Activate virtual environment
    Write-Host "Activating virtual environment..." -ForegroundColor Cyan
    & "$PSScriptRoot\..\venv\Scripts\Activate.ps1"
    Write-Host "✓ Virtual environment activated`n" -ForegroundColor Green
    
    # Start Main Server (must be first - others depend on it)
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "STEP 1: Starting Main Server" -ForegroundColor Yellow
    Write-Host "================================================================`n" -ForegroundColor Yellow
    
    $mainStarted = Start-Service-Process `
        -Name "Main Server" `
        -Directory "main_server" `
        -Command ".\venv\Scripts\Activate.ps1 ; .\start_server.ps1 -NoTLS" `
        -Port 8000 `
        -HealthUrl "http://localhost:8000/health"
    
    if (-not $mainStarted) {
        throw "Failed to start Main Server"
    }
    
    # Start Proxy
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "STEP 2: Starting Proxy Server" -ForegroundColor Yellow
    Write-Host "================================================================`n" -ForegroundColor Yellow
    
    $proxyStarted = Start-Service-Process `
        -Name "Proxy Server" `
        -Directory "proxy" `
        -Command ".\venv\Scripts\Activate.ps1 ; .\start_proxy.ps1" `
        -Port 8001 `
        -HealthUrl "http://localhost:8001/api/v1/health"
    
    if (-not $proxyStarted) {
        throw "Failed to start Proxy Server"
    }
    
    # Start Worker
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "STEP 3: Starting Worker" -ForegroundColor Yellow
    Write-Host "================================================================`n" -ForegroundColor Yellow
    
    $workerStarted = Start-Service-Process `
        -Name "Worker" `
        -Directory "worker" `
        -Command ".\venv\Scripts\Activate.ps1 ; python worker.py" `
        -Port 9100
    
    if (-not $workerStarted) {
        Write-Host "⚠ Worker failed to start, but continuing..." -ForegroundColor Yellow
    }
    
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "✓ ALL SERVICES STARTED" -ForegroundColor Green
    Write-Host "================================================================`n" -ForegroundColor Green
    
    Write-Host "Service URLs:" -ForegroundColor Cyan
    Write-Host "  Main Server:  http://localhost:8000" -ForegroundColor White
    Write-Host "  Proxy:        http://localhost:8001" -ForegroundColor White
    Write-Host "  Worker:       http://localhost:9100/metrics`n" -ForegroundColor White
    
    # Run Integration Tests
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "STEP 4: Running Integration Tests" -ForegroundColor Yellow
    Write-Host "================================================================`n" -ForegroundColor Yellow
    
    Start-Sleep -Seconds 3
    
    Write-Host "Executing integration test suite...`n" -ForegroundColor Cyan
    python "$PSScriptRoot\integration_test.py"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Integration tests PASSED" -ForegroundColor Green
        $testsPassed = $true
    } else {
        Write-Host "`n✗ Integration tests FAILED" -ForegroundColor Red
        $testsPassed = $false
    }
    
} catch {
    Write-Host "`n✗ ERROR: $_" -ForegroundColor Red
    $testsPassed = $false
} finally {
    # Cleanup
    if (-not $SkipCleanup) {
        Write-Host "`n================================================================" -ForegroundColor Yellow
        Write-Host "CLEANUP: Stopping Services" -ForegroundColor Yellow
        Write-Host "================================================================`n" -ForegroundColor Yellow
        
        Stop-All-Services
    } else {
        Write-Host "`n⚠ Cleanup skipped - services still running" -ForegroundColor Yellow
        Write-Host "To stop manually, run: Get-Process powershell | Where-Object {`$_.MainWindowTitle -like '*message*'} | Stop-Process" -ForegroundColor Yellow
    }
    
    # Final summary
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "TEST EXECUTION COMPLETE" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    if ($testsPassed) {
        Write-Host "✓ INTEGRATION TESTS PASSED" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "✗ INTEGRATION TESTS FAILED" -ForegroundColor Red
        exit 1
    }
}

