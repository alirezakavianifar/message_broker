# Check Prerequisites for Deployment
# This script checks if required tools are available

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CHECKING DEPLOYMENT PREREQUISITES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$allGood = $true

# Check for plink (PuTTY)
Write-Host "Checking for plink (PuTTY)..." -ForegroundColor Yellow
$plinkAvailable = Get-Command plink -ErrorAction SilentlyContinue
if ($plinkAvailable) {
    $plinkVersion = & plink -V 2>&1 | Select-Object -First 1
    Write-Host "[OK] plink found: $plinkVersion" -ForegroundColor Green
} else {
    Write-Host "[MISSING] plink (PuTTY) not found" -ForegroundColor Red
    Write-Host "  Download PuTTY from: https://www.putty.org/" -ForegroundColor White
    Write-Host "  Or install via Chocolatey: choco install putty" -ForegroundColor White
    Write-Host "  Or install via winget: winget install PuTTY.PuTTY" -ForegroundColor White
    $allGood = $false
}

# Check for WSL and sshpass (optional)
Write-Host "`nChecking for WSL and sshpass (optional)..." -ForegroundColor Yellow
$wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslAvailable) {
    try {
        $wslTest = wsl echo "test" 2>&1 | Out-String
        if ($wslTest -match "no installed distributions") {
            Write-Host "[INFO] WSL command exists but no distribution installed" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] WSL is available" -ForegroundColor Green
            $sshpassCheck = wsl which sshpass 2>&1 | Out-String
            if ($sshpassCheck -and $sshpassCheck -notmatch "not found" -and $sshpassCheck -notmatch "no installed distributions") {
                Write-Host "[OK] sshpass is available via WSL" -ForegroundColor Green
            } else {
                Write-Host "[INFO] sshpass not installed in WSL (optional)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "[INFO] WSL not working (optional)" -ForegroundColor Gray
    }
} else {
    Write-Host "[INFO] WSL not installed (optional)" -ForegroundColor Gray
}

# Check for SSH/SCP (Windows 10+)
Write-Host "`nChecking for SSH/SCP (Windows built-in)..." -ForegroundColor Yellow
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue
$scpAvailable = Get-Command scp -ErrorAction SilentlyContinue
if ($sshAvailable -and $scpAvailable) {
    Write-Host "[OK] SSH and SCP are available" -ForegroundColor Green
} else {
    Write-Host "[WARN] SSH/SCP not found" -ForegroundColor Yellow
    Write-Host "  Install OpenSSH: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor White
}

# Check for tar (for creating archives)
Write-Host "`nChecking for tar (for creating archives)..." -ForegroundColor Yellow
$tarAvailable = Get-Command tar -ErrorAction SilentlyContinue
if ($tarAvailable) {
    Write-Host "[OK] tar is available" -ForegroundColor Green
} else {
    Write-Host "[WARN] tar not found (will try alternatives)" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($allGood) {
    Write-Host "  ALL REQUIRED TOOLS AVAILABLE!" -ForegroundColor Green
    Write-Host "  You can proceed with deployment." -ForegroundColor Green
} else {
    Write-Host "  SOME TOOLS MISSING" -ForegroundColor Yellow
    Write-Host "  Please install missing tools before deployment." -ForegroundColor Yellow
}
Write-Host "========================================`n" -ForegroundColor Cyan

if (-not $allGood) {
    Write-Host "Quick install options:" -ForegroundColor Yellow
    Write-Host "  1. Install PuTTY (recommended):" -ForegroundColor White
    Write-Host "     winget install PuTTY.PuTTY" -ForegroundColor Cyan
    Write-Host "     OR download from: https://www.putty.org/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Or install WSL with sshpass:" -ForegroundColor White
    Write-Host "     wsl --install" -ForegroundColor Cyan
    Write-Host "     Then in WSL: sudo apt-get install sshpass" -ForegroundColor Cyan
    Write-Host ""
}

exit $(if ($allGood) { 0 } else { 1 })

