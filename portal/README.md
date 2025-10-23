# Message Broker Web Portal

Modern web interface for the Message Broker system, providing user and admin dashboards for message management, monitoring, and system administration.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [User Guide](#user-guide)
- [Admin Guide](#admin-guide)
- [Troubleshooting](#troubleshooting)
- [Production Deployment](#production-deployment)

---

## Overview

The web portal provides a user-friendly interface for:
- **Users**: View their messages, track delivery status, filter by status
- **Administrators**: Manage users, generate/revoke certificates, view system statistics, access all messages

### Technology Stack

- **Backend**: FastAPI with Jinja2 templates
- **Frontend**: Bootstrap 5 with Bootstrap Icons
- **Authentication**: JWT tokens via main server API
- **Session Management**: Encrypted sessions with configurable expiration
- **API Communication**: HTTPx async client for main server integration

---

## Features

### User Features

✅ **Authentication**
- Secure login with email/password
- Session management with auto-refresh
- Automatic logout on token expiration

✅ **Dashboard**
- View personal messages
- Filter by status (queued, delivered, failed)
- Pagination support
- Real-time status updates

✅ **Message Viewing**
- Masked phone numbers for privacy
- Delivery status tracking
- Attempt count monitoring
- Timestamp information (created, queued, delivered)

✅ **Profile**
- View account information
- Last login tracking
- User role display

### Admin Features

✅ **Admin Dashboard**
- System statistics overview
- Message status breakdown
- Recent activity tracking
- Quick action links

✅ **User Management**
- Create new users (user/admin roles)
- View all users with status
- Track last login times
- Email and role information

✅ **Certificate Management**
- Generate client certificates
- Revoke certificates with reason tracking
- Configure validity periods
- Domain association

✅ **Message Administration**
- View all messages (all clients)
- Decrypt message bodies (admin only)
- Search and filter capabilities
- Client-specific views

---

## Installation

### Prerequisites

- Python 3.8+
- Main server running and accessible
- Virtual environment configured

### Windows Setup

1. **Activate virtual environment**:
   ```powershell
   cd portal
   ..\venv\Scripts\Activate.ps1
   ```

2. **Install dependencies**:
   ```powershell
   pip install -r requirements.txt
   ```

3. **Create .env file** (optional):
   ```powershell
   copy ..\.env.template ..\.env
   # Edit .env with your configuration
   ```

4. **Start portal**:
   ```powershell
   .\start_portal.ps1
   ```

### Linux Setup

1. **Activate virtual environment**:
   ```bash
   cd portal
   source ../venv/bin/activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Start portal**:
   ```bash
   python app.py
   ```

Or with systemd:
```bash
sudo systemctl start portal
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAIN_SERVER_URL` | `https://localhost:8000` | Main server API URL |
| `MAIN_SERVER_VERIFY_SSL` | `false` | Verify SSL certificates |
| `PORTAL_HOST` | `0.0.0.0` | Portal bind address |
| `PORTAL_PORT` | `8080` | Portal port |
| `SESSION_SECRET` | _(required)_ | Session encryption secret |
| `SESSION_MAX_AGE` | `3600` | Session duration (seconds) |
| `LOG_LEVEL` | `INFO` | Logging level |
| `LOG_FILE_PATH` | `logs` | Log directory |
| `MESSAGES_PER_PAGE` | `20` | Pagination size |

### .env Example

```env
# Main Server
MAIN_SERVER_URL=https://localhost:8000
MAIN_SERVER_VERIFY_SSL=false

# Portal
PORTAL_HOST=0.0.0.0
PORTAL_PORT=8080

# Security
SESSION_SECRET=your-secure-random-secret-key-change-in-production

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=logs

# UI
MESSAGES_PER_PAGE=20
```

### Generate Secure Session Secret

```powershell
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

---

## Usage

### Starting the Portal

#### Windows (Batch)
```cmd
cd portal
start_portal.bat
```

#### Windows (PowerShell)
```powershell
cd portal
.\start_portal.ps1 -Port 8080 -LogLevel INFO
```

**PowerShell Parameters**:
- `-HostAddress`: Bind address (default: 0.0.0.0)
- `-Port`: Port number (default: 8080)
- `-LogLevel`: Log level (default: INFO)
- `-Reload`: Enable auto-reload (development only)

#### Linux
```bash
cd portal
python app.py
```

### Accessing the Portal

- **URL**: http://localhost:8080
- **Login**: Use credentials created via admin CLI or main server

**Default Admin** (if created):
```bash
cd main_server
python admin_cli.py user create admin@example.com --role admin
```

---

## User Guide

### Logging In

1. Navigate to http://localhost:8080
2. Click "Login" or visit http://localhost:8080/login
3. Enter your email and password
4. Click "Login"

### Viewing Messages

1. After login, you're redirected to your dashboard
2. Messages are displayed in a table with:
   - Message ID (truncated)
   - Masked sender number
   - Status badge
   - Attempt count
   - Timestamps

### Filtering Messages

1. Use the status filter dropdown
2. Select status:
   - **All Statuses**: Show everything
   - **Queued**: Messages waiting for delivery
   - **Delivered**: Successfully delivered messages
   - **Failed**: Messages that failed delivery
3. Click "Filter"
4. Click "Clear" to remove filter

### Pagination

- Use "Previous" and "Next" buttons to navigate
- Page number is displayed at the top
- 20 messages per page (configurable)

### Viewing Profile

1. Click your email in the top-right
2. Select "Profile"
3. View your account information:
   - User ID
   - Role
   - Status
   - Member since
   - Last login

### Logging Out

1. Click your email in the top-right
2. Select "Logout"

---

## Admin Guide

### Admin Dashboard

**Access**: http://localhost:8080/admin/dashboard

**Features**:
- Total messages count
- Total clients (active/revoked)
- Message status breakdown with percentages
- Recent activity (24h, 7d)
- Quick action buttons

### User Management

**Access**: http://localhost:8080/admin/users

#### Creating Users

1. Fill in the "Create New User" form:
   - Email address
   - Password (minimum 8 characters)
   - Role (user or admin)
2. Click "Create"
3. User receives confirmation

#### Viewing Users

- Table shows all users with:
  - User ID
  - Email
  - Role (with badge)
  - Status (active/inactive)
  - Created date
  - Last login date

### Certificate Management

**Access**: http://localhost:8080/admin/certificates

#### Generating Certificates

1. In "Generate Client Certificate" form:
   - Enter unique Client ID
   - (Optional) Enter domain
   - Set validity period in days (1-3650)
2. Click "Generate Certificate"
3. Certificates are created on main server

**Distribution**:
- Certificates are stored in `main_server/certs/`
- Distribute these files securely:
  - `client_id.crt` - Client certificate
  - `client_id.key` - Private key
  - `ca.crt` - CA certificate

#### Revoking Certificates

1. In "Revoke Client Certificate" form:
   - Enter Client ID
   - Provide revocation reason
2. Click "Revoke Certificate"
3. Confirm the action
4. Certificate is added to CRL

### Viewing All Messages

**Access**: http://localhost:8080/admin/messages

**Features**:
- View messages from all clients
- See client IDs
- Decrypt message bodies (admin privilege)
- Filter by status
- Pagination support

**Admin View Differences**:
- Shows client ID column
- Displays decrypted message bodies
- Can view messages from any client

---

## Troubleshooting

### Common Issues

#### 1. Cannot Connect to Main Server

**Symptoms**:
```
Failed to login: Connection refused
```

**Solutions**:
- Verify main server is running:
  ```powershell
  # Check if main server is up
  curl -k https://localhost:8000/health
  ```
- Check `MAIN_SERVER_URL` in configuration
- Verify network/firewall settings
- Check SSL verification settings

#### 2. Login Fails

**Symptoms**:
- "Invalid email or password" message

**Solutions**:
- Verify user exists:
  ```powershell
  cd main_server
  python admin_cli.py user list
  ```
- Create user if needed:
  ```powershell
  python admin_cli.py user create user@example.com --role user
  ```
- Check main server logs for authentication errors

#### 3. Session Expires Immediately

**Symptoms**:
- Logged out after every page refresh

**Solutions**:
- Check `SESSION_SECRET` is set
- Verify `SESSION_MAX_AGE` is reasonable (default: 3600 seconds)
- Clear browser cookies
- Restart portal

#### 4. Templates Not Found

**Symptoms**:
```
TemplateNotFound: base.html
```

**Solutions**:
- Verify `templates/` directory exists
- Check all template files are present
- Run from correct directory:
  ```powershell
  cd portal
  .\start_portal.ps1
  ```

#### 5. Port Already in Use

**Symptoms**:
```
ERROR: [Errno 10048] Only one usage of each socket address
```

**Solutions**:
- Use different port:
  ```powershell
  .\start_portal.ps1 -Port 8081
  ```
- Find and stop process:
  ```powershell
  netstat -ano | findstr :8080
  taskkill /PID <process_id> /F
  ```

### Debug Mode

Enable detailed logging:

```powershell
$env:LOG_LEVEL="DEBUG"
.\start_portal.ps1
```

Check logs:
```powershell
Get-Content logs\portal.log -Tail 50 -Wait
```

---

## Production Deployment

### Windows Production Setup

#### 1. Install as Windows Service (NSSM)

```powershell
# Install NSSM
choco install nssm

# Install service
nssm install MessageBrokerPortal "C:\message_broker\venv\Scripts\python.exe"
nssm set MessageBrokerPortal AppParameters "-m uvicorn portal.app:app --host 0.0.0.0 --port 8080"
nssm set MessageBrokerPortal AppDirectory "C:\message_broker\portal"
nssm set MessageBrokerPortal DisplayName "Message Broker Portal"
nssm set MessageBrokerPortal Start SERVICE_AUTO_START

# Set environment
nssm set MessageBrokerPortal AppEnvironmentExtra ^
  MAIN_SERVER_URL=https://mainserver.example.com ^
  SESSION_SECRET=your-production-secret ^
  LOG_LEVEL=INFO

# Start service
nssm start MessageBrokerPortal
```

### Linux Production Setup

#### 1. Install systemd Service

```bash
# Copy service file
sudo cp portal.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start
sudo systemctl enable portal
sudo systemctl start portal

# Check status
sudo systemctl status portal

# View logs
sudo journalctl -u portal -f
```

### Reverse Proxy (Nginx)

#### HTTP Configuration

```nginx
server {
    listen 80;
    server_name portal.example.com;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

#### HTTPS Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name portal.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name portal.example.com;
    return 301 https://$server_name$request_uri;
}
```

### Security Best Practices

#### 1. Session Security

```env
# Use strong session secret (32+ random bytes)
SESSION_SECRET=<output-of-secrets.token_urlsafe(32)>

# Set reasonable expiration
SESSION_MAX_AGE=3600  # 1 hour
```

#### 2. SSL/TLS

```env
# In production, always verify SSL
MAIN_SERVER_VERIFY_SSL=true

# Use HTTPS for main server
MAIN_SERVER_URL=https://mainserver.example.com:8000
```

#### 3. CORS Configuration

For production, configure CORS properly in main server API.

#### 4. Rate Limiting

Consider adding rate limiting at nginx level:

```nginx
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;

location /login {
    limit_req zone=login burst=10 nodelay;
    proxy_pass http://localhost:8080;
}
```

### Monitoring

#### Health Check Endpoint

```bash
curl http://localhost:8080/health
```

**Response**:
```json
{
  "status": "healthy",
  "timestamp": "2025-01-15T10:30:00Z",
  "service": "portal"
}
```

#### Log Monitoring

```bash
# Linux
tail -f /opt/message_broker/portal/logs/portal.log

# Windows
Get-Content C:\message_broker\portal\logs\portal.log -Tail 50 -Wait
```

### Performance Tuning

#### Multiple Workers

For production with high load:

```bash
uvicorn portal.app:app \
  --host 0.0.0.0 \
  --port 8080 \
  --workers 4 \
  --log-level info
```

#### Gunicorn (Linux)

```bash
gunicorn portal.app:app \
  --bind 0.0.0.0:8080 \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --access-logfile - \
  --error-logfile -
```

---

## Development

### Running in Development Mode

```powershell
# With auto-reload
.\start_portal.ps1 -Reload

# With debug logging
$env:LOG_LEVEL="DEBUG"
.\start_portal.ps1 -Reload
```

### Template Development

Templates are in `templates/` directory:
- `base.html` - Base layout with Bootstrap
- `index.html` - Landing page
- `login.html` - Login page
- `dashboard.html` - User dashboard
- `profile.html` - User profile
- `admin/` - Admin pages

### Adding New Pages

1. Create template in `templates/`
2. Add route in `app.py`
3. Add navigation link in `base.html`

---

## License

See root LICENSE file for details.

---

## Support

For issues and questions:
- Check logs: `portal/logs/portal.log`
- Health check: `http://localhost:8080/health`
- Review main documentation: `../README.md`
- Main server API: `../main_server/README.md`

