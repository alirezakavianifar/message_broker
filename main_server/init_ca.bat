@echo off
REM ============================================================================
REM Certificate Authority (CA) Initialization Script
REM Purpose: Create the root Certificate Authority for Message Broker System
REM Usage: init_ca.bat
REM ============================================================================

setlocal EnableDelayedExpansion

echo ============================================================================
echo Message Broker System - CA Initialization
echo ============================================================================
echo.

REM Check if OpenSSL is available
where openssl >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] OpenSSL not found in PATH!
    echo Please install OpenSSL and add it to your PATH.
    echo Download from: https://slproweb.com/products/Win32OpenSSL.html
    exit /b 1
)

REM Set directories
set "CA_DIR=%~dp0certs"
set "CRL_DIR=%~dp0crl"

echo CA Directory: %CA_DIR%
echo CRL Directory: %CRL_DIR%
echo.

REM Create directories if they don't exist
if not exist "%CA_DIR%" mkdir "%CA_DIR%"
if not exist "%CRL_DIR%" mkdir "%CRL_DIR%"

REM Check if CA already exists
if exist "%CA_DIR%\ca.key" (
    echo.
    echo [WARNING] CA private key already exists!
    echo Location: %CA_DIR%\ca.key
    echo.
    set /p CONFIRM="Do you want to recreate the CA? This will invalidate all existing certificates! (yes/no): "
    if /i not "!CONFIRM!"=="yes" (
        echo.
        echo CA initialization cancelled.
        exit /b 0
    )
    echo.
    echo [WARNING] Recreating CA - All existing certificates will be invalid!
    echo.
)

REM Generate CA private key (4096-bit RSA)
echo [1/5] Generating CA private key (4096-bit RSA)...
openssl genrsa -out "%CA_DIR%\ca.key" 4096
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to generate CA private key
    exit /b 1
)
echo [OK] CA private key generated

REM Set restrictive permissions on CA private key
echo [2/5] Setting restrictive permissions on CA private key...
icacls "%CA_DIR%\ca.key" /inheritance:r
icacls "%CA_DIR%\ca.key" /grant:r "%USERNAME%:F"
echo [OK] Permissions set (only %USERNAME% can access)

REM Generate self-signed CA certificate (10 years)
echo [3/5] Generating self-signed CA certificate (10 years validity)...
openssl req -x509 -new -nodes ^
    -key "%CA_DIR%\ca.key" ^
    -sha256 -days 3650 ^
    -out "%CA_DIR%\ca.crt" ^
    -subj "/CN=MessageBrokerCA/O=MessageBroker/C=US/ST=State/L=City"

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to generate CA certificate
    exit /b 1
)
echo [OK] CA certificate generated

REM Create serial number file for certificate tracking
echo [4/5] Initializing certificate serial number tracking...
echo 1000 > "%CA_DIR%\ca.srl"
echo [OK] Serial number initialized to 1000

REM Create empty CRL file
echo [5/5] Creating initial Certificate Revocation List (CRL)...
type nul > "%CRL_DIR%\revoked.pem"
echo [OK] CRL initialized

REM Display CA certificate information
echo.
echo ============================================================================
echo CA Certificate Information
echo ============================================================================
openssl x509 -in "%CA_DIR%\ca.crt" -noout -text | findstr /C:"Subject:" /C:"Validity" /C:"Not Before" /C:"Not After" /C:"Public-Key"

REM Calculate certificate fingerprint
echo.
echo Certificate Fingerprint (SHA-256):
openssl x509 -in "%CA_DIR%\ca.crt" -noout -fingerprint -sha256

echo.
echo ============================================================================
echo CA Initialization Complete!
echo ============================================================================
echo.
echo CA Files Location:
echo   - Private Key: %CA_DIR%\ca.key (KEEP SECURE!)
echo   - Certificate: %CA_DIR%\ca.crt
echo   - Serial File: %CA_DIR%\ca.srl
echo   - CRL:         %CRL_DIR%\revoked.pem
echo.
echo IMPORTANT SECURITY NOTES:
echo   1. Keep ca.key secure and backed up
echo   2. Never share ca.key with anyone
echo   3. Distribute ca.crt to all clients for verification
echo   4. Store backup of ca.key in a secure, encrypted location
echo.
echo Next steps:
echo   1. Back up %CA_DIR%\ca.key to a secure location
echo   2. Distribute %CA_DIR%\ca.crt to clients
echo   3. Generate client certificates using generate_cert.bat
echo.

endlocal

