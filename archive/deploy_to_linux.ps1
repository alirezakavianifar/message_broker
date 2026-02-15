# PowerShell Script to Deploy Message Broker to Linux Server
# Usage: .\deploy_to_linux.ps1 -ServerIP <IP> -Username <username> [-SSHKey <path>]

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerIP,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$SSHKey = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "",
    
    [Parameter(Mandatory=$false)]
    [int]$SSHPort = 2223,
    
    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "/opt/message_broker",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTransfer = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipServices = $false
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MESSAGE BROKER - LINUX DEPLOYMENT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if SSH/SCP are available
$scpAvailable = Get-Command scp -ErrorAction SilentlyContinue
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue
$plinkAvailable = Get-Command plink -ErrorAction SilentlyContinue

if (-not $scpAvailable -or -not $sshAvailable) {
    Write-Host "[ERROR] SSH/SCP not found. Please install OpenSSH client." -ForegroundColor Red
    Write-Host "Install with: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor Yellow
    exit 1
}

# Check for sshpass (via WSL) or plink for automatic password entry
$usePlink = $false
$useSshpass = $false
$useInteractivePassword = $false

# Check for plink (PuTTY) first - it's more reliable on Windows
$plinkAvailable = Get-Command plink -ErrorAction SilentlyContinue
if ($plinkAvailable) {
    $usePlink = $true
    Write-Host "[INFO] Using plink (PuTTY) for automatic password authentication" -ForegroundColor Green
} else {
    # Check for sshpass (usually available via WSL) - but verify WSL is actually working
    $wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wslAvailable) {
        try {
            # Test if WSL is actually installed and working
            $wslTest = wsl echo "test" 2>&1 | Out-String
            if ($wslTest -eq "test`r`n" -or ($wslTest -notmatch "no installed distributions" -and $wslTest -match "test")) {
                # WSL is working, check for sshpass
                $sshpassCheck = wsl which sshpass 2>&1 | Out-String
                if ($sshpassCheck -and $sshpassCheck -notmatch "not found" -and $sshpassCheck -notmatch "no installed distributions") {
                    $useSshpass = $true
                    $usePlink = $false
                    Write-Host "[INFO] Using sshpass (via WSL) for automatic password authentication" -ForegroundColor Green
                }
            }
        } catch {
            # WSL not working, will use plink if available
        }
    }
    
    # If neither plink nor sshpass available, show warning
    if ($Password -and -not $SSHKey -and -not $usePlink -and -not $useSshpass) {
        Write-Host "[WARN] Neither plink (PuTTY) nor sshpass (WSL) found." -ForegroundColor Yellow
        Write-Host "[INFO] Install PuTTY (includes plink.exe) for automatic password entry:" -ForegroundColor Yellow
        Write-Host "       Download from: https://www.putty.org/" -ForegroundColor White
        Write-Host "       Or install WSL with sshpass for automatic password entry." -ForegroundColor Yellow
        Write-Host "[INFO] Password will need to be entered manually during SSH/SCP operations." -ForegroundColor Yellow
        $useInteractivePassword = $true
    }
}

# Build SSH connection string
$sshHost = "${Username}@${ServerIP}"
$sshOptions = "-p ${SSHPort} -o StrictHostKeyChecking=no -o UserKnownHostsFile=`"$env:TEMP\known_hosts_temp`""

if ($SSHKey) {
    if (Test-Path $SSHKey) {
        $sshOptions += " -i `"$SSHKey`""
    } else {
        Write-Host "[WARN] SSH key file not found: $SSHKey" -ForegroundColor Yellow
        Write-Host "       Will use password authentication" -ForegroundColor Yellow
    }
}

