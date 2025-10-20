@echo off
REM ============================================================================
REM Certificate Renewal Script
REM Purpose: Renew an existing client certificate
REM Usage: renew_cert.bat <client_name> [validity_days]
REM Example: renew_cert.bat client_001 365
REM ============================================================================

setlocal EnableDelayedExpansion

REM Check arguments
if "%~1"=="" (
    echo Usage: renew_cert.bat ^<client_name^> [validity_days]
    echo.
    echo Arguments:
    echo   client_name    : Name of the client certificate to renew
    echo   validity_days  : Certificate validity in days (optional, default: 365)
    echo.
    echo Example:
    echo   renew_cert.bat client_001 365
    echo.
    exit /b 1
)

set "CLIENT_NAME=%~1"
set "VALIDITY_DAYS=%~2"
if "%VALIDITY_DAYS%"=="" set "VALIDITY_DAYS=365"

echo ============================================================================
echo Message Broker System - Certificate Renewal
echo ============================================================================
echo.
echo Client Name:     %CLIENT_NAME%
echo New Validity:    %VALIDITY_DAYS% days
echo.

set "CA_DIR=%~dp0certs"
set "CLIENT_DIR=%CA_DIR%\clients\%CLIENT_NAME%"

REM Check if certificate exists
if not exist "%CLIENT_DIR%\%CLIENT_NAME%.crt" (
    if not exist "%CLIENT_DIR%\%CLIENT_NAME%.crt.revoked" (
        echo [ERROR] Certificate not found for %CLIENT_NAME%!
        exit /b 1
    )
)

REM Get old certificate info
if exist "%CLIENT_DIR%\%CLIENT_NAME%.crt" (
    set "OLD_CERT=%CLIENT_DIR%\%CLIENT_NAME%.crt"
) else (
    set "OLD_CERT=%CLIENT_DIR%\%CLIENT_NAME%.crt.revoked"
)

echo Old Certificate Information:
openssl x509 -in "!OLD_CERT!" -noout -dates

echo.
set /p CONFIRM="Proceed with renewal? (yes/no): "
if /i not "%CONFIRM%"=="yes" (
    echo Renewal cancelled.
    exit /b 0
)
echo.

REM Backup old certificate
echo [1/7] Backing up old certificate...
set "BACKUP_DIR=%CLIENT_DIR%\backup"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

set "TIMESTAMP=%DATE:~-4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TIMESTAMP=%TIMESTAMP: =0%"

if exist "%CLIENT_DIR%\%CLIENT_NAME%.crt" (
    copy "%CLIENT_DIR%\%CLIENT_NAME%.crt" "%BACKUP_DIR%\%CLIENT_NAME%.crt.%TIMESTAMP%" >nul
)
if exist "%CLIENT_DIR%\%CLIENT_NAME%.key" (
    copy "%CLIENT_DIR%\%CLIENT_NAME%.key" "%BACKUP_DIR%\%CLIENT_NAME%.key.%TIMESTAMP%" >nul
)
echo [OK] Backup created in %BACKUP_DIR%

REM Generate new private key
echo [2/7] Generating new private key...
openssl genrsa -out "%CLIENT_DIR%\%CLIENT_NAME%.key.new" 2048 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to generate new private key
    exit /b 1
)
echo [OK] New private key generated

REM Generate new CSR
echo [3/7] Generating new Certificate Signing Request...
for /f "tokens=*" %%A in ('openssl x509 -in "!OLD_CERT!" -noout -subject') do set "OLD_SUBJECT=%%A"
set "OLD_SUBJECT=!OLD_SUBJECT:subject=!"

openssl req -new ^
    -key "%CLIENT_DIR%\%CLIENT_NAME%.key.new" ^
    -out "%CLIENT_DIR%\%CLIENT_NAME%.csr.new" ^
    -subj "!OLD_SUBJECT!" >nul 2>&1

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to generate CSR
    exit /b 1
)
echo [OK] CSR generated

REM Sign new certificate
echo [4/7] Signing new certificate (%VALIDITY_DAYS% days validity)...
openssl x509 -req ^
    -in "%CLIENT_DIR%\%CLIENT_NAME%.csr.new" ^
    -CA "%CA_DIR%\ca.crt" ^
    -CAkey "%CA_DIR%\ca.key" ^
    -CAcreateserial ^
    -out "%CLIENT_DIR%\%CLIENT_NAME%.crt.new" ^
    -days %VALIDITY_DAYS% ^
    -sha256 >nul 2>&1

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to sign certificate
    exit /b 1
)
echo [OK] Certificate signed

REM Replace old with new
echo [5/7] Replacing old certificate with new...
if exist "%CLIENT_DIR%\%CLIENT_NAME%.crt" (
    del "%CLIENT_DIR%\%CLIENT_NAME%.crt"
)
if exist "%CLIENT_DIR%\%CLIENT_NAME%.crt.revoked" (
    del "%CLIENT_DIR%\%CLIENT_NAME%.crt.revoked"
)
if exist "%CLIENT_DIR%\%CLIENT_NAME%.key" (
    del "%CLIENT_DIR%\%CLIENT_NAME%.key"
)

move "%CLIENT_DIR%\%CLIENT_NAME%.crt.new" "%CLIENT_DIR%\%CLIENT_NAME%.crt" >nul
move "%CLIENT_DIR%\%CLIENT_NAME%.key.new" "%CLIENT_DIR%\%CLIENT_NAME%.key" >nul
if exist "%CLIENT_DIR%\%CLIENT_NAME%.csr.new" (
    del "%CLIENT_DIR%\%CLIENT_NAME%.csr.new"
)
echo [OK] Certificates replaced

REM Calculate new fingerprint
echo [6/7] Calculating new certificate fingerprint...
openssl x509 -in "%CLIENT_DIR%\%CLIENT_NAME%.crt" -noout -fingerprint -sha256 > "%CLIENT_DIR%\fingerprint.txt"
echo [OK] Fingerprint calculated

REM Set permissions
echo [7/7] Setting restrictive permissions...
icacls "%CLIENT_DIR%\%CLIENT_NAME%.key" /inheritance:r >nul 2>&1
icacls "%CLIENT_DIR%\%CLIENT_NAME%.key" /grant:r "%USERNAME%:F" >nul 2>&1
echo [OK] Permissions set

echo.
echo ============================================================================
echo Certificate Renewal Complete!
echo ============================================================================
echo.
echo Client Name:     %CLIENT_NAME%
echo Valid For:       %VALIDITY_DAYS% days
echo Backup Location: %BACKUP_DIR%
echo.
echo New Certificate Information:
openssl x509 -in "%CLIENT_DIR%\%CLIENT_NAME%.crt" -noout -dates -fingerprint -sha256
echo.
echo IMPORTANT NEXT STEPS:
echo   1. Update database with new fingerprint and expiration:
echo.
echo      UPDATE clients 
echo      SET cert_fingerprint='NEW_FINGERPRINT',
echo          expires_at=DATE_ADD(NOW(), INTERVAL %VALIDITY_DAYS% DAY),
echo          status='active'
echo      WHERE client_id='%CLIENT_NAME%';
echo.
echo   2. Distribute new certificate to client:
echo      - %CLIENT_NAME%.key
echo      - %CLIENT_NAME%.crt
echo      - ca.crt
echo.
echo   3. Client must update their certificate files
echo   4. Old backups are in: %BACKUP_DIR%
echo.

endlocal

