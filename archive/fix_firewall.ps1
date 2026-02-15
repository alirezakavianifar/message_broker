# Script to help fix firewall issues for Message Broker services
# This script checks and opens ports 8000, 8001, and 8080

param(
    [string]$ServerIP = "91.92.206.217",
    [int]$SSHPort = 2223,
    [string]$Username = "root"
)

Write-Host "=== Message Broker Firewall Configuration ===" -ForegroundColor Cyan
Write-Host ""

# Check which firewall is running
Write-Host "1. Checking firewall status..." -ForegroundColor Green
$firewallCheck = ssh -p $SSHPort ${Username}@${ServerIP} @"
    if command -v ufw >/dev/null 2>&1; then
        echo 'UFW'
        ufw status
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo 'FIREWALLD'
        firewall-cmd --state
    elif command -v iptables >/dev/null 2>&1; then
        echo 'IPTABLES'
        iptables -L -n | head -10
    else
        echo 'NONE'
    fi
"@

Write-Host $firewallCheck
Write-Host ""

# Determine firewall type and provide commands
if ($firewallCheck -match "UFW") {
    Write-Host "2. Opening ports with UFW..." -ForegroundColor Green
    Write-Host ""
    Write-Host "Run these commands on the server:" -ForegroundColor Yellow
    Write-Host "  ssh -p $SSHPort ${Username}@${ServerIP}" -ForegroundColor White
    Write-Host "  ufw allow 8000/tcp" -ForegroundColor White
    Write-Host "  ufw allow 8001/tcp" -ForegroundColor White
    Write-Host "  ufw allow 8080/tcp" -ForegroundColor White
    Write-Host "  ufw reload" -ForegroundColor White
    Write-Host ""
    
    $openPorts = Read-Host "Would you like me to run these commands now? (y/n)"
    if ($openPorts -eq "y" -or $openPorts -eq "Y") {
        Write-Host "Opening ports..." -ForegroundColor Green
        ssh -p $SSHPort ${Username}@${ServerIP} "ufw allow 8000/tcp && ufw allow 8001/tcp && ufw allow 8080/tcp && ufw reload"
        Write-Host "Ports opened!" -ForegroundColor Green
    }
}
elseif ($firewallCheck -match "FIREWALLD") {
    Write-Host "2. Opening ports with firewalld..." -ForegroundColor Green
    Write-Host ""
    Write-Host "Run these commands on the server:" -ForegroundColor Yellow
    Write-Host "  ssh -p $SSHPort ${Username}@${ServerIP}" -ForegroundColor White
    Write-Host "  firewall-cmd --permanent --add-port=8000/tcp" -ForegroundColor White
    Write-Host "  firewall-cmd --permanent --add-port=8001/tcp" -ForegroundColor White
    Write-Host "  firewall-cmd --permanent --add-port=8080/tcp" -ForegroundColor White
    Write-Host "  firewall-cmd --reload" -ForegroundColor White
    Write-Host ""
    
    $openPorts = Read-Host "Would you like me to run these commands now? (y/n)"
    if ($openPorts -eq "y" -or $openPorts -eq "Y") {
        Write-Host "Opening ports..." -ForegroundColor Green
        ssh -p $SSHPort ${Username}@${ServerIP} "firewall-cmd --permanent --add-port=8000/tcp && firewall-cmd --permanent --add-port=8001/tcp && firewall-cmd --permanent --add-port=8080/tcp && firewall-cmd --reload"
        Write-Host "Ports opened!" -ForegroundColor Green
    }
}
elseif ($firewallCheck -match "IPTABLES") {
    Write-Host "2. Opening ports with iptables..." -ForegroundColor Green
    Write-Host ""
    Write-Host "Run these commands on the server:" -ForegroundColor Yellow
    Write-Host "  ssh -p $SSHPort ${Username}@${ServerIP}" -ForegroundColor White
    Write-Host "  iptables -A INPUT -p tcp --dport 8000 -j ACCEPT" -ForegroundColor White
    Write-Host "  iptables -A INPUT -p tcp --dport 8001 -j ACCEPT" -ForegroundColor White
    Write-Host "  iptables -A INPUT -p tcp --dport 8080 -j ACCEPT" -ForegroundColor White
    Write-Host "  iptables-save > /etc/iptables/rules.v4  # or use your distribution's method" -ForegroundColor White
    Write-Host ""
    Write-Host "Note: iptables rules need to be saved according to your distribution." -ForegroundColor Yellow
}
else {
    Write-Host "2. No local firewall detected." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The issue is likely:" -ForegroundColor Yellow
    Write-Host "  - Cloud provider firewall/security group blocking ports" -ForegroundColor White
    Write-Host "  - Network-level firewall" -ForegroundColor White
    Write-Host ""
}

Write-Host ""
Write-Host "3. Testing portal from server itself..." -ForegroundColor Green
$localTest = ssh -p $SSHPort ${Username}@${ServerIP} "curl -s http://localhost:8080 | head -20"
if ($localTest -match "html" -or $localTest -match "portal" -or $localTest.Length -gt 10) {
    Write-Host "  ✓ Portal works locally on the server" -ForegroundColor Green
    Write-Host "  This confirms the issue is firewall/network related" -ForegroundColor Yellow
} else {
    Write-Host "  ⚠ Portal may not be responding locally" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "=== Important Notes ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Cloud Provider Firewall:" -ForegroundColor Yellow
Write-Host "   Most cloud providers (AWS, Azure, GCP, DigitalOcean) have" -ForegroundColor White
Write-Host "   security groups or firewall rules that need to be configured separately." -ForegroundColor White
Write-Host ""
Write-Host "2. Required Ports:" -ForegroundColor Yellow
Write-Host "   - Port 8000: Main Server API (HTTPS)" -ForegroundColor White
Write-Host "   - Port 8001: Proxy Server API (HTTPS)" -ForegroundColor White
Write-Host "   - Port 8080: Portal (HTTP)" -ForegroundColor White
Write-Host ""
Write-Host "3. Test Access:" -ForegroundColor Yellow
Write-Host "   After opening ports, test from your PC:" -ForegroundColor White
$portalUrl = "http://${ServerIP}:8080"
$mainApiUrl = "https://${ServerIP}:8000/health"
$proxyApiUrl = "https://${ServerIP}:8001/health"
Write-Host "   - Portal: $portalUrl" -ForegroundColor White
Write-Host "   - Main API: $mainApiUrl" -ForegroundColor White
Write-Host "   - Proxy API: $proxyApiUrl" -ForegroundColor White
Write-Host ""