Write-Host "[INFO] Server: ${ServerIP}:${SSHPort}" -ForegroundColor Gray
Write-Host "[INFO] User: $Username" -ForegroundColor Gray
Write-Host "[INFO] Remote Path: $RemotePath" -ForegroundColor Gray
if ($Password -and -not $SSHKey) {
    Write-Host "[INFO] Authentication: Password (provided)" -ForegroundColor Gray
} elseif ($SSHKey) {
    Write-Host "[INFO] Authentication: SSH Key" -ForegroundColor Gray
} else {
    Write-Host "[INFO] Authentication: Interactive password prompt" -ForegroundColor Yellow
}
Write-Host ""

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
        # Use sshpass via WSL for automatic password entry
        $escapedPassword = $Password -replace '"', '\"' -replace '\$', '\$' -replace '`', '\`'
        $wslCommand = "sshpass -p '$escapedPassword' ssh -p $SSHPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${Username}@${ServerIP} '$Command'"
        if ($NoWait) {
            Start-Process wsl -ArgumentList $wslCommand -NoNewWindow -PassThru
        } else {
            $output = wsl bash -c $wslCommand 2>&1
            # Check if WSL error occurred and fall back to plink
            if ($output -match "no installed distributions") {
                Write-Host "[$timestamp] [WARN] WSL not available, falling back to plink..." -ForegroundColor Yellow
                $useSshpass = $false
                $usePlink = $true
                # Fall through to plink section
            } else {
                if ($Verbose) {
                    $output | ForEach-Object { Write-Host "[$timestamp] [REMOTE] $_" -ForegroundColor Gray }
                }
                return $output
            }
        }
    }
    
    if ($usePlink -and $Password) {
        # Use plink with password (escape special characters properly)
        $escapedPassword = $Password -replace '"', '"""'
        
        # Build plink arguments - use -hostkey with wildcard to accept any host key
        $plinkArgs = @("-P", $SSHPort, "-ssh", "-batch", "-pw", $escapedPassword)
        
        # On first connection, try without -batch to cache host key, then use -batch
        if (-not $script:hostKeyAccepted) {
            Write-Host "[$timestamp] [INFO] Caching SSH host key (first connection)..." -ForegroundColor Gray
            # Try once without -batch to cache the key
            $firstTryArgs = @("-P", $SSHPort, "-ssh", "-pw", $escapedPassword, "${Username}@${ServerIP}", "echo 'ok'")
            $firstOutput = & plink $firstTryArgs 2>&1
            # If it worked or key is now cached, mark as accepted
            if ($LASTEXITCODE -eq 0 -or $firstOutput -notmatch "host key") {
                $script:hostKeyAccepted = $true
            }
        }
        
        # Now run the actual command with -batch
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
        # Use standard SSH (will prompt for password interactively if needed)
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
        # Use sshpass via WSL for automatic password entry
        $escapedPassword = $Password -replace '"', '\"' -replace '\$', '\$' -replace '`', '\`'
        $wslCommand = "sshpass -p '$escapedPassword' scp -P $SSHPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null '$Source' ${Username}@${ServerIP}:$Destination"
        $output = wsl bash -c $wslCommand 2>&1
        # Check if WSL error occurred and fall back to plink
        if ($output -match "no installed distributions") {
            Write-Host "[$timestamp] [WARN] WSL not available, falling back to plink..." -ForegroundColor Yellow
            $useSshpass = $false
            $usePlink = $true
            # Fall through to plink section
        } else {
            if ($Verbose -and $output) {
                $output | ForEach-Object { Write-Host "[$timestamp] [SCP] $_" -ForegroundColor Gray }
            }
            return $output
        }
    }
    
    if ($usePlink -and $Password) {
        # Use pscp (PuTTY SCP) for password authentication
        $pscpAvailable = Get-Command pscp -ErrorAction SilentlyContinue
        if ($pscpAvailable) {
            $escapedPassword = $Password -replace '"', '"""'
            
            # Host key should already be cached from plink connection, but ensure it
            if (-not $script:hostKeyAccepted) {
                # Cache host key using plink first (pscp uses same registry)
                $firstTryArgs = @("-P", $SSHPort, "-ssh", "-pw", $escapedPassword, "${Username}@${ServerIP}", "echo 'ok'")
                & plink $firstTryArgs 2>&1 | Out-Null
                $script:hostKeyAccepted = $true
            }
            
            # Now use pscp with -batch to avoid prompts
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
        # Use standard SCP (will prompt for password interactively if needed)
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
    
    # Check if connection was successful
    if ($exitCode -eq 0 -or ($testResult -match "Connection successful")) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] SSH connection successful" -ForegroundColor Green
        if ($testResult) {
            $testResult | Where-Object { $_ -notmatch "Permanently added" } | ForEach-Object {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [SERVER INFO] $_" -ForegroundColor DarkGray
            }
        }
    } else {
        # Check for common connection errors
        if ($testResult -match "Connection refused" -or $testResult -match "Could not resolve" -or $testResult -match "Permission denied") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Cannot connect to server:" -ForegroundColor Red
            Write-Host $testResult -ForegroundColor Yellow
            Write-Host "`nPlease check:" -ForegroundColor Yellow
            Write-Host "  - Server IP and port are correct" -ForegroundColor White
            Write-Host "  - Username is correct" -ForegroundColor White
            Write-Host "  - Password is correct" -ForegroundColor White
            Write-Host "  - Server is accessible from this machine" -ForegroundColor White
            exit 1
        } else {
            # Might be a password prompt or other interactive prompt
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] SSH connection test completed" -ForegroundColor Green
            if ($useInteractivePassword) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] You may be prompted for password during deployment" -ForegroundColor Yellow
            }
        }
    }
} catch {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] SSH connection failed: $_" -ForegroundColor Red
    exit 1
}

# Step 1: Transfer project files
if (-not $SkipTransfer) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  STEP 1: TRANSFER PROJECT FILES" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $ProjectRoot = $PSScriptRoot
    
    # Create exclude list for files we don't need to transfer
    $excludePatterns = @(
        "venv",
        "__pycache__",
        "*.pyc",
        ".git",
        "logs",
        "*.log",
        "*.zip",
        ".env",
        "node_modules"
    )
    
    Write-Host "Creating archive of project files..." -ForegroundColor Yellow
    
    # Create temporary directory for archive
    $tempDir = Join-Path $env:TEMP "message_broker_deploy_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    # Copy project files (excluding unnecessary files)
    Write-Host "Copying project files to temporary directory..." -ForegroundColor Yellow
    $excludeDirs = @("venv", ".git", "__pycache__", "logs", "node_modules")
    $excludeFiles = @("*.pyc", "*.log", "*.zip")
    
    Get-ChildItem -Path $ProjectRoot -Recurse | Where-Object {
        $item = $_
        $relativePath = $item.FullName.Substring($ProjectRoot.Length + 1)
        
        # Skip excluded directories
        $skip = $false
        foreach ($excludeDir in $excludeDirs) {
            if ($relativePath -like "$excludeDir*" -or $relativePath -like "*\$excludeDir\*") {
                $skip = $true
                break
            }
        }
        
        # Skip excluded files
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
        $relativePath = $_.FullName.Substring($ProjectRoot.Length + 1)
        $destPath = Join-Path $tempDir $relativePath
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        if (-not $_.PSIsContainer) {
            Copy-Item $_.FullName -Destination $destPath -Force
        }
    }
    
    Write-Host "[OK] Files prepared for transfer" -ForegroundColor Green
    
    # Create tar archive
    $archiveName = "message_broker.tar.gz"
    $archivePath = Join-Path $env:TEMP $archiveName
    
    Write-Host "Creating compressed archive..." -ForegroundColor Yellow
    
    # Try using tar (available in Windows 10 1803+)
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
    
    # Try using 7zip if tar failed
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
    
    # Last resort: use Compress-Archive (creates .zip, will need to handle on server)
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
    Write-Host "This may take a few minutes depending on file size..." -ForegroundColor Gray
    
    $archiveNameOnServer = Split-Path $archivePath -Leaf
    $remoteArchivePath = "/tmp/$archiveNameOnServer"
    
    try {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting file transfer..." -ForegroundColor Yellow
        $fileSize = (Get-Item $archivePath).Length / 1MB
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Archive size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
        $scpResult = Invoke-SCPCommand -Source $archivePath -Destination $remoteArchivePath -Verbose
        if ($LASTEXITCODE -ne 0 -and $scpResult -match "error|failed|denied") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] SCP transfer failed:" -ForegroundColor Red
            Write-Host $scpResult -ForegroundColor Red
            throw "SCP transfer failed"
        }
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] Files transferred successfully" -ForegroundColor Green
    } catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] File transfer failed: $_" -ForegroundColor Red
        Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }
    
    # Clean up local archive
    Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "[INFO] Skipping file transfer (SkipTransfer flag set)" -ForegroundColor Yellow
}

