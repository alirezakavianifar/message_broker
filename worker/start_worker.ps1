#!/usr/bin/env pwsh
# Message Broker Worker - PowerShell Startup Script
# This script starts the worker process with proper environment

param(
    [string]$WorkerId = "worker-$PID",
    [int]$Concurrency = 4,
    [int]$RetryInterval = 30,
    [int]$MaxAttempts = 10000,
    [int]$MetricsPort = 9100,
    [string]$LogLevel = "INFO"
)

$ErrorActionPreference = "Stop"

# Change to script directory
Set-Location $PSScriptRoot

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Message Broker Worker - Starting" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check if virtual environment exists
if (-not (Test-Path "..\venv\Scripts\Activate.ps1")) {
    Write-Host "ERROR: Virtual environment not found at ..\venv" -ForegroundColor Red
    Write-Host "Please run setup first:" -ForegroundColor Yellow
    Write-Host "  cd .." -ForegroundColor Yellow
    Write-Host "  python -m venv venv" -ForegroundColor Yellow
    Write-Host "  .\venv\Scripts\Activate.ps1" -ForegroundColor Yellow
    Write-Host "  pip install -r worker\requirements.txt" -ForegroundColor Yellow
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
} else {
    Write-Host "WARNING: .env file not found. Using default configuration." -ForegroundColor Yellow
}

# Set environment variables (override with script parameters)
$env:WORKER_ID = $WorkerId
$env:WORKER_CONCURRENCY = $Concurrency
$env:WORKER_RETRY_INTERVAL = $RetryInterval
$env:WORKER_MAX_ATTEMPTS = $MaxAttempts
$env:WORKER_METRICS_PORT = $MetricsPort
$env:LOG_LEVEL = $LogLevel

# Set defaults if not set
if (-not $env:REDIS_HOST) { $env:REDIS_HOST = "localhost" }
if (-not $env:REDIS_PORT) { $env:REDIS_PORT = "6379" }
if (-not $env:REDIS_DB) { $env:REDIS_DB = "0" }
if (-not $env:REDIS_PASSWORD) { $env:REDIS_PASSWORD = "" }
if (-not $env:MAIN_SERVER_URL) { $env:MAIN_SERVER_URL = "https://localhost:8000" }
if (-not $env:WORKER_METRICS_ENABLED) { $env:WORKER_METRICS_ENABLED = "true" }
if (-not $env:LOG_FILE_PATH) { $env:LOG_FILE_PATH = "logs" }

# Display configuration
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Redis: $env:REDIS_HOST:$env:REDIS_PORT" -ForegroundColor White
Write-Host "  Main Server: $env:MAIN_SERVER_URL" -ForegroundColor White
Write-Host "  Worker ID: $env:WORKER_ID" -ForegroundColor White
Write-Host "  Concurrency: $env:WORKER_CONCURRENCY" -ForegroundColor White
Write-Host "  Retry Interval: $env:WORKER_RETRY_INTERVAL`s" -ForegroundColor White
Write-Host "  Max Attempts: $env:WORKER_MAX_ATTEMPTS" -ForegroundColor White
Write-Host "  Metrics Port: $env:WORKER_METRICS_PORT" -ForegroundColor White
Write-Host "  Log Level: $env:LOG_LEVEL" -ForegroundColor White
Write-Host ""

# Check Redis connection
Write-Host "Checking Redis connection..." -ForegroundColor Green
    try {
        $redisCheck = python -c "import redis; r = redis.Redis(host='$env:REDIS_HOST', port=$env:REDIS_PORT, db=$env:REDIS_DB, password='$env:REDIS_PASSWORD' if '$env:REDIS_PASSWORD' else None); r.ping(); print('[OK] Redis is running')"
        Write-Host $redisCheck -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Cannot connect to Redis at $env:REDIS_HOST:$env:REDIS_PORT" -ForegroundColor Red
        Write-Host "Make sure Redis is running: redis-server --service-start" -ForegroundColor Yellow
        exit 1
    }

# Check certificates
$certFiles = @(
    @{Path="certs\worker.crt"; Name="Worker certificate"},
    @{Path="certs\worker.key"; Name="Worker key"},
    @{Path="certs\ca.crt"; Name="CA certificate"}
)

foreach ($cert in $certFiles) {
    if (-not (Test-Path $cert.Path)) {
        Write-Host "ERROR: $($cert.Name) not found at $($cert.Path)" -ForegroundColor Red
        Write-Host "Please generate certificates first" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[OK] All certificates found" -ForegroundColor Green

# Create logs directory
if (-not (Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

Write-Host ""
Write-Host "Starting worker..." -ForegroundColor Green
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan

try {
    # Start the worker
    python worker.py
} catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "Worker encountered an error: $_" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "Check logs\worker.log for details" -ForegroundColor Yellow
    exit 1
} finally {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Worker stopped" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
}

