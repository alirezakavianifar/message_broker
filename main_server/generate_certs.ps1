# Generate certificates for all components
param(
    [string]$ClientName = "server",
    [string]$Domain = "localhost",
    [int]$ValidityDays = 365
)

$ErrorActionPreference = "Stop"

Write-Host "`nGenerating certificate for: $ClientName" -ForegroundColor Cyan

# Create config for certificate
$config = @"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $ClientName
O = MessageBroker
C = US

[v3_req]
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $Domain
DNS.2 = localhost
IP.1 = 127.0.0.1
"@

$configFile = "certs\${ClientName}_temp.cnf"
$config | Out-File -FilePath $configFile -Encoding ASCII

try {
    # Generate private key
    Write-Host "  1. Generating private key..."
    $result = openssl genrsa -out "certs\${ClientName}.key" 2048 2>&1
    Write-Host "     ✓ Private key generated"
    
    # Generate CSR
    Write-Host "  2. Generating certificate signing request..."
    $result = openssl req -new -key "certs\${ClientName}.key" -out "certs\${ClientName}.csr" -config $configFile 2>&1
    Write-Host "     ✓ CSR generated"
    
    # Sign with CA
    Write-Host "  3. Signing certificate with CA..."
    $result = openssl x509 -req -in "certs\${ClientName}.csr" -CA "certs\ca.crt" -CAkey "certs\ca.key" -CAcreateserial -out "certs\${ClientName}.crt" -days $ValidityDays -sha256 -extensions v3_req -extfile $configFile 2>&1
    Write-Host "     ✓ Certificate signed"
    
    # Clean up
    Remove-Item "certs\${ClientName}.csr" -ErrorAction SilentlyContinue
    Remove-Item $configFile -ErrorAction SilentlyContinue
    
    Write-Host "`n✓ Certificate generated successfully!" -ForegroundColor Green
    Write-Host "   Key: certs\${ClientName}.key"
    Write-Host "   Cert: certs\${ClientName}.crt"
    
} catch {
    Write-Host "`n✗ Error generating certificate: $_" -ForegroundColor Red
    exit 1
}

