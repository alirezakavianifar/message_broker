# Quick script to accept PuTTY host key for the server
# Run this once before deployment to cache the host key

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerIP,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [int]$SSHPort = 2223,
    
    [Parameter(Mandatory=$false)]
    [string]$Password = ""
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ACCEPT HOST KEY" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Accepting host key for $Username@${ServerIP}:$SSHPort" -ForegroundColor Yellow
Write-Host "When prompted, type 'y' and press Enter to accept the host key" -ForegroundColor Yellow
Write-Host ""

$plinkAvailable = Get-Command plink -ErrorAction SilentlyContinue
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue

if ($plinkAvailable) {
    if ($Password) {
        Write-Host "Using plink with password authentication..." -ForegroundColor Gray
        # Escape password properly for plink
        $escapedPassword = $Password -replace '\$', '`$'
        $plinkArgs = @("-P", $SSHPort, "-ssh", "-pw", $escapedPassword, "${Username}@${ServerIP}", "exit")
        & plink $plinkArgs
    } else {
        Write-Host "Using plink (you'll be prompted for password)..." -ForegroundColor Gray
        $plinkArgs = @("-P", $SSHPort, "-ssh", "${Username}@${ServerIP}", "exit")
        & plink $plinkArgs
    }
} elseif ($sshAvailable) {
    Write-Host "Using ssh (you'll be prompted for password)..." -ForegroundColor Gray
    $sshArgs = @("-p", $SSHPort, "${Username}@${ServerIP}", "exit")
    & ssh $sshArgs
} else {
    Write-Host "[ERROR] Neither plink nor ssh found!" -ForegroundColor Red
    exit 1
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[OK] Host key accepted! You can now run the deployment script." -ForegroundColor Green
} else {
    Write-Host "`n[WARN] Exit code: $LASTEXITCODE" -ForegroundColor Yellow
    Write-Host "If you accepted the host key (typed 'y'), you can proceed with deployment." -ForegroundColor Yellow
}

