@echo off
REM ============================================================================
REM Client Certificate Generation Script
REM Purpose: Generate client certificate signed by Message Broker CA
REM Usage: generate_cert.bat <client_name> [domain] [validity_days]
REM Example: generate_cert.bat client_001 example.com 365
REM ============================================================================

setlocal EnableDelayedExpansion

REM Check arguments
if "%~1"=="" (
    echo Usage: generate_cert.bat ^<client_name^> [domain] [validity_days]
    echo.
    echo Arguments:
    echo   client_name     : Unique identifier for the client (required)
    echo   domain         : Domain name (optional, default: default)
    echo   validity_days  : Certificate validity in days (optional, default: 365)
    echo.
    echo Example:
    echo   generate_cert.bat client_001 example.com 365
    echo.
    exit /b 1
)

REM Parse arguments
set "CLIENT_NAME=%~1"
set "DOMAIN=%~2"
set "VALIDITY_DAYS=%~3"

REM Set defaults
if "%DOMAIN%"=="" set "DOMAIN=default"
if "%VALIDITY_DAYS%"=="" set "VALIDITY_DAYS=365"

echo ============================================================================
echo Message Broker System - Client Certificate Generation
echo ============================================================================
echo.
echo Client Name:     %CLIENT_NAME%
echo Domain:          %DOMAIN%
echo Validity:        %VALIDITY_DAYS% days
echo.

REM Check if OpenSSL is available
where openssl >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] OpenSSL not found in PATH!
    exit /b 1
)

REM Set directories
set "CA_DIR=%~dp0certs"
set "OUTPUT_DIR=%~dp0certs\clients\%CLIENT_NAME%"

REM Check if CA exists
if not exist "%CA_DIR%\ca.key" (
    echo [ERROR] CA not initialized!
    echo Please run init_ca.bat first to create the Certificate Authority.
    exit /b 1
)

REM Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM Check if certificate already exists
if exist "%OUTPUT_DIR%\%CLIENT_NAME%.crt" (
    echo.
    echo [WARNING] Certificate already exists for %CLIENT_NAME%!
    set /p CONFIRM="Overwrite existing certificate? (yes/no): "
    if /i not "!CONFIRM!"=="yes" (
        echo Certificate generation cancelled.
        exit /b 0
    )
)

REM Generate client private key (2048-bit RSA)
echo [1/6] Generating client private key (2048-bit RSA)...
openssl genrsa -out "%OUTPUT_DIR%\%CLIENT_NAME%.key" 2048
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to generate private key
    exit /b 1
)
echo [OK] Private key generated

REM Set restrictive permissions on private key
echo [2/6] Setting restrictive permissions...
icacls "%OUTPUT_DIR%\%CLIENT_NAME%.key" /inheritance:r
icacls "%OUTPUT_DIR%\%CLIENT_NAME%.key" /grant:r "%USERNAME%:F"
echo [OK] Permissions set

REM Generate Certificate Signing Request (CSR)
echo [3/6] Generating Certificate Signing Request (CSR)...
openssl req -new ^
    -key "%OUTPUT_DIR%\%CLIENT_NAME%.key" ^
    -out "%OUTPUT_DIR%\%CLIENT_NAME%.csr" ^
    -subj "/CN=%CLIENT_NAME%/O=MessageBroker/OU=%DOMAIN%"

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to generate CSR
    exit /b 1
)
echo [OK] CSR generated

REM Sign certificate with CA
echo [4/6] Signing certificate with CA (%VALIDITY_DAYS% days validity)...
openssl x509 -req ^
    -in "%OUTPUT_DIR%\%CLIENT_NAME%.csr" ^
    -CA "%CA_DIR%\ca.crt" ^
    -CAkey "%CA_DIR%\ca.key" ^
    -CAcreateserial ^
    -out "%OUTPUT_DIR%\%CLIENT_NAME%.crt" ^
    -days %VALIDITY_DAYS% ^
    -sha256

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to sign certificate
    exit /b 1
)
echo [OK] Certificate signed

REM Calculate certificate fingerprint
echo [5/6] Calculating certificate fingerprint...
openssl x509 -in "%OUTPUT_DIR%\%CLIENT_NAME%.crt" -noout -fingerprint -sha256 > "%OUTPUT_DIR%\fingerprint.txt"
set /p FINGERPRINT=<"%OUTPUT_DIR%\fingerprint.txt"
echo %FINGERPRINT% > "%OUTPUT_DIR%\fingerprint.txt"
echo [OK] Fingerprint calculated

REM Copy CA certificate for client
echo [6/6] Copying CA certificate...
copy /Y "%CA_DIR%\ca.crt" "%OUTPUT_DIR%\ca.crt" >nul
echo [OK] CA certificate copied

REM Create installation script for client
echo [7/7] Creating installation script...
(
    echo @echo off
    echo REM Certificate Installation Script for %CLIENT_NAME%
    echo REM Copy these files to your client application:
    echo echo.
    echo echo Certificate Files:
    echo echo   - %CLIENT_NAME%.key  ^(Private Key - KEEP SECURE!^)
    echo echo   - %CLIENT_NAME%.crt  ^(Client Certificate^)
    echo echo   - ca.crt              ^(CA Certificate^)
    echo echo.
    echo echo For Python/httpx:
    echo echo   cert=^("%CLIENT_NAME%.crt", "%CLIENT_NAME%.key"^)
    echo echo   verify="ca.crt"
    echo echo.
    echo pause
) > "%OUTPUT_DIR%\install_instructions.bat"

REM Verify certificate
echo.
echo ============================================================================
echo Certificate Verification
echo ============================================================================
openssl verify -CAfile "%CA_DIR%\ca.crt" "%OUTPUT_DIR%\%CLIENT_NAME%.crt"

REM Display certificate information
echo.
echo ============================================================================
echo Certificate Information
echo ============================================================================
openssl x509 -in "%OUTPUT_DIR%\%CLIENT_NAME%.crt" -noout -text | findstr /C:"Subject:" /C:"Issuer:" /C:"Not Before" /C:"Not After"

echo.
echo ============================================================================
echo Certificate Generation Complete!
echo ============================================================================
echo.
echo Output Directory: %OUTPUT_DIR%
echo.
echo Generated Files:
echo   - %CLIENT_NAME%.key       : Private key (KEEP SECURE!)
echo   - %CLIENT_NAME%.crt       : Client certificate
echo   - %CLIENT_NAME%.csr       : Certificate signing request
echo   - ca.crt                   : CA certificate (for verification)
echo   - fingerprint.txt          : Certificate fingerprint (SHA-256)
echo   - install_instructions.bat : Installation guide
echo.
echo Certificate Fingerprint:
type "%OUTPUT_DIR%\fingerprint.txt"
echo.
echo IMPORTANT:
echo   1. Deliver the following files to the client SECURELY:
echo      - %CLIENT_NAME%.key
echo      - %CLIENT_NAME%.crt
echo      - ca.crt
echo   2. Store the fingerprint in the database for verification
echo   3. Keep a backup of all files in a secure location
echo.
echo Database Registration:
echo   Run the following SQL to register this certificate:
echo.
echo   INSERT INTO clients ^(client_id, cert_fingerprint, domain, 
echo     status, issued_at, expires_at^) VALUES
echo   ^('%CLIENT_NAME%', 'FINGERPRINT', '%DOMAIN%', 
echo     'active', NOW^(^), DATE_ADD^(NOW^(^), INTERVAL %VALIDITY_DAYS% DAY^)^);
echo.
echo   Replace FINGERPRINT with the value from fingerprint.txt
echo.

endlocal

