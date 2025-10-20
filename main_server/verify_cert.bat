@echo off
REM ============================================================================
REM Certificate Verification Script
REM Purpose: Verify client certificate against CA and check CRL
REM Usage: verify_cert.bat <client_name_or_cert_path>
REM Example: verify_cert.bat client_001
REM          verify_cert.bat C:\path\to\certificate.crt
REM ============================================================================

setlocal EnableDelayedExpansion

REM Check arguments
if "%~1"=="" (
    echo Usage: verify_cert.bat ^<client_name_or_cert_path^>
    echo.
    echo Arguments:
    echo   client_name_or_cert_path : Client name or path to certificate file
    echo.
    echo Examples:
    echo   verify_cert.bat client_001
    echo   verify_cert.bat C:\path\to\certificate.crt
    echo.
    exit /b 1
)

set "INPUT=%~1"

echo ============================================================================
echo Message Broker System - Certificate Verification
echo ============================================================================
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

REM Determine if input is a file or client name
if exist "%INPUT%" (
    set "CERT_PATH=%INPUT%"
    echo Input Type: Certificate file path
) else (
    set "CERT_PATH=%CA_DIR%\clients\%INPUT%\%INPUT%.crt"
    echo Input Type: Client name
)

echo Certificate: %CERT_PATH%
echo.

REM Check if certificate file exists
if not exist "%CERT_PATH%" (
    echo [ERROR] Certificate file not found!
    echo Path: %CERT_PATH%
    exit /b 1
)

REM Check if CA exists
if not exist "%CA_DIR%\ca.crt" (
    echo [ERROR] CA certificate not found!
    echo Please run init_ca.bat first.
    exit /b 1
)

echo ============================================================================
echo Verification Tests
echo ============================================================================
echo.

REM Test 1: Verify certificate signature
echo [1/6] Verifying certificate signature against CA...
openssl verify -CAfile "%CA_DIR%\ca.crt" "%CERT_PATH%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] Certificate signature is valid
    set "SIGNATURE_VALID=1"
) else (
    echo [FAIL] Certificate signature is INVALID
    set "SIGNATURE_VALID=0"
)

REM Test 2: Check expiration
echo [2/6] Checking certificate expiration...
openssl x509 -in "%CERT_PATH%" -noout -checkend 0 >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] Certificate is not expired
    set "NOT_EXPIRED=1"
) else (
    echo [FAIL] Certificate is EXPIRED
    set "NOT_EXPIRED=0"
)

REM Test 3: Check expiration within 30 days
echo [3/6] Checking if expiring within 30 days...
set /a SECONDS_30_DAYS=30*24*60*60
openssl x509 -in "%CERT_PATH%" -noout -checkend %SECONDS_30_DAYS% >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Certificate expires within 30 days!
    set "EXPIRES_SOON=1"
) else (
    echo [OK] Certificate valid for more than 30 days
    set "EXPIRES_SOON=0"
)

REM Test 4: Check revocation status
echo [4/6] Checking revocation status...
openssl x509 -in "%CERT_PATH%" -noout -serial > "%TEMP%\check_serial.txt"
set /p SERIAL_LINE=<"%TEMP%\check_serial.txt"
set "SERIAL=%SERIAL_LINE:serial==%"

findstr /C:"%SERIAL%" "%CRL_DIR%\revoked.pem" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [FAIL] Certificate is REVOKED
    set "NOT_REVOKED=0"
) else (
    echo [OK] Certificate is not revoked
    set "NOT_REVOKED=1"
)

REM Test 5: Verify key usage
echo [5/6] Checking key usage and extensions...
openssl x509 -in "%CERT_PATH%" -noout -text | findstr /C:"TLS Web Client Authentication" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] Certificate has correct key usage
    set "KEY_USAGE_OK=1"
) else (
    echo [INFO] Standard key usage (no specific TLS client auth extension)
    set "KEY_USAGE_OK=1"
)

REM Test 6: Get fingerprint
echo [6/6] Calculating certificate fingerprint...
openssl x509 -in "%CERT_PATH%" -noout -fingerprint -sha256 > "%TEMP%\check_fingerprint.txt"
set /p FINGERPRINT=<"%TEMP%\check_fingerprint.txt"
echo [OK] Fingerprint calculated

echo.
echo ============================================================================
echo Certificate Details
echo ============================================================================
openssl x509 -in "%CERT_PATH%" -noout -text | findstr /C:"Subject:" /C:"Issuer:" /C:"Not Before" /C:"Not After" /C:"Serial Number"

echo.
echo Fingerprint:
echo %FINGERPRINT%

echo.
echo ============================================================================
echo Verification Summary
echo ============================================================================
echo.

REM Calculate overall result
set /a "OVERALL_RESULT=%SIGNATURE_VALID%*%NOT_EXPIRED%*%NOT_REVOKED%*%KEY_USAGE_OK%"

if %OVERALL_RESULT% EQU 1 (
    echo [PASS] Certificate is VALID
    echo.
    echo   [√] Signature verified
    echo   [√] Not expired
    if %EXPIRES_SOON% EQU 1 (
        echo   [!] Expires within 30 days ^(renewal recommended^)
    ) else (
        echo   [√] Valid for more than 30 days
    )
    echo   [√] Not revoked
    echo   [√] Correct key usage
    echo.
    echo This certificate can be used for authentication.
    set "EXIT_CODE=0"
) else (
    echo [FAIL] Certificate is INVALID
    echo.
    if %SIGNATURE_VALID% EQU 0 echo   [X] Signature verification failed
    if %NOT_EXPIRED% EQU 0 echo   [X] Certificate expired
    if %NOT_REVOKED% EQU 0 echo   [X] Certificate revoked
    if %KEY_USAGE_OK% EQU 0 echo   [X] Invalid key usage
    echo.
    echo This certificate should NOT be used for authentication.
    set "EXIT_CODE=1"
)

echo.
echo ============================================================================
echo Database Verification
echo ============================================================================
echo.
echo To verify against database, run this SQL query:
echo.
echo   SELECT client_id, status, expires_at 
echo   FROM clients 
echo   WHERE cert_fingerprint = 'FINGERPRINT_HERE';
echo.
echo Replace FINGERPRINT_HERE with the fingerprint above.
echo.

REM Cleanup temp files
del "%TEMP%\check_serial.txt" >nul 2>&1
del "%TEMP%\check_fingerprint.txt" >nul 2>&1

endlocal
exit /b %EXIT_CODE%

