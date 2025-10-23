#!/usr/bin/env pwsh
# Install All Message Broker Services
# Installs: Main Server, Proxy, Worker, Portal

param(
    [string]$AppRoot = "C:\MessageBroker"
)

$ErrorActionPreference = "Stop"

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Installing All Message Broker Services" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

# Check if NSSM is installed
$nssmPath = (Get-Command nssm -ErrorAction SilentlyContinue).Source
if (-not $nssmPath) {
    Write-Host "Installing NSSM..." -ForegroundColor Yellow
    choco install nssm -y
    refreshenv
}

$scriptDir = $PSScriptRoot

# Install services in order
$services = @(
    @{Name="Main Server"; Script="install_main_server_service.ps1"},
    @{Name="Proxy"; Script="install_proxy_service.ps1"},
    @{Name="Worker"; Script="install_worker_service.ps1"},
    @{Name="Portal"; Script="install_portal_service.ps1"}
)

$installed = 0
$failed = 0

foreach ($service in $services) {
    Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Installing $($service.Name)..." -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------`n" -ForegroundColor Yellow
    
    $scriptPath = Join-Path $scriptDir $service.Script
    
    if (Test-Path $scriptPath) {
        try {
            & $scriptPath -AppRoot $AppRoot
            $installed++
            Write-Host "  OK $($service.Name) installed" -ForegroundColor Green
        } catch {
            Write-Host "  ERROR Failed to install $($service.Name): $_" -ForegroundColor Red
            $failed++
        }
    } else {
        Write-Host "  WARN Script not found: $scriptPath" -ForegroundColor Yellow
        $failed++
    }
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Installation Summary" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

Write-Host "Installed: $installed" -ForegroundColor Green
Write-Host "Failed:    $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Gray" })
Write-Host ""

# Display installed services
Write-Host "Installed Services:" -ForegroundColor Cyan
Get-Service -Name "MessageBroker*" | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "Service Management Commands:" -ForegroundColor Cyan
Write-Host "  Start All:   Get-Service MessageBroker* | Start-Service" -ForegroundColor White
Write-Host "  Stop All:    Get-Service MessageBroker* | Stop-Service" -ForegroundColor White
Write-Host "  Status:      Get-Service MessageBroker*" -ForegroundColor White
Write-Host ""

$response = Read-Host "Start all services now? (y/n)"
if ($response -eq 'y') {
    Write-Host "`nStarting services in order..." -ForegroundColor Cyan
    
    $startOrder = @(
        "MessageBrokerMainServer",
        "MessageBrokerProxy",
        "MessageBrokerWorker",
        "MessageBrokerPortal"
    )
    
    foreach ($serviceName in $startOrder) {
        Write-Host "  Starting $serviceName..." -ForegroundColor Yellow
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Host "    OK $serviceName started" -ForegroundColor Green
        } else {
            Write-Host "    WARN $serviceName not running" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Get-Service -Name "MessageBroker*" | Format-Table Name, Status -AutoSize
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "All Services Installation Complete" -ForegroundColor Green
Write-Host "================================================================`n" -ForegroundColor Green