# Step 2: Run deployment script on remote server
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STEP 2: DEPLOY ON REMOTE SERVER" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create deployment script to run on remote server
# Use single-quoted here-string to prevent PowerShell parsing
$deployScript = @'
#!/bin/bash
# Don't exit on error - we want to see all errors
set -o pipefail

# Function to print timestamped messages
log_info() {
    echo "[$(date '+%H:%M:%S')] [INFO] $1"
}

log_ok() {
    echo "[$(date '+%H:%M:%S')] [OK] $1"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] [ERROR] $1" >&2
}

log_warn() {
    echo "[$(date '+%H:%M:%S')] [WARN] $1"
}

log_step() {
    echo ""
    echo "========================================"
    echo "  $1"
    echo "========================================"
    echo ""
}

log_info "Starting Message Broker deployment..."
log_info "Server: $(hostname)"
log_info "User: $(whoami)"
log_info "Date: $(date)"
echo ""

REMOTE_PATH="/opt/message_broker"

# Debug: Show REMOTE_PATH value
echo "[DEBUG] REMOTE_PATH is set to: $REMOTE_PATH"

# Use archive name from environment if provided, otherwise detect
if [ -n "\$ARCHIVE_NAME_ON_SERVER" ]; then
    ARCHIVE_NAME="\$ARCHIVE_NAME_ON_SERVER"
    ARCHIVE_PATH="/tmp/\$ARCHIVE_NAME"
else
    # Detect archive file (could be .tar.gz or .zip)
    if [ -f "/tmp/message_broker.zip" ]; then
        ARCHIVE_NAME="message_broker.zip"
        ARCHIVE_PATH="/tmp/\$ARCHIVE_NAME"
    elif [ -f "/tmp/message_broker.tar.gz" ]; then
        ARCHIVE_NAME="message_broker.tar.gz"
        ARCHIVE_PATH="/tmp/\$ARCHIVE_NAME"
    else
        # Try to find any message_broker archive
        ARCHIVE_PATH=$(ls /tmp/message_broker.* 2>/dev/null | head -1)
        if [ -z "$ARCHIVE_PATH" ]; then
            echo "[WARN] No archive file found in /tmp/"
        fi
    fi
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then 
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Determine if we need to use sudo (we're already root, so we don't)
SUDO_CMD=""
log_info "Running as root - sudo not needed"

# Extract archive
log_step "STEP 1: EXTRACTING PROJECT FILES"
if [ -f "$ARCHIVE_PATH" ]; then
    log_info "Archive found: $ARCHIVE_PATH"
    log_info "Extracting to: $REMOTE_PATH"
    if [ -z "$REMOTE_PATH" ]; then
        log_error "REMOTE_PATH is not set!"
        exit 1
    fi
    mkdir -p "$REMOTE_PATH"
    cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }
    log_info "Current directory: $(pwd)"
    if [[ "\$ARCHIVE_PATH" == *.zip ]]; then
        log_info "Extracting ZIP archive..."
        unzip -q "\$ARCHIVE_PATH" || (log_warn "unzip failed, trying Python..." && python3 -m zipfile -e "\$ARCHIVE_PATH" .)
    else
        log_info "Extracting TAR.GZ archive..."
        tar -xzf "\$ARCHIVE_PATH" --verbose 2>&1 | head -20
        log_info "... (showing first 20 files, extraction continues)"
    fi
    rm -f "\$ARCHIVE_PATH"
    log_ok "Files extracted successfully"
    log_info "Project files in: $(pwd)"
else
    log_warn "Archive not found, assuming files already deployed"
    log_info "Checking if project exists at: $REMOTE_PATH"
    if [ ! -d "$REMOTE_PATH" ]; then
        log_error "Project directory not found at $REMOTE_PATH"
        exit 1
    fi
fi

