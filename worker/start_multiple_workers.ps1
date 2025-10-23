#!/usr/bin/env pwsh
# Message Broker - Multiple Workers Launcher
# This script starts multiple worker processes for concurrent message processing

param(
    [int]$NumWorkers = 3,
    [int]$Concurrency = 4,
    [int]$RetryInterval = 30,
    [int]$MaxAttempts = 10000,
    [int]$BaseMetricsPort = 9100,
    [string]$LogLevel = "INFO"
)

$ErrorActionPreference = "Stop"

# Change to script directory
Set-Location $PSScriptRoot

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Message Broker - Multiple Workers Launcher" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting $NumWorkers worker processes..." -ForegroundColor Green
Write-Host ""

$jobs = @()

for ($i = 1; $i -le $NumWorkers; $i++) {
    $workerId = "worker-$i-$PID"
    $metricsPort = $BaseMetricsPort + $i - 1
    
    Write-Host "Starting Worker $i" -ForegroundColor Green
    Write-Host "  ID: $workerId" -ForegroundColor White
    Write-Host "  Metrics Port: $metricsPort" -ForegroundColor White
    Write-Host "  Concurrency: $Concurrency" -ForegroundColor White
    
    $job = Start-Job -ScriptBlock {
        param($scriptPath, $workerId, $concurrency, $retryInterval, $maxAttempts, $metricsPort, $logLevel)
        
        Set-Location (Split-Path $scriptPath)
        
        & powershell.exe -File $scriptPath `
            -WorkerId $workerId `
            -Concurrency $concurrency `
            -RetryInterval $retryInterval `
            -MaxAttempts $maxAttempts `
            -MetricsPort $metricsPort `
            -LogLevel $logLevel
    } -ArgumentList (
        (Join-Path $PSScriptRoot "start_worker.ps1"),
        $workerId,
        $Concurrency,
        $RetryInterval,
        $MaxAttempts,
        $metricsPort,
        $LogLevel
    )
    
    $jobs += $job
    Write-Host "  ✓ Started (Job ID: $($job.Id))" -ForegroundColor Green
    Write-Host ""
    
    # Small delay to stagger startup
    Start-Sleep -Milliseconds 500
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "All $NumWorkers workers started" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Worker Job IDs: $($jobs.Id -join ', ')" -ForegroundColor Cyan
Write-Host ""
Write-Host "Commands:" -ForegroundColor Yellow
Write-Host "  View output: Receive-Job -Id <JobId> -Keep" -ForegroundColor White
Write-Host "  Stop all: Get-Job | Stop-Job; Get-Job | Remove-Job" -ForegroundColor White
Write-Host "  Check status: Get-Job" -ForegroundColor White
Write-Host ""
Write-Host "Metrics ports: $BaseMetricsPort to $($BaseMetricsPort + $NumWorkers - 1)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop all workers..." -ForegroundColor Yellow

try {
    # Wait for jobs with periodic status updates
    while ($true) {
        Start-Sleep -Seconds 10
        
        $running = ($jobs | Get-Job | Where-Object { $_.State -eq 'Running' }).Count
        $completed = ($jobs | Get-Job | Where-Object { $_.State -eq 'Completed' }).Count
        $failed = ($jobs | Get-Job | Where-Object { $_.State -eq 'Failed' }).Count
        
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Status: $running running, $completed completed, $failed failed" -ForegroundColor Cyan
        
        # Check if all jobs have finished
        if ($running -eq 0) {
            Write-Host ""
            Write-Host "All workers have stopped" -ForegroundColor Yellow
            break
        }
    }
} catch {
    Write-Host ""
    Write-Host "Caught interrupt signal" -ForegroundColor Yellow
} finally {
    Write-Host ""
    Write-Host "Stopping all workers..." -ForegroundColor Yellow
    
    $jobs | ForEach-Object {
        Stop-Job -Id $_.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "All workers stopped" -ForegroundColor Green
}

