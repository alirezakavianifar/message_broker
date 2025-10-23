#!/usr/bin/env pwsh
# Message Broker Main Server - PowerShell Startup Script
param(
    [string]$HostAddress = "0.0.0.0",
    [int]$Port = 8000,
    [string]$LogLevel = "INFO",
    [switch]$NoTLS,
    [switch]$Reload
)

$ErrorActionPreference = "Stop"

# Change to script directory
Set-Location $PSScriptRoot

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Message Broker Main Server - Starting" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check if virtual environment exists
if (-not (Test-Path "..\venv\Scripts\Activate.ps1")) {
    Write-Host "ERROR: Virtual environment not found at ..\venv" -ForegroundColor Red
    Write-Host "Please run setup first:" -ForegroundColor Yellow
    Write-Host "  cd .." -ForegroundColor Yellow
    Write-Host "  python -m venv venv" -ForegroundColor Yellow
    Write-Host "  .\venv\Scripts\Activate.ps1" -ForegroundColor Yellow
    Write-Host "  pip install -r main_server\requirements.txt" -ForegroundColor Yellow
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
if (-not $env:DATABASE_URL) { 
    $env:DATABASE_URL = "mysql+pymysql://systemuser:StrongPass123!@localhost/message_system" 
}
if (-not $env:MAIN_SERVER_HOST) { $env:MAIN_SERVER_HOST = $Host }
if (-not $env:MAIN_SERVER_PORT) { $env:MAIN_SERVER_PORT = $Port }
if (-not $env:LOG_LEVEL) { $env:LOG_LEVEL = $LogLevel }
if (-not $env:METRICS_ENABLED) { $env:METRICS_ENABLED = "true" }
if (-not $env:JWT_SECRET) { 
    $env:JWT_SECRET = "change_this_secret_in_production"
    Write-Host "WARNING: Using default JWT secret. Set JWT_SECRET in production!" -ForegroundColor Yellow
}
if (-not $env:ENCRYPTION_KEY_PATH) { $env:ENCRYPTION_KEY_PATH = "secrets/encryption.key" }
if (-not $env:LOG_FILE_PATH) { $env:LOG_FILE_PATH = "logs" }

# Display configuration
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Database: $env:DATABASE_URL" -ForegroundColor White
Write-Host "  Host: $($env:MAIN_SERVER_HOST):$($env:MAIN_SERVER_PORT)" -ForegroundColor White
Write-Host "  Log Level: $env:LOG_LEVEL" -ForegroundColor White
Write-Host "  Metrics: $env:METRICS_ENABLED" -ForegroundColor White
Write-Host "  TLS: $(if ($NoTLS) { 'Disabled' } else { 'Enabled' })" -ForegroundColor White
Write-Host ""

# Check database connection
Write-Host "Checking database connection..." -ForegroundColor Green
try {
    $dbCheck = python -c "import pymysql; import os; url = os.environ.get('DATABASE_URL'); parts = url.split('//')[1].split('@'); creds = parts[0].split(':'); host_db = parts[1].split('/'); host = host_db[0].split(':')[0]; port = int(host_db[0].split(':')[1]) if ':' in host_db[0] else 3306; db = host_db[1].split('?')[0]; conn = pymysql.connect(host=host, port=port, user=creds[0], password=creds[1], database=db); conn.close(); print('✓ Database connection successful')" 2>&1
    Write-Host $dbCheck -ForegroundColor Green
} catch {
    Write-Host "WARNING: Cannot connect to database" -ForegroundColor Yellow
    Write-Host "Please check database configuration and ensure MySQL is running" -ForegroundColor Yellow
}

# Check certificates (unless NoTLS)
if (-not $NoTLS) {
    $certFiles = @(
        @{Path="certs\server.crt"; Name="Server certificate"},
        @{Path="certs\server.key"; Name="Server key"},
        @{Path="certs\ca.crt"; Name="CA certificate"}
    )
    
    $allCertsFound = $true
    foreach ($cert in $certFiles) {
        if (-not (Test-Path $cert.Path)) {
            Write-Host "ERROR: $($cert.Name) not found at $($cert.Path)" -ForegroundColor Red
            $allCertsFound = $false
        }
    }
    
    if (-not $allCertsFound) {
        Write-Host "Please initialize CA and generate certificates first:" -ForegroundColor Yellow
        Write-Host "  .\init_ca.bat" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "✓ All certificates found" -ForegroundColor Green
}

# Create necessary directories
@("logs", "secrets") | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ | Out-Null
        Write-Host "✓ Created $_ directory" -ForegroundColor Green
    }
}

# Check/create encryption key
if (-not (Test-Path $env:ENCRYPTION_KEY_PATH)) {
    Write-Host "Generating encryption key..." -ForegroundColor Green
    $pyCmd = "from cryptography.fernet import Fernet; import os; key_path = os.environ.get('ENCRYPTION_KEY_PATH'); os.makedirs(os.path.dirname(key_path), exist_ok=True); open(key_path, 'wb').write(Fernet.generate_key())"
    python -c $pyCmd
    Write-Host "✓ Encryption key generated at $env:ENCRYPTION_KEY_PATH" -ForegroundColor Green
}

# Build uvicorn command
$uvicornArgs = @(
    "main_server.api:app",
    "--host", $env:MAIN_SERVER_HOST,
    "--port", $env:MAIN_SERVER_PORT,
    "--log-level", $env:LOG_LEVEL.ToLower()
)

if (-not $NoTLS) {
    $uvicornArgs += @(
        "--ssl-keyfile", "certs/server.key",
        "--ssl-certfile", "certs/server.crt",
        "--ssl-ca-certs", "certs/ca.crt"
    )
}

if ($Reload) {
    $uvicornArgs += "--reload"
    Write-Host "⚠ Auto-reload enabled (development mode)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Starting main server..." -ForegroundColor Green
$protocol = if ($NoTLS) { "http" } else { "https" }
Write-Host "API Documentation: ${protocol}://localhost:$($env:MAIN_SERVER_PORT)/docs" -ForegroundColor Cyan
Write-Host "ReDoc: ${protocol}://localhost:$($env:MAIN_SERVER_PORT)/redoc" -ForegroundColor Cyan
Write-Host "Health Check: ${protocol}://localhost:$($env:MAIN_SERVER_PORT)/health" -ForegroundColor Cyan
Write-Host "Metrics: ${protocol}://localhost:$($env:MAIN_SERVER_PORT)/metrics" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan

try {
    # Start the server
    uvicorn @uvicornArgs
} catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "Server encountered an error: $_" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "Check logs\main_server.log for details" -ForegroundColor Yellow
    exit 1
} finally {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Main server stopped" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
}

