# How to Remote Desktop to Linux Server from Windows

This guide shows you how to set up remote desktop access to your Linux server from Windows.

## Option 1: XRDP (Recommended - Works with Windows Remote Desktop)

XRDP allows you to connect using Windows' built-in Remote Desktop Connection.

### Step 1: Install XRDP on the Server

SSH into your server and run:

```bash
# Update package list
apt update

# Install XRDP
apt install -y xrdp

# Install a desktop environment (if not already installed)
# For Ubuntu/Debian, install XFCE (lightweight):
apt install -y xfce4 xfce4-goodies

# For CentOS/RHEL:
# yum install -y xrdp
# yum groupinstall -y "Xfce"
```

### Step 2: Configure XRDP

```bash
# Configure XRDP to use XFCE
echo "xfce4-session" > ~/.xsession

# Or for all users:
echo "xfce4-session" > /etc/xrdp/startwm.sh
chmod +x /etc/xrdp/startwm.sh

# Start and enable XRDP service
systemctl enable xrdp
systemctl start xrdp

# Check status
systemctl status xrdp
```

### Step 3: Configure Firewall

```bash
# Allow RDP port (3389) through firewall
ufw allow 3389/tcp

# Or for firewalld (CentOS/RHEL):
# firewall-cmd --permanent --add-port=3389/tcp
# firewall-cmd --reload
```

**Important:** Also open port 3389 in your cloud provider's firewall/security group.

### Step 4: Connect from Windows

1. Open **Remote Desktop Connection** (search for "Remote Desktop" in Windows)
2. Enter the server IP: `91.92.206.217:3389`
3. Click **Connect**
4. Enter credentials:
   - Username: `root` (or your user)
   - Password: Your server password
5. Click **OK**

---

## Option 2: VNC (Alternative)

VNC is another popular remote desktop solution.

### Step 1: Install VNC Server

```bash
# Install VNC server
apt install -y tigervnc-standalone-server tigervnc-common

# Or for CentOS/RHEL:
# yum install -y tigervnc-server
```

### Step 2: Set VNC Password

```bash
# Set VNC password for root
vncpasswd

# Or for a specific user:
# su - username
# vncpasswd
```

### Step 3: Start VNC Server

```bash
# Start VNC server (display :1, port 5901)
vncserver :1 -geometry 1920x1080 -depth 24

# To stop:
# vncserver -kill :1
```

### Step 4: Configure Firewall

```bash
# Allow VNC port (5901 for display :1)
ufw allow 5901/tcp
```

### Step 5: Connect from Windows

1. Install a VNC client:
   - **TightVNC Viewer**: https://www.tightvnc.com/download.php
   - **RealVNC Viewer**: https://www.realvnc.com/download/viewer/
   - **UltraVNC**: https://www.uvnc.com/downloads/ultravnc.html

2. Connect to: `91.92.206.217:5901`

---

## Option 3: X11 Forwarding over SSH (For GUI Applications Only)

This allows you to run GUI applications from the server and display them on your Windows machine.

### Step 1: Install X Server on Windows

Install **Xming** or **VcXsrv**:
- **Xming**: https://sourceforge.net/projects/xming/
- **VcXsrv**: https://sourceforge.net/projects/vcxsrv/

### Step 2: Connect with X11 Forwarding

```powershell
# Enable X11 forwarding in SSH
ssh -X -p 2223 root@91.92.206.217

# Or use PuTTY:
# Connection > SSH > X11 > Enable X11 forwarding
```

### Step 3: Run GUI Applications

```bash
# Once connected, you can run GUI apps:
firefox
gedit
# etc.
```

---

## Option 4: NoMachine (Easy Setup)

NoMachine is a commercial solution with a free version.

### Step 1: Install NoMachine on Server

```bash
# Download and install NoMachine
wget https://download.nomachine.com/download/8.x/Linux/nomachine_8.x.x_x86_64.deb
dpkg -i nomachine_*.deb

# Or for CentOS/RHEL:
# wget https://download.nomachine.com/download/8.x/Linux/nomachine_8.x.x_x86_64.rpm
# rpm -ivh nomachine_*.rpm
```

### Step 2: Install NoMachine Client on Windows

Download from: https://www.nomachine.com/download

### Step 3: Connect

Use the server IP and credentials.

---

## Troubleshooting

### XRDP Connection Issues

**Problem:** Can't connect to XRDP
- Check if XRDP is running: `systemctl status xrdp`
- Check firewall: `ufw status`
- Check if port 3389 is open in cloud provider firewall
- Check XRDP logs: `tail -f /var/log/xrdp-sesman.log`

**Problem:** Black screen after connecting
- Reconfigure XRDP session:
  ```bash
  echo "xfce4-session" > ~/.xsession
  chmod +x ~/.xsession
  ```

**Problem:** "Connection refused"
- Restart XRDP: `systemctl restart xrdp`
- Check if port is listening: `netstat -tlnp | grep 3389`

### VNC Issues

**Problem:** VNC connection fails
- Check if VNC is running: `ps aux | grep vnc`
- Check firewall rules
- Verify VNC password is set correctly

---

## Security Recommendations

1. **Change Default Ports:**
   ```bash
   # Edit XRDP config
   nano /etc/xrdp/xrdp.ini
   # Change port=3389 to a custom port
   ```

2. **Use SSH Tunnel (Recommended):**
   ```powershell
   # Create SSH tunnel
   ssh -L 3389:localhost:3389 -p 2223 root@91.92.206.217
   
   # Then connect to localhost:3389 in Remote Desktop
   ```

3. **Limit Access:**
   - Use firewall rules to restrict access to specific IPs
   - Consider using VPN instead of direct RDP access

4. **Use Strong Passwords:**
   - Ensure all user accounts have strong passwords
   - Consider disabling root login via RDP

---

## Quick Setup Script for XRDP

Save this as `setup_xrdp.sh` and run it on the server:

```bash
#!/bin/bash
# Quick XRDP setup script

echo "Installing XRDP and XFCE..."
apt update
apt install -y xrdp xfce4 xfce4-goodies

echo "Configuring XRDP..."
echo "xfce4-session" > ~/.xsession
chmod +x ~/.xsession

echo "Starting XRDP service..."
systemctl enable xrdp
systemctl start xrdp

echo "Configuring firewall..."
ufw allow 3389/tcp

echo "XRDP setup complete!"
echo "Connect from Windows using: 91.92.206.217:3389"
echo ""
echo "IMPORTANT: Also open port 3389 in your cloud provider's firewall!"
```

---

## Summary

**Recommended:** Use **XRDP** for the easiest setup that works with Windows Remote Desktop.

**Steps:**
1. Install XRDP and a desktop environment on the server
2. Configure XRDP to use the desktop environment
3. Open port 3389 in server firewall and cloud provider firewall
4. Connect from Windows using Remote Desktop Connection

**Connection Details:**
- Server: `91.92.206.217:3389`
- Username: `root` (or your user)
- Password: Your server password

