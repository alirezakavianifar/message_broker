# Message Broker System - Source Code Package

**Version**: 1.0.0  
**Package Date**: November 1, 2025  
**Platform**: Windows Server 2019/2022

---

## Package Contents

This package contains the complete source code for the Message Broker System, including:

- **Proxy Server** - Client-facing API with mutual TLS
- **Main Server** - Central API, database, and certificate management
- **Worker Service** - Message queue processing
- **Web Portal** - User and admin interface
- **Client Scripts** - Example Python client
- **Documentation** - Complete user and admin manuals
- **Deployment Scripts** - Installation and service setup
- **Test Suite** - Comprehensive testing tools

---

## What's Included

✅ All Python source code  
✅ Configuration files (.yaml, .ini)  
✅ Database schemas and migrations  
✅ Startup scripts (.ps1, .bat)  
✅ Complete documentation  
✅ Test scripts and test plans  
✅ Certificate generation scripts  

---

## What's Excluded (For Security)

❌ **Virtual Environment** (`venv/`) - Will be created during setup  
❌ **Private Keys** (`*.key`) - Generate during setup  
❌ **Client Certificates** (`*.crt`, `*.csr`, `*.pem`) - Generate during setup  
❌ **Secrets** (`secrets/`) - Generated during setup  
❌ **Log Files** (`logs/`, `*.log`) - Generated at runtime  
❌ **Python Cache** (`__pycache__/`) - Generated at runtime  
❌ **Git History** (`.git/`) - Not needed for deployment  
❌ **Environment Files** (`.env`) - Create from template  

---

## Quick Setup Instructions

1. **Extract** the zip file to your target directory

2. **Create Virtual Environment**:
   ```powershell
   python -m venv venv
   .\venv\Scripts\Activate.ps1
   ```

3. **Install Dependencies**:
   ```powershell
   # Install main dependencies
   pip install -r main_server\requirements.txt
   pip install -r proxy\requirements.txt
   pip install -r worker\requirements.txt
   pip install -r portal\requirements.txt
   ```

4. **Generate Certificates**:
   ```powershell
   cd main_server
   .\init_ca.bat
   .\generate_cert.bat proxy
   .\generate_cert.bat worker
   ```

5. **Setup Database**:
   - Create MySQL database
   - Run Alembic migrations: `alembic upgrade head`

6. **Start Services**:
   ```powershell
   .\start_all_services.ps1
   ```

---

## Full Documentation

See `README.md` for complete setup instructions and `deployment/DEPLOYMENT_GUIDE.md` for production deployment.

---

## Support

- **User Manual**: `docs/USER_MANUAL.md`
- **Admin Manual**: `docs/ADMIN_MANUAL.md`
- **Operations Guide**: `docs/OPERATIONS_RUNBOOK.md`
- **API Specification**: `API_SPECIFICATION.md`

---

**Note**: This is a clean source code package. Certificates, environment files, and secrets need to be generated/configured during deployment for security reasons.
