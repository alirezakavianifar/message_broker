# Message Broker - Thin Client Implementation Guide

**Welcome!** This package contains everything you need to understand and test the thin client implementation.

## 📁 Package Structure

```
thin_client_package/
├── README.md                    ← You are here - Start reading!
├── QUICK_START.md               ← Quick start guide (read next)
│
├── docs/                        ← Documentation folder
│   ├── API_REFERENCE.md         ← Complete API documentation
│   ├── PLATFORM_GUIDE.md        ← Windows vs Linux/Mac guidance
│   └── USER_MANUAL.md           ← Full user manual (reference)
│
├── scripts/                     ← Ready-to-use scripts
│   ├── send_message_windows.ps1 ← For Windows (use this on Windows)
│   ├── send_message_linux.sh    ← For Linux/Mac/WSL
│   └── send_message_python.py   ← Optional Python version
│
└── tests/                       ← Test files
    ├── test_message_valid.json   ← Valid message example
    └── test_message_invalid.json ← Invalid message (for testing validation)
```

## 🚀 Getting Started (3 Steps)

### Step 1: Read This File
You're doing it! This README explains the package structure.

### Step 2: Read QUICK_START.md
Open `QUICK_START.md` - it's a concise guide that tells you exactly what to do.

### Step 3: Choose Your Platform
- **Windows?** → Read `docs/PLATFORM_GUIDE.md` → Use `scripts/send_message_windows.ps1`
- **Linux/Mac?** → Read `docs/PLATFORM_GUIDE.md` → Use `scripts/send_message_linux.sh`

## 📚 What's in Each Folder?

### `docs/` - Documentation
- **API_REFERENCE.md** - Complete API details (endpoints, request/response formats, error codes)
- **PLATFORM_GUIDE.md** - Platform-specific notes (which script to use, troubleshooting)
- **USER_MANUAL.md** - Comprehensive user manual (reference guide)

### `scripts/` - Ready-to-Use Scripts
- **send_message_windows.ps1** - PowerShell script for Windows
- **send_message_linux.sh** - Bash script for Linux/Mac/WSL
- **send_message_python.py** - Python script (optional, all platforms)

### `tests/` - Test Files
- **test_message_valid.json** - Example of a valid message
- **test_message_invalid.json** - Example of invalid message (tests validation)

## ✅ Before You Start Testing

Make sure you have:
- [ ] Proxy server running (port 8001)
- [ ] Client certificates:
  - [ ] `client.crt` - Your certificate
  - [ ] `client.key` - Your private key
  - [ ] `ca.crt` - CA certificate

## 🎯 Quick Test

1. Open `QUICK_START.md`
2. Find your platform (Windows or Linux/Mac)
3. Follow the example command
4. Test with `tests/test_message_valid.json`

## 💡 Key Concept

**Thin Client = No Python Required!**

You can send messages using:
- ✅ curl (Linux/Mac/WSL)
- ✅ PowerShell script (Windows)
- ✅ Any HTTP client (Postman, JavaScript, etc.)

The server handles all the complexity - you just send HTTP requests!

## ❓ Need Help?

1. **Quick questions?** → Check `QUICK_START.md`
2. **Platform issues?** → Check `docs/PLATFORM_GUIDE.md`
3. **API details?** → Check `docs/API_REFERENCE.md`
4. **Still stuck?** → Contact your team lead with the error message

---

**Next Step**: Open `QUICK_START.md` and follow the instructions!

