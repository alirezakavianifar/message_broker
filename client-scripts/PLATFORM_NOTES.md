# Platform-Specific Notes

This document provides platform-specific guidance for using the Message Broker client scripts.

## Windows

### Recommended Approach: PowerShell Script

**For Windows users, we strongly recommend using `send_message.ps1`** rather than trying to use `curl.exe` directly.

**Why?**
- Windows `curl.exe` uses Schannel (Windows SSL provider) which has different certificate handling than OpenSSL
- Schannel may have issues importing PEM format certificates
- The PowerShell script handles certificate paths and formats correctly

**Usage**:
```powershell
.\send_message.ps1 -Sender "+1234567890" -Message "Hello, world!"
```

### Alternative: OpenSSL-based curl

If you prefer using curl directly on Windows, use an OpenSSL-based version:

1. **Git Bash** (if Git for Windows is installed):
   ```bash
   # In Git Bash
   curl -X POST https://your-server:8001/api/v1/messages \
     --cert client.crt --key client.key --cacert ca.crt \
     -H "Content-Type: application/json" \
     -d '{"sender_number": "+1234567890", "message_body": "Hello"}'
   ```

2. **WSL (Windows Subsystem for Linux)**:
   ```bash
   # In WSL
   curl -X POST https://your-server:8001/api/v1/messages \
     --cert client.crt --key client.key --cacert ca.crt \
     -H "Content-Type: application/json" \
     -d '{"sender_number": "+1234567890", "message_body": "Hello"}'
   ```

3. **Native Windows curl.exe** (if you must use it):
   - May require converting certificates to PFX format
   - Or use with `-k` flag to bypass certificate verification (development only)
   - Not recommended for production use

## Linux / macOS

### Recommended: Bash Script or curl Directly

Both approaches work well as curl uses OpenSSL on these platforms.

**Bash Script**:
```bash
./send_message.sh "+1234567890" "Hello, world!"
```

**curl Directly**:
```bash
curl -X POST https://your-server:8001/api/v1/messages \
  --cert client.crt --key client.key --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{"sender_number": "+1234567890", "message_body": "Hello"}'
```

## Summary

| Platform | Recommended Method | Alternative |
|----------|-------------------|-------------|
| **Windows** | PowerShell script (`send_message.ps1`) | Git Bash curl, WSL curl |
| **Linux** | Bash script or curl directly | Python script (optional) |
| **macOS** | Bash script or curl directly | Python script (optional) |

## Certificate Format

All certificates are in **PEM format**:
- Text format starting with `-----BEGIN`
- Works seamlessly with OpenSSL-based curl (Linux/Mac/WSL)
- May require conversion for native Windows tools (use PowerShell script instead)

## Testing Results

Based on validation testing:

✅ **Linux/Mac/WSL curl**: Works perfectly with PEM certificates  
✅ **Windows PowerShell script**: Works reliably, handles certificates correctly  
⚠️ **Windows native curl.exe**: May have certificate import issues (use PowerShell script instead)  
✅ **Python script**: Works on all platforms (requires Python and dependencies)

