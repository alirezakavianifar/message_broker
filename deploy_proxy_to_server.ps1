# PowerShell Script to Deploy Proxy Service to Proxy Server
# Usage: .\deploy_proxy_to_server.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$Password = "Pc`$123456",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTransfer = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipServices = $false
)

$ErrorActionPreference = "Stop"

# Proxy server details
$ServerIP = "91.92.206.217"
$SSHPort = 2221
$Username = "root"
$RemotePath = "/opt/message_broker_proxy"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  PROXY SERVICE - DEPLOYMENT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[INFO] Proxy Server: ${ServerIP}:${SSHPort}" -ForegroundColor Gray
Write-Host "[INFO] User: $Username" -ForegroundColor Gray
Write-Host "[INFO] Remote Path: $RemotePath" -ForegroundColor Gray
Write-Host "[INFO] Main Server URL: https://173.32.115.223:8000" -ForegroundColor Gray
Write-Host ""

# Check if SSH/SCP are available
$scpAvailable = Get-Command scp -ErrorAction SilentlyContinue
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue
$plinkAvailable = Get-Command plink -ErrorAction SilentlyContinue

if (-not $scpAvailable -or -not $sshAvailable) {
    Write-Host "[ERROR] SSH/SCP not found. Please install OpenSSH client." -ForegroundColor Red
    Write-Host "Install with: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor Yellow
    exit 1
}

# Check for plink (PuTTY) first - it's more reliable on Windows
$usePlink = $false
$useSshpass = $false
$useInteractivePassword = $false

if ($plinkAvailable) {
    $usePlink = $true
    Write-Host "[INFO] Using plink (PuTTY) for automatic password authentication" -ForegroundColor Green
} else {
    # Check for sshpass (usually available via WSL)
    $wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wslAvailable) {
        try {
            $wslTest = wsl echo "test" 2>&1 | Out-String
            if ($wslTest -eq "test`r`n" -or ($wslTest -notmatch "no installed distributions" -and $wslTest -match "test")) {
                $sshpassCheck = wsl which sshpass 2>&1 | Out-String
                if ($sshpassCheck -and $sshpassCheck -notmatch "not found" -and $sshpassCheck -notmatch "no installed distributions") {
                    $useSshpass = $true
                    Write-Host "[INFO] Using sshpass (via WSL) for automatic password authentication" -ForegroundColor Green
                }
            }
        } catch {
            # WSL not working
        }
    }
    
    if ($Password -and -not $usePlink -and -not $useSshpass) {
        Write-Host "[WARN] Neither plink (PuTTY) nor sshpass (WSL) found." -ForegroundColor Yellow
        Write-Host "[INFO] Install PuTTY (includes plink.exe) for automatic password entry:" -ForegroundColor Yellow
        Write-Host "       Download from: https://www.putty.org/" -ForegroundColor White
        Write-Host "[INFO] Password will need to be entered manually during SSH/SCP operations." -ForegroundColor Yellow
        $useInteractivePassword = $true
    }
}

