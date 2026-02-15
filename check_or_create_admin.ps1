# PowerShell Script to Check and Create Admin User
# Checks if admin user exists, creates one if not

param(
    [Parameter(Mandatory=$false)]
    [string]$Password = "Pc`$123456",
    
    [Parameter(Mandatory=$false)]
    [string]$AdminEmail = "admin@example.com",
    
    [Parameter(Mandatory=$false)]
    [string]$AdminPassword = "AdminPass123!",
    
    [Parameter(Mandatory=$false)]
    [string]$DBPassword = "MsgBrckr#TnN`$2025"
)

$ErrorActionPreference = "Stop"

# Main server details
$ServerIP = "173.32.115.223"
$SSHPort = 2221
$Username = "root"
$RemotePath = "/opt/message_broker"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CHECK/CREATE ADMIN USER" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[INFO] Server: ${ServerIP}:${SSHPort}" -ForegroundColor Gray
Write-Host "[INFO] Admin Email: $AdminEmail" -ForegroundColor Gray
Write-Host ""

# Check for SSH tools
$plinkAvailable = Get-Command plink -ErrorAction SilentlyContinue
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue

if (-not $sshAvailable -and -not $plinkAvailable) {
    Write-Host "[ERROR] SSH not found. Please install OpenSSH client or PuTTY." -ForegroundColor Red
    exit 1
}

# Determine which method to use
$usePlink = $false
if ($plinkAvailable) {
    $usePlink = $true
    Write-Host "[INFO] Using Plink (PuTTY) for SSH" -ForegroundColor Green
} else {
    Write-Host "[INFO] Using standard SSH" -ForegroundColor Yellow
    Write-Host "[INFO] You will be prompted for password: $Password" -ForegroundColor Yellow
}

# Helper function to execute SSH commands
function Invoke-SSHCommand {
    param(
        [string]$Command,
        [switch]$Verbose
    )
    
    if ($usePlink -and $Password) {
        $escapedPassword = $Password -replace '"', '"""'
        $plinkArgs = @("-P", $SSHPort, "-ssh", "-batch", "-pw", $escapedPassword, "${Username}@${ServerIP}", $Command)
        $output = & plink $plinkArgs 2>&1
        if ($Verbose) {
            $output | ForEach-Object { Write-Host "[REMOTE] $_" -ForegroundColor Gray }
        }
        return $output
    } else {
        $sshArgs = @("-p", $SSHPort, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=$env:TEMP\known_hosts_temp")
        if ($Password) {
            Write-Host "[INFO] Enter password when prompted: $Password" -ForegroundColor Yellow
        }
        $output = & ssh $sshArgs "${Username}@${ServerIP}" $Command 2>&1
        if ($Verbose) {
            $output | ForEach-Object { Write-Host "[REMOTE] $_" -ForegroundColor Gray }
        }
        return $output
    }
}

# Test SSH connection
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Testing SSH connection..." -ForegroundColor Yellow
try {
    $testResult = Invoke-SSHCommand -Command "echo 'Connection successful'; hostname" -Verbose
    if ($testResult -match "Connection successful") {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] SSH connection successful" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Connection test failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[ERROR] SSH connection failed: $_" -ForegroundColor Red
    exit 1
}

# Create a temporary script on the server
Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Creating temporary script on server..." -ForegroundColor Yellow

# Escape password for bash
$adminPasswordEscaped = $AdminPassword -replace "'", "'\''"

# Create the script content - use Python to load .env properly
$scriptContent = @"
#!/bin/bash
cd $RemotePath
source venv/bin/activate
cd main_server
python3 << 'PYEOF'
import os
from dotenv import load_dotenv
load_dotenv('../.env')
os.system('python admin_cli.py user list 2>&1')
PYEOF
"@

# Write script to server (with Unix line endings)
$scriptPath = "/tmp/check_admin_$$.sh"
$scriptContentUnix = $scriptContent -replace "`r`n", "`n" -replace "`r", "`n"
[System.IO.File]::WriteAllText("$env:TEMP\check_admin_temp.sh", $scriptContentUnix)

# Transfer script
if ($usePlink) {
    $pscpAvailable = Get-Command pscp -ErrorAction SilentlyContinue
    if ($pscpAvailable) {
        $escapedPassword = $Password -replace '"', '"""'
        $pscpArgs = @("-P", $SSHPort, "-batch", "-pw", $escapedPassword, "$env:TEMP\check_admin_temp.sh", "${Username}@${ServerIP}:$scriptPath")
        & pscp $pscpArgs 2>&1 | Out-Null
    } else {
        Write-Host "[ERROR] pscp not found. Cannot transfer script." -ForegroundColor Red
        exit 1
    }
} else {
    $scpArgs = @("-P", $SSHPort, "-o", "StrictHostKeyChecking=no")
    & scp $scpArgs "$env:TEMP\check_admin_temp.sh" "${Username}@${ServerIP}:$scriptPath" 2>&1 | Out-Null
}

# Make executable and run
$checkCommand = "chmod +x $scriptPath && bash $scriptPath"
$userList = Invoke-SSHCommand -Command $checkCommand -Verbose

# Clean up
Remove-Item "$env:TEMP\check_admin_temp.sh" -ErrorAction SilentlyContinue
Invoke-SSHCommand -Command "rm -f $scriptPath" | Out-Null

# Check if any admin users exist
$hasAdmin = $false
$adminEmails = @()

if ($userList) {
    $lines = $userList -split "`n"
    foreach ($line in $lines) {
        if ($line -match "admin" -and $line -match "@") {
            # Try to extract email
            if ($line -match "([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})") {
                $email = $matches[1]
                # Check if role is admin
                if ($line -match "\s+admin\s+" -or $line -match "admin") {
                    $hasAdmin = $true
                    if ($adminEmails -notcontains $email) {
                        $adminEmails += $email
                    }
                }
            }
        }
    }
}

if ($hasAdmin) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] Admin user(s) found:" -ForegroundColor Green
    $adminEmails | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor White
    }
    Write-Host "`nYou can log in to the portal using any of these admin emails." -ForegroundColor Cyan
    exit 0
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] No admin users found" -ForegroundColor Yellow
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Creating admin user: $AdminEmail" -ForegroundColor Yellow

