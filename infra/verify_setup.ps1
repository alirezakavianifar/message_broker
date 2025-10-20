# Verification Script for Message Broker System Phase 0
# Checks if all required files and directories are present

Write-Host "=== Message Broker System - Phase 0 Verification ===" -ForegroundColor Cyan
Write-Host ""

$errors = 0
$warnings = 0

function Test-PathExists {
    param(
        [string]$Path,
        [string]$Description,
        [bool]$IsRequired = $true
    )
    
    if (Test-Path $Path) {
        Write-Host "[OK] $Description" -ForegroundColor Green
    } else {
        if ($IsRequired) {
            Write-Host "[ERROR] $Description - Missing!" -ForegroundColor Red
            $script:errors++
        } else {
            Write-Host "[WARNING] $Description - Missing (optional)" -ForegroundColor Yellow
            $script:warnings++
        }
    }
}

Write-Host "Checking Directory Structure..." -ForegroundColor Yellow
Write-Host ""

# Main directories
Test-PathExists "proxy" "Proxy directory"
Test-PathExists "main_server" "Main server directory"
Test-PathExists "worker" "Worker directory"
Test-PathExists "portal" "Portal directory"
Test-PathExists "client-scripts" "Client scripts directory"
Test-PathExists "monitoring" "Monitoring directory"
Test-PathExists "infra" "Infrastructure directory"

Write-Host ""
Write-Host "Checking Subdirectories..." -ForegroundColor Yellow
Write-Host ""

# Subdirectories
Test-PathExists "proxy/certs" "Proxy certificates directory"
Test-PathExists "main_server/certs" "Main server certificates directory"
Test-PathExists "main_server/crl" "Certificate revocation list directory"
Test-PathExists "worker/certs" "Worker certificates directory"
Test-PathExists "portal/templates" "Portal templates directory"
Test-PathExists "portal/static" "Portal static files directory"
Test-PathExists "monitoring/grafana" "Grafana directory"
Test-PathExists "monitoring/grafana/dashboards" "Grafana dashboards directory"
Test-PathExists "monitoring/grafana/datasources" "Grafana datasources directory"

Write-Host ""
Write-Host "Checking Configuration Files..." -ForegroundColor Yellow
Write-Host ""

# Configuration files
Test-PathExists "env.template" "Environment template file"
Test-PathExists ".gitignore" "Git ignore file"
Test-PathExists "proxy/config.yaml" "Proxy configuration"
Test-PathExists "worker/config.yaml" "Worker configuration"
Test-PathExists "monitoring/prometheus.yml" "Prometheus configuration"

Write-Host ""
Write-Host "Checking Requirements Files..." -ForegroundColor Yellow
Write-Host ""

# Requirements files
Test-PathExists "proxy/requirements.txt" "Proxy requirements"
Test-PathExists "main_server/requirements.txt" "Main server requirements"
Test-PathExists "worker/requirements.txt" "Worker requirements"
Test-PathExists "portal/requirements.txt" "Portal requirements"
Test-PathExists "client-scripts/requirements.txt" "Client scripts requirements"

Write-Host ""
Write-Host "Checking Documentation..." -ForegroundColor Yellow
Write-Host ""

# Documentation
Test-PathExists "README.md" "README file"
Test-PathExists "CONTRIBUTING.md" "Contributing guidelines"
Test-PathExists "CHANGELOG.md" "Changelog"
Test-PathExists "plan.md" "Project plan"
Test-PathExists "detail.md" "Project details"

Write-Host ""
Write-Host "Checking Scripts..." -ForegroundColor Yellow
Write-Host ""

# Scripts
Test-PathExists "client-scripts/send_message.py" "Client message sender script"
Test-PathExists "infra/setup_windows.ps1" "Windows setup script"
Test-PathExists "infra/backup.ps1" "Backup script"

Write-Host ""
Write-Host "Checking Optional Files..." -ForegroundColor Yellow
Write-Host ""

# Optional but recommended
Test-PathExists ".env" ".env file (created from template)" -IsRequired $false
Test-PathExists "venv" "Python virtual environment" -IsRequired $false
Test-PathExists "logs" "Logs directory" -IsRequired $false

Write-Host ""
Write-Host "Checking Git Repository..." -ForegroundColor Yellow
Write-Host ""

if (Test-Path ".git") {
    Write-Host "[OK] Git repository initialized" -ForegroundColor Green
    
    # Check for commits
    try {
        $commitCount = (git rev-list --count HEAD 2>$null)
        if ($commitCount -gt 0) {
            Write-Host "[OK] Initial commit present ($commitCount commits)" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] No commits found" -ForegroundColor Yellow
            $warnings++
        }
    } catch {
        Write-Host "[WARNING] Could not check commit history" -ForegroundColor Yellow
        $warnings++
    }
} else {
    Write-Host "[ERROR] Git repository not initialized!" -ForegroundColor Red
    $errors++
}

Write-Host ""
Write-Host "=== Verification Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Errors: $errors" -ForegroundColor White
Write-Host "Warnings: $warnings" -ForegroundColor White
Write-Host ""

if ([int]$errors -eq 0 -and [int]$warnings -eq 0) {
    Write-Host "SUCCESS: All checks passed! Phase 0 is complete." -ForegroundColor Green
    Write-Host ""
    exit 0
} elseif ([int]$errors -eq 0) {
    Write-Host "SUCCESS: Phase 0 Complete! All required items present." -ForegroundColor Green
    Write-Host "Note: $warnings warning(s) - some optional items missing (normal for Phase 0)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Optional items will be created during setup:" -ForegroundColor White
    Write-Host "  - .env (copy from env.template)" -ForegroundColor Gray
    Write-Host "  - venv (create with: python -m venv venv)" -ForegroundColor Gray
    Write-Host "  - logs (created automatically by services)" -ForegroundColor Gray
    Write-Host ""
    exit 0
} else {
    Write-Host "FAILURE: $errors error(s) found!" -ForegroundColor Red
    if ([int]$warnings -gt 0) {
        Write-Host "Also: $warnings warning(s)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Please ensure all required files and directories are present." -ForegroundColor Red
    Write-Host ""
    exit 1
}

