# PowerShell script to connect to Linux server
# Server details from image
param(
    [switch]$UsePlink,
    [switch]$Interactive
)

$serverIP = "91.92.206.217"
$serverPort = "2221"
$serverUser = "root"
$serverPassword = "Pc`$123456"  # Escaped $ for PowerShell

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Connecting to Linux Server" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server: $serverIP" -ForegroundColor Yellow
Write-Host "Port: $serverPort" -ForegroundColor Yellow
Write-Host "User: $serverUser" -ForegroundColor Yellow
Write-Host ""

# Check for available SSH tools
$plinkAvailable = Get-Command plink -ErrorAction SilentlyContinue
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue

# Determine which method to use
$usePlinkMethod = $false
if ($UsePlink -or (-not $Interactive)) {
    if ($plinkAvailable) {
        $usePlinkMethod = $true
        Write-Host "Using Plink (PuTTY) for automatic password authentication" -ForegroundColor Green
    } elseif ($sshAvailable) {
        Write-Host "Plink not found. Using standard SSH (will prompt for password)" -ForegroundColor Yellow
        Write-Host "Password: $serverPassword" -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: Neither Plink nor SSH found!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please install one of the following:" -ForegroundColor Yellow
        Write-Host "  1. PuTTY (includes plink.exe) - Recommended for automatic password entry" -ForegroundColor White
        Write-Host "     Download from: https://www.putty.org/" -ForegroundColor Gray
        Write-Host "  2. OpenSSH Client (Windows 10/11)" -ForegroundColor White
        Write-Host "     Settings > Apps > Optional Features > Add 'OpenSSH Client'" -ForegroundColor Gray
        exit 1
    }
} else {
    if ($sshAvailable) {
        Write-Host "Using standard SSH (interactive mode)" -ForegroundColor Green
        Write-Host "You will be prompted to enter the password: $serverPassword" -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: SSH command not found!" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# Connect using Plink (automatic password entry)
if ($usePlinkMethod) {
    Write-Host "Connecting via Plink..." -ForegroundColor Green
    Write-Host ""
    
    # Escape password for plink (plink handles $ differently)
    $escapedPassword = $serverPassword -replace '"', '"""'
    
    # Build plink arguments
    $plinkArgs = @(
        "-P", $serverPort,
        "-ssh",
        "-pw", $escapedPassword,
        "${serverUser}@${serverIP}"
    )
    
    # Execute plink
    & plink $plinkArgs
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "Connection ended with exit code: $exitCode" -ForegroundColor Yellow
    }
}
# Connect using standard SSH (interactive password entry)
elseif ($sshAvailable) {
    Write-Host "Connecting via SSH..." -ForegroundColor Green
    Write-Host ""
    
    # Standard SSH connection (will prompt for password)
    ssh -p $serverPort $serverUser@$serverIP
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "Connection ended with exit code: $exitCode" -ForegroundColor Yellow
    }
}