# Install system dependencies
log_step "STEP 2: INSTALLING SYSTEM DEPENDENCIES"
log_info "Detecting package manager..."
if command -v apt-get &> /dev/null; then
    log_info "Using apt-get (Debian/Ubuntu)"
    export DEBIAN_FRONTEND=noninteractive
    log_info "Updating package lists..."
    apt-get update 2>&1 | tail -5
    
    log_info "Installing apt-utils (if needed)..."
    apt-get install -y apt-utils 2>/dev/null || true
    
    log_info "Installing Python and basic tools..."
    apt-get install -y python3 python3-pip python3-venv openssl 2>&1 | grep -E "(Setting up|Unpacking|done)" || true
    
    log_info "Installing MySQL server..."
    if ! apt-get install -y mysql-server 2>/dev/null; then
        log_warn "mysql-server not available, trying default-mysql-server..."
        apt-get install -y default-mysql-server 2>&1 | grep -E "(Setting up|Unpacking|done)" || log_warn "Could not install MySQL server"
    else
        log_ok "MySQL server installed"
    fi
    
    log_info "Installing Redis server..."
    if ! apt-get install -y redis-server 2>/dev/null; then
        log_warn "redis-server not available via apt-get"
    else
        log_ok "Redis server installed"
    fi
elif command -v yum &> /dev/null; then
    log_info "Using yum (CentOS/RHEL)"
    log_info "Installing Python and dependencies..."
    yum install -y python3 python3-pip openssl 2>&1 | tail -5 || true
    log_info "Installing MariaDB and Redis..."
    yum install -y mariadb-server mariadb redis 2>&1 | tail -5 || log_warn "Could not install all packages"
elif command -v dnf &> /dev/null; then
    log_info "Using dnf (Fedora/modern RHEL)"
    log_info "Installing Python and dependencies..."
    dnf install -y python3 python3-pip python3-venv openssl 2>&1 | tail -5 || true
    log_info "Installing MariaDB and Redis..."
    dnf install -y mariadb-server mariadb redis 2>&1 | tail -5 || log_warn "Could not install all packages"
else
    log_warn "Unknown package manager. Please install dependencies manually:"
    echo "  - python3, python3-pip, python3-venv"
    echo "  - mysql-server or mariadb-server"
    echo "  - redis-server or redis"
    echo "  - openssl"
fi

# Start and enable MySQL
log_info "Starting MySQL service..."
if systemctl start mysql 2>/dev/null || systemctl start mysqld 2>/dev/null; then
    systemctl enable mysql 2>/dev/null || systemctl enable mysqld 2>/dev/null || true
    log_ok "MySQL service started and enabled"
    systemctl status mysql --no-pager -l 2>/dev/null | head -3 || systemctl status mysqld --no-pager -l 2>/dev/null | head -3 || true
else
    log_warn "Could not start MySQL service"
fi

# Start and enable Redis
log_info "Starting Redis service..."
if systemctl start redis 2>/dev/null || systemctl start redis-server 2>/dev/null; then
    systemctl enable redis 2>/dev/null || systemctl enable redis-server 2>/dev/null || true
    log_ok "Redis service started and enabled"
    systemctl status redis --no-pager -l 2>/dev/null | head -3 || systemctl status redis-server --no-pager -l 2>/dev/null | head -3 || true
else
    log_warn "Could not start Redis service"
fi

# Create Python virtual environment
log_step "STEP 3: SETTING UP PYTHON ENVIRONMENT"
log_info "Python version: $(python3 --version 2>&1)"
if [ -z "$REMOTE_PATH" ]; then
    log_error "REMOTE_PATH is not set!"
    exit 1
fi
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }
log_info "Working directory: $(pwd)"
if [ ! -d "venv" ]; then
    log_info "Creating Python virtual environment..."
    python3 -m venv venv
    log_ok "Virtual environment created"
else
    log_info "Virtual environment already exists"
fi
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    log_info "Virtual environment activated"
    log_info "Python path: $(which python)"
else
    log_error "Virtual environment activation script not found!"
    exit 1
fi

# Install Python dependencies
log_info "Upgrading pip..."
pip install --upgrade pip 2>&1 | tail -3 || log_warn "Failed to upgrade pip"

log_info "Installing Python dependencies from requirements files..."
if [ -f "main_server/requirements.txt" ]; then
    log_info "Installing main_server requirements..."
    pip install -r main_server/requirements.txt 2>&1 | grep -E "(Collecting|Installing|Successfully|Requirement already)" | tail -10 || log_warn "Some packages may have failed"
fi
if [ -f "proxy/requirements.txt" ]; then
    log_info "Installing proxy requirements..."
    pip install -r proxy/requirements.txt 2>&1 | grep -E "(Collecting|Installing|Successfully|Requirement already)" | tail -10 || log_warn "Some packages may have failed"
fi
if [ -f "worker/requirements.txt" ]; then
    log_info "Installing worker requirements..."
    pip install -r worker/requirements.txt 2>&1 | grep -E "(Collecting|Installing|Successfully|Requirement already)" | tail -10 || log_warn "Some packages may have failed"
fi
if [ -f "portal/requirements.txt" ]; then
    log_info "Installing portal requirements..."
    pip install -r portal/requirements.txt 2>&1 | grep -E "(Collecting|Installing|Successfully|Requirement already)" | tail -10 || log_warn "Some packages may have failed"
fi
log_ok "Python dependencies installation completed"

# Verify cryptography is installed (needed for encryption key)
echo "[INFO] Verifying cryptography module..."
python3 -c "import cryptography" 2>/dev/null && echo "[OK] Cryptography module available" || echo "[WARN] Cryptography module not available"

# Create necessary directories
echo ""
echo "[INFO] Creating necessary directories..."
mkdir -p "$REMOTE_PATH/logs"
mkdir -p "$REMOTE_PATH/main_server/certs"
mkdir -p "$REMOTE_PATH/main_server/secrets"
mkdir -p "$REMOTE_PATH/proxy/certs"
mkdir -p "$REMOTE_PATH/worker/certs"
mkdir -p "$REMOTE_PATH/portal/logs"

