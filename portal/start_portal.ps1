#!/usr/bin/env pwsh
# Message Broker Portal - PowerShell Startup Script

param(
    [string]$HostAddress = "0.0.0.0",
    [int]$Port = 5000,
    [string]$LogLevel = "INFO",
    [switch]$Reload
)

$ErrorActionPreference = "Stop"

# Change to script directory
Set-Location $PSScriptRoot

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Message Broker Portal - Starting" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check if virtual environment exists
if (-not (Test-Path "..\venv\Scripts\Activate.ps1")) {
    Write-Host "ERROR: Virtual environment not found at ..\venv" -ForegroundColor Red
    Write-Host "Please run setup first:" -ForegroundColor Yellow
    Write-Host "  cd .." -ForegroundColor Yellow
    Write-Host "  python -m venv venv" -ForegroundColor Yellow
    Write-Host "  .\venv\Scripts\Activate.ps1" -ForegroundColor Yellow
    Write-Host "  pip install -r portal\requirements.txt" -ForegroundColor Yellow
    exit 1
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Green
& "..\venv\Scripts\Activate.ps1"

# Load environment variables from .env if exists
if (Test-Path "..\.env") {
    Write-Host "Loading environment variables from .env..." -ForegroundColor Green
    Get-Content "..\.env" | ForEach-Object {
        if ($_ -match '^([^#][^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

# Set default environment variables
if (-not $env:MAIN_SERVER_URL) { $env:MAIN_SERVER_URL = "https://localhost:8000" }
if (-not $env:MAIN_SERVER_VERIFY_SSL) { $env:MAIN_SERVER_VERIFY_SSL = "false" }
if (-not $env:PORTAL_HOST) { $env:PORTAL_HOST = $HostAddress }
if (-not $env:PORTAL_PORT) { $env:PORTAL_PORT = $Port }
if (-not $env:SESSION_SECRET) { 
    $env:SESSION_SECRET = "change_this_session_secret_in_production"
    Write-Host "WARNING: Using default session secret. Set SESSION_SECRET in production!" -ForegroundColor Yellow
}
if (-not $env:LOG_LEVEL) { $env:LOG_LEVEL = $LogLevel }
if (-not $env:LOG_FILE_PATH) { $env:LOG_FILE_PATH = "logs" }
if (-not $env:MESSAGES_PER_PAGE) { $env:MESSAGES_PER_PAGE = "20" }

# Display configuration
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Main Server: $env:MAIN_SERVER_URL" -ForegroundColor White
Write-Host "  Portal Host: $($env:PORTAL_HOST):$($env:PORTAL_PORT)" -ForegroundColor White
Write-Host "  Log Level: $env:LOG_LEVEL" -ForegroundColor White
Write-Host "  SSL Verification: $env:MAIN_SERVER_VERIFY_SSL" -ForegroundColor White
Write-Host ""

# Check templates directory
if (-not (Test-Path "templates")) {
    Write-Host "ERROR: templates directory not found" -ForegroundColor Red
    Write-Host "Please ensure all portal files are present" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Templates directory found" -ForegroundColor Green

# Create logs directory
if (-not (Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" | Out-Null
    Write-Host "[OK] Created logs directory" -ForegroundColor Green
}

# Build uvicorn command
$uvicornArgs = @(
    "app:app",
    "--host", $env:PORTAL_HOST,
    "--port", $env:PORTAL_PORT,
    "--log-level", $env:LOG_LEVEL.ToLower()
)

if ($Reload) {
    $uvicornArgs += "--reload"
    Write-Host "[WARN] Auto-reload enabled (development mode)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Starting portal..." -ForegroundColor Green
Write-Host "Portal URL: http://localhost:$($env:PORTAL_PORT)" -ForegroundColor Cyan
Write-Host "Login with your credentials to access the dashboard" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan

try {
    # Start the portal
    uvicorn @uvicornArgs
} catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "Portal encountered an error: $_" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "Check logs\portal.log for details" -ForegroundColor Yellow
    exit 1
} finally {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Portal stopped" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
}

