# Thin Client Implementation - Start Here

## Overview

The Message Broker system uses a **thin client architecture**, which means clients can send messages using **any HTTP client** - no Python or special libraries required!

## Key Benefits

✅ **No Python dependencies** on client machines  
✅ **No virtual environments** needed  
✅ **Works with any HTTP client** (curl, Postman, JavaScript, Go, etc.)  
✅ **Simple to use** - just HTTP POST requests

## How It Works

```
Client → HTTP POST (with mTLS certificates) → Proxy Server → Redis Queue → Worker → Main Server
```

The proxy server handles all the complex logic:
- Message validation (E.164 phone format, length checks)
- Certificate authentication
- Redis queuing
- Main server communication

Clients just send simple HTTP requests!

## Quick Examples

### Windows (Recommended)

Use the PowerShell script:
```powershell
.\send_message.ps1 -Sender "+1234567890" -Message "Hello, world!"
```

### Linux/Mac/WSL

Use curl directly:
```bash
curl -X POST https://your-server:8001/api/v1/messages \
  --cert client.crt --key client.key --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{"sender_number": "+1234567890", "message_body": "Hello, world!"}'
```

Or use the bash script:
```bash
./send_message.sh "+1234567890" "Hello, world!"
```

## What You Need

1. **Client Certificates** (provided by administrator):
   - `client.crt` - Your certificate
   - `client.key` - Your private key (keep secure!)
   - `ca.crt` - CA certificate

2. **HTTP Client**:
   - Windows: PowerShell script (recommended) or curl
   - Linux/Mac: curl or bash script
   - Any platform: Postman, or any programming language

## Testing Checklist

Before testing, verify:
- [ ] Proxy server is running (`curl http://localhost:8001/api/v1/health`)
- [ ] Redis is running
- [ ] Certificates are available in `client-scripts/certs/`
- [ ] You've chosen the right script for your platform

## Platform-Specific Notes

**Windows Users**:  
- ✅ Use `send_message.ps1` (recommended)
- ⚠️ Native `curl.exe` may have certificate issues - use PowerShell script instead

**Linux/Mac Users**:  
- ✅ Use `send_message.sh` or curl directly
- ✅ Works seamlessly with PEM certificates

See `client-scripts/PLATFORM_NOTES.md` for detailed platform guidance.

## Next Steps

1. **Read your platform section** in `client-scripts/PLATFORM_NOTES.md`
2. **Review API documentation** in `client-scripts/README.md`
3. **Test with example files**:
   - `test_message.json` - Valid message
   - `test_message_invalid.json` - Invalid format (for validation testing)

## Common Questions

**Q: Do I need Python?**  
A: No! Python is completely optional. Use curl or the provided scripts.

**Q: Which method should I use?**  
A: 
- Windows → PowerShell script
- Linux/Mac → Bash script or curl
- Any platform → Python script (if you prefer Python)

**Q: What if I get certificate errors?**  
A: See troubleshooting section in `client-scripts/README.md` or `client-scripts/PLATFORM_NOTES.md`

## Full Documentation

- **Quick Start**: This file
- **Platform Guide**: `client-scripts/PLATFORM_NOTES.md`
- **API Documentation**: `client-scripts/README.md`
- **User Manual**: `docs/USER_MANUAL.md`
- **Test Results**: `VALIDATION_RESULTS.md`

---

**Ready to start?** Check `client-scripts/PLATFORM_NOTES.md` for your platform-specific instructions!

