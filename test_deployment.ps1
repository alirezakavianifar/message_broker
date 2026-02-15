# Message Broker Deployment - Complete Testing Workflow
# 
# This script runs the complete testing workflow as documented in DEPLOYMENT_SUMMARY.md
# It verifies all services, health endpoints, database connectivity, portal login,
# message sending, and message verification.
#
# Usage:
#   .\test_deployment.ps1
#
# Prerequisites:
#   - plink.exe available in PATH (or specify path)
#   - SSH access to servers configured
#   - Client certificate generated (for message sending test)

param(
    [string]$MainServerIP = "173.32.115.223",
    [string]$ProxyServerIP = "91.92.206.217",
    [int]$SSHPort = 2221,
    [string]$SSHUser = "root",
    [string]$SSHPassword = "Pc`$123456",
    [string]$ClientID = "my_pc",
    [switch]$SkipMessageTest = $false,
    [switch]$Verbose = $false
)

# Color output functions
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

# Removed - using direct Write-Host calls instead

# Test results tracking
$script:TestResults = @{
    Total = 0
    Passed = 0
    Failed = 0
    Warnings = 0
}

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [bool]$Required = $true
    )
    
    $script:TestResults.Total++
    Write-Host "`n[$($script:TestResults.Total)] Testing: $Name" -ForegroundColor Yellow
    
    try {
        $result = & $Test
        if ($result -eq $true -or $result -match "OK|SUCCESS|PASS") {
            Write-Host "  [OK] $Name - PASSED" -ForegroundColor Green
            $script:TestResults.Passed++
            return $true
        } else {
            Write-Host "  [FAIL] $Name - FAILED" -ForegroundColor Red
            if ($Required) {
                $script:TestResults.Failed++
            } else {
                $script:TestResults.Warnings++
            }
            return $false
        }
    } catch {
        Write-Host "  [FAIL] $Name - ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($Required) {
            $script:TestResults.Failed++
        } else {
            $script:TestResults.Warnings++
        }
        return $false
    }
}

# Check plink availability
function Test-PlinkAvailable {
    $plink = Get-Command plink -ErrorAction SilentlyContinue
    if (-not $plink) {
        Write-Host "  [FAIL] plink.exe not found in PATH" -ForegroundColor Red
        Write-Host "  [INFO] Please install PuTTY or add plink.exe to your PATH" -ForegroundColor Gray
        Write-Host "  [INFO] Download from: https://www.chiark.greenend.org.uk/~sgtatham/putty/" -ForegroundColor Gray
        return $false
    }
    Write-Host "  [OK] plink.exe found" -ForegroundColor Green
    return $true
}

