# Message Broker Client Scripts

This directory contains example client implementations for sending messages to the Message Broker system.

## Important: Thin Client Architecture

**The Message Broker uses a thin client architecture.** This means:

- ✅ **No Python or special libraries required** - Use any HTTP client
- ✅ **No virtual environments needed** - Use curl, Postman, or any HTTP tool
- ✅ **Works with any programming language** - JavaScript, Go, Java, Python, etc.
- ✅ **Zero client-side dependencies** - Just send HTTP POST requests

The proxy server handles all the complex logic (validation, queuing, etc.). Clients just need to send HTTP requests with mutual TLS certificates.

## Quick Start

### Using curl (Linux/Mac/WSL - Recommended)

**Note**: On Linux, macOS, and WSL, curl uses OpenSSL which works seamlessly with PEM certificates.

```bash
curl -X POST https://your-server:8001/api/v1/messages \
  --cert client.crt \
  --key client.key \
  --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{
    "sender_number": "+1234567890",
    "message_body": "Hello, world!"
  }'
```

See `send_message.sh` for a complete bash script example.

### Using PowerShell Script (Windows - Recommended)

**For Windows users**, we recommend using the PowerShell script (`send_message.ps1`) instead of curl.exe directly. Windows curl.exe uses Schannel which has different certificate handling and may have issues with PEM format certificates.

```powershell
.\send_message.ps1 -Sender "+1234567890" -Message "Hello, world!"
```

The PowerShell script handles certificate paths correctly and works reliably on Windows.

### Using Python (Optional Convenience Script)

The `send_message.py` script is provided as a **convenience tool only**. You don't need it - any HTTP client works!

**Requirements** (only if using Python script):
- Python 3.8+
- Install dependencies: `pip install -r requirements.txt`

**Usage**:
```bash
python send_message.py \
  --sender "+1234567890" \
  --message "Hello, world!" \
  --cert client.crt \
  --key client.key \
  --ca ca.crt \
  --proxy-url https://your-server:8001
```

## API Details

### Endpoint

```
POST https://your-server:8001/api/v1/messages
```

### Authentication

Mutual TLS (mTLS) is required. You must provide:
- Client certificate (`client.crt`)
- Client private key (`client.key`)
- CA certificate (`ca.crt`)

### Request Body

```json
{
  "sender_number": "+1234567890",
  "message_body": "Your message text here"
}
```

**Fields**:
- `sender_number` (required): Phone number in E.164 format (must start with `+`)
- `message_body` (required): Message text (max 1000 characters)
- `metadata` (optional): Additional metadata (not typically needed)

### Response

```json
{
  "message_id": "uuid-here",
  "status": "queued",
  "client_id": "your-client-id",
  "queued_at": "2025-01-15T10:30:00Z",
  "position": 5
}
```

**HTTP Status Codes**:
- `202 Accepted`: Message successfully queued
- `400 Bad Request`: Invalid message format (check sender_number format)
- `401 Unauthorized`: Invalid or missing client certificate
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error (contact support)
- `503 Service Unavailable`: Redis/main server unavailable

## Examples

### Bash Script (curl) - Linux/Mac/WSL

See `send_message.sh` for a complete example with error handling.

**Platform Note**: This script works best on Linux, macOS, and WSL where curl uses OpenSSL. For Windows native environments, use the PowerShell script instead.

### PowerShell Script (Windows)

See `send_message.ps1` for a Windows PowerShell example.

### Python Script

See `send_message.py` for a Python convenience wrapper (optional).

### JavaScript/Node.js

```javascript
const https = require('https');
const fs = require('fs');

const options = {
  hostname: 'your-server',
  port: 8001,
  path: '/api/v1/messages',
  method: 'POST',
  cert: fs.readFileSync('client.crt'),
  key: fs.readFileSync('client.key'),
  ca: fs.readFileSync('ca.crt'),
  headers: { 'Content-Type': 'application/json' }
};

const data = JSON.stringify({
  sender_number: '+1234567890',
  message_body: 'Hello, world!'
});

const req = https.request(options, (res) => {
  let body = '';
  res.on('data', (chunk) => { body += chunk; });
  res.on('end', () => console.log(JSON.parse(body)));
});

req.on('error', (e) => console.error(e));
req.write(data);
req.end();
```

### Go

