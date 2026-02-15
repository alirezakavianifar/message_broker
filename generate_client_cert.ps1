# Generate Client Certificate for Message Broker
# This script generates a client certificate that you can use to send messages

param(
    [Parameter(Mandatory=$true)]
    [string]$ClientName,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerAddress = "173.32.115.223",
    
    [Parameter(Mandatory=$false)]
    [int]$ValidityDays = 365
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Generate Client Certificate" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if OpenSSL is available
if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: OpenSSL is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install OpenSSL:" -ForegroundColor Yellow
    Write-Host "  1. Download from: https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Yellow
    Write-Host "  2. Or use: choco install openssl" -ForegroundColor Yellow
    exit 1
}

# Check if CA certificates exist on server
Write-Host "[INFO] Connecting to server to check CA certificates..." -ForegroundColor Yellow
$caCheck = plink -P 2221 -ssh -batch -pw "Pc`$123456" root@$ServerAddress "test -f /opt/message_broker/main_server/certs/ca.crt && echo 'EXISTS' || echo 'NOT_FOUND'"

if ($caCheck -notmatch "EXISTS") {
    Write-Host "ERROR: CA certificate not found on server" -ForegroundColor Red
    Write-Host "Please ensure the main server is properly set up" -ForegroundColor Yellow
    exit 1
}

# Create local certs directory
$certsDir = ".\client-scripts\certs"
if (-not (Test-Path $certsDir)) {
    New-Item -ItemType Directory -Path $certsDir -Force | Out-Null
}

# Download CA certificate from server
Write-Host "`n[1/5] Downloading CA certificate from server..." -ForegroundColor Cyan
pscp -P 2221 -batch -pw "Pc`$123456" root@${ServerAddress}:/opt/message_broker/main_server/certs/ca.crt "$certsDir\ca.crt"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to download CA certificate" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ CA certificate downloaded" -ForegroundColor Green

# Generate client private key
Write-Host "`n[2/5] Generating client private key..." -ForegroundColor Cyan
$keyPath = "$certsDir\$ClientName.key"
& openssl genrsa -out $keyPath 2048
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to generate private key" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Private key generated: $keyPath" -ForegroundColor Green

# Generate Certificate Signing Request
Write-Host "`n[3/5] Generating Certificate Signing Request..." -ForegroundColor Cyan
$csrPath = "$certsDir\$ClientName.csr"
$subj = "/CN=$ClientName/O=MessageBroker/OU=Client"
& openssl req -new -key $keyPath -out $csrPath -subj $subj
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to generate CSR" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ CSR generated" -ForegroundColor Green

# Upload CSR to server and sign it
Write-Host "`n[4/5] Uploading CSR to server for signing..." -ForegroundColor Cyan
pscp -P 2221 -batch -pw "Pc`$123456" $csrPath root@${ServerAddress}:/tmp/$ClientName.csr
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to upload CSR" -ForegroundColor Red
    exit 1
}

# Sign certificate on server
Write-Host "  Signing certificate on server..." -ForegroundColor Cyan
$bashScriptContent = 'cd /opt/message_broker/main_server/certs' + "`n"
$bashScriptContent += "if openssl x509 -req -in /tmp/$ClientName.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out /tmp/$ClientName.crt -days $ValidityDays -sha256; then" + "`n"
$bashScriptContent += "    echo SUCCESS" + "`n"
$bashScriptContent += "else" + "`n"
$bashScriptContent += "    echo FAILED" + "`n"
$bashScriptContent += "fi"
# Write script to temp file and execute
$tempScript = [System.IO.Path]::GetTempFileName()
$bashScriptContent | Out-File -FilePath $tempScript -Encoding ASCII
pscp -P 2221 -batch -pw "Pc`$123456" $tempScript root@${ServerAddress}:/tmp/sign_cert.sh | Out-Null
$signResult = plink -P 2221 -ssh -batch -pw "Pc`$123456" root@$ServerAddress "bash /tmp/sign_cert.sh"
Remove-Item $tempScript -ErrorAction SilentlyContinue
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@$ServerAddress "rm -f /tmp/sign_cert.sh" | Out-Null

if ($signResult -notmatch "SUCCESS") {
    Write-Host "ERROR: Failed to sign certificate on server" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Certificate signed" -ForegroundColor Green

# Download signed certificate
Write-Host "`n[5/5] Downloading signed certificate..." -ForegroundColor Cyan
$certPath = "$certsDir\$ClientName.crt"
pscp -P 2221 -batch -pw "Pc`$123456" root@${ServerAddress}:/tmp/$ClientName.crt $certPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to download signed certificate" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Certificate downloaded: $certPath" -ForegroundColor Green

# Clean up temporary files on server
plink -P 2221 -ssh -batch -pw "Pc`$123456" root@$ServerAddress "rm -f /tmp/$ClientName.csr /tmp/$ClientName.crt" | Out-Null

# Display summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Certificate Generated Successfully!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Certificate Files:" -ForegroundColor Cyan
Write-Host "  Client Certificate: $certPath" -ForegroundColor White
Write-Host "  Private Key:        $keyPath" -ForegroundColor White
Write-Host "  CA Certificate:     $certsDir\ca.crt" -ForegroundColor White
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Use the PowerShell script to send messages:" -ForegroundColor Yellow
Write-Host "     .\client-scripts\send_message.ps1 -Sender `"+1234567890`" -Message `"Hello!`" -ProxyUrl `"https://91.92.206.217:8001`"" -ForegroundColor White
Write-Host ""
Write-Host "  2. Or use curl directly:" -ForegroundColor Yellow
Write-Host "     curl.exe -X POST https://91.92.206.217:8001/api/v1/messages `" -ForegroundColor White
Write-Host "       --cert `"$certPath`" --key `"$keyPath`" --cacert `"$certsDir\ca.crt`" `" -ForegroundColor White
Write-Host "       -H `"Content-Type: application/json`" `" -ForegroundColor White
Write-Host "       -d `"{\`"sender_number\`":\`"+1234567890\`",\`"message_body\`":\`"Hello!\`"}`"" -ForegroundColor White
Write-Host ""

