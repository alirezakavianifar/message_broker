# Interactive Deployment Helper Script
# This script helps you run the deployment with proper input

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MESSAGE BROKER - DEPLOYMENT HELPER" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if deployment script exists
if (-not (Test-Path "deploy_to_linux.ps1")) {
    Write-Host "[ERROR] deploy_to_linux.ps1 not found!" -ForegroundColor Red
    Write-Host "Please make sure you're in the project root directory." -ForegroundColor Yellow
    exit 1
}

Write-Host "This script will help you deploy to your Linux server." -ForegroundColor Yellow
Write-Host "You'll need:" -ForegroundColor Yellow
Write-Host "  1. Server IP address" -ForegroundColor White
Write-Host "  2. SSH username" -ForegroundColor White
Write-Host "  3. SSH port (default: 2223)" -ForegroundColor White
Write-Host "  4. Optional: SSH private key path`n" -ForegroundColor White

# Get server IP
$serverIP = Read-Host "Enter server IP address"
if ([string]::IsNullOrWhiteSpace($serverIP)) {
    Write-Host "[ERROR] Server IP is required!" -ForegroundColor Red
    exit 1
}

# Get username
$username = Read-Host "Enter SSH username (e.g., ubuntu, root, admin)"
if ([string]::IsNullOrWhiteSpace($username)) {
    Write-Host "[ERROR] Username is required!" -ForegroundColor Red
    exit 1
}

# Get SSH port
$sshPortInput = Read-Host "Enter SSH port [2223]"
if ([string]::IsNullOrWhiteSpace($sshPortInput)) {
    $sshPort = 2223
} else {
    if (-not [int]::TryParse($sshPortInput, [ref]$sshPort)) {
        Write-Host "[WARN] Invalid port, using default 2223" -ForegroundColor Yellow
        $sshPort = 2223
    }
}

# Get SSH key or password
$useKey = Read-Host "Do you want to use SSH key authentication? (y/n) [n]"
$sshKey = ""
$password = ""

if ($useKey -eq "y" -or $useKey -eq "Y" -or $useKey -eq "yes") {
    $sshKeyPath = Read-Host "Enter path to SSH private key"
    if (-not [string]::IsNullOrWhiteSpace($sshKeyPath)) {
        if (Test-Path $sshKeyPath) {
            $sshKey = $sshKeyPath
        } else {
            Write-Host "[WARN] SSH key file not found: $sshKeyPath" -ForegroundColor Yellow
            Write-Host "       Will use password authentication instead" -ForegroundColor Yellow
        }
    }
} else {
    # Prompt for password securely
    $securePassword = Read-Host "Enter SSH password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

# Build command
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT PARAMETERS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Server IP:    $serverIP" -ForegroundColor White
Write-Host "Username:     $username" -ForegroundColor White
Write-Host "SSH Port:     $sshPort" -ForegroundColor White
if ($sshKey) {
    Write-Host "SSH Key:      $sshKey" -ForegroundColor White
} else {
    Write-Host "SSH Key:      (password authentication)" -ForegroundColor Gray
}
Write-Host ""

$confirm = Read-Host "Proceed with deployment? (y/n) [y]"
if ($confirm -eq "n" -or $confirm -eq "N" -or $confirm -eq "no") {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
}

# Build deployment command
$deployCmd = ".\deploy_to_linux.ps1 -ServerIP `"$serverIP`" -Username `"$username`" -SSHPort $sshPort"
if ($sshKey) {
    $deployCmd += " -SSHKey `"$sshKey`""
} elseif ($password) {
    $deployCmd += " -Password `"$password`""
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  STARTING DEPLOYMENT" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
Write-Host "Command: $deployCmd`n" -ForegroundColor Gray

# Run deployment
try {
    Invoke-Expression $deployCmd
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT SCRIPT COMPLETED" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
} catch {
    Write-Host "`n[ERROR] Deployment failed: $_" -ForegroundColor Red
    Write-Host "Please check the error messages above." -ForegroundColor Yellow
    exit 1
}

