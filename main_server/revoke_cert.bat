@echo off
REM ============================================================================
REM Certificate Revocation Script
REM Purpose: Revoke a client certificate and update CRL
REM Usage: revoke_cert.bat <client_name> [reason]
REM Example: revoke_cert.bat client_001 "Certificate compromised"
REM ============================================================================

setlocal EnableDelayedExpansion

REM Check arguments
if "%~1"=="" (
    echo Usage: revoke_cert.bat ^<client_name^> [reason]
    echo.
    echo Arguments:
    echo   client_name : Name of the client certificate to revoke (required)
    echo   reason      : Reason for revocation (optional)
    echo.
    echo Example:
    echo   revoke_cert.bat client_001 "Certificate compromised"
    echo.
    exit /b 1
)

REM Parse arguments
set "CLIENT_NAME=%~1"
set "REASON=%~2"
if "%REASON%"=="" set "REASON=Unspecified"

echo ============================================================================
echo Message Broker System - Certificate Revocation
echo ============================================================================
echo.
echo Client Name: %CLIENT_NAME%
echo Reason:      %REASON%
echo Timestamp:   %DATE% %TIME%
echo.

REM Check if OpenSSL is available
where openssl >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] OpenSSL not found in PATH!
    exit /b 1
)

REM Set directories
set "CA_DIR=%~dp0certs"
set "CRL_DIR=%~dp0crl"
set "CLIENT_CERT_DIR=%CA_DIR%\clients\%CLIENT_NAME%"

REM Check if CA exists
if not exist "%CA_DIR%\ca.key" (
    echo [ERROR] CA not initialized!
    echo Please run init_ca.bat first.
    exit /b 1
)

REM Check if certificate exists
if not exist "%CLIENT_CERT_DIR%\%CLIENT_NAME%.crt" (
    echo [ERROR] Certificate not found for %CLIENT_NAME%!
    echo Location checked: %CLIENT_CERT_DIR%
    echo.
    echo Available certificates:
    if exist "%CA_DIR%\clients" (
        dir /B "%CA_DIR%\clients" 2>nul
    ) else (
        echo   ^(none^)
    )
    exit /b 1
)

REM Confirm revocation
echo [WARNING] This action will permanently revoke the certificate!
echo.
set /p CONFIRM="Are you sure you want to revoke this certificate? (yes/no): "
if /i not "%CONFIRM%"=="yes" (
    echo.
    echo Revocation cancelled.
    exit /b 0
)
echo.

REM Get certificate serial number
echo [1/5] Extracting certificate serial number...
openssl x509 -in "%CLIENT_CERT_DIR%\%CLIENT_NAME%.crt" -noout -serial > "%TEMP%\serial.txt"
set /p SERIAL_LINE=<"%TEMP%\serial.txt"
set "SERIAL=%SERIAL_LINE:serial==%"
echo [OK] Serial: %SERIAL%

REM Get certificate fingerprint
echo [2/5] Calculating certificate fingerprint...
openssl x509 -in "%CLIENT_CERT_DIR%\%CLIENT_NAME%.crt" -noout -fingerprint -sha256 > "%TEMP%\fingerprint.txt"
set /p FINGERPRINT_LINE=<"%TEMP%\fingerprint.txt"
echo [OK] Fingerprint obtained

REM Add to CRL
echo [3/5] Adding certificate to revocation list...
(
    echo Certificate: %CLIENT_NAME%
    echo Serial: %SERIAL%
    echo %FINGERPRINT_LINE%
    echo Reason: %REASON%
    echo Revoked: %DATE% %TIME%
    echo ============================================
) >> "%CRL_DIR%\revoked.pem"
echo [OK] Certificate added to CRL

REM Rename certificate files (mark as revoked)
echo [4/5] Marking certificate files as revoked...
if exist "%CLIENT_CERT_DIR%\%CLIENT_NAME%.crt" (
    move "%CLIENT_CERT_DIR%\%CLIENT_NAME%.crt" "%CLIENT_CERT_DIR%\%CLIENT_NAME%.crt.revoked" >nul 2>&1
)
if exist "%CLIENT_CERT_DIR%\%CLIENT_NAME%.key" (
    move "%CLIENT_CERT_DIR%\%CLIENT_NAME%.key" "%CLIENT_CERT_DIR%\%CLIENT_NAME%.key.revoked" >nul 2>&1
)

REM Create revocation log entry
echo [5/5] Creating revocation log entry...
set "LOG_FILE=%CRL_DIR%\revocation_log.txt"
(
    echo [%DATE% %TIME%] %CLIENT_NAME% - %REASON%
) >> "%LOG_FILE%"
echo [OK] Log entry created

REM Create revocation record file
set "REVOCATION_FILE=%CLIENT_CERT_DIR%\REVOKED.txt"
(
    echo ============================================
    echo CERTIFICATE REVOKED
    echo ============================================
    echo Client:      %CLIENT_NAME%
    echo Reason:      %REASON%
    echo Revoked By:  %USERNAME%
    echo Revoked At:  %DATE% %TIME%
    echo Serial:      %SERIAL%
    echo %FINGERPRINT_LINE%
    echo ============================================
) > "%REVOCATION_FILE%"

echo.
echo ============================================================================
echo Certificate Revocation Complete!
echo ============================================================================
echo.
echo Client Name:     %CLIENT_NAME%
echo Reason:          %REASON%
echo Revoked By:      %USERNAME%
echo Revoked At:      %DATE% %TIME%
echo.
echo Certificate Files (marked as revoked):
echo   - %CLIENT_CERT_DIR%\%CLIENT_NAME%.crt.revoked
echo   - %CLIENT_CERT_DIR%\%CLIENT_NAME%.key.revoked
echo.
echo CRL Updated:     %CRL_DIR%\revoked.pem
echo Log File:        %CRL_DIR%\revocation_log.txt
echo.
echo IMPORTANT NEXT STEPS:
echo   1. Update database to mark certificate as revoked:
echo.
echo      UPDATE clients 
echo      SET status='revoked', 
echo          revoked_at=NOW^(^), 
echo          revocation_reason='%REASON%'
echo      WHERE client_id='%CLIENT_NAME%';
echo.
echo   2. Notify all services to reload CRL
echo   3. The client will be rejected on next connection attempt
echo   4. Consider generating a new certificate if client is legitimate
echo.
echo To generate a new certificate for this client:
echo   generate_cert.bat %CLIENT_NAME%
echo.

REM Cleanup temp files
del "%TEMP%\serial.txt" >nul 2>&1
del "%TEMP%\fingerprint.txt" >nul 2>&1

endlocal

