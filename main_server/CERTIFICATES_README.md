# Certificate Management Guide

**Message Broker System - Windows Environment**  
**Version:** 1.0.0  
**Platform:** Windows 10/11

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Certificate Authority Setup](#certificate-authority-setup)
5. [Client Certificate Management](#client-certificate-management)
6. [Certificate Verification](#certificate-verification)
7. [Certificate Revocation](#certificate-revocation)
8. [Certificate Renewal](#certificate-renewal)
9. [Certificate Distribution](#certificate-distribution)
10. [Troubleshooting](#troubleshooting)
11. [Security Best Practices](#security-best-practices)

---

## Overview

The Message Broker System uses **Mutual TLS (mTLS)** authentication for secure communication between:
- Clients → Proxy Server
- Proxy Server → Main Server
- Workers → Main Server

This guide covers the complete certificate lifecycle:
- CA initialization
- Certificate generation
- Certificate verification
- Certificate revocation
- Certificate renewal

---

## Prerequisites

### Required Software

1. **OpenSSL** (for Windows)
   - Download: https://slproweb.com/products/Win32OpenSSL.html
   - Install and add to PATH
   - Verify: `openssl version`

2. **Windows PowerShell** or **Command Prompt**
   - Run as Administrator for some operations

### Directory Structure

```
main_server/
├── certs/                    # Certificate storage
│   ├── ca.key               # CA private key (KEEP SECURE!)
│   ├── ca.crt               # CA certificate (distribute to clients)
│   ├── ca.srl               # Serial number tracking
│   └── clients/             # Client certificates
│       └── <client_name>/
│           ├── <client>.key
│           ├── <client>.crt
│           ├── ca.crt
│           └── fingerprint.txt
├── crl/                      # Certificate Revocation List
│   ├── revoked.pem          # List of revoked certificates
│   └── revocation_log.txt   # Revocation audit log
└── *.bat                     # Management scripts
```

---

## Quick Start

### 1. Initialize Certificate Authority

```batch
cd main_server
init_ca.bat
```

This creates:
- `certs/ca.key` - CA private key (4096-bit RSA)
- `certs/ca.crt` - CA certificate (10-year validity)
- `certs/ca.srl` - Certificate serial tracking
- `crl/revoked.pem` - Empty CRL

**⚠️ IMPORTANT:** Back up `ca.key` immediately to a secure location!

### 2. Generate Client Certificate

```batch
generate_cert.bat client_001 example.com 365
```

Arguments:
- `client_001` - Client identifier (required)
- `example.com` - Domain (optional, default: "default")
- `365` - Validity in days (optional, default: 365)

Output location: `certs/clients/client_001/`

### 3. Verify Certificate

```batch
verify_cert.bat client_001
```

### 4. List All Certificates

```batch
list_certs.bat all
```

Options: `all`, `active`, `revoked`

---

## Certificate Authority Setup

### Initialization

The Certificate Authority (CA) is the root of trust for all certificates.

```batch
REM Initialize CA (first time only)
init_ca.bat
```

**What This Does:**
1. Generates 4096-bit RSA private key for CA
2. Creates self-signed CA certificate (10-year validity)
3. Sets restrictive permissions on CA private key
4. Initializes serial number tracking
5. Creates empty CRL

**CA Certificate Details:**
- **Common Name (CN):** MessageBrokerCA
- **Organization (O):** MessageBroker
- **Validity:** 10 years
- **Key Size:** 4096-bit RSA
- **Signature Algorithm:** SHA-256

### Backup CA Private Key

**Critical:** The CA private key must be backed up securely!

```powershell
# Create encrypted backup
$source = "main_server\certs\ca.key"
$destination = "D:\secure_backup\ca_key_backup_$(Get-Date -Format 'yyyyMMdd').key"

# Copy to secure location
Copy-Item $source $destination

# Optionally encrypt with GPG or similar
gpg --symmetric --cipher-algo AES256 $destination
```

### Recreating CA

⚠️ **Warning:** Recreating the CA invalidates ALL existing certificates!

If you must recreate:
1. Back up existing certificates
2. Run `init_ca.bat` and confirm recreation
3. Re-issue all client certificates
4. Distribute new CA certificate to all clients

---

## Client Certificate Management

### Generating Client Certificates

#### Basic Usage

```batch
generate_cert.bat client_name
```

#### With Domain

```batch
generate_cert.bat client_001 example.com
```

#### Custom Validity

```batch
generate_cert.bat client_001 example.com 730
```

(730 days = 2 years)

#### Generated Files

For each client, the following files are created in `certs/clients/<client_name>/`:

| File | Description | Security |
|------|-------------|----------|
| `<client>.key` | Private key (2048-bit RSA) | **CRITICAL - Keep secure!** |
| `<client>.crt` | Client certificate | Distribute to client |
| `<client>.csr` | Certificate signing request | Can delete after generation |
| `ca.crt` | CA certificate | Distribute to client |
| `fingerprint.txt` | SHA-256 fingerprint | Store in database |
| `install_instructions.bat` | Installation guide | Helpful reference |

### Certificate Properties

**Client Certificate Details:**
- **Common Name (CN):** Client identifier
- **Organization (O):** MessageBroker
- **Organizational Unit (OU):** Domain name
- **Issuer:** MessageBrokerCA
- **Key Size:** 2048-bit RSA
- **Validity:** 365 days (default, configurable)
- **Signature Algorithm:** SHA-256

### Database Registration

After generating a certificate, register it in the database:

```sql
-- Get fingerprint from fingerprint.txt
-- Example: SHA256 Fingerprint=AB:CD:EF:...

INSERT INTO clients (
    client_id,
    cert_fingerprint,
    domain,
    status,
    issued_at,
    expires_at
) VALUES (
    'client_001',
    'ABCDEF...', -- SHA-256 fingerprint (remove colons)
    'example.com',
    'active',
    NOW(),
    DATE_ADD(NOW(), INTERVAL 365 DAY)
);
```

---

## Certificate Verification

### Verify Certificate

```batch
REM By client name
verify_cert.bat client_001

REM By certificate path
verify_cert.bat C:\path\to\certificate.crt
```

### Verification Checks

The verification script performs these checks:

1. **Signature Verification**
   - Verifies certificate is signed by trusted CA
   - Validates signature algorithm

2. **Expiration Check**
   - Confirms certificate is not expired
   - Warns if expiring within 30 days

3. **Revocation Check**
   - Checks if certificate is in CRL
   - Verifies against local revocation list

4. **Key Usage Verification**
   - Validates certificate purpose
   - Checks for TLS client authentication

5. **Fingerprint Calculation**
   - Generates SHA-256 fingerprint
   - For database verification

### Verification Results

**Valid Certificate:**
```
[PASS] Certificate is VALID
  [√] Signature verified
  [√] Not expired
  [√] Valid for more than 30 days
  [√] Not revoked
  [√] Correct key usage
```

**Invalid Certificate:**
```
[FAIL] Certificate is INVALID
  [X] Certificate revoked
```

### Manual Verification

```batch
REM Verify certificate signature
openssl verify -CAfile certs\ca.crt certs\clients\client_001\client_001.crt

REM Check expiration
openssl x509 -in certs\clients\client_001\client_001.crt -noout -dates

REM Get fingerprint
openssl x509 -in certs\clients\client_001\client_001.crt -noout -fingerprint -sha256

REM View certificate details
openssl x509 -in certs\clients\client_001\client_001.crt -noout -text
```

---

## Certificate Revocation

### When to Revoke

Revoke a certificate immediately if:
- Private key is compromised
- Client is no longer authorized
- Certificate was issued in error
- Security breach suspected

### Revocation Process

```batch
revoke_cert.bat client_001 "Certificate compromised"
```

Arguments:
- `client_001` - Client to revoke (required)
- `"Certificate compromised"` - Reason (optional)

### What Happens

1. Certificate serial number extracted
2. Certificate added to CRL (`crl/revoked.pem`)
3. Certificate files renamed to `.revoked`
4. Revocation logged to `crl/revocation_log.txt`
5. Revocation record created in certificate directory

### Update Database

After revocation, update the database:

```sql
UPDATE clients 
SET 
    status = 'revoked',
    revoked_at = NOW(),
    revocation_reason = 'Certificate compromised'
WHERE client_id = 'client_001';
```

### Reload CRL

After revoking a certificate:

1. **Services must reload CRL**
   - Restart proxy service
   - Restart main server
   - Or implement hot-reload mechanism

2. **Verify rejection**
   - Client should be rejected on next connection attempt

### View Revoked Certificates

```batch
REM View CRL
type crl\revoked.pem

REM View revocation log
type crl\revocation_log.txt

REM List only revoked certificates
list_certs.bat revoked
```

---

## Certificate Renewal

### When to Renew

Renew certificates:
- 30 days before expiration (recommended)
- After security policy updates
- When increasing key size
- For compromised-then-recovered scenarios

### Renewal Process

```batch
renew_cert.bat client_001 365
```

Arguments:
- `client_001` - Client to renew (required)
- `365` - New validity in days (optional, default: 365)

### What Happens

1. Old certificate backed up to `backup/` subdirectory
2. New private key generated
3. New certificate signed by CA
4. Old certificate replaced
5. New fingerprint calculated

### Renewal vs. Re-issue

| Renewal | Re-issue |
|---------|----------|
| Keeps same client identity | New client identity |
| Generates new key pair | Optionally keeps key |
| Updates expiration | Full new certificate |
| Use for routine updates | Use for changes |

### Update Database After Renewal

```sql
-- Get new fingerprint from fingerprint.txt

UPDATE clients 
SET 
    cert_fingerprint = 'NEW_FINGERPRINT',
    expires_at = DATE_ADD(NOW(), INTERVAL 365 DAY),
    status = 'active'
WHERE client_id = 'client_001';
```

### Distribute Renewed Certificate

1. Package files for client:
   ```
   - client_001.key (new)
   - client_001.crt (new)
   - ca.crt (same)
   ```

2. Securely deliver to client (encrypted email, secure file transfer)

3. Client updates certificate files

4. Client restarts application

5. Verify new certificate works

### Backup Management

Backups are stored in: `certs/clients/<client_name>/backup/`

Format: `<client>.<ext>.<timestamp>`

Example:
```
backup/
├── client_001.crt.20251020_143025
├── client_001.key.20251020_143025
└── client_001.crt.20251015_091512
```

**Recommendation:** Keep backups for 90 days after renewal.

---

## Certificate Distribution

### Secure Distribution Methods

#### Method 1: Encrypted Email

```powershell
# Create encrypted archive
$clientName = "client_001"
$sourceDir = "main_server\certs\clients\$clientName"
$archiveName = "${clientName}_certificates.zip"

# Create ZIP with password
Compress-Archive -Path "$sourceDir\*.crt","$sourceDir\*.key","$sourceDir\ca.crt" `
    -DestinationPath $archiveName

# Send via encrypted email
# Password should be communicated separately (phone, SMS)
```

#### Method 2: Secure File Transfer

- Use SFTP or SCP
- Use secure cloud storage with encryption
- Use company VPN with file share

#### Method 3: Physical Media

- Encrypted USB drive
- Hand delivery for high-security scenarios

### Client Installation

Create client installation package:

```
client_001_package/
├── client_001.key        # Private key
├── client_001.crt        # Client certificate
├── ca.crt                # CA certificate
├── README.txt            # Installation instructions
└── test_connection.py    # Test script
```

**README.txt Example:**

```
Message Broker Client Certificate Installation

1. Place certificate files in your application directory:
   - client_001.key
   - client_001.crt
   - ca.crt

2. Update your application configuration:
   
   Using curl (No Python required):
   ```bash
   curl -X POST https://proxy.example.com:8001/api/v1/messages \
     --cert client_001.crt \
     --key client_001.key \
     --cacert ca.crt \
     -H "Content-Type: application/json" \
     -d '{
       "sender_number": "+1234567890",
       "message_body": "Your message here"
     }'
   ```
   
   Python (httpx) - Optional:
   ```python
   cert = ("client_001.crt", "client_001.key")
   verify = "ca.crt"
   
   response = httpx.post(
       "https://proxy.example.com:8001/api/v1/messages",
       json={
           "sender_number": "+1234567890",
           "message_body": "Your message here"
       },
       cert=cert,
       verify=verify
   )
   ```
   
   Note: You can use any HTTP client (curl, Postman, JavaScript, Go, etc.).
   Python is NOT required - it's just one option.

3. Set file permissions (Linux/Mac):
   chmod 600 client_001.key
   chmod 644 client_001.crt ca.crt

4. Test connection:
   # Using curl:
   curl --cert client_001.crt --key client_001.key --cacert ca.crt \
     https://proxy.example.com:8001/health
   
   # Or using Python script (if available):
   python test_connection.py

5. Backup certificates securely

For support, contact: support@messagebroker.example.com
See client-scripts/README.md for more examples
```

---

## Troubleshooting

### Common Issues

#### 1. "OpenSSL not found"

**Problem:** OpenSSL is not in PATH

**Solution:**
```powershell
# Add OpenSSL to PATH
$env:PATH += ";C:\Program Files\OpenSSL-Win64\bin"

# Or install via Chocolatey
choco install openssl
```

#### 2. "CA not initialized"

**Problem:** Trying to generate certificate before initializing CA

**Solution:**
```batch
# Run CA initialization first
init_ca.bat
```

#### 3. "Certificate verification failed"

**Possible Causes:**
- Certificate expired
- Certificate revoked
- Wrong CA certificate
- Certificate file corrupted

**Solution:**
```batch
# Verify certificate
verify_cert.bat client_001

# Check expiration
openssl x509 -in cert.crt -noout -dates

# Check CRL
type crl\revoked.pem | findstr client_001
```

#### 4. "Permission denied" on certificate files

**Problem:** Insufficient permissions

**Solution:**
```powershell
# Set correct permissions
icacls cert.key /inheritance:r
icacls cert.key /grant:r "%USERNAME%:F"
```

#### 5. Client connection rejected

**Checklist:**
- [ ] Certificate not expired: `verify_cert.bat client`
- [ ] Certificate not revoked: Check CRL
- [ ] Correct CA certificate on client
- [ ] Certificate fingerprint in database
- [ ] Client status = 'active' in database
- [ ] Server trusts CA certificate

### Debug Commands

```batch
REM Verify certificate chain
openssl verify -CAfile ca.crt -verbose client.crt

REM Check certificate dates
openssl x509 -in client.crt -noout -dates

REM View certificate details
openssl x509 -in client.crt -noout -text

REM Check private key
openssl rsa -in client.key -check

REM Verify private key matches certificate
openssl x509 -in client.crt -noout -modulus
openssl rsa -in client.key -noout -modulus
REM (outputs should match)

REM Test TLS connection
openssl s_client -connect proxy.example.com:8001 ^
    -cert client.crt -key client.key -CAfile ca.crt
```

---

## Security Best Practices

### CA Security

✅ **DO:**
- Keep CA private key encrypted and backed up
- Limit access to CA key (administrators only)
- Store CA key on encrypted filesystem
- Use hardware security module (HSM) for production
- Regularly audit CA operations
- Keep CA offline when not generating certificates

❌ **DON'T:**
- Share CA private key
- Store CA key in version control
- Keep CA key on publicly accessible servers
- Use weak passwords for CA key encryption

### Client Certificate Security

✅ **DO:**
- Use strong key sizes (minimum 2048-bit RSA)
- Set short validity periods (365 days)
- Implement automated renewal process
- Monitor expiration dates
- Revoke compromised certificates immediately
- Use certificate pinning where possible

❌ **DON'T:**
- Reuse private keys
- Store private keys unencrypted
- Share certificates between clients
- Ignore expiration warnings

### Distribution Security

✅ **DO:**
- Encrypt certificate packages
- Use secure communication channels
- Verify recipient identity
- Communicate passwords separately
- Confirm successful installation
- Delete insecure copies

❌ **DON'T:**
- Send certificates via unencrypted email
- Post certificates in public channels
- Leave certificates in downloads folder
- Use weak archive passwords

### Operational Security

✅ **DO:**
- Maintain audit logs of all operations
- Review CRL regularly
- Monitor certificate usage
- Implement certificate rotation
- Test revocation process
- Document procedures

❌ **DON'T:**
- Skip backup procedures
- Ignore security alerts
- Delay revocations
- Forget to update database
- Skip verification tests

---

## Certificate Scripts Reference

### Available Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `init_ca.bat` | Initialize Certificate Authority | `init_ca.bat` |
| `generate_cert.bat` | Generate client certificate | `generate_cert.bat <name> [domain] [days]` |
| `revoke_cert.bat` | Revoke certificate | `revoke_cert.bat <name> [reason]` |
| `renew_cert.bat` | Renew certificate | `renew_cert.bat <name> [days]` |
| `verify_cert.bat` | Verify certificate | `verify_cert.bat <name>` |
| `list_certs.bat` | List certificates | `list_certs.bat [all\|active\|revoked]` |

### Exit Codes

All scripts use standard exit codes:
- `0` - Success
- `1` - Error

Check exit code:
```batch
generate_cert.bat client_001
if %ERRORLEVEL% EQU 0 (echo Success) else (echo Failed)
```

---

## Appendix

### Certificate Lifecycle

```
[Initialize CA] → [Generate Certificate] → [Distribute] → [Use] → [Monitor]
                                              ↓                      ↓
                                            [Renew] ← ← ← ← ← ← ← ← [Expiring?]
                                              ↓
                                            [Revoke] (if compromised)
```

### File Permissions (Windows)

```powershell
# CA private key (read-only for owner)
icacls ca.key /inheritance:r
icacls ca.key /grant:r "%USERNAME%:R"

# Client private key (full control for owner)
icacls client.key /inheritance:r
icacls client.key /grant:r "%USERNAME%:F"

# Certificates (readable by all)
icacls *.crt /grant Everyone:R
```

### Certificate Renewal Schedule

| Days Before Expiry | Action |
|--------------------|--------|
| 60 days | Monitor alert |
| 30 days | Warning notification |
| 14 days | Generate renewal certificate |
| 7 days | Critical alert |
| 0 days | Certificate expired (revoked status) |

---

**Document Version:** 1.0.0  
**Last Updated:** October 2025  
**Contact:** support@messagebroker.example.com