```go
package main

import (
    "bytes"
    "crypto/tls"
    "crypto/x509"
    "encoding/json"
    "io/ioutil"
    "net/http"
)

func main() {
    // Load certificates
    cert, _ := tls.LoadX509KeyPair("client.crt", "client.key")
    caCert, _ := ioutil.ReadFile("ca.crt")
    caCertPool := x509.NewCertPool()
    caCertPool.AppendCertsFromPEM(caCert)

    // Configure TLS
    tlsConfig := &tls.Config{
        Certificates: []tls.Certificate{cert},
        RootCAs:      caCertPool,
    }

    // Create HTTP client
    client := &http.Client{
        Transport: &http.Transport{TLSClientConfig: tlsConfig},
    }

    // Prepare request
    data, _ := json.Marshal(map[string]string{
        "sender_number": "+1234567890",
        "message_body":  "Hello, world!",
    })

    req, _ := http.NewRequest("POST", "https://your-server:8001/api/v1/messages",
        bytes.NewBuffer(data))
    req.Header.Set("Content-Type", "application/json")

    // Send request
    resp, _ := client.Do(req)
    defer resp.Body.Close()
    body, _ := ioutil.ReadAll(resp.Body)
    println(string(body))
}
```

## Certificate Requirements

1. **Client Certificate** (`client.crt`): Your client certificate in PEM format
2. **Private Key** (`client.key`): Your private key in PEM format (keep secure!)
3. **CA Certificate** (`ca.crt`): Certificate Authority certificate in PEM format

All certificates must be in PEM format. Contact your administrator to obtain certificates.

## Message Format Requirements

### Sender Number Format (E.164)

- Must start with `+`
- Must include country code
- Only digits after the `+`
- Total length: 8-16 characters (including `+`)

**Valid examples**:
- `+1234567890` ✅
- `+442012345678` ✅
- `+491234567890` ✅

**Invalid examples**:
- `1234567890` ❌ (missing `+`)
- `+1-234-567-890` ❌ (contains dashes)
- `+1 234 567 890` ❌ (contains spaces)

### Message Body

- Required field
- Maximum length: 1000 characters
- Cannot be empty or whitespace-only

## Troubleshooting

### Certificate Errors

- Verify certificate files exist and are readable
- Check certificates are in PEM format (text format, starts with `-----BEGIN`)
- Verify certificate not expired: `openssl x509 -in client.crt -noout -dates`
- Contact administrator if certificate expired

### Windows curl.exe Certificate Issues

**Problem**: `curl.exe` on Windows (which uses Schannel) may have issues importing PEM certificates, showing errors like:
```
curl: (58) schannel: Failed to import cert file, last error is 0x80092002
```

**Solutions**:
1. **Use the PowerShell script** (`send_message.ps1`) - Recommended for Windows users
2. **Use OpenSSL-based curl** via:
   - Git Bash (if Git for Windows is installed)
   - WSL (Windows Subsystem for Linux)
   - Install OpenSSL-based curl separately
3. **Convert certificates to PFX format** (if using native Windows tools):
   ```powershell
   openssl pkcs12 -export -out client.pfx -inkey client.key -in client.crt -certfile ca.crt
   ```
   Then use PowerShell's `Invoke-RestMethod` with `Get-PfxCertificate`

**Note**: Linux/Mac curl (OpenSSL-based) works seamlessly with PEM certificates. Windows users should prefer the PowerShell script.

### Connection Errors

- Verify proxy URL is correct: `https://your-server:8001/api/v1/messages`
- Check network connectivity
- Verify firewall allows connection to port 8001
- Check proxy service is running

### Validation Errors

- Ensure sender_number starts with `+` and contains only digits
- Check message_body is not empty and under 1000 characters
- Verify JSON format is correct

## Files in This Directory

- `send_message.py` - Python convenience script (optional)
- `send_message.sh` - Bash script using curl (recommended)
- `send_message.ps1` - PowerShell script for Windows
- `requirements.txt` - Python dependencies (only needed for Python script)
- `README.md` - This file
- `certs/` - Directory for client certificates (create this, don't commit to git!)

## Security Notes

- ⚠️ **Never commit certificates to version control**
- ⚠️ **Keep your private key (`client.key`) secure**
- ⚠️ **Use secure networks when sending messages**
- ⚠️ **Rotate certificates periodically** (as per your organization's policy)

## Platform-Specific Guidance

For platform-specific notes and recommendations (especially Windows vs Linux/Mac):
- See [PLATFORM_NOTES.md](PLATFORM_NOTES.md) for detailed platform guidance
- Windows users: Use PowerShell script (`send_message.ps1`) for best results
- Linux/Mac/WSL users: Use bash script or curl directly

## Support

For questions or issues:
- Check the main [User Manual](../docs/USER_MANUAL.md)
- See [PLATFORM_NOTES.md](PLATFORM_NOTES.md) for platform-specific help
- Contact your system administrator
- Review API documentation in `proxy/README.md`

