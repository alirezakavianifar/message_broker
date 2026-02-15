# Quick Deployment Script for Message Broker
# This script deploys to the specified server with automatic password entry

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP = "173.32.115.223",
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "root",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "Abbas`$12345",
    
    [Parameter(Mandatory=$false)]
    [int]$SSHPort = 2222
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MESSAGE BROKER - QUICK DEPLOYMENT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Server: $($ServerIP):$SSHPort" -ForegroundColor White
Write-Host "  User: $Username" -ForegroundColor White
Write-Host "  Password: [HIDDEN]" -ForegroundColor White
Write-Host ""

# Check if deploy_to_linux.ps1 exists
if (-not (Test-Path "deploy_to_linux.ps1")) {
    Write-Host "[ERROR] deploy_to_linux.ps1 not found!" -ForegroundColor Red
    Write-Host "Please run this script from the project root directory." -ForegroundColor Yellow
    exit 1
}

# Run the deployment script
Write-Host "Starting deployment..." -ForegroundColor Green
Write-Host ""

& .\deploy_to_linux.ps1 -ServerIP $ServerIP -Username $Username -Password $Password -SSHPort $SSHPort

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "Starting services on remote server..." -ForegroundColor Yellow
    $startCommand = "sudo systemctl start main_server proxy worker portal && echo 'Services started' && sudo systemctl status main_server --no-pager -l | head -10"
    
    # Use the same authentication method
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $wslCheck = wsl which sshpass 2>$null
        if ($wslCheck -and $wslCheck -notmatch "not found") {
            $escapedPassword = $Password -replace '"', '\"' -replace '\$', '\$' -replace '`', '\`'
            wsl bash -c "sshpass -p '$escapedPassword' ssh -p $SSHPort -o StrictHostKeyChecking=no ${Username}@${ServerIP} '$startCommand'"
        }
    } elseif (Get-Command plink -ErrorAction SilentlyContinue) {
        $escapedPassword = $Password -replace '"', '"""'
        & plink -P $SSHPort -ssh -batch -pw $escapedPassword "${Username}@${ServerIP}" $startCommand
    } else {
        Write-Host "[INFO] Please manually start services:" -ForegroundColor Yellow
        Write-Host "  ssh -p $SSHPort $Username@$ServerIP 'sudo systemctl start main_server proxy worker portal'" -ForegroundColor White
    }
    
    Write-Host "`nService URLs:" -ForegroundColor Yellow
    Write-Host "  Main Server API:  https://$($ServerIP):8000/docs" -ForegroundColor White
    Write-Host "  Proxy API:        https://$($ServerIP):8001/api/v1/docs" -ForegroundColor White
    Write-Host "  Web Portal:       http://$($ServerIP):8080" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "`n[ERROR] Deployment failed. Check the output above for details." -ForegroundColor Red
    exit 1
}

