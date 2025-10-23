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

### Via Python Client Script

#### Prerequisites

- Python 3.8 or higher
- Client certificates (provided by administrator)
- Client script (`send_message.py`)

#### Setup

1. Install Python if not already installed
2. Install required packages:
   ```bash
   pip install requests
   ```

3. Place certificates in a secure location:
   - `client.crt` - Your certificate
   - `client.key` - Your private key (**keep secure!**)
   - `ca.crt` - CA certificate

#### Sending a Message

**Basic Usage**:

```python
import requests
import json

# Configuration
proxy_url = "https://your-server:8001/api/v1/messages"
cert_file = "path/to/client.crt"
key_file = "path/to/client.key"
ca_file = "path/to/ca.crt"

# Message data
message = {
    "sender_number": "+1234567890",
    "message_body": "Hello, this is a test message"
}

# Send message
response = requests.post(
    proxy_url,
    json=message,
    cert=(cert_file, key_file),
    verify=ca_file
)

# Check response
if response.status_code == 200:
    result = response.json()
    print(f"Message sent! ID: {result['message_id']}")
else:
    print(f"Error: {response.status_code}")
    print(response.text)
```

**Using the Provided Script**:

```bash
python send_message.py --sender "+1234567890" --message "Your message here" --cert client.crt --key client.key
```

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
4. Contact administrator if certificate expired

**Problem**: "Invalid sender number" error

**Solutions**:
1. Check number format: `+[country code][number]`
2. Remove any spaces or dashes
3. Ensure starts with `+`
4. Example correct format: `+1234567890`

**Problem**: Connection refused

**Solutions**:
1. Check proxy URL is correct
2. Verify network connectivity
3. Check firewall not blocking connection
4. Contact administrator

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

**Security Note**: Keep your private key (client.key) secure! Don't share it or commit it to version control.

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

```python
import requests

response = requests.post(
    "https://server:8001/api/v1/messages",
    json={
        "sender_number": "+1234567890",
        "message_body": "Your message"
    },
    cert=("client.crt", "client.key"),
    verify="ca.crt"
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

