# Quick Start Guide - How to Send Messages

## Understanding the System

This is a **Message Broker System** for applications to send messages via API, NOT a chat application.

### System Purpose (from plan.md):
- **Client Applications** send messages via API (with mTLS certificates)
- **Web Portal** is for viewing/monitoring messages (READ-ONLY)
- Messages are queued, processed, and stored encrypted

---

## How Messages Work

### ❌ What You CANNOT Do:
- Send messages through the web portal
- Users cannot message each other through the portal

### ✅ What You CAN Do:
1. **Applications send messages** via REST API with client certificates
2. **View messages** in the portal (users see their own, admins see all)
3. **Monitor message status** (queued, delivered, failed)

---

## How to Send a Message

### Option 1: Using the Client Script (Recommended)

1. **Generate a client certificate** (via portal):
   - Go to: http://localhost:5000/admin/certificates
   - Click "Generate New Certificate"
   - Client ID: `my_app`
   - Download the certificate files

2. **Place certificates** in `client-scripts/certs/`:
   - `my_app.crt` (client certificate)
   - `my_app.key` (private key)
   - `ca.crt` (CA certificate)

3. **Send a message**:
   ```powershell
   cd client-scripts
   python send_message.py --sender "+1234567890" --message "Hello World" --cert certs/my_app.crt --key certs/my_app.key --ca certs/ca.crt
   ```

4. **View the message**:
   - Go to: http://localhost:5000/admin/messages
   - You'll see the message you just sent

---

## For Testing: Quick Demo Without Certificates

Since you want to see messages in the portal, here's a quick way to create test messages:

### Create Test Messages via Internal API:
```python
# This bypasses the proxy for testing purposes
import httpx

with httpx.Client(verify=False) as client:
    response = client.post(
        "https://localhost:8000/internal/messages/register",
        json={
            "message_id": "test-123",
            "sender_number": "+1234567890",
            "message_body": "Test message for portal viewing",
            "client_id": "test_client",
            "queued_at": "2025-10-25T20:00:00"
        }
    )
    print(response.json())
```

Then view it at: http://localhost:5000/admin/messages

---

## Web Portal Features (from plan.md)

### User Panel:
- **Login** with username/password
- **View own messages only**
- **Search & filter** by date/status
- **See metadata** (timestamp, status)
- **NO sending capability**

### Admin Panel:
- **Manage users**
- **View all messages** (across all clients)
- **Manage certificates**
- **View system statistics**
- **NO message editing/sending**

---

## Architecture Summary

```
External Application (with certificate)
    ↓
POST /api/v1/messages (to Proxy on port 8001)
    ↓
Proxy validates certificate & message
    ↓
Main Server receives and queues (port 8000)
    ↓
Redis Queue
    ↓
Worker processes message
    ↓
Database (encrypted storage)
    ↓
Web Portal displays message (read-only)
```

---

## Use Cases (from plan.md)

This system is designed for:

1. **Application-to-Application messaging**
   - Mobile apps sending notifications
   - Backend services exchanging data
   - IoT devices sending telemetry

2. **NOT for:**
   - Direct user-to-user chat
   - Sending messages through a web UI
   - Real-time messaging between portal users

---

## If You Want User-to-User Messaging

The current system is NOT designed for that. You would need to add:

1. **New endpoints** for users to send messages via portal
2. **Authentication** to identify sender
3. **Recipient selection** in the UI
4. **Real-time notifications** (WebSocket/SSE)
5. **Message threads/conversations**

This would be a significant architectural change beyond the scope of plan.md.