# Create script to create admin user - use Python to load .env properly
$createScriptContent = @"
#!/bin/bash
cd $RemotePath
source venv/bin/activate
cd main_server
python3 << 'PYEOF'
import os
from dotenv import load_dotenv
load_dotenv('../.env')
os.system('python admin_cli.py user create $AdminEmail --role admin --password $adminPasswordEscaped 2>&1')
PYEOF
"@

$createScriptPath = "/tmp/create_admin_$$.sh"
$createScriptContentUnix = $createScriptContent -replace "`r`n", "`n" -replace "`r", "`n"
[System.IO.File]::WriteAllText("$env:TEMP\create_admin_temp.sh", $createScriptContentUnix)

# Transfer script
if ($usePlink) {
    $pscpArgs = @("-P", $SSHPort, "-batch", "-pw", $escapedPassword, "$env:TEMP\create_admin_temp.sh", "${Username}@${ServerIP}:$createScriptPath")
    & pscp $pscpArgs 2>&1 | Out-Null
} else {
    $scpArgs = @("-P", $SSHPort, "-o", "StrictHostKeyChecking=no")
    & scp $scpArgs "$env:TEMP\create_admin_temp.sh" "${Username}@${ServerIP}:$createScriptPath" 2>&1 | Out-Null
}

# Execute
$createCommand = "chmod +x $createScriptPath && bash $createScriptPath"
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Executing user creation..." -ForegroundColor Yellow
$createResult = Invoke-SSHCommand -Command $createCommand -Verbose

# Clean up
Remove-Item "$env:TEMP\create_admin_temp.sh" -ErrorAction SilentlyContinue
Invoke-SSHCommand -Command "rm -f $createScriptPath" | Out-Null

# Check if creation was successful
if ($createResult -match "Access denied" -or $createResult -match "1045") {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Database authentication failed" -ForegroundColor Red
    Write-Host "The database password may be incorrect or the user doesn't have access." -ForegroundColor Yellow
    exit 1
} elseif ($createResult -match "created successfully" -or ($createResult -match "OK" -and $createResult -notmatch "Error" -and $createResult -notmatch "X")) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] Admin user created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  LOGIN CREDENTIALS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Email:    $AdminEmail" -ForegroundColor White
    Write-Host "Password: $AdminPassword" -ForegroundColor White
    Write-Host ""
    Write-Host "Portal URL: http://msgportal.samsolutions.ir:8080" -ForegroundColor Cyan
    Write-Host "            http://${ServerIP}:8080" -ForegroundColor Cyan
    Write-Host ""
} elseif ($createResult -match "already exists" -or $createResult -match "duplicate") {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [OK] Admin user already exists!" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  LOGIN CREDENTIALS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Email:    $AdminEmail" -ForegroundColor White
    Write-Host "Password: (use the password you set when creating this user)" -ForegroundColor White
    Write-Host ""
    Write-Host "Portal URL: http://msgportal.samsolutions.ir:8080" -ForegroundColor Cyan
    Write-Host "            http://${ServerIP}:8080" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Failed to create admin user" -ForegroundColor Red
    Write-Host "Output:" -ForegroundColor Yellow
    $createResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    exit 1
}

Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Script completed!" -ForegroundColor Green
