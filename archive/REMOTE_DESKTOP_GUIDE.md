# Remote Desktop Access Guide

## Connecting to Linux Server from Windows

### Step 1: Open Remote Desktop Connection
1. Press `Win + R`
2. Type `mstsc` and press Enter
3. Or search for "Remote Desktop Connection" in Windows Start menu

### Step 2: Connect to Server
- **Computer:** `91.92.206.217:3389`
- **Username:** `root`
- **Password:** Your root password (same as SSH)

### Step 3: Firewall Configuration
If connection fails, open port **3389 (TCP)** in your cloud provider's firewall:
- **DigitalOcean:** Networking → Firewalls → Add Inbound Rule
- **AWS:** Security Groups → Inbound Rules → Add Rule (Port 3389)
- **Azure:** Network Security Groups → Inbound Rules → Add Rule

### Step 4: Access Portal Locally
Once connected to the remote desktop:
1. Open a web browser (Firefox/Chromium should be available)
2. Navigate to: `http://localhost:8080`
3. Login with:
   - **Email:** `admin@example.com`
   - **Password:** `AdminPass123!`

### Alternative: X11 Forwarding (No Desktop Environment)
If you prefer not to install a full desktop, you can use X11 forwarding:

**On Windows:**
1. Install [VcXsrv](https://sourceforge.net/projects/vcxsrv/) or [Xming](https://sourceforge.net/projects/xming/)
2. Start X server
3. Connect via SSH with X11 forwarding:
   ```powershell
   ssh -p 2223 -X root@91.92.206.217
   ```
4. Then run: `firefox http://localhost:8080` or `chromium http://localhost:8080`

### Troubleshooting
- **Connection refused:** Check firewall rules for port 3389
- **Black screen:** Try restarting xrdp: `systemctl restart xrdp`
- **Can't login:** Make sure you're using the root user and correct password

