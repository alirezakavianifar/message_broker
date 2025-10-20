@echo off
REM ============================================================================
REM Certificate Listing Script
REM Purpose: List all certificates with their status
REM Usage: list_certs.bat [status]
REM        status: all, active, revoked (default: all)
REM ============================================================================

setlocal EnableDelayedExpansion

set "FILTER=%~1"
if "%FILTER%"=="" set "FILTER=all"

echo ============================================================================
echo Message Broker System - Certificate List
echo ============================================================================
echo.
echo Filter: %FILTER%
echo.

set "CA_DIR=%~dp0certs"
set "CLIENTS_DIR=%CA_DIR%\clients"

if not exist "%CLIENTS_DIR%" (
    echo [INFO] No certificates found.
    echo Run generate_cert.bat to create client certificates.
    exit /b 0
)

echo ============================================================================
echo Format: [Status] Client Name - Expires - Fingerprint
echo ============================================================================
echo.

set "COUNT=0"
set "ACTIVE_COUNT=0"
set "REVOKED_COUNT=0"
set "EXPIRED_COUNT=0"

for /d %%C in ("%CLIENTS_DIR%\*") do (
    set "CLIENT_NAME=%%~nxC"
    set "CLIENT_DIR=%%C"
    
    REM Check if certificate exists
    if exist "!CLIENT_DIR!\!CLIENT_NAME!.crt" (
        REM Active certificate
        set /a "ACTIVE_COUNT+=1"
        if /i "%FILTER%"=="all" (
            call :DisplayCert "!CLIENT_DIR!" "!CLIENT_NAME!" "ACTIVE"
        ) else if /i "%FILTER%"=="active" (
            call :DisplayCert "!CLIENT_DIR!" "!CLIENT_NAME!" "ACTIVE"
        )
    ) else if exist "!CLIENT_DIR!\!CLIENT_NAME!.crt.revoked" (
        REM Revoked certificate
        set /a "REVOKED_COUNT+=1"
        if /i "%FILTER%"=="all" (
            call :DisplayCert "!CLIENT_DIR!" "!CLIENT_NAME!" "REVOKED"
        ) else if /i "%FILTER%"=="revoked" (
            call :DisplayCert "!CLIENT_DIR!" "!CLIENT_NAME!" "REVOKED"
        )
    )
    set /a "COUNT+=1"
)

echo.
echo ============================================================================
echo Summary
echo ============================================================================
echo Total Clients:    %COUNT%
echo Active:           %ACTIVE_COUNT%
echo Revoked:          %REVOKED_COUNT%
echo.

exit /b 0

:DisplayCert
set "CERT_DIR=%~1"
set "CERT_NAME=%~2"
set "STATUS=%~3"

if "%STATUS%"=="ACTIVE" (
    set "CERT_FILE=%CERT_DIR%\%CERT_NAME%.crt"
    set "STATUS_MARK=[✓]"
) else (
    set "CERT_FILE=%CERT_DIR%\%CERT_NAME%.crt.revoked"
    set "STATUS_MARK=[X]"
)

REM Get expiration date
for /f "tokens=*" %%A in ('openssl x509 -in "!CERT_FILE!" -noout -enddate 2^>nul') do set "ENDDATE=%%A"
set "ENDDATE=!ENDDATE:notAfter=!"

REM Get fingerprint
for /f "tokens=2 delims==" %%A in ('openssl x509 -in "!CERT_FILE!" -noout -fingerprint -sha256 2^>nul') do set "FINGERPRINT=%%A"

echo !STATUS_MARK! %STATUS:~0,7% - %CERT_NAME% - !ENDDATE! - !FINGERPRINT:~0,20!...

exit /b 0

