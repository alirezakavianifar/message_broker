# Opening Port 3389 for Remote Desktop

## The Problem
xrdp is running correctly on the server, but the cloud provider's firewall is blocking port 3389.

## Solution: Open Port 3389 in Cloud Provider Firewall

### For DigitalOcean:
1. Go to your Droplet → **Networking** tab
2. Click **Firewalls** → **Create Firewall** (or edit existing)
3. Add **Inbound Rule**:
   - **Type:** Custom
   - **Protocol:** TCP
   - **Port Range:** 3389
   - **Sources:** All IPv4, All IPv6 (or your IP for security)
4. Click **Create** or **Save**

### For AWS:
1. Go to **EC2** → **Security Groups**
2. Select your instance's security group
3. Click **Edit Inbound Rules**
4. Click **Add Rule**:
   - **Type:** Custom TCP
   - **Port Range:** 3389
   - **Source:** 0.0.0.0/0 (or your IP for security)
5. Click **Save Rules**

### For Azure:
1. Go to your VM → **Networking**
2. Click **Add Inbound Port Rule**
3. Configure:
   - **Destination port ranges:** 3389
   - **Protocol:** TCP
   - **Action:** Allow
   - **Priority:** (any number)
   - **Name:** RDP
4. Click **Add**

### For Google Cloud:
1. Go to **VPC Network** → **Firewall Rules**
2. Click **Create Firewall Rule**
3. Configure:
   - **Name:** allow-rdp
   - **Direction:** Ingress
   - **Targets:** All instances in the network
   - **Source IP ranges:** 0.0.0.0/0 (or your IP)
   - **Protocols and ports:** TCP: 3389
4. Click **Create**

### For Other Providers:
Look for:
- **Firewall Rules**
- **Security Groups**
- **Network Security Groups**
- **Inbound Rules**

Add a rule allowing **TCP port 3389** from your IP or all IPs.

## After Opening the Port:
1. Wait 1-2 minutes for the rule to propagate
2. Try connecting again with Remote Desktop:
   - Computer: `91.92.206.217:3389`
   - Username: `root`

## Security Note:
For better security, consider restricting the source IP to your own IP address instead of allowing all IPs (0.0.0.0/0).

