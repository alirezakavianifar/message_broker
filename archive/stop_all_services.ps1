# Stop All Message Broker Services
# This script stops all running message broker components

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Red
Write-Host "  MESSAGE BROKER - STOP ALL SERVICES" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

Write-Host "Searching for running services..." -ForegroundColor Yellow
Write-Host ""

$stoppedCount = 0

# Find and stop all Python processes related to the message broker
$pythonProcesses = Get-Process python -ErrorAction SilentlyContinue

if ($pythonProcesses) {
    foreach ($proc in $pythonProcesses) {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)").CommandLine
            
            # Check if this is one of our services
            $isOurService = $false
            $serviceName = ""
            
            if ($cmdLine -like "*main_server.api*" -or $cmdLine -like "*main_server\api*") {
                $isOurService = $true
                $serviceName = "Main Server"
            }
            elseif ($cmdLine -like "*proxy.app*" -or $cmdLine -like "*proxy\app*") {
                $isOurService = $true
                $serviceName = "Proxy Server"
            }
            elseif ($cmdLine -like "*worker.py*" -or $cmdLine -like "*worker\worker*") {
                $isOurService = $true
                $serviceName = "Worker"
            }
            elseif ($cmdLine -like "*portal.app*" -or $cmdLine -like "*portal\app*") {
                $isOurService = $true
                $serviceName = "Web Portal"
            }
            
            if ($isOurService) {
                Write-Host "Stopping $serviceName (PID: $($proc.Id))..." -ForegroundColor Yellow
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Host "[OK] $serviceName stopped" -ForegroundColor Green
                $stoppedCount++
            }
        }
        catch {
            Write-Host "[WARN] Could not stop process $($proc.Id): $_" -ForegroundColor Yellow
        }
    }
}

# Also check for uvicorn processes
$uvicornProcesses = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
    $cmdLine -like "*uvicorn*"
}

foreach ($proc in $uvicornProcesses) {
    try {
        $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)").CommandLine
        Write-Host "Stopping uvicorn process (PID: $($proc.Id))..." -ForegroundColor Yellow
        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        Write-Host "[OK] Uvicorn process stopped" -ForegroundColor Green
        $stoppedCount++
    }
    catch {
        Write-Host "[WARN] Could not stop process $($proc.Id): $_" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CLEANUP COMPLETE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($stoppedCount -eq 0) {
    Write-Host "[INFO] No running services found" -ForegroundColor Cyan
} else {
    Write-Host "[OK] Stopped $stoppedCount service(s)" -ForegroundColor Green
}

# Verify no processes remain
Write-Host "`nVerifying all services stopped..." -ForegroundColor Yellow

$remainingProcesses = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
    $cmdLine -like "*message_broker*" -or 
    $cmdLine -like "*main_server*" -or 
    $cmdLine -like "*proxy*" -or 
    $cmdLine -like "*worker*" -or 
    $cmdLine -like "*portal*"
}

if ($remainingProcesses) {
    Write-Host "[WARN] Some processes may still be running:" -ForegroundColor Yellow
    foreach ($proc in $remainingProcesses) {
        Write-Host "  PID: $($proc.Id)" -ForegroundColor Gray
    }
    Write-Host "`nTo force stop all Python processes, run:" -ForegroundColor Yellow
    Write-Host "  Get-Process python | Stop-Process -Force" -ForegroundColor Gray
} else {
    Write-Host "[OK] All services stopped successfully" -ForegroundColor Green
}

# Check if ports are still in use
Write-Host "`nChecking ports..." -ForegroundColor Yellow

$ports = @(8000, 8001, 5000)
$portsInUse = @()

foreach ($port in $ports) {
    $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($connection) {
        $portsInUse += $port
        Write-Host "[WARN] Port $port still in use" -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Port $port is free" -ForegroundColor Green
    }
}

if ($portsInUse.Count -gt 0) {
    Write-Host "`nPorts still in use: $($portsInUse -join ', ')" -ForegroundColor Yellow
    Write-Host "To find processes using these ports:" -ForegroundColor Gray
    foreach ($port in $portsInUse) {
        Write-Host "  netstat -ano | findstr `":$port`"" -ForegroundColor Gray
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  DONE" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "To start services again, run:" -ForegroundColor Yellow
Write-Host "  .\start_all_services.ps1" -ForegroundColor White
Write-Host ""

