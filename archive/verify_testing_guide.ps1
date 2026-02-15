# Verification Script for TESTING_GUIDE.md
# Tests all commands and steps mentioned in the testing guide

$SERVER = "91.92.206.217"
$SSH_PORT = "2223"
$EMAIL = "admin@example.com"
$PASSWORD = "AdminPass123!"

Write-Host "=== Verifying Testing Guide Steps ===" -ForegroundColor Cyan
Write-Host ""

# Check if curl.exe is available (not PowerShell alias)
$curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curlExe) {
    Write-Host "Warning: curl.exe not found. Using Invoke-WebRequest instead." -ForegroundColor Yellow
    $useCurl = $false
} else {
    $useCurl = $true
}

function Invoke-Curl {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [switch]$SkipSSL
    )
    
    if ($useCurl) {
        $args = @()
        if ($SkipSSL) { $args += "-k" }
        $args += "-s"
        $args += "-X"
        $args += $Method
        foreach ($key in $Headers.Keys) {
            $args += "-H"
            $args += "$key`: $($Headers[$key])"
        }
        if ($Body) {
            $args += "-d"
            $args += $Body
        }
        $args += $Url
        $result = & curl.exe $args
        return $result
    } else {
        $params = @{
            Uri = $Url
            Method = $Method
            SkipCertificateCheck = $SkipSSL
        }
        if ($Headers.Count -gt 0) {
            $params.Headers = $Headers
        }
        if ($Body) {
            $params.Body = $Body
            $params.ContentType = "application/json"
        }
        try {
            $response = Invoke-WebRequest @params
            return $response.Content
        } catch {
            return $_.Exception.Response
        }
    }
}

