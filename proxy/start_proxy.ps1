# ============================================================================
# Proxy Server Startup Script (PowerShell)
# Purpose: Start the Message Broker Proxy Server with proper configuration
# Usage: .\start_proxy.ps1 [-Dev] [-Port 8001] [-Workers 4]
# ============================================================================

param(
    [switch]$Dev,
    [int]$Port = 8001,
    [int]$Workers = 1,  # Default to 1 worker on Windows to avoid log rotation issues
    [switch]$NoTLS
)

$ErrorActionPreference = "Stop"

# Change to script directory
Set-Location $PSScriptRoot

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Message Broker Proxy Server" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if in virtual environment
if (-not $env:VIRTUAL_ENV) {
    Write-Host "[INFO] Activating virtual environment..." -ForegroundColor Yellow
    $venvPath = "..\venv\Scripts\Activate.ps1"
    if (Test-Path $venvPath) {
        & $venvPath
    } else {
        Write-Host "[WARNING] Virtual environment not found" -ForegroundColor Yellow
        Write-Host "[INFO] Using system Python" -ForegroundColor Yellow
    }
}

# Check Python availability
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Python not found in PATH!" -ForegroundColor Red
    exit 1
}

# Check/install dependencies
Write-Host "[INFO] Checking dependencies..." -ForegroundColor Yellow
python -c "import fastapi, uvicorn, redis, httpx" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[INFO] Installing required packages..." -ForegroundColor Yellow
    python -m pip install -r requirements.txt --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to install packages!" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Dependencies installed" -ForegroundColor Green
}

# Create logs directory
if (-not (Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" -Force | Out-Null
}

# Load environment variables from parent .env if exists
if (Test-Path "..\.env") {
    Write-Host "[INFO] Loading environment from .env" -ForegroundColor Yellow
    Get-Content "..\.env" | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*?)\s*=\s*(.*?)\s*$') {
            $name = $matches[1]
            $value = $matches[2]
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

# Set default environment variables if not already set
if (-not $env:REDIS_HOST) { $env:REDIS_HOST = "localhost" }
if (-not $env:REDIS_PORT) { $env:REDIS_PORT = "6379" }
if (-not $env:REDIS_DB) { $env:REDIS_DB = "0" }
if (-not $env:REDIS_PASSWORD) { $env:REDIS_PASSWORD = "" }
if (-not $env:MAIN_SERVER_URL) { $env:MAIN_SERVER_URL = "https://localhost:8000" }
if (-not $env:LOG_LEVEL) { $env:LOG_LEVEL = "INFO" }
if (-not $env:LOG_FILE_PATH) { $env:LOG_FILE_PATH = "logs" }

# Display configuration
Write-Host ""
Write-Host "Configuration:" -ForegroundColor White
Write-Host "  Port:        $Port" -ForegroundColor Gray
Write-Host "  Workers:     $Workers" -ForegroundColor Gray
Write-Host "  Redis:       $($env:REDIS_HOST):$($env:REDIS_PORT)" -ForegroundColor Gray
Write-Host "  Main Server: $($env:MAIN_SERVER_URL)" -ForegroundColor Gray
Write-Host "  Log Level:   $($env:LOG_LEVEL)" -ForegroundColor Gray
Write-Host "  TLS:         $(if ($NoTLS) { 'Disabled' } else { 'Enabled' })" -ForegroundColor Gray
Write-Host ""

# Check certificates
$certsExist = $true
if (-not (Test-Path "certs\proxy.crt")) {
    Write-Host "[WARNING] Proxy certificate not found: certs\proxy.crt" -ForegroundColor Yellow
    $certsExist = $false
}
if (-not (Test-Path "certs\ca.crt")) {
    Write-Host "[WARNING] CA certificate not found: certs\ca.crt" -ForegroundColor Yellow
    $certsExist = $false
}

if (-not $certsExist -and -not $NoTLS) {
    Write-Host ""
    Write-Host "[INFO] To generate certificates:" -ForegroundColor Yellow
    Write-Host "  cd ..\main_server" -ForegroundColor Gray
    Write-Host "  .\generate_cert.bat proxy" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] Starting without TLS..." -ForegroundColor Yellow
    $NoTLS = $true
}

# Build uvicorn command
$uvicornArgs = @(
    "app:app",
    "--host", "0.0.0.0",
    "--port", $Port,
    "--log-level", $env:LOG_LEVEL.ToLower()
)

if ($Dev) {
    Write-Host "Starting in DEVELOPMENT mode (hot-reload enabled)..." -ForegroundColor Green
    $uvicornArgs += "--reload"
} else {
    Write-Host "Starting in PRODUCTION mode..." -ForegroundColor Green
    $uvicornArgs += "--workers", $Workers
}

if (-not $NoTLS -and $certsExist) {
    Write-Host "TLS mutual authentication: ENABLED" -ForegroundColor Green
    $uvicornArgs += @(
        "--ssl-keyfile", "certs/proxy.key",
        "--ssl-certfile", "certs/proxy.crt",
        "--ssl-ca-certs", "certs/ca.crt"
    )
    Write-Host "Server will be available at: https://localhost:$Port" -ForegroundColor White
} else {
    Write-Host "TLS: DISABLED (development only)" -ForegroundColor Yellow
    Write-Host "Server will be available at: http://localhost:$Port" -ForegroundColor White
}

Write-Host ""
Write-Host "API Documentation: http://localhost:$Port/docs" -ForegroundColor White
Write-Host "Metrics:          http://localhost:$Port/metrics" -ForegroundColor White
Write-Host ""
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Gray
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# Start uvicorn
uvicorn @uvicornArgs