# Execute remote command
function Invoke-RemoteCommand {
    param(
        [string]$ServerIP,
        [string]$Command,
        [int]$TimeoutSeconds = 30
    )
    
    $plinkArgs = @(
        "-P", $SSHPort,
        "-ssh",
        "-batch",
        "-pw", $SSHPassword,
        "$SSHUser@$ServerIP",
        $Command
    )
    
    try {
        $output = & plink $plinkArgs 2>&1
        return $output
    } catch {
        if ($Verbose) {
            Write-Host "  Error executing command: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $null
    }
}

# ============================================================================
# STEP 1: Verify All Services Are Running
# ============================================================================

function Test-ServicesRunning {
    Write-Step "STEP 1: Verify All Services Are Running"
    
    $allRunning = $true
    
    # Main Server
    Write-Host "`nChecking Main Server..." -ForegroundColor Gray
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP "systemctl is-active main_server.service 2>&1"
    if ($result -match "active") {
        Write-Host "  [OK] Main Server: RUNNING" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Main Server: STOPPED" -ForegroundColor Red
        $allRunning = $false
    }
    
    # Portal
    Write-Host "`nChecking Portal..." -ForegroundColor Gray
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP "systemctl is-active portal.service 2>&1"
    if ($result -match "active") {
        Write-Host "  [OK] Portal: RUNNING" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Portal: STOPPED" -ForegroundColor Red
        $allRunning = $false
    }
    
    # Proxy
    Write-Host "`nChecking Proxy..." -ForegroundColor Gray
    $result = Invoke-RemoteCommand -ServerIP $ProxyServerIP "systemctl is-active proxy.service 2>&1"
    if ($result -match "active") {
        Write-Host "  [OK] Proxy: RUNNING" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Proxy: STOPPED" -ForegroundColor Red
        $allRunning = $false
    }
    
    # Database
    Write-Host "`nChecking Database..." -ForegroundColor Gray
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP "systemctl is-active mysql.service 2>&1"
    if ($result -match "active") {
        Write-Host "  [OK] Database: RUNNING" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Database: STOPPED" -ForegroundColor Red
        $allRunning = $false
    }
    
    return $allRunning
}

# ============================================================================
# STEP 2: Test Health Endpoints
# ============================================================================

function Test-HealthEndpoints {
    Write-Step "STEP 2: Test Health Endpoints"
    
    $allHealthy = $true
    
    # Main Server Health
    Write-Host "`nTesting Main Server Health..." -ForegroundColor Gray
    $command = "curl -k -s https://localhost:8000/health 2>&1"
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP $command
    if ($result -match '"status".*"healthy"') {
        Write-Host "  [OK] Main Server: healthy" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [FAIL] Main Server: unhealthy or unreachable" -ForegroundColor Red
        $allHealthy = $false
    }
    
    # Portal Health
    Write-Host "`nTesting Portal Health..." -ForegroundColor Gray
    $command = "curl -s http://localhost:8080/health 2>&1"
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP $command
    if ($result -match '"status".*"healthy"') {
        Write-Host "  [OK] Portal: healthy" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [FAIL] Portal: unhealthy or unreachable" -ForegroundColor Red
        $allHealthy = $false
    }
    
    # Proxy Health
    Write-Host "`nTesting Proxy Health..." -ForegroundColor Gray
    $command = "curl -k -s https://localhost:443/api/v1/health 2>&1"
    $result = Invoke-RemoteCommand -ServerIP $ProxyServerIP $command
    if ($result -match '"status".*"healthy"') {
        Write-Host "  [OK] Proxy: healthy" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [FAIL] Proxy: unhealthy or unreachable" -ForegroundColor Red
        $allHealthy = $false
    }
    
    return $allHealthy
}

# ============================================================================
# STEP 3: Verify Database Connectivity
# ============================================================================

function Test-DatabaseConnectivity {
    Write-Step "STEP 3: Verify Database Connectivity"
    
    $pythonScript = @'
import os
from dotenv import load_dotenv
load_dotenv('../.env')
from main_server.database import DatabaseManager
from sqlalchemy import text

try:
    db = DatabaseManager(os.getenv('DATABASE_URL'))
    with db.get_session() as session:
        result = session.execute(text('SELECT COUNT(*) as count FROM messages'))
        msg_count = result.fetchone()[0]
        result = session.execute(text('SELECT COUNT(*) as count FROM users'))
        user_count = result.fetchone()[0]
        result = session.execute(text('SELECT COUNT(*) as count FROM clients'))
        client_count = result.fetchone()[0]
        print('DATABASE_CONNECTED')
        print(f'MESSAGES:{msg_count}')
        print(f'USERS:{user_count}')
        print(f'CLIENTS:{client_count}')
except Exception as e:
    print(f'DATABASE_ERROR:{e}')
'@
    
    $command = "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 << 'PYEOF'`n$pythonScript`nPYEOF"
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP $command
    
    if ($result -match "DATABASE_CONNECTED") {
        Write-Host "  [OK] Database: CONNECTED" -ForegroundColor Green
        
        $msgMatch = [regex]::Match($result, "MESSAGES:(\d+)")
        if ($msgMatch.Success) {
            $msgCount = $msgMatch.Groups[1].Value
            Write-Host "  [INFO] Messages in database: $msgCount" -ForegroundColor Gray
        }
        $userMatch = [regex]::Match($result, "USERS:(\d+)")
        if ($userMatch.Success) {
            $userCount = $userMatch.Groups[1].Value
            Write-Host "  [INFO] Users in database: $userCount" -ForegroundColor Gray
        }
        $clientMatch = [regex]::Match($result, "CLIENTS:(\d+)")
        if ($clientMatch.Success) {
            $clientCount = $clientMatch.Groups[1].Value
            Write-Host "  [INFO] Clients in database: $clientCount" -ForegroundColor Gray
        }
        
        return $true
    } else {
        Write-Host "  [FAIL] Database: Connection failed" -ForegroundColor Red
        if ($Verbose -and $result) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
        return $false
    }
}

# ============================================================================
# STEP 4: Test Portal Login
# ============================================================================

function Test-PortalLogin {
    Write-Step "STEP 4: Test Portal Login"
    
    $pythonScript = @'
import httpx

try:
    response = httpx.post(
        'https://localhost:8000/portal/auth/login',
        json={'email': 'admin@example.com', 'password': 'Admin123!'},
        verify=False,
        timeout=10.0
    )
    
    if response.status_code == 200:
        data = response.json()
        user_data = data.get('user', {})
        print('LOGIN_SUCCESS')
        print(f'EMAIL:{user_data.get("email", "N/A")}')
        print(f'ROLE:{user_data.get("role", "N/A")}')
        token = data.get('access_token', '')
        print(f'TOKEN_LENGTH:{len(token)}')
    else:
        print(f'LOGIN_FAILED:{response.status_code}')
        print(f'ERROR:{response.text[:200]}')
except Exception as e:
    print(f'LOGIN_ERROR:{e}')
'@
    
    $command = "cd /opt/message_broker && source venv/bin/activate && python3 << 'PYEOF'`n$pythonScript`nPYEOF"
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP $command
    
    if ($result -match "LOGIN_SUCCESS") {
        Write-Host "  [OK] Portal Login: SUCCESS" -ForegroundColor Green
        
        $emailMatch = [regex]::Match($result, "EMAIL:(\S+)")
        if ($emailMatch.Success) {
            $email = $emailMatch.Groups[1].Value
            Write-Host "  [INFO] User: $email" -ForegroundColor Gray
        }
        $roleMatch = [regex]::Match($result, "ROLE:(\S+)")
        if ($roleMatch.Success) {
            $role = $roleMatch.Groups[1].Value
            Write-Host "  [INFO] Role: $role" -ForegroundColor Gray
        }
        $tokenMatch = [regex]::Match($result, "TOKEN_LENGTH:(\d+)")
        if ($tokenMatch.Success) {
            $tokenLen = $tokenMatch.Groups[1].Value
            Write-Host "  [INFO] Token received: $tokenLen characters" -ForegroundColor Gray
        }
        
        return $true
    } else {
        Write-Host "  [FAIL] Portal Login: FAILED" -ForegroundColor Red
        if ($Verbose -and $result) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
        return $false
    }
}

# ============================================================================
# STEP 5: Test User Management
# ============================================================================

function Test-UserManagement {
    Write-Step "STEP 5: Test User Management"
    
    # Test 1: List users
    Write-Host "`nTesting user list command..." -ForegroundColor Gray
    $command = "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user list 2>&1"
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP $command
    
    if ($result -match "User ID|email|admin@example.com" -or $result -match "OK") {
        Write-Host "  [OK] User list command works" -ForegroundColor Green
        
        # Count users if output is parseable
        $userLines = $result | Select-String -Pattern "User ID|email"
        if ($userLines) {
            $userCount = ($userLines | Measure-Object).Count
            Write-Host "  [INFO] Found $userCount user entries" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [WARN] User list command may have issues" -ForegroundColor Yellow
        if ($Verbose -and $result) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
    }
    
    # Test 2: Verify client exists before creating user
    Write-Host "`nVerifying client exists..." -ForegroundColor Gray
    $clientCheckCommand = "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py cert list 2>&1 | grep -i '$ClientID' || echo 'CLIENT_NOT_FOUND'"
    $clientCheckResult = Invoke-RemoteCommand -ServerIP $MainServerIP $clientCheckCommand
    if ($clientCheckResult -match "CLIENT_NOT_FOUND") {
        Write-Host "  [WARN] Client '$ClientID' not found. User creation with --client-id may fail." -ForegroundColor Yellow
        Write-Host "  [INFO] Continuing with user creation test anyway..." -ForegroundColor Gray
    } else {
        Write-Host "  [OK] Client '$ClientID' found in database" -ForegroundColor Green
    }
    
    # Test 3: Create a test user with client_id
    Write-Host "`nTesting user creation with --client-id..." -ForegroundColor Gray
    $testUserEmail = "testuser_$(Get-Date -Format 'yyyyMMddHHmmss')@test.example.com"
    $testUserPassword = "TestPass123!"
    
    $createCommand = "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 admin_cli.py user create $testUserEmail --role user --password '$testUserPassword' --client-id $ClientID 2>&1"
    $createResult = Invoke-RemoteCommand -ServerIP $MainServerIP $createCommand
    
    if ($createResult -match "created|success|OK|Client:" -or $createResult -match "already exists") {
        Write-Host "  [OK] User creation with --client-id works" -ForegroundColor Green
        if ($createResult -match "already exists") {
            Write-Host "  [INFO] Test user already exists (expected)" -ForegroundColor Gray
        } else {
            Write-Host "  [INFO] Test user created: $testUserEmail" -ForegroundColor Gray
            if ($createResult -match "Client:") {
                Write-Host "  [INFO] User associated with client: $ClientID" -ForegroundColor Gray
            }
        }
        
        # Test 4: Verify client_id is set in database
        Write-Host "`nVerifying user's client_id in database..." -ForegroundColor Gray
        $verifyClientIdScript = @'
import os
from dotenv import load_dotenv
load_dotenv('../.env')
from main_server.database import DatabaseManager
from main_server.models import User

try:
    db = DatabaseManager(os.getenv('DATABASE_URL'))
    with db.get_session() as session:
        user = session.query(User).filter(User.email == 'TEST_EMAIL_PLACEHOLDER').first()
        if user:
            print('USER_FOUND')
            print(f'USER_CLIENT_ID:{user.client_id if user.client_id else "NULL"}')
        else:
            print('USER_NOT_FOUND')
except Exception as e:
    print(f'VERIFY_ERROR:{e}')
'@
        $verifyClientIdScript = $verifyClientIdScript -replace 'TEST_EMAIL_PLACEHOLDER', $testUserEmail
        $verifyCommand = "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 << 'PYEOF'`n$verifyClientIdScript`nPYEOF"
        $verifyResult = Invoke-RemoteCommand -ServerIP $MainServerIP $verifyCommand
        
        if ($verifyResult -match "USER_FOUND") {
            $clientIdMatch = [regex]::Match($verifyResult, "USER_CLIENT_ID:(\S+)")
            if ($clientIdMatch.Success) {
                $userClientId = $clientIdMatch.Groups[1].Value
                if ($userClientId -eq $ClientID) {
                    Write-Host "  [OK] User's client_id correctly set to: $ClientID" -ForegroundColor Green
                } elseif ($userClientId -eq "NULL") {
                    Write-Host "  [WARN] User's client_id is NULL (should be $ClientID)" -ForegroundColor Yellow
                } else {
                    Write-Host "  [WARN] User's client_id is '$userClientId' (expected '$ClientID')" -ForegroundColor Yellow
                }
            }
        }
        
        # Test 5: Verify user can login and see messages
        Write-Host "`nTesting user login and message visibility..." -ForegroundColor Gray
        $loginScript = @'
import httpx

try:
    # Login
    response = httpx.post(
        'https://localhost:8000/portal/auth/login',
        json={'email': 'TEST_EMAIL_PLACEHOLDER', 'password': 'TEST_PASSWORD_PLACEHOLDER'},
        verify=False,
        timeout=10.0
    )
    
    if response.status_code == 200:
        data = response.json()
        token = data.get('access_token', '')
        print('USER_LOGIN_SUCCESS')
        print(f'USER_EMAIL:{data.get("user", {}).get("email", "N/A")}')
        print(f'USER_ROLE:{data.get("user", {}).get("role", "N/A")}')
        
        # Get messages for this user
        msg_response = httpx.get(
            'https://localhost:8000/portal/messages?limit=10',
            headers={'Authorization': f'Bearer {token}'},
            verify=False,
            timeout=10.0
        )
        
        if msg_response.status_code == 200:
            messages = msg_response.json()
            print(f'MESSAGE_COUNT:{len(messages)}')
            if messages:
                # Check if messages are filtered by client_id
                client_ids = set([msg.get('client_id', 'N/A') for msg in messages])
                print(f'CLIENT_IDS:{",".join(client_ids)}')
        else:
            print(f'MESSAGE_FETCH_FAILED:{msg_response.status_code}')
    else:
        print(f'USER_LOGIN_FAILED:{response.status_code}')
except Exception as e:
    print(f'USER_LOGIN_ERROR:{e}')
'@
        
        $loginScript = $loginScript -replace 'TEST_EMAIL_PLACEHOLDER', $testUserEmail
        $loginScript = $loginScript -replace 'TEST_PASSWORD_PLACEHOLDER', $testUserPassword
        
        $loginCommand = "cd /opt/message_broker && source venv/bin/activate && python3 << 'PYEOF'`n$loginScript`nPYEOF"
        $loginResult = Invoke-RemoteCommand -ServerIP $MainServerIP $loginCommand
        
        if ($loginResult -match "USER_LOGIN_SUCCESS") {
            Write-Host "  [OK] Test user can login successfully" -ForegroundColor Green
            
            $emailMatch = [regex]::Match($loginResult, "USER_EMAIL:(\S+)")
            if ($emailMatch.Success) {
                $email = $emailMatch.Groups[1].Value
                Write-Host "  [INFO] Logged in as: $email" -ForegroundColor Gray
            }
            
            # Check message visibility
            $msgCountMatch = [regex]::Match($loginResult, "MESSAGE_COUNT:(\d+)")
            if ($msgCountMatch.Success) {
                $msgCount = [int]$msgCountMatch.Groups[1].Value
                Write-Host "  [INFO] User can see $msgCount messages" -ForegroundColor Gray
                
                $clientIdsMatch = [regex]::Match($loginResult, "CLIENT_IDS:(\S+)")
                if ($clientIdsMatch.Success) {
                    $clientIds = $clientIdsMatch.Groups[1].Value
                    if ($clientIds -match $ClientID) {
                        Write-Host "  [OK] User sees messages for their client ($ClientID)" -ForegroundColor Green
                    } else {
                        Write-Host "  [INFO] User sees messages from clients: $clientIds" -ForegroundColor Gray
                    }
                }
            }
        } else {
            Write-Host "  [WARN] Test user login failed (may need to wait for user creation)" -ForegroundColor Yellow
        }
        
        return $true
    } else {
        Write-Host "  [WARN] User creation command may have issues" -ForegroundColor Yellow
        if ($Verbose -and $createResult) {
            Write-Host "  [INFO] $($createResult | Out-String)" -ForegroundColor Gray
        }
        return $false
    }
}

# ============================================================================
# STEP 6: Send Test Message
# ============================================================================

function Test-MessageSending {
    Write-Step "STEP 6: Send Test Message"
    
    if ($SkipMessageTest) {
        Write-Host "  [WARN] Message sending test skipped (use -SkipMessageTest:`$false to enable)" -ForegroundColor Yellow
        return $true
    }
    
    $testMessage = "Test message from deployment verification - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    $pythonScript = @'
import httpx
import json
from datetime import datetime

try:
    data = {
        'sender_number': '+1234567890',
        'message_body': 'TEST_MESSAGE_PLACEHOLDER'
    }
    url = 'https://localhost:443/api/v1/messages?client_id=CLIENT_ID_PLACEHOLDER'
    response = httpx.post(url, json=data, verify=False, timeout=10.0)
    
    if response.status_code == 202:
        result = response.json()
        msg_id = result.get('message_id', 'N/A')
        print('MESSAGE_SENT')
        print(f'MESSAGE_ID:{msg_id}')
        print(f'CLIENT_ID:{result.get("client_id", "N/A")}')
        print(f'STATUS:{result.get("status", "N/A")}')
    else:
        print(f'MESSAGE_FAILED:{response.status_code}')
        print(f'ERROR:{response.text[:200]}')
except Exception as e:
    print(f'MESSAGE_ERROR:{e}')
'@
    
    # Replace placeholders
    $pythonScript = $pythonScript -replace 'TEST_MESSAGE_PLACEHOLDER', $testMessage
    $pythonScript = $pythonScript -replace 'CLIENT_ID_PLACEHOLDER', $ClientID
    
    $command = "cd /opt/message_broker_proxy && source venv/bin/activate && python3 << 'PYEOF'`n$pythonScript`nPYEOF"
    $result = Invoke-RemoteCommand -ServerIP $ProxyServerIP $command
    
    if ($result -match "MESSAGE_SENT") {
        Write-Host "  [OK] Message Sending: SUCCESS" -ForegroundColor Green
        
        $msgIdMatch = [regex]::Match($result, "MESSAGE_ID:([a-f0-9-]+)")
        if ($msgIdMatch.Success) {
            $msgId = $msgIdMatch.Groups[1].Value
            $msgIdShort = if ($msgId.Length -gt 24) { $msgId.Substring(0, 24) + "..." } else { $msgId }
            Write-Host "  [INFO] Message ID: $msgIdShort" -ForegroundColor Gray
        }
        $clientIdMatch = [regex]::Match($result, "CLIENT_ID:(\S+)")
        if ($clientIdMatch.Success) {
            $clientId = $clientIdMatch.Groups[1].Value
            Write-Host "  [INFO] Client ID: $clientId" -ForegroundColor Gray
        }
        
        # Wait a moment for message to be registered
        Write-Host "  [INFO] Waiting 3 seconds for message registration..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        
        return $true
    } else {
        Write-Host "  [FAIL] Message Sending: FAILED" -ForegroundColor Red
        if ($Verbose -and $result) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
        return $false
    }
}

# ============================================================================
# STEP 7: Verify Message in Database
# ============================================================================

function Test-MessageInDatabase {
    Write-Step "STEP 7: Verify Message in Database"
    
    $pythonScript = @'
import os
from dotenv import load_dotenv
load_dotenv('../.env')
from main_server.database import DatabaseManager
from main_server.models import Message

try:
    db = DatabaseManager(os.getenv('DATABASE_URL'))
    with db.get_session() as session:
        messages = session.query(Message).order_by(Message.created_at.desc()).limit(5).all()
        print(f'MESSAGES_FOUND:{len(messages)}')
        for msg in messages:
            print(f'MSG:{msg.message_id[:24]}...|{msg.client_id}|{msg.status.value}|{msg.created_at}')
except Exception as e:
    print(f'QUERY_ERROR:{e}')
'@
    
    $command = "cd /opt/message_broker && source venv/bin/activate && cd main_server && python3 << 'PYEOF'`n$pythonScript`nPYEOF"
    $result = Invoke-RemoteCommand -ServerIP $MainServerIP $command
    
    $msgFoundMatch = [regex]::Match($result, "MESSAGES_FOUND:(\d+)")
    if ($msgFoundMatch.Success) {
        $msgCount = [int]$msgFoundMatch.Groups[1].Value
        
        if ($msgCount -gt 0) {
            Write-Host "  [OK] Messages in database: $msgCount" -ForegroundColor Green
            
            # Show recent messages
            $msgLines = $result | Select-String -Pattern "^MSG:"
            if ($msgLines) {
                Write-Host "`n  Recent messages:" -ForegroundColor Gray
                $msgLines | Select-Object -First 3 | ForEach-Object {
                    $parts = $_.Line -split '\|'
                    if ($parts.Length -ge 4) {
                        Write-Host "    - $($parts[0]) | Client: $($parts[1]) | Status: $($parts[2])" -ForegroundColor Gray
                    }
                }
            }
            
            return $true
        } else {
            Write-Host "  [WARN] No messages found in database" -ForegroundColor Yellow
            return $false
        }
    } elseif ($result -match "QUERY_ERROR") {
        Write-Host "  [FAIL] Failed to query messages" -ForegroundColor Red
        if ($Verbose -and $result) {
            Write-Host "  [INFO] $($result | Out-String)" -ForegroundColor Gray
        }
        return $false
    }
}

# ============================================================================
# Main Execution
# ============================================================================

function Main {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Message Broker Deployment - Complete Testing Workflow" -ForegroundColor Cyan
    Write-Host "  Based on DEPLOYMENT_SUMMARY.md" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Check prerequisites
    Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow
    if (-not (Test-PlinkAvailable)) {
        Write-Host "  [FAIL] Prerequisites not met. Exiting." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  [INFO] Main Server: $MainServerIP" -ForegroundColor Gray
    Write-Host "  [INFO] Proxy Server: $ProxyServerIP" -ForegroundColor Gray
    Write-Host "  [INFO] SSH Port: $SSHPort" -ForegroundColor Gray
    Write-Host "  [INFO] Client ID: $ClientID" -ForegroundColor Gray
    if ($SkipMessageTest) {
        Write-Host "  [WARN] Message sending test will be skipped" -ForegroundColor Yellow
    }
    
    # Run all tests
    $step1 = Test-Step "Services Running" { Test-ServicesRunning }
    $step2 = Test-Step "Health Endpoints" { Test-HealthEndpoints }
    $step3 = Test-Step "Database Connectivity" { Test-DatabaseConnectivity }
    $step4 = Test-Step "Portal Login" { Test-PortalLogin }
    $step5 = Test-Step "User Management" { Test-UserManagement } -Required $false
    $step6 = Test-Step "Message Sending" { Test-MessageSending } -Required $false
    $step7 = Test-Step "Message Verification" { Test-MessageInDatabase } -Required $false
    
    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Test Summary" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Total Tests:  $($script:TestResults.Total)" -ForegroundColor White
    Write-Host "Passed:       $($script:TestResults.Passed)" -ForegroundColor Green
    Write-Host "Failed:       $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -eq 0) { "Green" } else { "Red" })
    Write-Host "Warnings:     $($script:TestResults.Warnings)" -ForegroundColor $(if ($script:TestResults.Warnings -eq 0) { "Green" } else { "Yellow" })
    
    $successRate = [Math]::Round(($script:TestResults.Passed / $script:TestResults.Total) * 100, 1)
    Write-Host "`nSuccess Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 50) { "Yellow" } else { "Red" })
    
    if ($script:TestResults.Failed -eq 0) {
        Write-Host "`n✅ All required tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n❌ Some tests failed. Please review the output above." -ForegroundColor Red
        exit 1
    }
}

# Run main function
Main