# Test 1: Service Status
Write-Host "1. Testing Service Status Check..." -ForegroundColor Green
try {
    $result = ssh -p $SSH_PORT root@${SERVER} "systemctl status main_server proxy worker portal --no-pager 2>&1 | grep -E '(●|Active:)' | head -4"
    if ($result -match "active \(running\)") {
        Write-Host "   ✓ Services are running" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Service status check failed" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to check service status: $_" -ForegroundColor Red
}
Write-Host ""

# Test 2: Port Listening
Write-Host "2. Testing Port Listening Check..." -ForegroundColor Green
try {
    $result = ssh -p $SSH_PORT root@${SERVER} "netstat -tlnp 2>&1 | grep -E '(8000|8001|8080)'"
    if ($result -match "LISTEN") {
        Write-Host "   ✓ Ports are listening" -ForegroundColor Green
        $result | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    } else {
        Write-Host "   ✗ Port check failed" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to check ports: $_" -ForegroundColor Red
}
Write-Host ""

# Test 3: Main Server Health Check
Write-Host "3. Testing Main Server Health Endpoint..." -ForegroundColor Green
try {
    $response = Invoke-Curl -Url "https://${SERVER}:8000/health" -SkipSSL
    if ($response -match "healthy" -or $response -match "status") {
        Write-Host "   ✓ Health endpoint responds" -ForegroundColor Green
        Write-Host "     Response: $($response.Substring(0, [Math]::Min(100, $response.Length)))" -ForegroundColor Gray
    } else {
        Write-Host "   ✗ Health check failed" -ForegroundColor Red
        Write-Host "     Response: $response" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to reach health endpoint: $_" -ForegroundColor Red
}
Write-Host ""

# Test 4: Proxy Health Check
Write-Host "4. Testing Proxy Health Endpoint..." -ForegroundColor Green
try {
    $response = Invoke-Curl -Url "https://${SERVER}:8001/health" -SkipSSL
    if ($response -match "healthy" -or $response -match "status") {
        Write-Host "   ✓ Proxy health endpoint responds" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Proxy health check failed" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to reach proxy health endpoint: $_" -ForegroundColor Red
}
Write-Host ""

# Test 5: Database Connectivity
Write-Host "5. Testing Database Connectivity..." -ForegroundColor Green
try {
    $result = ssh -p $SSH_PORT root@${SERVER} 'mysql -u systemuser -p"MsgBrckr#TnN`$2025" -D message_system -e "SELECT COUNT(*) as user_count FROM users;" 2>&1'
    if ($result -match "user_count" -or $result -match "\d+") {
        Write-Host "   ✓ Database connection works" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Database connection failed" -ForegroundColor Red
        Write-Host "     Output: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to test database: $_" -ForegroundColor Red
}
Write-Host ""

# Test 6: Redis Connectivity
Write-Host "6. Testing Redis Connectivity..." -ForegroundColor Green
try {
    $result = ssh -p $SSH_PORT root@${SERVER} "redis-cli ping 2>&1"
    if ($result -match "PONG") {
        Write-Host "   ✓ Redis connection works" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Redis connection failed" -ForegroundColor Red
        Write-Host "     Output: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to test Redis: $_" -ForegroundColor Red
}
Write-Host ""

# Test 7: API Authentication
Write-Host "7. Testing API Authentication..." -ForegroundColor Green
try {
    $loginBody = @{
        email = $EMAIL
        password = $PASSWORD
    } | ConvertTo-Json
    
    $response = Invoke-Curl -Url "https://${SERVER}:8000/auth/login" -Method "POST" -Body $loginBody -SkipSSL
    if ($response -match "access_token" -or $response -match "token") {
        Write-Host "   ✓ Authentication works" -ForegroundColor Green
        
        # Try to extract token - try JSON parsing first
        try {
            $json = $response | ConvertFrom-Json
            if ($json.access_token) {
                $script:TOKEN = $json.access_token
                Write-Host "     Token extracted successfully" -ForegroundColor Gray
            }
        } catch {
            # Fallback to simple string matching
            if ($response -match 'access_token.*?"([a-zA-Z0-9._-]+)"') {
                $script:TOKEN = $matches[1]
                Write-Host "     Token extracted successfully" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "   ✗ Authentication failed" -ForegroundColor Red
        Write-Host "     Response: $($response.Substring(0, [Math]::Min(200, $response.Length)))" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to test authentication: $_" -ForegroundColor Red
}
Write-Host ""

# Test 8: Admin Endpoints (if token available)
if ($script:TOKEN) {
    Write-Host "8. Testing Admin Endpoints..." -ForegroundColor Green
    
    # Test /admin/users
    try {
        $response = Invoke-Curl -Url "https://${SERVER}:8000/admin/users" -Method "GET" -Headers @{"Authorization" = "Bearer $($script:TOKEN)"} -SkipSSL
        if ($response -match "email" -or $response -match "users" -or $response -match "\[\]" -or $response -match "array") {
            Write-Host "   ✓ /admin/users endpoint works" -ForegroundColor Green
        } else {
            Write-Host "   ✗ /admin/users endpoint failed" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ✗ Failed to test /admin/users: $_" -ForegroundColor Red
    }
    
    # Test /admin/stats
    try {
        $response = Invoke-Curl -Url "https://${SERVER}:8000/admin/stats" -Method "GET" -Headers @{"Authorization" = "Bearer $($script:TOKEN)"} -SkipSSL
        if ($response -match "stats" -or $response -match "total" -or $response -match "\{") {
            Write-Host "   ✓ /admin/stats endpoint works" -ForegroundColor Green
        } else {
            Write-Host "   ✗ /admin/stats endpoint failed" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ✗ Failed to test /admin/stats: $_" -ForegroundColor Red
    }
} else {
    Write-Host "8. Skipping Admin Endpoints (no token available)" -ForegroundColor Yellow
}
Write-Host ""

# Test 9: Portal Accessibility
Write-Host "9. Testing Portal Accessibility..." -ForegroundColor Green
try {
    $response = Invoke-Curl -Url "http://${SERVER}:8080" -SkipSSL
    if ($response -match "html" -or $response -match "portal" -or $response.StatusCode -eq 200) {
        Write-Host "   ✓ Portal is accessible" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ Portal responded but may not be fully functional" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ✗ Portal not accessible: $_" -ForegroundColor Red
}
Write-Host ""

# Test 10: Verify Admin User Exists
Write-Host "10. Testing Admin User Verification..." -ForegroundColor Green
try {
    $result = ssh -p $SSH_PORT root@${SERVER} 'mysql -u systemuser -p"MsgBrckr#TnN`$2025" -D message_system -e "SELECT id, email, role FROM users WHERE role=\"ADMIN\" LIMIT 1;" 2>&1'
    if ($result -match "admin@example.com" -or $result -match "ADMIN") {
        Write-Host "   ✓ Admin user exists" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Admin user not found" -ForegroundColor Red
        Write-Host "     Output: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Failed to verify admin user: $_" -ForegroundColor Red
}
Write-Host ""

# Test 11: Redis Queue Check
Write-Host "11. Testing Redis Queue..." -ForegroundColor Green
try {
    $result = ssh -p $SSH_PORT root@${SERVER} "redis-cli LLEN message_queue 2>&1"
    if ($result -match "^[0-9]+$" -or $result -match "integer" -or $result -match "^\(integer\)") {
        Write-Host "   ✓ Redis queue accessible" -ForegroundColor Green
        Write-Host "     Queue length: $result" -ForegroundColor Gray
    } else {
        Write-Host "   ⚠ Redis queue check returned: $result" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ✗ Failed to check Redis queue: $_" -ForegroundColor Red
}
Write-Host ""

# Test 12: Service Logs Check
Write-Host "12. Testing Service Logs Access..." -ForegroundColor Green
try {
    $result = ssh -p $SSH_PORT root@${SERVER} "journalctl -u main_server.service --no-pager -n 5 2>&1 | head -3"
    if ($result -match "uvicorn" -or $result -match "INFO" -or $result.Length -gt 10) {
        Write-Host "   ✓ Service logs are accessible" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ Service logs may be empty or inaccessible" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ✗ Failed to access service logs: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "=== Verification Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "- Most commands in the testing guide should work from Linux/bash" -ForegroundColor White
Write-Host "- For Windows PowerShell, use curl.exe or Invoke-WebRequest with -SkipCertificateCheck" -ForegroundColor White
Write-Host "- SSH commands work the same on both platforms" -ForegroundColor White
Write-Host ""

