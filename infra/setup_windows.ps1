# Windows Setup Script for Message Broker System
# Run this script as Administrator

param(
    [switch]$SkipChoco,
    [switch]$SkipMySQL,
    [switch]$SkipRedis
)

Write-Host "=== Message Broker System - Windows Setup ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

# Install Chocolatey if not present
if (-not $SkipChoco) {
    Write-Host "Checking Chocolatey installation..." -ForegroundColor Yellow
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Chocolatey..." -ForegroundColor Green
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    } else {
        Write-Host "Chocolatey already installed." -ForegroundColor Green
    }
}

# Install MySQL
if (-not $SkipMySQL) {
    Write-Host "`nInstalling MySQL..." -ForegroundColor Yellow
    choco install mysql -y
    Write-Host "MySQL installed. Please configure root password." -ForegroundColor Green
}

# Install Redis
if (-not $SkipRedis) {
    Write-Host "`nInstalling Redis..." -ForegroundColor Yellow
    choco install redis-64 -y
    redis-server --service-install
    redis-server --service-start
    Write-Host "Redis installed and started as service." -ForegroundColor Green
}

# Install OpenSSL
Write-Host "`nInstalling OpenSSL..." -ForegroundColor Yellow
choco install openssl -y

# Create Python virtual environment
Write-Host "`nCreating Python virtual environment..." -ForegroundColor Yellow
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (Test-Path "venv") {
    Write-Host "Virtual environment already exists." -ForegroundColor Green
} else {
    python -m venv venv
    Write-Host "Virtual environment created." -ForegroundColor Green
}

# Activate virtual environment and install dependencies
Write-Host "`nInstalling Python dependencies..." -ForegroundColor Yellow
& "$projectRoot\venv\Scripts\Activate.ps1"
pip install --upgrade pip

pip install -r proxy/requirements.txt
pip install -r main_server/requirements.txt
pip install -r worker/requirements.txt
pip install -r portal/requirements.txt
pip install -r client-scripts/requirements.txt

Write-Host "Python dependencies installed." -ForegroundColor Green

# Create .env from template
Write-Host "`nSetting up environment configuration..." -ForegroundColor Yellow
if (-not (Test-Path ".env")) {
    Copy-Item "env.template" ".env"
    Write-Host "Created .env file from template. Please edit with your configuration." -ForegroundColor Yellow
} else {
    Write-Host ".env file already exists." -ForegroundColor Green
}

# Create secrets directory
Write-Host "`nCreating secrets directory..." -ForegroundColor Yellow
$secretsPath = "C:\app_secrets"
if (-not (Test-Path $secretsPath)) {
    New-Item -ItemType Directory -Path $secretsPath -Force | Out-Null
    
    # Set permissions (Administrators only)
    $acl = Get-Acl $secretsPath
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
    
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($adminRule)
    Set-Acl $secretsPath $acl
    
    Write-Host "Secrets directory created at $secretsPath" -ForegroundColor Green
} else {
    Write-Host "Secrets directory already exists." -ForegroundColor Green
}

# Generate AES key
Write-Host "`nGenerating AES encryption key..." -ForegroundColor Yellow
$aesKeyPath = "$secretsPath\aes.key"
if (-not (Test-Path $aesKeyPath)) {
    python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | Out-File -FilePath $aesKeyPath -Encoding ASCII -NoNewline
    Write-Host "AES key generated at $aesKeyPath" -ForegroundColor Green
} else {
    Write-Host "AES key already exists." -ForegroundColor Green
}

# Create logs directory
Write-Host "`nCreating logs directory..." -ForegroundColor Yellow
if (-not (Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    Write-Host "Logs directory created." -ForegroundColor Green
} else {
    Write-Host "Logs directory already exists." -ForegroundColor Green
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Configure MySQL database (see README.md)" -ForegroundColor White
Write-Host "2. Edit .env file with your configuration" -ForegroundColor White
Write-Host "3. Generate certificates (see README.md)" -ForegroundColor White
Write-Host "4. Run database migrations" -ForegroundColor White
Write-Host "5. Start the services" -ForegroundColor White
Write-Host ""