# Build SSH connection string
$sshHost = "${Username}@${ServerIP}"
$sshOptions = "-p ${SSHPort} -o StrictHostKeyChecking=no -o UserKnownHostsFile=`"$env:TEMP\known_hosts_temp`""

# Initialize host key acceptance flag
$script:hostKeyAccepted = $false

# Helper function to execute SSH commands with automatic password entry
function Invoke-SSHCommand {
    param(
        [string]$Command,
        [switch]$NoWait,
        [switch]$Verbose
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    if ($Verbose) {
        Write-Host "[$timestamp] [SSH] Executing: $Command" -ForegroundColor Cyan
    }
    
    if ($useSshpass -and $Password) {
        $escapedPassword = $Password -replace '"', '\"' -replace '\$', '\$' -replace '`', '\`'
        $wslCommand = "sshpass -p '$escapedPassword' ssh -p $SSHPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${Username}@${ServerIP} '$Command'"
        if ($NoWait) {
            Start-Process wsl -ArgumentList $wslCommand -NoNewWindow -PassThru
        } else {
            $output = wsl bash -c $wslCommand 2>&1
            if ($output -match "no installed distributions") {
                Write-Host "[$timestamp] [WARN] WSL not available, falling back to plink..." -ForegroundColor Yellow
                $useSshpass = $false
                $usePlink = $true
            } else {
                if ($Verbose) {
                    $output | ForEach-Object { Write-Host "[$timestamp] [REMOTE] $_" -ForegroundColor Gray }
                }
                return $output
            }
        }
    }
    
    if ($usePlink -and $Password) {
        $escapedPassword = $Password -replace '"', '"""'
        $plinkArgs = @("-P", $SSHPort, "-ssh", "-batch", "-pw", $escapedPassword)
        
        if (-not $script:hostKeyAccepted) {
            Write-Host "[$timestamp] [INFO] Caching SSH host key (first connection)..." -ForegroundColor Gray
            $firstTryArgs = @("-P", $SSHPort, "-ssh", "-pw", $escapedPassword, "${Username}@${ServerIP}", "echo 'ok'")
            $firstOutput = & plink $firstTryArgs 2>&1
            if ($LASTEXITCODE -eq 0 -or $firstOutput -notmatch "host key") {
                $script:hostKeyAccepted = $true
            }
        }
        
        $plinkArgs += @("${Username}@${ServerIP}", $Command)
        
        if ($NoWait) {
            Start-Process plink -ArgumentList $plinkArgs -NoNewWindow -PassThru
        } else {
            $output = & plink $plinkArgs 2>&1
            if ($Verbose) {
                $output | ForEach-Object { Write-Host "[$timestamp] [REMOTE] $_" -ForegroundColor Gray }
            }
            return $output
        }
    } else {
        $sshArgs = $sshOptions -split ' '
        if ($useInteractivePassword) {
            Write-Host "[$timestamp] [INFO] Enter password when prompted: $Password" -ForegroundColor Yellow
        }
        if ($NoWait) {
            Start-Process ssh -ArgumentList ($sshArgs + $sshHost + $Command) -NoNewWindow -PassThru
        } else {
            $output = & ssh $sshArgs $sshHost $Command 2>&1
            if ($Verbose) {
                $output | ForEach-Object { Write-Host "[$timestamp] [REMOTE] $_" -ForegroundColor Gray }
            }
            return $output
        }
    }
}

# Helper function to execute SCP commands with automatic password entry
function Invoke-SCPCommand {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$Verbose
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    if ($Verbose) {
        Write-Host "[$timestamp] [SCP] Transferring: $Source -> ${Username}@${ServerIP}:$Destination" -ForegroundColor Cyan
    }
    
    if ($useSshpass -and $Password) {
        $escapedPassword = $Password -replace '"', '\"' -replace '\$', '\$' -replace '`', '\`'
        $wslCommand = "sshpass -p '$escapedPassword' scp -P $SSHPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null '$Source' ${Username}@${ServerIP}:$Destination"
        $output = wsl bash -c $wslCommand 2>&1
        if ($output -match "no installed distributions") {
            Write-Host "[$timestamp] [WARN] WSL not available, falling back to plink..." -ForegroundColor Yellow
            $useSshpass = $false
            $usePlink = $true
        } else {
            if ($Verbose -and $output) {
                $output | ForEach-Object { Write-Host "[$timestamp] [SCP] $_" -ForegroundColor Gray }
            }
            return $output
        }
    }
    
    if ($usePlink -and $Password) {
        $pscpAvailable = Get-Command pscp -ErrorAction SilentlyContinue
        if ($pscpAvailable) {
            $escapedPassword = $Password -replace '"', '"""'
            
            if (-not $script:hostKeyAccepted) {
                $firstTryArgs = @("-P", $SSHPort, "-ssh", "-pw", $escapedPassword, "${Username}@${ServerIP}", "echo 'ok'")
                & plink $firstTryArgs 2>&1 | Out-Null
                $script:hostKeyAccepted = $true
            }
            
            $pscpArgs = @("-P", $SSHPort, "-batch", "-pw", $escapedPassword, $Source, "${Username}@${ServerIP}:$Destination")
            $output = & pscp $pscpArgs 2>&1
            if ($Verbose -and $output) {
                $output | ForEach-Object { Write-Host "[$timestamp] [SCP] $_" -ForegroundColor Gray }
            }
            return $output
        } else {
            Write-Host "[ERROR] pscp (PuTTY SCP) not found. Please install PuTTY." -ForegroundColor Red
            throw "pscp not available"
        }
    } else {
        $scpArgs = @("-P", $SSHPort, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=$env:TEMP\known_hosts_temp")
        if ($useInteractivePassword) {
            Write-Host "[$timestamp] [INFO] Enter password when prompted: $Password" -ForegroundColor Yellow
        }
        $output = & scp $scpArgs $Source "${sshHost}:$Destination" 2>&1
        if ($Verbose -and $output) {
            $output | ForEach-Object { Write-Host "[$timestamp] [SCP] $_" -ForegroundColor Gray }
        }
        return $output
    }
}

# Test SSH connection
Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Testing SSH connection..." -ForegroundColor Yellow
try {
    $testResult = Invoke-SSHCommand -Command "echo 'Connection successful'; hostname; uname -a" -Verbose
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0 -or ($testResult -match "Connection successful")) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] SSH connection successful" -ForegroundColor Green
        if ($testResult) {
            $testResult | Where-Object { $_ -notmatch "Permanently added" } | ForEach-Object {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [SERVER INFO] $_" -ForegroundColor DarkGray
            }
        }
    } else {
        if ($testResult -match "Connection refused" -or $testResult -match "Could not resolve" -or $testResult -match "Permission denied") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Cannot connect to server:" -ForegroundColor Red
            Write-Host $testResult -ForegroundColor Yellow
            exit 1
        }
    }
} catch {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] SSH connection failed: $_" -ForegroundColor Red
    exit 1
}

# Step 1: Transfer proxy files
if (-not $SkipTransfer) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  STEP 1: TRANSFER PROXY FILES" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $ProjectRoot = $PSScriptRoot
    $ProxyDir = Join-Path $ProjectRoot "proxy"
    
    if (-not (Test-Path $ProxyDir)) {
        Write-Host "[ERROR] Proxy directory not found: $ProxyDir" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Creating archive of proxy files..." -ForegroundColor Yellow
    
    # Create temporary directory for archive
    $tempDir = Join-Path $env:TEMP "proxy_deploy_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    # Copy proxy files (excluding unnecessary files)
    Write-Host "Copying proxy files to temporary directory..." -ForegroundColor Yellow
    $excludeDirs = @("__pycache__", "logs", "*.log")
    $excludeFiles = @("*.pyc", "*.log")
    
    Get-ChildItem -Path $ProxyDir -Recurse | Where-Object {
        $item = $_
        $relativePath = $item.FullName.Substring($ProxyDir.Length + 1)
        
        $skip = $false
        foreach ($excludeDir in $excludeDirs) {
            if ($relativePath -like "$excludeDir*" -or $relativePath -like "*\$excludeDir\*") {
                $skip = $true
                break
            }
        }
        
        if (-not $skip) {
            foreach ($excludeFile in $excludeFiles) {
                if ($item.Name -like $excludeFile) {
                    $skip = $true
                    break
                }
            }
        }
        
        -not $skip
    } | ForEach-Object {
        $relativePath = $_.FullName.Substring($ProxyDir.Length + 1)
        $destPath = Join-Path $tempDir $relativePath
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        if (-not $_.PSIsContainer) {
            Copy-Item $_.FullName -Destination $destPath -Force
        }
    }
    
    # Also copy deploy_proxy.sh if it exists
    $deployScript = Join-Path $ProxyDir "deploy_proxy.sh"
    if (Test-Path $deployScript) {
        Copy-Item $deployScript -Destination (Join-Path $tempDir "deploy_proxy.sh") -Force
    }
    
    Write-Host "[OK] Files prepared for transfer" -ForegroundColor Green
    
    # Create tar archive
    $archiveName = "proxy_service.tar.gz"
    $archivePath = Join-Path $env:TEMP $archiveName
    
    Write-Host "Creating compressed archive..." -ForegroundColor Yellow
    
    $tarAvailable = Get-Command tar -ErrorAction SilentlyContinue
    $archiveCreated = $false
    
    if ($tarAvailable) {
        try {
            Push-Location $tempDir
            & tar -czf $archivePath * 2>&1 | Out-Null
            Pop-Location
            if (Test-Path $archivePath) {
                $archiveCreated = $true
            }
        } catch {
            Write-Host "[WARN] tar command failed, trying alternatives..." -ForegroundColor Yellow
        }
    }
    
    if (-not $archiveCreated) {
        if (Get-Command 7z -ErrorAction SilentlyContinue) {
            Write-Host "Using 7zip instead..." -ForegroundColor Yellow
            Push-Location $tempDir
            & 7z a -tgzip "$archivePath" * | Out-Null
            Pop-Location
            if (Test-Path $archivePath) {
                $archiveCreated = $true
            }
        }
    }
    
    if (-not $archiveCreated) {
        Write-Host "Using PowerShell Compress-Archive..." -ForegroundColor Yellow
        $zipPath = $archivePath -replace '\.tar\.gz$', '.zip'
        Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
        if (Test-Path $zipPath) {
            $archivePath = $zipPath
            $archiveName = Split-Path $zipPath -Leaf
            $archiveCreated = $true
        }
    }
    
    if (-not $archiveCreated) {
        Write-Host "[ERROR] Cannot create archive. Please install tar (Windows 10 1803+) or 7zip." -ForegroundColor Red
        Remove-Item $tempDir -Recurse -Force
        exit 1
    }
    
    Write-Host "[OK] Archive created: $archivePath" -ForegroundColor Green
    
    # Transfer archive to server
    Write-Host "`nTransferring files to server..." -ForegroundColor Yellow
    $archiveNameOnServer = Split-Path $archivePath -Leaf
    $remoteArchivePath = "/tmp/$archiveNameOnServer"
    
    try {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting file transfer..." -ForegroundColor Yellow
        $fileSize = (Get-Item $archivePath).Length / 1MB
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Archive size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
        
        Invoke-SCPCommand -Source $archivePath -Destination $remoteArchivePath -Verbose
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] Files transferred successfully" -ForegroundColor Green
    } catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] File transfer failed: $_" -ForegroundColor Red
        Remove-Item $tempDir -Recurse -Force
        Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
        exit 1
    }
    
    # Clean up local temp directory
    Remove-Item $tempDir -Recurse -Force
    Write-Host "[OK] Local temporary files cleaned up" -ForegroundColor Green
} else {
    Write-Host "`n[INFO] Skipping file transfer (SkipTransfer=true)" -ForegroundColor Yellow
    $archiveNameOnServer = "proxy_service.tar.gz"
    $remoteArchivePath = "/tmp/$archiveNameOnServer"
}