# Setup MySQL database
echo ""
log_info "Setting up MySQL database..."
DB_PASSWORD="YourStrongPassword123!"
DB_EXISTS=$(mysql -u root -e "SHOW DATABASES LIKE 'message_system';" 2>/dev/null | grep message_system || echo "")
if [ -z "$DB_EXISTS" ]; then
    log_info "Creating database and user..."
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS message_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'systemuser'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EOF
    log_ok "Database created"
else
    log_info "Database already exists"
    # Check if user exists and update password if needed
    USER_EXISTS=$(mysql -u root -e "SELECT user FROM mysql.user WHERE user='systemuser' AND host='localhost';" 2>/dev/null | grep systemuser || echo "")
    if [ -n "$USER_EXISTS" ]; then
        log_info "Updating database user password..."
        # Escape single quotes in password for MySQL
        DB_PASSWORD_ESCAPED=$(echo "$DB_PASSWORD" | sed "s/'/''/g")
        mysql -u root <<EOF
ALTER USER 'systemuser'@'localhost' IDENTIFIED BY '$DB_PASSWORD_ESCAPED';
FLUSH PRIVILEGES;
EOF
        # Verify password was updated by testing connection
        if mysql -u systemuser -p"$DB_PASSWORD" -e "SELECT 1;" message_system 2>/dev/null | grep -q "1"; then
            log_ok "Database user password updated and verified"
        else
            log_warn "Password update may have failed - will try to recreate user"
            mysql -u root <<EOF
DROP USER IF EXISTS 'systemuser'@'localhost';
CREATE USER 'systemuser'@'localhost' IDENTIFIED BY '$DB_PASSWORD_ESCAPED';
GRANT ALL PRIVILEGES ON message_system.* TO 'systemuser'@'localhost';
FLUSH PRIVILEGES;
EOF
            log_ok "Database user recreated with new password"
        fi
    fi
fi

# Create/update .env file BEFORE running migrations (so Alembic has correct password)
log_step "STEP 4: CONFIGURING ENVIRONMENT"
log_info "Creating/updating .env file..."
if [ ! -f "$REMOTE_PATH/.env" ]; then
    log_info "Creating .env file..."
    cat > "$REMOTE_PATH/.env" <<ENVEOF
# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=message_system
DB_USER=systemuser
DB_PASSWORD=$DB_PASSWORD
DATABASE_URL=mysql+pymysql://systemuser:$(python3 -c "import urllib.parse; print(urllib.parse.quote('$DB_PASSWORD'))" 2>/dev/null || echo "$DB_PASSWORD")@localhost:3306/message_system

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# Security - AES Encryption Key Path
AES_KEY_PATH=$REMOTE_PATH/main_server/secrets/aes.key

# JWT Configuration (CHANGE THESE IN PRODUCTION!)
JWT_SECRET=your-production-secret-key-min-32-chars-change-this
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=30

# Admin Credentials (Portal)
ADMIN_USER=admin@example.com
ADMIN_PASS=AdminPass123!

# TLS/Certificate Paths
CA_CERT_PATH=$REMOTE_PATH/main_server/certs/ca.crt
SERVER_KEY_PATH=$REMOTE_PATH/main_server/certs/server.key
SERVER_CERT_PATH=$REMOTE_PATH/main_server/certs/server.crt

# Service Endpoints
PROXY_URL=https://localhost:8001
MAIN_SERVER_URL=https://localhost:8000
PORTAL_URL=http://localhost:8080

# Worker Configuration
WORKER_RETRY_INTERVAL=30
WORKER_MAX_ATTEMPTS=10000
WORKER_CONCURRENCY=4

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=$REMOTE_PATH/logs
LOG_ROTATION_DAYS=7
ENVEOF
    # Convert Windows line endings to Unix (remove \r characters)
    sed -i 's/\r$//' "$REMOTE_PATH/.env"
    log_ok ".env file created"
    log_warn "Please update .env file with production values (especially JWT_SECRET and passwords)!"
else
    log_info ".env file already exists"
    # Fix line endings if file was transferred from Windows
    sed -i 's/\r$//' "$REMOTE_PATH/.env"
    # Update DB_PASSWORD in existing .env file
    # URL encode the password for DATABASE_URL (handle special characters like $, !, etc.)
    DB_PASSWORD_URL=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$DB_PASSWORD'))" 2>/dev/null || echo "$DB_PASSWORD")
    
    if grep -q "DB_PASSWORD=" "$REMOTE_PATH/.env"; then
        sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" "$REMOTE_PATH/.env"
        sed -i "s|DATABASE_URL=mysql+pymysql://systemuser:.*@localhost|DATABASE_URL=mysql+pymysql://systemuser:$DB_PASSWORD_URL@localhost|" "$REMOTE_PATH/.env"
        log_ok "Updated DB_PASSWORD in .env file"
    else
        # Add DB_PASSWORD if it doesn't exist
        echo "DB_PASSWORD=$DB_PASSWORD" >> "$REMOTE_PATH/.env"
        # Update DATABASE_URL if it exists
        if grep -q "DATABASE_URL=" "$REMOTE_PATH/.env"; then
            sed -i "s|DATABASE_URL=mysql+pymysql://systemuser:.*@localhost|DATABASE_URL=mysql+pymysql://systemuser:$DB_PASSWORD_URL@localhost|" "$REMOTE_PATH/.env"
        fi
        log_ok "Added DB_PASSWORD to .env file"
    fi
    # Fix line endings if file was transferred from Windows
    sed -i 's/\r$//' "$REMOTE_PATH/.env"
fi

# Initialize database schema
log_step "STEP 5: INITIALIZING DATABASE SCHEMA"
log_info "Loading environment variables..."
cd "$REMOTE_PATH" || { log_error "Failed to cd to $REMOTE_PATH"; exit 1; }
export $(cat .env | grep -v '^#' | xargs)

