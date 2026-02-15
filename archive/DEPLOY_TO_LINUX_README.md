# Linux Server Deployment Guide

This guide explains how to deploy the Message Broker system to a Linux server using SSH.

## Prerequisites

1. **Windows Machine (Local)**:
   - PowerShell 5.1 or higher
   - OpenSSH Client (usually pre-installed on Windows 10/11)
   - If not installed: `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0`

2. **Linux Server (Remote)**:
   - Ubuntu/Debian or CentOS/RHEL
   - SSH access with sudo privileges
   - Port 2223 (or your custom SSH port) accessible
   - Internet connection for package installation

## Usage

### Basic Deployment

```powershell
.\deploy_to_linux.ps1 -ServerIP <SERVER_IP> -Username <USERNAME>
```

**Example:**
```powershell
.\deploy_to_linux.ps1 -ServerIP 192.168.1.100 -Username ubuntu
```

### With SSH Key Authentication

```powershell
.\deploy_to_linux.ps1 -ServerIP <SERVER_IP> -Username <USERNAME> -SSHKey "C:\path\to\private_key"
```

**Example:**
```powershell
.\deploy_to_linux.ps1 -ServerIP 192.168.1.100 -Username ubuntu -SSHKey "C:\Users\YourName\.ssh\id_rsa"
```

### Custom SSH Port

```powershell
.\deploy_to_linux.ps1 -ServerIP <SERVER_IP> -Username <USERNAME> -SSHPort 2223
```

### Skip File Transfer (if files already on server)

```powershell
.\deploy_to_linux.ps1 -ServerIP <SERVER_IP> -Username <USERNAME> -SkipTransfer
```

### Skip Service Installation

```powershell
.\deploy_to_linux.ps1 -ServerIP <SERVER_IP> -Username <USERNAME> -SkipServices
```

## What the Script Does

1. **Tests SSH Connection**: Verifies you can connect to the server
2. **Transfers Project Files**: Creates an archive and transfers it to the server
3. **Installs Dependencies**: 
   - Python 3, pip, venv
   - MySQL server
   - Redis server
   - OpenSSL
4. **Sets Up Python Environment**: Creates virtual environment and installs Python packages
5. **Configures Database**: Creates MySQL database and user
6. **Initializes Database Schema**: Runs Alembic migrations
7. **Generates Certificates**: Creates CA and component certificates if they don't exist
8. **Creates Service User**: Creates `messagebroker` user for running services
9. **Installs Systemd Services**: Sets up services for automatic startup
10. **Creates Admin User**: Creates default admin user if it doesn't exist

## After Deployment

### Start Services

```bash
ssh <username>@<server_ip> -p 2223
sudo systemctl start main_server proxy worker portal
```

### Check Service Status

```bash
sudo systemctl status main_server
sudo systemctl status proxy
sudo systemctl status worker
sudo systemctl status portal
```

### View Logs

```bash
# View logs for a specific service
sudo journalctl -u main_server -f
sudo journalctl -u proxy -f
sudo journalctl -u worker -f
sudo journalctl -u portal -f

# View all service logs
sudo journalctl -u main_server -u proxy -u worker -u portal -f
```

### Enable Services (Auto-start on boot)

```bash
sudo systemctl enable main_server proxy worker portal
```

### Stop Services

```bash
sudo systemctl stop portal worker proxy main_server
```

## Important Configuration

### Update .env File

After deployment, you **MUST** update the `.env` file with production values:

```bash
ssh <username>@<server_ip> -p 2223
sudo nano /opt/message_broker/.env
```

**Critical values to change:**
- `JWT_SECRET`: Use a strong, random secret (minimum 32 characters)
- `HASH_SALT`: Use a strong, random salt
- `DB_PASSWORD`: Change the default database password
- `MAIN_SERVER_URL`: Update with your server's actual URL/IP

### Firewall Configuration

Make sure these ports are open on your server:

```bash
# Ubuntu/Debian
sudo ufw allow 8000/tcp  # Main Server (HTTPS)
sudo ufw allow 8001/tcp  # Proxy (HTTPS)
sudo ufw allow 5000/tcp  # Web Portal (HTTP)
sudo ufw allow 2223/tcp  # SSH (if custom port)

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --permanent --add-port=8001/tcp
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --permanent --add-port=2223/tcp
sudo firewall-cmd --reload
```

## Accessing the Services

After starting the services:

- **Main Server API**: `https://<SERVER_IP>:8000/docs`
- **Proxy API**: `https://<SERVER_IP>:8001/api/v1/docs`
- **Web Portal**: `http://<SERVER_IP>:5000`

**Default Admin Credentials:**
- Email: `admin@example.com`
- Password: `AdminPass123!`

**⚠️ IMPORTANT**: Change the admin password immediately after first login!

## Troubleshooting

### SSH Connection Issues

If you can't connect:
1. Verify the server IP and port are correct
2. Check if SSH is running: `sudo systemctl status sshd`
3. Verify firewall allows the SSH port
4. Check if your SSH key has correct permissions (600)

### Service Won't Start

1. Check service status: `sudo systemctl status <service_name>`
2. View detailed logs: `sudo journalctl -u <service_name> -n 50`
3. Verify certificates exist: `ls -la /opt/message_broker/main_server/certs/`
4. Check database connection: `mysql -u systemuser -p message_system`
5. Check Redis connection: `redis-cli ping`

### Certificate Errors

If you see certificate errors:
1. Regenerate certificates:
   ```bash
   cd /opt/message_broker/main_server/certs
   # Follow certificate generation steps from deployment guide
   ```

### Database Connection Errors

1. Verify MySQL is running: `sudo systemctl status mysql`
2. Check database exists: `mysql -u root -p -e "SHOW DATABASES;"`
3. Verify user permissions: `mysql -u root -p -e "SHOW GRANTS FOR 'systemuser'@'localhost';"`

### Redis Connection Errors

1. Verify Redis is running: `sudo systemctl status redis`
2. Test connection: `redis-cli ping` (should return PONG)

## Manual Deployment Steps

If the automated script fails, you can deploy manually by following the steps in:
- `DEPLOYMENT_GUIDE_FA.md` (Persian/Farsi guide)
- `LINUX_DEPLOYMENT_GUIDE.md` (English guide)

## Security Checklist

Before going to production:

- [ ] Change all default passwords in `.env`
- [ ] Generate new certificates (don't use test certificates)
- [ ] Configure firewall rules
- [ ] Set up SSL/TLS certificates for production domain
- [ ] Enable log rotation
- [ ] Set up database backups
- [ ] Configure Redis persistence (AOF)
- [ ] Review and harden systemd service files
- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Review file permissions

## Support

For issues or questions:
1. Check the logs: `sudo journalctl -u <service_name> -f`
2. Review the deployment guides
3. Check service status: `sudo systemctl status <service_name>`