# Step 2: Execute remote deployment script
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STEP 2: EXECUTE REMOTE DEPLOYMENT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Transfer deployment script if it exists locally
$localDeployScript = Join-Path $PSScriptRoot "proxy\deploy_proxy.sh"
$remoteScriptPath = "/tmp/deploy_proxy.sh"

if (Test-Path $localDeployScript) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Transferring deployment script..." -ForegroundColor Yellow
    try {
        Invoke-SCPCommand -Source $localDeployScript -Destination $remoteScriptPath -Verbose
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] Deployment script transferred" -ForegroundColor Green
    } catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Failed to transfer deployment script: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[WARN] Local deployment script not found, will create on server" -ForegroundColor Yellow
}

# Make script executable and run it
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Executing remote deployment script..." -ForegroundColor Yellow

$isRoot = Invoke-SSHCommand -Command "whoami" 2>&1
$useSudo = $true
if ($isRoot -match "root") {
    $useSudo = $false
    Write-Host "[INFO] Running as root - skipping sudo" -ForegroundColor Gray
}

$envCmd = ""
if ($SkipServices) {
    $envCmd += "SKIP_SERVICES=true "
}
$envCmd += "ARCHIVE_NAME_ON_SERVER=$archiveNameOnServer "
$envCmd += "REMOTE_PATH=$RemotePath "
$envCmd += "MAIN_SERVER_URL=https://173.32.115.223:8000 "

