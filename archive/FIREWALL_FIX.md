# Fixing Firewall Issues for Portal Access

If you can't access the portal from your PC (`http://91.92.206.217:8080`), the issue is likely a firewall blocking the ports.

## Quick Fix Commands

### Step 1: Check which firewall is running

```bash
ssh -p 2223 root@91.92.206.217 "which ufw firewall-cmd iptables 2>/dev/null | head -1"
```

### Step 2: Open ports based on your firewall

#### If using UFW (Ubuntu/Debian):

```bash
ssh -p 2223 root@91.92.206.217 "ufw allow 8000/tcp && ufw allow 8001/tcp && ufw allow 8080/tcp && ufw reload && ufw status"
```

#### If using firewalld (CentOS/RHEL):

```bash
ssh -p 2223 root@91.92.206.217 "firewall-cmd --permanent --add-port=8000/tcp && firewall-cmd --permanent --add-port=8001/tcp && firewall-cmd --permanent --add-port=8080/tcp && firewall-cmd --reload && firewall-cmd --list-ports"
```

#### If using iptables:

```bash
ssh -p 2223 root@91.92.206.217 "iptables -A INPUT -p tcp --dport 8000 -j ACCEPT && iptables -A INPUT -p tcp --dport 8001 -j ACCEPT && iptables -A INPUT -p tcp --dport 8080 -j ACCEPT && iptables-save"
```

### Step 3: Test portal locally on server

```bash
ssh -p 2223 root@91.92.206.217 "curl -s http://localhost:8080 | head -10"
```

If this works, the portal is running correctly and the issue is definitely the firewall.

## Cloud Provider Firewall

**IMPORTANT:** Most cloud providers have their own firewall/security groups that need to be configured separately from the server firewall.

### Common Cloud Providers:

1. **DigitalOcean**: Go to Networking → Firewalls → Create/Edit firewall rules
2. **AWS**: Go to EC2 → Security Groups → Edit inbound rules
3. **Azure**: Go to Network Security Groups → Add inbound security rules
4. **GCP**: Go to VPC Network → Firewall rules → Create firewall rule
5. **Linode**: Go to Firewalls → Create/Edit firewall

### Required Ports to Open:

- **Port 8000** (TCP) - Main Server API (HTTPS)
- **Port 8001** (TCP) - Proxy Server API (HTTPS)  
- **Port 8080** (TCP) - Portal (HTTP)

### Test After Opening Ports:

From your PC, try accessing:
- Portal: `http://91.92.206.217:8080`
- Main API: `https://91.92.206.217:8000/health`
- Proxy API: `https://91.92.206.217:8001/health`

## Troubleshooting

### Check if portal works locally:

```bash
ssh -p 2223 root@91.92.206.217 "curl -I http://localhost:8080"
```

Expected: `HTTP/1.1 200 OK` or similar

### Check if ports are listening:

```bash
ssh -p 2223 root@91.92.206.217 "netstat -tlnp | grep -E '(8000|8001|8080)'"
```

Expected: All three ports should show `LISTEN`

### Check firewall status:

```bash
# For UFW
ssh -p 2223 root@91.92.206.217 "ufw status numbered"

# For firewalld
ssh -p 2223 root@91.92.206.217 "firewall-cmd --list-all"
```

## Quick One-Liner to Open All Ports (UFW)

If you're using UFW and want to quickly open all required ports:

```bash
ssh -p 2223 root@91.92.206.217 "ufw allow 8000/tcp comment 'Main Server API' && ufw allow 8001/tcp comment 'Proxy Server API' && ufw allow 8080/tcp comment 'Portal' && ufw reload && echo 'Ports opened successfully!' && ufw status | grep -E '(8000|8001|8080)'"
```