log_info "Initializing database schema..."
cd "$REMOTE_PATH/main_server" || { log_error "Failed to cd to $REMOTE_PATH/main_server"; exit 1; }
if [ -f "../venv/bin/activate" ]; then
    source ../venv/bin/activate
else
    log_error "Virtual environment not found at ../venv/bin/activate"
    exit 1
fi

# Set PYTHONPATH
export PYTHONPATH="$REMOTE_PATH"

# Verify DB_PASSWORD is set
if [ -z "$DB_PASSWORD" ]; then
    log_error "DB_PASSWORD is not set in environment!"
    log_info "Loading from .env file..."
    export $(cat ../.env | grep -v '^#' | xargs)
fi

# Test database connection before running migrations
log_info "Testing database connection..."
if mysql -u systemuser -p"$DB_PASSWORD" -e "SELECT 1;" message_system 2>/dev/null | grep -q "1"; then
    log_ok "Database connection successful"
else
    log_error "Database connection failed with password from .env"
    log_info "Attempting to fix password..."
    # Try to reset password again
    DB_PASSWORD_ESCAPED=$(echo "$DB_PASSWORD" | sed "s/'/''/g")
    mysql -u root <<EOF
ALTER USER 'systemuser'@'localhost' IDENTIFIED BY '$DB_PASSWORD_ESCAPED';
FLUSH PRIVILEGES;
EOF
    # Test again
    if mysql -u systemuser -p"$DB_PASSWORD" -e "SELECT 1;" message_system 2>/dev/null | grep -q "1"; then
        log_ok "Database connection successful after password reset"
    else
        log_error "Database connection still failing - please check password manually"
        log_warn "Skipping migrations - database connection issue"
    fi
fi

log_info "Running database migrations..."
if [ -f "alembic.ini" ]; then
    # Ensure environment variables are loaded
    export $(cat ../.env | grep -v '^#' | xargs)
    export PYTHONPATH="$REMOTE_PATH"
    alembic upgrade head || log_warn "Alembic migration failed or already up to date"
else
    log_warn "alembic.ini not found, skipping migrations"
fi

# Generate certificates if they don't exist
echo ""
log_info "Checking certificates..."
CERTS_DIR="$REMOTE_PATH/main_server/certs"
if [ ! -f "$CERTS_DIR/ca.crt" ]; then
    log_info "Generating CA certificate..."
    mkdir -p "$CERTS_DIR"
    cd "$CERTS_DIR" || { log_error "Failed to cd to $CERTS_DIR"; exit 1; }
    openssl genrsa -out ca.key 4096
    chmod 600 ca.key
    openssl req -new -x509 -days 3650 -key ca.key -out ca.crt -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US"
    chmod 644 ca.crt
    log_ok "CA certificate generated"
fi

# Generate server certificate
if [ ! -f "$CERTS_DIR/server.crt" ]; then
    log_info "Generating server certificate..."
    cd "$CERTS_DIR" || { log_error "Failed to cd to $CERTS_DIR"; exit 1; }
    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -subj "/CN=server/O=MessageBroker/C=US"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365 -sha256
    chmod 600 server.key
    chmod 644 server.crt
    rm -f server.csr
    log_ok "Server certificate generated"
fi

# Generate proxy certificate
PROXY_CERTS_DIR="$REMOTE_PATH/proxy/certs"
if [ ! -f "$PROXY_CERTS_DIR/proxy.crt" ]; then
    log_info "Generating proxy certificate..."
    mkdir -p "$PROXY_CERTS_DIR"
    cd "$PROXY_CERTS_DIR" || { log_error "Failed to cd to $PROXY_CERTS_DIR"; exit 1; }
    openssl genrsa -out proxy.key 2048
    openssl req -new -key proxy.key -out proxy.csr -subj "/CN=proxy/O=MessageBroker/C=US"
    openssl x509 -req -in proxy.csr -CA "$CERTS_DIR/ca.crt" -CAkey "$CERTS_DIR/ca.key" -CAcreateserial -out proxy.crt -days 365 -sha256
    chmod 600 proxy.key
    chmod 644 proxy.crt
    cp "$CERTS_DIR/ca.crt" .
    rm -f proxy.csr
    log_ok "Proxy certificate generated"
fi

# Generate worker certificate
WORKER_CERTS_DIR="$REMOTE_PATH/worker/certs"
if [ ! -f "$WORKER_CERTS_DIR/worker.crt" ]; then
    log_info "Generating worker certificate..."
    mkdir -p "$WORKER_CERTS_DIR"
    cd "$WORKER_CERTS_DIR" || { log_error "Failed to cd to $WORKER_CERTS_DIR"; exit 1; }
    openssl genrsa -out worker.key 2048
    openssl req -new -key worker.key -out worker.csr -subj "/CN=worker/O=MessageBroker/C=US"
    openssl x509 -req -in worker.csr -CA "$CERTS_DIR/ca.crt" -CAkey "$CERTS_DIR/ca.key" -CAcreateserial -out worker.crt -days 365 -sha256
    chmod 600 worker.key
    chmod 644 worker.crt
    cp "$CERTS_DIR/ca.crt" .
    rm -f worker.csr
    log_ok "Worker certificate generated"
fi

# Generate encryption key if needed (after dependencies are installed)
if [ ! -f "$REMOTE_PATH/main_server/secrets/encryption.key" ]; then
    echo "Generating encryption key..."
    cd "$REMOTE_PATH/main_server" || { echo "[ERROR] Failed to cd to $REMOTE_PATH/main_server"; exit 1; }
    if [ -f "../venv/bin/activate" ]; then
        source ../venv/bin/activate
        # Check if cryptography is available
        if python3 -c "from cryptography.fernet import Fernet" 2>/dev/null; then
            # Try to generate encryption key
            python3 << 'PYEOF'