$sudoPrefix = if ($useSudo) { "sudo " } else { "" }
$remoteCommand = "${sudoPrefix}$envCmd bash $remoteScriptPath 2>&1 | tee /tmp/proxy_deploy_output.log"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] This will take several minutes. Output will stream in real-time..." -ForegroundColor Gray
Write-Host ""

try {
    $sshResult = Invoke-SSHCommand -Command $remoteCommand -Verbose
    
    # Fetch the log file for complete output
    Write-Host ""
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Fetching deployment log..." -ForegroundColor Yellow
    $logContent = Invoke-SSHCommand -Command "cat /tmp/proxy_deploy_output.log" 2>&1
    
    if ($logContent) {
        Write-Host "`n=== DEPLOYMENT LOG ===" -ForegroundColor Cyan
        $logContent | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        Write-Host "=== END LOG ===" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] Deployment completed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Check service status: ssh -p $SSHPort $Username@${ServerIP} 'systemctl status proxy'" -ForegroundColor White
    Write-Host "  2. Check logs: ssh -p $SSHPort $Username@${ServerIP} 'journalctl -u proxy -f'" -ForegroundColor White
    Write-Host "  3. Test endpoint: curl -k https://${ServerIP}:8001/health" -ForegroundColor White
    
} catch {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Deployment failed: $_" -ForegroundColor Red
    Write-Host "[INFO] Check /tmp/proxy_deploy_output.log on the server for details" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Deployment script completed!" -ForegroundColor Green

