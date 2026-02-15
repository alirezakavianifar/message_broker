# Start All Message Broker Services
# This script starts all 4 components in separate PowerShell windows

param(
    [switch]$Sequential,  # If set, wait for each service to fully start before launching next
    [switch]$Silent       # If set, start services in hidden windows (no console visible)
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MESSAGE BROKER - START ALL SERVICES" -ForegroundColor Cyan
if ($Silent) {
    Write-Host "  (Silent Mode - Services Running in Background)" -ForegroundColor Gray
}
Write-Host "========================================`n" -ForegroundColor Cyan

$ProjectRoot = $PSScriptRoot

# Verify we're in the correct directory
if (-not (Test-Path "$ProjectRoot\main_server\api.py")) {
    Write-Host "[ERROR] Cannot find main_server/api.py" -ForegroundColor Red
    Write-Host "Please run this script from the project root directory." -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Project root: $ProjectRoot" -ForegroundColor Gray

# Check prerequisites
Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow

# Check Python
try {
    $pythonVersion = & "$ProjectRoot\venv\Scripts\python.exe" --version 2>&1
    Write-Host "[OK] Python: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Python not found in venv" -ForegroundColor Red
    Write-Host "Run: python -m venv venv" -ForegroundColor Yellow
    exit 1
}

# Check MySQL
try {
    $mysqlService = Get-Service | Where-Object { $_.Name -like "*mysql*" -and $_.Status -eq "Running" }
    if ($mysqlService) {
        Write-Host "[OK] MySQL service running" -ForegroundColor Green
    } else {
        Write-Host "[WARN] MySQL service not found or not running" -ForegroundColor Yellow
        Write-Host "       Start MySQL with: net start MySQL80" -ForegroundColor Gray
    }
} catch {
    Write-Host "[WARN] Could not check MySQL status" -ForegroundColor Yellow
}

# Check Redis
try {
    $redisCheck = redis-cli ping 2>&1
    if ($redisCheck -eq "PONG") {
        Write-Host "[OK] Redis running" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Redis not responding" -ForegroundColor Yellow
        Write-Host "       Start Redis with: redis-server --service-start" -ForegroundColor Gray
    }
} catch {
    Write-Host "[WARN] Redis-cli not found or Redis not running" -ForegroundColor Yellow
}

# Check certificates
if (Test-Path "$ProjectRoot\main_server\certs\server.crt") {
    Write-Host "[OK] Certificates found" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Certificates not found" -ForegroundColor Red
    Write-Host "Run certificate generation script first." -ForegroundColor Yellow
    exit 1
}

# Check/create encryption key
$encryptionKeyPath = "$ProjectRoot\main_server\secrets\encryption.key"
if (Test-Path $encryptionKeyPath) {
    Write-Host "[OK] Encryption key found" -ForegroundColor Green
} else {
    Write-Host "[INFO] Generating encryption key..." -ForegroundColor Yellow
    try {
        $secretsDir = "$ProjectRoot\main_server\secrets"
        if (-not (Test-Path $secretsDir)) {
            New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
        }
        
        $pyCmd = "from cryptography.fernet import Fernet; open(r'$encryptionKeyPath', 'wb').write(Fernet.generate_key())"
        & "$ProjectRoot\venv\Scripts\python.exe" -c $pyCmd
        
        if (Test-Path $encryptionKeyPath) {
            Write-Host "[OK] Encryption key generated" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to generate encryption key" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "[ERROR] Failed to generate encryption key: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STARTING SERVICES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$services = @(
    @{
        Name = "Main Server"
        Script = "main_server\start_server.ps1"
        Port = 8000
        HealthUrl = "https://localhost:8000/health"
    },
    @{
        Name = "Proxy Server"
        Script = "proxy\start_proxy.ps1"
        Port = 8001
        HealthUrl = "https://localhost:8001/api/v1/health"
    },
    @{
        Name = "Worker"
        Script = "worker\start_worker.ps1"
        Port = $null
        HealthUrl = $null
    },
    @{
        Name = "Web Portal"
        Script = "portal\start_portal.ps1"
        Port = 5000
        HealthUrl = "http://localhost:5000"
    }
)

$startedProcesses = @()

foreach ($service in $services) {
    Write-Host "Starting $($service.Name)..." -ForegroundColor Yellow
    
    $scriptPath = Join-Path $ProjectRoot $service.Script
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "[ERROR] Script not found: $scriptPath" -ForegroundColor Red
        continue
    }
    
    # Check if port is already in use
    if ($service.Port) {
        $portInUse = Get-NetTCPConnection -LocalPort $service.Port -ErrorAction SilentlyContinue
        if ($portInUse) {
            Write-Host "[WARN] Port $($service.Port) already in use - service may already be running" -ForegroundColor Yellow
        }
    }
    
    # Start the service in a new window
    # Use pwsh if available, otherwise fall back to powershell
    $psExecutable = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    
    # Determine window style
    $windowStyle = if ($Silent) { "Hidden" } else { "Normal" }
    
    try {
        $process = Start-Process $psExecutable -ArgumentList "-NoExit", "-File", $scriptPath -PassThru -WindowStyle $windowStyle
        $startedProcesses += $process
        Write-Host "[OK] $($service.Name) started (PID: $($process.Id))$(if ($Silent) { ' [Hidden]' })" -ForegroundColor Green
        
        # Wait a bit for service to initialize
        if ($Sequential) {
            Write-Host "      Waiting for service to initialize..." -ForegroundColor Gray
            Start-Sleep -Seconds 5
            
            # Try health check if available
            if ($service.HealthUrl) {
                $maxAttempts = 12
                $attempt = 0
                $healthy = $false
                
                while ($attempt -lt $maxAttempts -and -not $healthy) {
                    $attempt++
                    try {
                        $response = Invoke-WebRequest -Uri $service.HealthUrl -SkipCertificateCheck -TimeoutSec 2 -ErrorAction Stop
                        $healthy = $true
                        Write-Host "      Health check passed!" -ForegroundColor Green
                    } catch {
                        if ($attempt -lt $maxAttempts) {
                            Write-Host "      Waiting... (attempt $attempt/$maxAttempts)" -ForegroundColor Gray
                            Start-Sleep -Seconds 5
                        } else {
                            Write-Host "      Could not verify health (may still be starting)" -ForegroundColor Yellow
                        }
                    }
                }
            } else {
                Start-Sleep -Seconds 3
            }
        } else {
            Start-Sleep -Seconds 1
        }
        
    } catch {
        Write-Host "[ERROR] Failed to start $($service.Name): $_" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ALL SERVICES STARTED" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Service URLs:" -ForegroundColor Yellow
Write-Host "  Main Server API:  https://localhost:8000/docs" -ForegroundColor White
Write-Host "  Proxy API:        https://localhost:8001/api/v1/docs" -ForegroundColor White
Write-Host "  Web Portal:       http://localhost:5000" -ForegroundColor White
Write-Host "  Health Checks:    /health on each service" -ForegroundColor Gray

Write-Host "`nRunning Health Checks..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$healthChecks = @(
    @{ Name = "Main Server"; Url = "https://localhost:8000/health" },
    @{ Name = "Proxy Server"; Url = "https://localhost:8001/api/v1/health" },
    @{ Name = "Web Portal"; Url = "http://localhost:5000" }
)

foreach ($check in $healthChecks) {
    try {
        $response = Invoke-WebRequest -Uri $check.Url -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop
        Write-Host "[OK] $($check.Name) is responding" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] $($check.Name) not responding yet (may still be starting)" -ForegroundColor Yellow
    }
}

# Check worker process
if (Get-Process python -ErrorAction SilentlyContinue | Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -like "*worker.py*" }) {
    Write-Host "[OK] Worker process is running" -ForegroundColor Green
} else {
    Write-Host "[WARN] Worker process not detected" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  READY TO USE!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Open Web Portal:  http://localhost:5000" -ForegroundColor White
Write-Host "2. Login as admin (or create admin user)" -ForegroundColor White
Write-Host "3. Generate client certificate" -ForegroundColor White
Write-Host "4. Send test message" -ForegroundColor White

Write-Host "`nTo stop all services:" -ForegroundColor Yellow
if ($Silent) {
    Write-Host "  .\stop_all_services.ps1" -ForegroundColor White
    Write-Host "  OR: Get-Process python | Stop-Process -Force" -ForegroundColor Gray
} else {
    Write-Host "  Press Ctrl+C in each window, or run:" -ForegroundColor White
    Write-Host "  .\stop_all_services.ps1" -ForegroundColor Gray
}

Write-Host "`nView logs:" -ForegroundColor Yellow
Write-Host "  Get-Content logs\*.log -Tail 50 -Wait" -ForegroundColor Gray

Write-Host "`n========================================`n" -ForegroundColor Cyan

# Keep track of started processes
if ($startedProcesses.Count -gt 0) {
    Write-Host "Started $($startedProcesses.Count) service(s)" -ForegroundColor Cyan
    Write-Host "Process IDs: $($startedProcesses.Id -join ', ')" -ForegroundColor Gray
}

Write-Host "`nPress Enter to exit this window (services will keep running)..." -ForegroundColor Yellow
Read-Host

