# How to Send Messages from Your PC

This guide explains how to send messages to the Message Broker service from your Windows PC.

## Prerequisites

1. **OpenSSL** - Required for certificate generation
   - Download from: https://slproweb.com/products/Win32OpenSSL.html
   - Or install via Chocolatey: `choco install openssl`

2. **PuTTY Tools** (plink and pscp) - Already available if you've been using the deployment scripts

## Step 1: Generate Client Certificate

You need a client certificate to authenticate with the proxy server. Run the certificate generation script:

```powershell
.\generate_client_cert.ps1 -ClientName "my_client" -ServerAddress "173.32.115.223"
```

**Parameters:**
- `-ClientName`: A unique name for your client (e.g., "my_pc", "john_doe")
- `-ServerAddress`: The main server address (default: 173.32.115.223)
- `-ValidityDays`: Certificate validity in days (default: 365)

**Example:**
```powershell
.\generate_client_cert.ps1 -ClientName "my_pc"
```

This will:
1. Download the CA certificate from the server
2. Generate a private key on your PC
3. Create a certificate signing request
4. Upload it to the server for signing
5. Download the signed certificate

**Output files** (in `client-scripts\certs\`):
- `my_client.crt` - Your client certificate
- `my_client.key` - Your private key (KEEP SECRET!)
- `ca.crt` - CA certificate

## Step 2: Send a Message

### Option A: Using PowerShell Script (Recommended for Windows)

```powershell
cd client-scripts
.\send_message.ps1 `
    -Sender "+1234567890" `
    -Message "Hello from my PC!" `
    -CertPath ".\certs\my_client.crt" `
    -KeyPath ".\certs\my_client.key" `
    -CaPath ".\certs\ca.crt" `
    -ProxyUrl "https://91.92.206.217:8001"
```

**Parameters:**
- `-Sender`: Phone number in E.164 format (must start with `+`)
- `-Message`: Your message text (max 1000 characters)
- `-CertPath`: Path to your client certificate
- `-KeyPath`: Path to your private key
- `-CaPath`: Path to CA certificate
- `-ProxyUrl`: Proxy server URL (default: https://localhost:8001)

### Option B: Using curl.exe

```powershell
curl.exe -X POST https://91.92.206.217:8001/api/v1/messages `
    --cert ".\client-scripts\certs\my_client.crt" `
    --key ".\client-scripts\certs\my_client.key" `
    --cacert ".\client-scripts\certs\ca.crt" `
    -H "Content-Type: application/json" `
    -d "{\"sender_number\":\"+1234567890\",\"message_body\":\"Hello from my PC!\"}"
```

### Option C: Using Python Script

```powershell
cd client-scripts
python send_message.py `
    --sender "+1234567890" `
    --message "Hello from my PC!" `
    --cert ".\certs\my_client.crt" `
    --key ".\certs\my_client.key" `
    --ca ".\certs\ca.crt" `
    --proxy-url "https://91.92.206.217:8001"
```

## Proxy Server Information

- **Proxy Server URL**: `https://91.92.206.217:8001`
- **API Endpoint**: `https://91.92.206.217:8001/api/v1/messages`
- **Port**: 8001 (HTTPS)

## Message Format Requirements

### Sender Number (E.164 Format)
- Must start with `+`
- Must include country code
- Only digits after the `+`
- Total length: 8-16 characters

**Valid examples:**
- `+1234567890` ✅
- `+442012345678` ✅
- `+491234567890` ✅

**Invalid examples:**
- `1234567890` ❌ (missing `+`)
- `+1-234-567-890` ❌ (contains dashes)
- `+1 234 567 890` ❌ (contains spaces)

### Message Body
- Required field
- Maximum length: 1000 characters
- Cannot be empty or whitespace-only

## Response Codes

- **202 Accepted**: Message successfully queued
- **400 Bad Request**: Invalid message format (check sender_number format)
- **401 Unauthorized**: Invalid or missing client certificate
- **429 Too Many Requests**: Rate limit exceeded (100 requests per 60 seconds)
- **500 Internal Server Error**: Server error
- **503 Service Unavailable**: Redis/main server unavailable

## Example Response (Success)

```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "client_id": "my_client",
  "queued_at": "2025-12-31T14:30:00Z",
  "position": 5
}
```

## Troubleshooting

### Certificate Errors

**Problem**: `401 Unauthorized` or certificate validation failed

**Solutions:**
1. Verify certificate files exist and are readable
2. Check certificates are in PEM format (text format, starts with `-----BEGIN`)
3. Verify certificate not expired: `openssl x509 -in client.crt -noout -dates`
4. Ensure certificate Common Name (CN) matches the client name you used

### Connection Errors

**Problem**: Cannot connect to proxy server

**Solutions:**
1. Verify proxy URL is correct: `https://91.92.206.217:8001`
2. Check network connectivity: `ping 91.92.206.217`
3. Verify firewall allows connection to port 8001
4. Check proxy service is running on the server

### Windows curl.exe Certificate Issues

**Problem**: `curl: (58) schannel: Failed to import cert file`

**Solutions:**
1. **Use the PowerShell script** (`send_message.ps1`) - Recommended
2. **Use Git Bash** (if Git for Windows is installed) - Git Bash includes OpenSSL-based curl
3. **Use WSL** (Windows Subsystem for Linux)

## Security Notes

⚠️ **Important Security Reminders:**

- ⚠️ **Never commit certificates to version control**
- ⚠️ **Keep your private key (`*.key`) secure** - Never share it!
- ⚠️ **Use secure networks when sending messages**
- ⚠️ **Rotate certificates periodically** (as per your organization's policy)

## Quick Reference

**Generate certificate:**
```powershell
.\generate_client_cert.ps1 -ClientName "my_client"
```

**Send message:**
```powershell
.\client-scripts\send_message.ps1 -Sender "+1234567890" -Message "Hello!" -ProxyUrl "https://91.92.206.217:8001"
```

## Need Help?

- Check the main [README.md](client-scripts/README.md) in `client-scripts/`
- Review [PLATFORM_NOTES.md](client-scripts/PLATFORM_NOTES.md) for platform-specific guidance
- Contact your system administrator

