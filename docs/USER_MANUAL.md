# Message Broker System - User Manual

**Version**: 1.0.0  
**Last Updated**: October 2025  
**Audience**: End Users

---

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Portal Features](#portal-features)
4. [Sending Messages](#sending-messages)
5. [Viewing Messages](#viewing-messages)
6. [Account Management](#account-management)
7. [Troubleshooting](#troubleshooting)
8. [FAQ](#faq)

---

## Introduction

Welcome to the Message Broker System! This system allows you to securely send and track messages through our platform.

### What You Can Do

- ✅ Send messages via secure API
- ✅ View your message history
- ✅ Track message delivery status
- ✅ Search and filter messages
- ✅ Manage your account

### Key Features

- **Secure**: All messages encrypted and transmitted over mutual TLS
- **Reliable**: Messages queued and retried until delivered
- **Traceable**: Full message history and delivery tracking
- **Privacy-Focused**: Only you can see your messages

---

## Getting Started

### Accessing the Portal

1. Open your web browser
2. Navigate to: `https://your-server:5000`
3. Click "Login"

### First Login

1. Enter your credentials:
   - **Email**: Provided by administrator
   - **Password**: Provided by administrator
2. Click "Sign In"
3. **Important**: Change your password on first login!

### Changing Your Password

1. Click your name in the top-right corner
2. Select "Profile"
3. Click "Change Password"
4. Enter:
   - Current password
   - New password (min 8 characters)
   - Confirm new password
5. Click "Update Password"

**Password Requirements**:
- Minimum 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number

---

## Portal Features

### Dashboard

Your dashboard shows:
- **Recent Messages**: Your last 10 messages
- **Statistics**: Total messages, delivery rate, recent activity
- **Quick Actions**: Send new message, search messages

### Navigation Menu

- **Home**: Dashboard overview
- **Messages**: View all your messages
- **Send**: Send a new message
- **Profile**: Manage your account
- **Help**: Documentation and support

---

## Sending Messages

### Via Web Portal

**Not yet implemented** - Messages must be sent via API

### Via HTTP API (Recommended - No Dependencies Required)

The message broker uses a **thin client architecture**. You can send messages using **any HTTP client** - no Python or special libraries required!

#### Prerequisites

- Client certificates (provided by administrator)
- Any HTTP client (curl, Postman, or any programming language)

#### Certificate Setup

Place certificates in a secure location:
- `client.crt` - Your certificate
- `client.key` - Your private key (**keep secure!**)
- `ca.crt` - CA certificate

#### Sending a Message

**Using curl (Linux/Mac/WSL - Recommended for these platforms)**:

```bash
curl -X POST https://your-server:8001/api/v1/messages \
  --cert client.crt \
  --key client.key \
  --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{
    "sender_number": "+1234567890",
    "message_body": "Hello, this is a test message"
  }'
```

**Note**: On Windows, `curl.exe` uses Schannel which may have issues with PEM certificates. Windows users should use the PowerShell script (below) instead.

**Using PowerShell Script (Windows - Recommended)**:

```powershell
# Use the provided PowerShell script (recommended for Windows)
.\send_message.ps1 -Sender "+1234567890" -Message "Hello, this is a test message"
```

Or using PowerShell's Invoke-RestMethod (requires PFX certificate):

```powershell
$body = @{
    sender_number = "+1234567890"
    message_body = "Hello, this is a test message"
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://your-server:8001/api/v1/messages" `
  -Method Post `
  -Certificate (Get-PfxCertificate -FilePath "client.pfx") `
  -Body $body `
  -ContentType "application/json"
```

**Using Python (Optional - Convenience Only)**:

```python
import requests

response = requests.post(
    "https://your-server:8001/api/v1/messages",
    json={
        "sender_number": "+1234567890",
        "message_body": "Hello, this is a test message"
    },
    cert=("client.crt", "client.key"),
    verify="ca.crt"
)

if response.status_code == 202:
    result = response.json()
    print(f"Message sent! ID: {result['message_id']}")
```

**Using JavaScript/Node.js**:

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
  headers: {
    'Content-Type': 'application/json'
  }
};

const data = JSON.stringify({
  sender_number: '+1234567890',
  message_body: 'Hello, this is a test message'
});

const req = https.request(options, (res) => {
  let body = '';
  res.on('data', (chunk) => { body += chunk; });
  res.on('end', () => {
    const result = JSON.parse(body);
    console.log('Message sent! ID:', result.message_id);
  });
});

req.write(data);
req.end();
```

**Using the Provided Python Script (Optional Convenience Tool)**:

If you prefer using Python, a convenience script is available in `client-scripts/send_message.py`:

```bash
python send_message.py --sender "+1234567890" --message "Your message here" --cert client.crt --key client.key --ca ca.crt
```

**Note**: The Python script is just a convenience wrapper around HTTP requests. You can use any HTTP client you prefer!

#### Message Format

**Required Fields**:
- `sender_number`: Phone number in E.164 format (e.g., +1234567890)
- `message_body`: Your message text (max 1000 characters)

**Sender Number Format**:
- Must start with `+`
- Must include country code
- Only digits after `+`
- Examples:
  - ✅ `+1234567890` (correct)
  - ❌ `1234567890` (missing +)
  - ❌ `+1-234-567-890` (contains dashes)

---

## Viewing Messages

### View All Messages

1. Click "Messages" in the navigation menu
2. See all your messages with:
   - Message ID
   - Sender number (partially masked for privacy)
   - Status (Pending, Delivered, Failed)
   - Created date
   - Delivered date (if applicable)

### Message Status

| Status | Meaning |
|--------|---------|
| **Pending** | Message is queued, delivery in progress |
| **Delivered** | Message successfully delivered |
| **Failed** | Message delivery failed (will retry) |

**Note**: Messages are retried every 30 seconds until delivered.

### Search Messages

1. Click "Messages"
2. Use search filters:
   - **Date Range**: Filter by date
   - **Status**: Filter by delivery status
   - **Sender**: Search by sender number

3. Click "Search"

### View Message Details

1. Click on any message in the list
2. View full details:
   - Message ID
   - Sender number
   - Message body
   - Status
   - Created timestamp
   - Delivered timestamp
   - Attempt count

---

## Account Management

### Update Your Profile

1. Click your name → "Profile"
2. View your account information:
   - Email
   - Client ID
   - Last login
   - Account created date

### Change Password

1. Go to Profile → "Change Password"
2. Enter current password
3. Enter new password (twice)
4. Click "Update"

### View Login History

1. Go to Profile → "Activity"
2. See your recent logins:
   - Login time
   - IP address (if logged)
   - Status (success/failed)

---

## Troubleshooting

### Can't Login

**Problem**: "Invalid credentials" error

**Solutions**:
1. Check email is correct
2. Check password (case-sensitive)
3. Clear browser cache and cookies
4. Try different browser
5. Contact administrator for password reset

### Can't Send Messages

**Problem**: Certificate errors

**Solutions**:
1. Verify certificate files exist:
   - client.crt
   - client.key
   - ca.crt
2. Check certificate not expired:
   ```bash
   openssl x509 -in client.crt -noout -dates
   ```
3. Ensure certificates are in correct format (PEM)
4. Verify certificate paths are correct in your HTTP client
5. Contact administrator if certificate expired

**Problem**: "Invalid sender number" error

**Solutions**:
1. Check number format: `+[country code][number]` (E.164 format)
2. Remove any spaces or dashes
3. Ensure starts with `+`
4. Example correct format: `+1234567890`

**Problem**: Connection refused

**Solutions**:
1. Check proxy URL is correct: `https://your-server:8001/api/v1/messages`
2. Verify network connectivity (try ping or telnet)
3. Check firewall not blocking connection to port 8001
4. Verify the proxy service is running
5. Contact administrator

**Problem**: "Python/pip not found" when trying to use Python script

**Solutions**:
1. **You don't need Python!** Use curl (Linux/Mac) or the PowerShell script (Windows) instead
2. The Python script is optional - any HTTP client works
3. If you prefer Python, install it from python.org
4. Or use PowerShell, Node.js, or any other HTTP-capable tool

**Problem**: Windows curl.exe certificate import errors

**Solutions**:
1. **Use the PowerShell script** (`send_message.ps1`) - This is the recommended approach for Windows
2. Use Git Bash (if installed) which has OpenSSL-based curl
3. Use WSL (Windows Subsystem for Linux) for OpenSSL-based curl
4. The PowerShell script handles certificates correctly and works reliably on Windows

### Messages Stuck in "Pending"

This is normal! Messages are retried every 30 seconds until delivered.

If message remains pending for over 5 minutes:
1. Check message status later
2. Contact administrator if persistent

### Can't View Messages

**Problem**: Blank message list

**Solutions**:
1. Check you've sent messages
2. Try different date range
3. Clear filters
4. Refresh page
5. Try different browser

---

## FAQ

### How long are messages stored?

Messages are stored for 90 days by default. After 90 days, messages may be archived or deleted.

### Can I edit or delete messages?

No. Once sent, messages cannot be edited or deleted. This ensures message integrity and audit trail.

### How secure are my messages?

Very secure:
- ✅ Messages transmitted over mutual TLS
- ✅ Messages encrypted at rest in database
- ✅ Only you can view your messages
- ✅ Sender numbers hashed for privacy
- ✅ Full audit logging

### How fast are messages delivered?

- **Initial attempt**: Immediate (within seconds)
- **Retries**: Every 30 seconds
- **Typical delivery**: Under 1 minute
- **Maximum attempts**: 10,000 (≈80 hours)

### What if delivery fails?

Messages are automatically retried every 30 seconds until:
- Successfully delivered, OR
- Maximum retry attempts reached

You'll see the attempt count in message details.

### Can I see other users' messages?

No. You can only see messages you sent. Administrators can view all messages for support purposes.

### How do I get certificates?

Contact your system administrator. They will:
1. Generate certificates for you
2. Provide three files securely
3. Give you instructions for setup

### My certificate expired - what do I do?

Contact your administrator for a new certificate. They will:
1. Generate a new certificate
2. Provide new files
3. You update your client script

### Can I use the system from multiple computers?

Yes! You can:
- **Portal**: Login from any computer with your credentials
- **API**: Copy your certificates to any computer (securely!)
- **No special software needed**: Use curl, Postman, or any HTTP client on any platform

**Security Note**: Keep your private key (client.key) secure! Don't share it or commit it to version control.

### Do I need Python to send messages?

**No!** Python is completely optional. You can use:
- **curl** (Linux, macOS, WSL - uses OpenSSL, works perfectly)
- **PowerShell script** (`send_message.ps1` - Windows, recommended)
- **Postman** or Insomnia (GUI tools)
- **Any programming language** with HTTP support (JavaScript, Go, Java, C#, etc.)

The Python script (`send_message.py`) is just a convenience wrapper - it's not required.

### Which method should I use on Windows?

**Recommended**: Use the PowerShell script (`send_message.ps1`). 

Windows `curl.exe` uses Schannel which may have issues with PEM certificates. The PowerShell script handles certificates correctly and is the most reliable option on Windows.

For more platform-specific guidance, see `client-scripts/PLATFORM_NOTES.md`.

### How do I get support?

Contact your administrator:
- **Email**: [Your support email]
- **Phone**: [Your support phone]
- **Help Portal**: [Your help desk URL]

---

## Best Practices

### Security

- ✅ Use strong, unique password
- ✅ Change password regularly (every 90 days)
- ✅ Keep certificates secure
- ✅ Never share your private key
- ✅ Logout when done
- ✅ Use secure networks (avoid public WiFi)

### Message Sending

- ✅ Use correct phone number format
- ✅ Keep messages under 1000 characters
- ✅ Verify sender number before sending
- ✅ Check message status after sending
- ✅ Contact support if persistent failures

### Portal Usage

- ✅ Use search filters to find messages quickly
- ✅ Check dashboard for quick overview
- ✅ Monitor message delivery rates
- ✅ Report any issues promptly

---

## Appendix

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl + /` | Open search |
| `Ctrl + N` | New message (if implemented) |
| `Ctrl + R` | Refresh message list |
| `Esc` | Close modal/dialog |

### Supported Browsers

- ✅ Chrome 90+
- ✅ Firefox 88+
- ✅ Edge 90+
- ✅ Safari 14+

### Phone Number Format Reference

| Country | Format Example | Country Code |
|---------|----------------|--------------|
| USA | +12345678901 | +1 |
| UK | +442012345678 | +44 |
| Germany | +491234567890 | +49 |
| France | +33123456789 | +33 |

**General Format**: `+[country code][area code][number]` (no spaces or dashes)

### Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Message sent |
| 400 | Bad Request | Check message format |
| 401 | Unauthorized | Check certificates |
| 429 | Too Many Requests | Wait and retry |
| 500 | Server Error | Contact support |

---

## Getting Help

### Quick Help

- **Portal Help**: Click "Help" in navigation menu
- **Tooltips**: Hover over (?) icons for help
- **Error Messages**: Read carefully for solutions

### Contact Support

**Email**: support@yourcompany.com  
**Phone**: [Your support number]  
**Hours**: Monday-Friday, 9 AM - 5 PM

**What to include when contacting support**:
- Your email/client ID
- What you were trying to do
- Error message (if any)
- Screenshot (if applicable)

---

## Quick Reference Card

### Sending Messages (API)

**Using curl (Recommended - No dependencies)**:

```bash
curl -X POST https://server:8001/api/v1/messages \
  --cert client.crt --key client.key --cacert ca.crt \
  -H "Content-Type: application/json" \
  -d '{"sender_number": "+1234567890", "message_body": "Your message"}'
```

**Using Python (Optional)**:

```python
import requests
response = requests.post(
    "https://server:8001/api/v1/messages",
    json={"sender_number": "+1234567890", "message_body": "Your message"},
    cert=("client.crt", "client.key"), verify="ca.crt"
)
```

### Check Message Status

1. Login to portal
2. Go to Messages
3. Find your message
4. Check Status column

### Get Help

- Portal: Click "Help"
- Email: support@yourcompany.com
- Phone: [Your number]

---

**Document Version**: 1.0.0  
**Last Updated**: October 2025  
**For questions or feedback, contact**: support@yourcompany.com

