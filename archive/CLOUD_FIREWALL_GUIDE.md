# Cloud Provider Firewall Configuration Guide

## Problem
You can't access the portal from your PC (`http://91.92.206.217:8080`) even though:
- ✅ All services are running
- ✅ Port 8080 is listening on the server
- ✅ No local firewall is blocking ports

**Solution:** Configure your cloud provider's firewall/security group to allow inbound traffic.

## Required Ports to Open

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 8000 | Main Server API | TCP | HTTPS API endpoint |
| 8001 | Proxy Server API | TCP | HTTPS Proxy endpoint |
| 8080 | Portal | TCP | HTTP Web interface |

## Step-by-Step Instructions by Provider

### DigitalOcean

1. **Go to DigitalOcean Dashboard**
   - Navigate to: https://cloud.digitalocean.com/networking/firewalls

2. **Create or Edit Firewall**
   - Click "Create Firewall" or select existing firewall attached to your droplet
   - Name: `message-broker-firewall` (or any name)

3. **Add Inbound Rules**
   - Click "Add Inbound Rule"
   - **Rule 1:**
     - Type: `Custom`
     - Protocol: `TCP`
     - Port Range: `8000`
     - Sources: `All IPv4` (or specific IPs)
   - **Rule 2:**
     - Type: `Custom`
     - Protocol: `TCP`
     - Port Range: `8001`
     - Sources: `All IPv4`
   - **Rule 3:**
     - Type: `Custom`
     - Protocol: `TCP`
     - Port Range: `8080`
     - Sources: `All IPv4`

4. **Apply to Droplet**
   - Select your droplet (91.92.206.217)
   - Click "Apply to Droplet"

### AWS (EC2)

1. **Go to EC2 Dashboard**
   - Navigate to: https://console.aws.amazon.com/ec2/
   - Click "Security Groups" in left menu

2. **Select Security Group**
   - Find the security group attached to your instance
   - Click on it to view details

3. **Edit Inbound Rules**
   - Click "Edit inbound rules"
   - Click "Add rule" for each port:
     - **Port 8000:**
       - Type: `Custom TCP`
       - Port: `8000`
       - Source: `0.0.0.0/0` (or your IP)
       - Description: `Main Server API`
     - **Port 8001:**
       - Type: `Custom TCP`
       - Port: `8001`
       - Source: `0.0.0.0/0`
       - Description: `Proxy Server API`
     - **Port 8080:**
       - Type: `Custom TCP`
       - Port: `8080`
       - Source: `0.0.0.0/0`
       - Description: `Portal`
   - Click "Save rules"

### Azure

1. **Go to Azure Portal**
   - Navigate to: https://portal.azure.com
   - Go to your Virtual Machine

2. **Open Network Security Group**
   - Click "Networking" in left menu
   - Click on the Network Security Group name

3. **Add Inbound Security Rules**
   - Click "Inbound security rules"
   - Click "+ Add" for each port:
     - **Port 8000:**
       - Source: `Any` or `IP Addresses`
       - Source port ranges: `*`
       - Destination: `Any`
       - Service: `Custom`
       - Protocol: `TCP`
       - Destination port ranges: `8000`
       - Action: `Allow`
       - Priority: `1000` (or any available)
       - Name: `Allow-MainServer-API`
     - **Port 8001:**
       - Same settings, port `8001`
       - Name: `Allow-Proxy-API`
     - **Port 8080:**
       - Same settings, port `8080`
       - Name: `Allow-Portal`
   - Click "Add" for each rule

### Google Cloud Platform (GCP)

1. **Go to GCP Console**
   - Navigate to: https://console.cloud.google.com
   - Go to "VPC network" → "Firewall"

2. **Create Firewall Rule**
   - Click "Create Firewall Rule"
   - Name: `allow-message-broker-ports`
   - Direction: `Ingress`
   - Action: `Allow`
   - Targets: `All instances in the network` (or specific tags)
   - Source IP ranges: `0.0.0.0/0` (or your IP)
   - Protocols and ports: `Specified protocols and ports`
   - Check `TCP` and enter: `8000,8001,8080`
   - Click "Create"

