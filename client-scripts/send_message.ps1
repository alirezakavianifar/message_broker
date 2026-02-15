# Message Broker Client - PowerShell Script Example
#
# This script demonstrates how to send messages using PowerShell (no Python required).
#
# Usage:
#   .\send_message.ps1 -Sender "+1234567890" -Message "Hello, world!"
#
# Or with custom certificates and URL:
#   .\send_message.ps1 -Sender "+1234567890" -Message "Hello, world!" `
#     -CertPath ".\certs\client.crt" `
#     -KeyPath ".\certs\client.key" `
#     -CaPath ".\certs\ca.crt" `
#     -ProxyUrl "https://your-server:8001"

param(
    [Parameter(Mandatory=$true)]
    [string]$Sender,
    
    [Parameter(Mandatory=$true)]
    [string]$Message,
    
    [Parameter(Mandatory=$false)]
    [string]$CertPath = ".\certs\client.crt",
    
    [Parameter(Mandatory=$false)]
    [string]$KeyPath = ".\certs\client.key",
    
    [Parameter(Mandatory=$false)]
    [string]$CaPath = ".\certs\ca.crt",
    
    [Parameter(Mandatory=$false)]
    [string]$ProxyUrl = "https://91.92.206.217:443",
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Show help
if ($Help) {
    Write-Host "Message Broker Client - PowerShell Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\send_message.ps1 -Sender <phone> -Message <text> [options]"
    Write-Host ""
    Write-Host "Required Parameters:"
    Write-Host "  -Sender <phone>        Phone number in E.164 format (e.g., +1234567890)"
    Write-Host "  -Message <text>        Message body (max 1000 characters)"
    Write-Host ""
    Write-Host "Optional Parameters:"
    Write-Host "  -CertPath <path>       Path to client certificate (default: .\certs\client.crt)"
    Write-Host "  -KeyPath <path>        Path to client private key (default: .\certs\client.key)"
    Write-Host "  -CaPath <path>         Path to CA certificate (default: .\certs\ca.crt)"
    Write-Host "  -ProxyUrl <url>        Proxy server URL (default: https://localhost:8001)"
    Write-Host "  -Help                  Show this help message"
    Write-Host ""
    exit 0
}

# Validate sender number format
if ($Sender -notmatch '^\+\d{7,15}$') {
    Write-Host "Error: Invalid sender number format" -ForegroundColor Red
    Write-Host "Sender number must be in E.164 format: +[country code][number]" -ForegroundColor Yellow
    Write-Host "Example: +1234567890" -ForegroundColor Yellow
    exit 1
}

# Validate message length
if ($Message.Length -gt 1000) {
    Write-Host "Error: Message body exceeds 1000 characters" -ForegroundColor Red
    exit 1
}

# Check certificate files exist
if (-not (Test-Path $CertPath)) {
    Write-Host "Error: Certificate file not found: $CertPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $KeyPath)) {
    Write-Host "Error: Private key file not found: $KeyPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $CaPath)) {
    Write-Host "Error: CA certificate file not found: $CaPath" -ForegroundColor Red
    exit 1
}

# Prepare JSON payload
$body = @{
    sender_number = $Sender
    message_body = $Message
} | ConvertTo-Json -Compress

Write-Host "Sending message..." -ForegroundColor Yellow
Write-Host "  Sender: $Sender"
Write-Host "  Message: $Message"
Write-Host "  Proxy: $ProxyUrl"
Write-Host "  Certificate: $CertPath"
Write-Host ("-" * 50)

# For proper mTLS in PowerShell, we recommend using curl.exe (which is available on Windows 10+)
# Note: PowerShell aliases 'curl' to Invoke-WebRequest, so we must use 'curl.exe' explicitly

$curlExe = "curl.exe"
if (Get-Command $curlExe -ErrorAction SilentlyContinue) {
    # Use curl.exe if available (Windows 10+ has curl.exe)
    try {
        # Build curl command arguments
        $curlArgs = @(
            "-X", "POST",
            "$ProxyUrl/api/v1/messages",
            "--cert", $CertPath,
            "--key", $KeyPath,
            "--cacert", $CaPath,
            "-H", "Content-Type: application/json",
            "-d", $body
        )
        
        Write-Host "Executing curl.exe..." -ForegroundColor Cyan
        $response = & $curlExe $curlArgs 2>&1
        
        # Check exit code
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Message sent successfully!" -ForegroundColor Green
            Write-Host $response
            exit 0
        }
        else {
            Write-Host "✗ Error sending message (exit code: $LASTEXITCODE)" -ForegroundColor Red
            Write-Host $response -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-Host "✗ Error executing curl.exe" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Error: curl.exe is not available" -ForegroundColor Red
    Write-Host "Please install curl or use the Python script" -ForegroundColor Yellow
    Write-Host "Alternatively, use Invoke-RestMethod with proper certificate handling" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "For proper mTLS support in PowerShell, you may need to:" -ForegroundColor Yellow
    Write-Host "  1. Convert certificates to PFX format" -ForegroundColor Yellow
    Write-Host "  2. Use .NET HttpClient with X509Certificate2" -ForegroundColor Yellow
    Write-Host "  3. Install curl.exe" -ForegroundColor Yellow
    exit 1
}

