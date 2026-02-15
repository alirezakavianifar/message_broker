# Quick Start Guide

## What is This?

The Message Broker uses a **thin client architecture** - you can send messages using **any HTTP client** without installing Python or special libraries!

## Choose Your Platform

### 🪟 Windows

**Use the PowerShell script:**

```powershell
cd scripts
.\send_message_windows.ps1 -Sender "+1234567890" -Message "Hello, world!"
```

**That's it!** The script handles everything.

> **Why PowerShell script?** Windows `curl.exe` may have certificate issues. The PowerShell script works reliably.

---

### 🐧 Linux / Mac / WSL

**Option 1: Use the bash script (easiest)**

```bash
cd scripts
chmod +x send_message_linux.sh
./send_message_linux.sh "+1234567890" "Hello, world!"
```

**Option 2: Use curl directly**

```bash
curl -X POST https://your-server:8001/api/v1/messages \
  --cert client.crt --key client.key --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{"sender_number": "+1234567890", "message_body": "Hello, world!"}'
```

---

## Prerequisites

Before testing, you need:

1. **Proxy server running**
   ```bash
   # Test if it's running:
   curl http://localhost:8001/api/v1/health
   ```

2. **Client certificates** (get from your administrator):
   - `client.crt` - Your certificate
   - `client.key` - Your private key (keep secure!)
   - `ca.crt` - CA certificate

   Place these in the same directory as the scripts, or update paths in the scripts.

## Quick Test

1. **Place certificates** in `scripts/` folder (or update paths)
2. **Run the appropriate script** for your platform (see above)
3. **Check the response** - you should see a message ID if successful

## Example Output

**Success:**
```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "client_id": "your-client-id",
  "queued_at": "2025-12-21T10:30:00Z"
}
```

**Error (invalid phone format):**
```json
{
  "detail": [{
    "type": "value_error",
    "loc": ["body", "sender_number"],
    "msg": "Invalid phone number format. Must match E.164 format..."
  }]
}
```

## Testing with Test Files

Use the provided test files:

```bash
# Windows
.\send_message_windows.ps1 -Sender "+1234567890" -Message (Get-Content ..\tests\test_message_valid.json | ConvertFrom-Json).message_body

# Linux/Mac
./send_message_linux.sh "+1234567890" "$(cat ../tests/test_message_valid.json | jq -r '.message_body')"
```

## Troubleshooting

**"Certificate not found"**
- Make sure certificate files are in the scripts folder
- Or update the certificate paths in the script

**"Connection refused"**
- Check if proxy server is running: `curl http://localhost:8001/api/v1/health`
- Check firewall settings

**"Invalid phone number format"**
- Phone must start with `+` (e.g., `+1234567890`)
- No spaces or dashes allowed

**Still having issues?**
- Check `docs/PLATFORM_GUIDE.md` for platform-specific help
- Check `docs/API_REFERENCE.md` for detailed API information

## What's Next?

Once you've successfully sent a message:
1. ✅ Try different phone numbers
2. ✅ Test with invalid inputs (see `tests/test_message_invalid.json`)
3. ✅ Review `docs/API_REFERENCE.md` for more details
4. ✅ Try integrating into your own application

---

**Ready?** Go back to `README.md` and start testing!