try:
    from cryptography.fernet import Fernet
    import os
    os.makedirs('secrets', exist_ok=True)
    with open('secrets/encryption.key', 'wb') as f:
        f.write(Fernet.generate_key())
    print("Encryption key generated successfully")
except Exception as e:
    print(f"Error generating encryption key: {e}")
    import sys
    sys.exit(1)
PYEOF
            if [ $? -eq 0 ]; then
                chmod 600 secrets/encryption.key
                echo "[OK] Encryption key generated"
            else
                echo "[WARN] Failed to generate encryption key - you may need to generate it manually"
            fi
        else
            echo "[WARN] Cryptography module not available - skipping encryption key generation"
            echo "[INFO] You can generate it later with: python3 -c \"from cryptography.fernet import Fernet; open('secrets/encryption.key', 'wb').write(Fernet.generate_key())\""
        fi
    else
        echo "[WARN] Virtual environment not found, skipping encryption key generation"
    fi
fi

# .env file is already created/updated before migrations (see above)

# Create service user
echo ""
echo "[INFO] Creating service user..."
if ! id "messagebroker" &>/dev/null; then
    useradd -r -s /bin/false messagebroker
    echo "[OK] Service user created"
else
    echo "[INFO] Service user already exists"
fi

# Set ownership and permissions
echo ""
echo "[INFO] Setting permissions..."
chown -R messagebroker:messagebroker "$REMOTE_PATH"
chmod 700 "$REMOTE_PATH/main_server/certs"
chmod 600 "$REMOTE_PATH/main_server/certs"/*.key 2>/dev/null || true
chmod 600 "$REMOTE_PATH/main_server/secrets"/* 2>/dev/null || true

# Install systemd services
if [ "\$SKIP_SERVICES" != "true" ]; then
    echo ""
    echo "[INFO] Installing systemd services..."
    if [ -f "$REMOTE_PATH/main_server/main_server.service" ]; then
        # Update service files with correct paths
        sed -i "s|/opt/message_broker|$REMOTE_PATH|g" "$REMOTE_PATH/main_server/main_server.service"
        sed -i "s|/opt/message_broker|$REMOTE_PATH|g" "$REMOTE_PATH/proxy/proxy.service"
        sed -i "s|/opt/message_broker|$REMOTE_PATH|g" "$REMOTE_PATH/worker/worker.service"
        sed -i "s|/opt/message_broker|$REMOTE_PATH|g" "$REMOTE_PATH/portal/portal.service"
        
        cp "$REMOTE_PATH/main_server/main_server.service" /etc/systemd/system/
        cp "$REMOTE_PATH/proxy/proxy.service" /etc/systemd/system/
        cp "$REMOTE_PATH/worker/worker.service" /etc/systemd/system/
        cp "$REMOTE_PATH/portal/portal.service" /etc/systemd/system/
        
        systemctl daemon-reload
        systemctl enable main_server proxy worker portal
        
        echo "[OK] Services installed and enabled"
    else
        echo "[WARN] Service files not found, skipping service installation"
    fi
else
    echo "[INFO] Skipping service installation (SKIP_SERVICES=true)"
fi

# Create admin user (if admin_cli.py exists)
echo ""
echo "[INFO] Checking for admin user..."
cd "$REMOTE_PATH/main_server" || { echo "[ERROR] Failed to cd to $REMOTE_PATH/main_server"; exit 1; }
if [ -f "../venv/bin/activate" ]; then
    source ../venv/bin/activate
else
    echo "[ERROR] Virtual environment not found"
    exit 1
fi
if [ -f "admin_cli.py" ]; then
    log_info "Checking for existing admin user..."
    ADMIN_EXISTS=$(python3 admin_cli.py user list 2>/dev/null | grep -i admin || echo "")
    if [ -z "$ADMIN_EXISTS" ]; then
        log_info "Creating admin user..."
        python3 admin_cli.py user create admin@example.com --role admin --password "AdminPass123!" 2>&1 || log_warn "Failed to create admin user (may already exist)"
    else
        log_info "Admin user already exists"
    fi
else
    log_warn "admin_cli.py not found, skipping admin user creation"
fi

log_step "DEPLOYMENT COMPLETE!"
log_ok "All deployment steps completed successfully"
echo ""
log_info "Next steps:"
echo "1. Review and update .env file: $REMOTE_PATH/.env"
echo "2. Start services:"
echo "   sudo systemctl start main_server proxy worker portal"
echo "3. Check service status:"
echo "   sudo systemctl status main_server"
echo "4. View logs:"
echo "   sudo journalctl -u main_server -f"
echo ""
log_info "Deployment finished at: $(date)"
echo ""
'@

# Replace the hardcoded path with the actual remote path
# Since we're using a single-quoted here-string, variables are literal
# We need to replace the hardcoded path with the actual path
Write-Host "[DEBUG] Replacing /opt/message_broker with: $RemotePath" -ForegroundColor Gray
$deployScript = $deployScript -replace '/opt/message_broker', $RemotePath

# Also ensure REMOTE_PATH variable assignment uses the correct path
$deployScript = $deployScript -replace 'REMOTE_PATH="/opt/message_broker"', "REMOTE_PATH=`"$RemotePath`""

# Write deployment script to temp file (UTF-8 without BOM for Linux compatibility)
$remoteScriptPath = "/tmp/deploy_message_broker.sh"
$localScriptPath = Join-Path $env:TEMP "deploy_message_broker.sh"
# Convert Windows line endings (CRLF) to Unix line endings (LF)
$deployScript = $deployScript -replace "`r`n", "`n" -replace "`r", "`n"
# Use UTF8NoBOM encoding to avoid BOM issues on Linux
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($localScriptPath, $deployScript, $utf8NoBom)

# Transfer and execute deployment script
Write-Host "Transferring deployment script..." -ForegroundColor Yellow
try {
    $scpResult = Invoke-SCPCommand -Source $localScriptPath -Destination $remoteScriptPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host $scpResult -ForegroundColor Red
        throw "Failed to transfer deployment script"
    }
} catch {
    Write-Host "[ERROR] Failed to transfer deployment script: $_" -ForegroundColor Red
    Remove-Item $localScriptPath -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "[OK] Deployment script transferred" -ForegroundColor Green

# Execute deployment script on remote server
Write-Host "`nExecuting deployment on remote server..." -ForegroundColor Yellow
Write-Host "This will take several minutes. Please wait..." -ForegroundColor Gray

$skipServicesFlag = if ($SkipServices) { "SKIP_SERVICES=true" } else { "" }
$archiveNameVar = "ARCHIVE_NAME_ON_SERVER=$archiveNameOnServer"

try {
    # First, check the script syntax on the server
    Write-Host "[INFO] Validating script syntax..." -ForegroundColor Gray
    $syntaxCheck = Invoke-SSHCommand -Command "bash -n $remoteScriptPath 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Script syntax error detected:" -ForegroundColor Red
        Write-Host $syntaxCheck -ForegroundColor Yellow
        Write-Host "[INFO] Downloading script for inspection..." -ForegroundColor Yellow
        # Download the script back to see what went wrong
        $debugScriptPath = Join-Path $env:TEMP "deploy_message_broker_debug.sh"
        Invoke-SCPCommand -Source "${sshHost}:$remoteScriptPath" -Destination $debugScriptPath
        Write-Host "[INFO] Script saved to: $debugScriptPath" -ForegroundColor Yellow
        Write-Host "[INFO] Please check the script for syntax errors" -ForegroundColor Yellow
        exit 1
    }
    
    # Check if user is root (if so, don't use sudo)
    $isRoot = Invoke-SSHCommand -Command "whoami" 2>&1
    $useSudo = $true
    if ($isRoot -match "root") {
        $useSudo = $false
        Write-Host "[INFO] Running as root - skipping sudo" -ForegroundColor Gray
    }
    
    # Pass environment variables to remote script
    $envCmd = ""
    if ($SkipServices) {
        $envCmd += "SKIP_SERVICES=true "
    }
    $envCmd += "ARCHIVE_NAME_ON_SERVER=$archiveNameOnServer "
    
    # Use sudo only if not root
    $sudoPrefix = if ($useSudo) { "sudo " } else { "" }
    $remoteCommand = "${sudoPrefix}$envCmd bash $remoteScriptPath 2>&1 | tee /tmp/deploy_output.log"
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] Executing remote deployment script..." -ForegroundColor Yellow
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] This will take several minutes. Output will stream in real-time..." -ForegroundColor Gray
    Write-Host ""
    
    # Execute with verbose output streaming
    $sshResult = Invoke-SSHCommand -Command $remoteCommand -Verbose
    
    # Also fetch the log file for complete output
    Write-Host ""
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] Fetching complete deployment log..." -ForegroundColor Gray
    $logOutput = Invoke-SSHCommand -Command "cat /tmp/deploy_output.log 2>/dev/null || echo 'Log file not found'" -Verbose
    if ($logOutput) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  COMPLETE DEPLOYMENT OUTPUT" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan
        $logOutput | ForEach-Object { Write-Host $_ }
    }
    
    # Display the output
    if ($sshResult) {
        $sshResult | ForEach-Object { 
            if ($_ -notmatch "Permanently added") {
                Write-Host $_ 
            }
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Deployment script returned non-zero exit code: $LASTEXITCODE" -ForegroundColor Yellow
        Write-Host "       Some steps may have failed, but deployment may have partially completed" -ForegroundColor Yellow
        Write-Host "       Please check the output above for specific errors" -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Deployment completed successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "[ERROR] Deployment failed: $_" -ForegroundColor Red
    Remove-Item $localScriptPath -Force -ErrorAction SilentlyContinue
    exit 1
}

# Clean up
Remove-Item $localScriptPath -Force -ErrorAction SilentlyContinue
Invoke-SSHCommand -Command "rm -f $remoteScriptPath" | Out-Null

# Final instructions
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "To start services on the remote server, run:" -ForegroundColor Yellow
Write-Host "  ssh $sshOptions $sshHost 'sudo systemctl start main_server proxy worker portal'" -ForegroundColor White

Write-Host "`nTo check service status:" -ForegroundColor Yellow
Write-Host "  ssh $sshOptions $sshHost 'sudo systemctl status main_server'" -ForegroundColor White

Write-Host "`nTo view logs:" -ForegroundColor Yellow
Write-Host "  ssh $sshOptions $sshHost 'sudo journalctl -u main_server -f'" -ForegroundColor White

Write-Host "`nService URLs (after starting services):" -ForegroundColor Yellow
Write-Host "  Main Server API:  https://$($ServerIP):8000/docs" -ForegroundColor White
Write-Host "  Proxy API:        https://$($ServerIP):8001/api/v1/docs" -ForegroundColor White
Write-Host "  Web Portal:       http://$($ServerIP):8080" -ForegroundColor White

Write-Host "`nIMPORTANT: Update the .env file on the server with production values!" -ForegroundColor Red
Write-Host "  ssh $sshOptions $sshHost 'sudo nano $RemotePath/.env'" -ForegroundColor White

Write-Host "`n"

