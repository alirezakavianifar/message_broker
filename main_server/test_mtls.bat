@echo off
REM ============================================================================
REM Mutual TLS Test Script Wrapper (Windows)
REM Purpose: Test mutual TLS authentication functionality
REM Usage: test_mtls.bat [validate|server|client]
REM ============================================================================

setlocal EnableDelayedExpansion

set "MODE=%~1"
if "%MODE%"=="" set "MODE=validate"

echo ============================================================================
echo Mutual TLS Test - Message Broker System
echo ============================================================================
echo.

REM Check if Python is available
where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python not found in PATH!
    echo Please install Python 3.8+ and add to PATH.
    exit /b 1
)

REM Check if required packages are installed
python -c "import httpx, uvicorn, fastapi" 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Installing required Python packages...
    python -m pip install httpx uvicorn fastapi --quiet
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to install required packages!
        echo Please run: pip install httpx uvicorn fastapi
        exit /b 1
    )
    echo [OK] Packages installed
    echo.
)

REM Run appropriate test mode
if /i "%MODE%"=="validate" (
    echo Running certificate validation tests...
    echo.
    python test_mtls.py --validate-only
) else if /i "%MODE%"=="server" (
    echo Starting mTLS test server...
    echo.
    echo Server will listen on https://localhost:8443
    echo Press Ctrl+C to stop the server
    echo.
    echo In another terminal, run: test_mtls.bat client
    echo.
    python test_mtls.py --server-only
) else if /i "%MODE%"=="client" (
    echo Running client connection tests...
    echo.
    echo NOTE: This requires a running test server!
    echo.
    python test_mtls.py --client-only
) else (
    echo Invalid mode: %MODE%
    echo.
    echo Usage: test_mtls.bat [validate^|server^|client]
    echo.
    echo Modes:
    echo   validate : Validate certificate setup (default)
    echo   server   : Start test HTTPS server with mTLS
    echo   client   : Run client connection tests
    echo.
    echo Example Workflow:
    echo   Terminal 1: test_mtls.bat server
    echo   Terminal 2: test_mtls.bat client
    echo.
    exit /b 1
)

endlocal