### Linode

1. **Go to Linode Dashboard**
   - Navigate to: https://cloud.linode.com/firewalls

2. **Create or Edit Firewall**
   - Click "Create Firewall" or select existing
   - Name: `message-broker-firewall`

3. **Add Inbound Rules**
   - Click "Add an Inbound Rule" for each port:
     - **Port 8000:**
       - Label: `Main Server API`
       - Protocol: `TCP`
       - Ports: `8000`
       - Sources: `0.0.0.0/0` (or your IP)
     - **Port 8001:**
       - Label: `Proxy Server API`
       - Protocol: `TCP`
       - Ports: `8001`
       - Sources: `0.0.0.0/0`
     - **Port 8080:**
       - Label: `Portal`
       - Protocol: `TCP`
       - Ports: `8080`
       - Sources: `0.0.0.0/0`

4. **Assign to Linode**
   - Select your Linode instance
   - Click "Assign"

### Vultr

1. **Go to Vultr Dashboard**
   - Navigate to: https://my.vultr.com/
   - Go to your server

2. **Configure Firewall**
   - Click "Firewall" tab
   - Click "Add Firewall Rule" for each port:
     - **Port 8000:**
       - Protocol: `TCP`
       - Port: `8000`
       - Source: `0.0.0.0/0`
     - **Port 8001:**
       - Protocol: `TCP`
       - Port: `8001`
       - Source: `0.0.0.0/0`
     - **Port 8080:**
       - Protocol: `TCP`
       - Port: `8080`
       - Source: `0.0.0.0/0`

## Security Best Practices

⚠️ **Important Security Notes:**

1. **Restrict Source IPs (Recommended)**
   - Instead of `0.0.0.0/0` (all IPs), use your specific IP or IP range
   - Find your IP: https://whatismyipaddress.com/
   - Example: `123.45.67.89/32` (single IP)

2. **Use HTTPS for Production**
   - Port 8080 (Portal) uses HTTP
   - Consider setting up a reverse proxy with SSL/TLS
   - Or use a VPN for secure access

3. **Regular Security Audits**
   - Review firewall rules periodically
   - Remove unused rules
   - Monitor access logs

## Testing After Configuration

After opening the ports, test from your PC:

### Test Portal (HTTP)
```powershell
# PowerShell
Invoke-WebRequest -Uri "http://91.92.206.217:8080" -UseBasicParsing | Select-Object StatusCode

# Or open in browser
# http://91.92.206.217:8080
```

### Test Main Server API (HTTPS)
```powershell
# PowerShell (skip certificate check for self-signed cert)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
Invoke-WebRequest -Uri "https://91.92.206.217:8000/health" -UseBasicParsing
```

### Test Proxy API (HTTPS)
```powershell
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
Invoke-WebRequest -Uri "https://91.92.206.217:8001/health" -UseBasicParsing
```

## Troubleshooting

### Still Can't Access?

1. **Verify Ports Are Open**
   - Use online port checker: https://www.yougetsignal.com/tools/open-ports/
   - Enter IP: `91.92.206.217`
   - Check ports: `8000`, `8001`, `8080`

2. **Check Service Status**
   ```bash
   ssh -p 2223 root@91.92.206.217 "systemctl status portal"
   ```

3. **Verify Ports Are Listening**
   ```bash
   ssh -p 2223 root@91.92.206.217 "netstat -tlnp | grep -E '(8000|8001|8080)'"
   ```

4. **Check Cloud Provider Status**
   - Ensure your server/instance is running
   - Check for any network issues in provider dashboard

## Quick Reference

**Your Server IP:** `91.92.206.217`  
**SSH Port:** `2223` (already open)  
**Required Ports:**
- `8000` - Main Server API (HTTPS)
- `8001` - Proxy Server API (HTTPS)
- `8080` - Portal (HTTP)

**Portal URL:** `http://91.92.206.217:8080`

