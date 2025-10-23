#!/usr/bin/env pwsh
# Install Main Server as Windows Service
# Requires: NSSM (Non-Sucking Service Manager) or built-in sc.exe

param(
    [string]$AppRoot = "C:\MessageBroker",
    [string]$ServiceName = "MessageBrokerMainServer",
    [string]$DisplayName = "Message Broker - Main Server",
    [string]$Description = "Message Broker System Main Server API",
    [switch]$UseNSSM = $true
)

$ErrorActionPreference = "Stop"

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Installing Main Server as Windows Service" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Service '$ServiceName' already exists. Stopping and removing..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    if ($UseNSSM) {
        nssm remove $ServiceName confirm
    } else {
        sc.exe delete $ServiceName
    }
    Start-Sleep -Seconds 2
}

# Verify paths
$pythonExe = "$AppRoot\venv\Scripts\python.exe"
$uvicornExe = "$AppRoot\venv\Scripts\uvicorn.exe"
$appModule = "main_server.api:app"
$workingDir = $AppRoot

if (-not (Test-Path $pythonExe)) {
    Write-Host "ERROR: Python executable not found at $pythonExe" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $uvicornExe)) {
    Write-Host "ERROR: Uvicorn executable not found at $uvicornExe" -ForegroundColor Red
    Write-Host "Run: pip install uvicorn" -ForegroundColor Yellow
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  App Root: $AppRoot"
Write-Host "  Service Name: $ServiceName"
Write-Host "  Python: $pythonExe"
Write-Host "  Uvicorn: $uvicornExe"
Write-Host "  Working Directory: $workingDir"
Write-Host ""

if ($UseNSSM) {
    # Install using NSSM (recommended)
    Write-Host "Installing service using NSSM..." -ForegroundColor Cyan
    
    # Check if NSSM is installed
    $nssmPath = (Get-Command nssm -ErrorAction SilentlyContinue).Source
    if (-not $nssmPath) {
        Write-Host "NSSM not found. Installing via Chocolatey..." -ForegroundColor Yellow
        choco install nssm -y
        refreshenv
    }
    
    # Install service
    $arguments = @(
        "$appModule",
        "--host", "0.0.0.0",
        "--port", "8000",
        "--ssl-keyfile", "$AppRoot\main_server\certs\server.key",
        "--ssl-certfile", "$AppRoot\main_server\certs\server.crt",
        "--ssl-ca-certs", "$AppRoot\main_server\certs\ca.crt",
        "--log-level", "info"
    )
    
    nssm install $ServiceName $uvicornExe $arguments
    nssm set $ServiceName AppDirectory $workingDir
    nssm set $ServiceName DisplayName $DisplayName
    nssm set $ServiceName Description $Description
    nssm set $ServiceName Start SERVICE_AUTO_START
    
    # Set dependencies
    nssm set $ServiceName DependOnService MySQL Memurai
    
    # Set output redirection
    nssm set $ServiceName AppStdout "$AppRoot\logs\main_server_stdout.log"
    nssm set $ServiceName AppStderr "$AppRoot\logs\main_server_stderr.log"
    
    # Set rotation
    nssm set $ServiceName AppRotateFiles 1
    nssm set $ServiceName AppRotateOnline 1
    nssm set $ServiceName AppRotateSeconds 86400
    nssm set $ServiceName AppRotateBytes 104857600
    
    Write-Host "  OK Service installed with NSSM" -ForegroundColor Green
    
} else {
    # Install using sc.exe (built-in, but less flexible)
    Write-Host "Installing service using sc.exe..." -ForegroundColor Cyan
    
    # Create wrapper script
    $wrapperScript = "$AppRoot\main_server\start_service.bat"
    $wrapperContent = @"
@echo off
cd /d "$AppRoot"
call venv\Scripts\activate.bat
cd main_server
python -m uvicorn main_server.api:app --host 0.0.0.0 --port 8000 --ssl-keyfile certs\server.key --ssl-certfile certs\server.crt --ssl-ca-certs certs\ca.crt
"@
    Set-Content -Path $wrapperScript -Value $wrapperContent -Force
    
    # Register service
    sc.exe create $ServiceName binPath= $wrapperScript start= auto DisplayName= $DisplayName
    sc.exe description $ServiceName $Description
    sc.exe config $ServiceName depend= MySQL/Memurai
    
    Write-Host "  OK Service installed with sc.exe" -ForegroundColor Green
}

# Set service to restart on failure
sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000

Write-Host ""
Write-Host "Service Actions:" -ForegroundColor Cyan
Write-Host "  Start:   net start $ServiceName" -ForegroundColor White
Write-Host "  Stop:    net stop $ServiceName" -ForegroundColor White
Write-Host "  Status:  sc.exe query $ServiceName" -ForegroundColor White
Write-Host "  Logs:    Get-Content $AppRoot\logs\main_server.log -Tail 50" -ForegroundColor White
Write-Host ""

# Ask to start service
$response = Read-Host "Start service now? (y/n)"
if ($response -eq 'y') {
    Write-Host "Starting service..." -ForegroundColor Cyan
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq 'Running') {
        Write-Host "  OK Service started successfully" -ForegroundColor Green
    } else {
        Write-Host "  WARN Service status: $($service.Status)" -ForegroundColor Yellow
        Write-Host "  Check logs for details" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Main Server Service Installation Complete" -ForegroundColor Green
Write-Host "================================================================`n" -ForegroundColor Green

