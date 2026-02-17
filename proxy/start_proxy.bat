@echo off
REM ============================================================================
REM Proxy Server Startup Script (Windows)
REM Purpose: Start the Message Broker Proxy Server
REM Usage: start_proxy.bat [--dev|--prod]
REM ============================================================================

setlocal EnableDelayedExpansion

set "MODE=%~1"
if "%MODE%"=="" set "MODE=--prod"

echo ============================================================================
echo Message Broker Proxy Server
echo ============================================================================
echo.

REM Check if in virtual environment
if not defined VIRTUAL_ENV (
    echo [INFO] Activating virtual environment...
    if exist "..\venv\Scripts\activate.bat" (
        call ..\venv\Scripts\activate.bat
    ) else (
        echo [WARNING] Virtual environment not found at ..\venv
        echo [INFO] Using system Python
    )
)

REM Check if Python is available
where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python not found in PATH!
    exit /b 1
)

REM Check if required packages are installed
python -c "import fastapi, uvicorn, redis, httpx" 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Installing required packages...
    python -m pip install -r requirements.txt
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to install required packages!
        exit /b 1
    )
)

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir logs

REM Set environment variables
if not exist ".env" (
    if exist "..\env.template" (
        echo [INFO] Creating .env from template...
        copy "..\env.template" ".env" >nul
    )
)

REM Load environment variables from .env
if exist ".env" (
    echo [INFO] Loading environment from .env
    for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
        set "%%A=%%B"
    )
)

echo.
echo Configuration:
echo   Redis:       %REDIS_HOST%:%REDIS_PORT%
echo   Main Server: %MAIN_SERVER_URL%
echo   Log Level:   %LOG_LEVEL%
echo   Certs Dir:   certs/
echo.

REM Check if certificates exist
if not exist "certs\proxy.crt" (
    echo [WARNING] Proxy certificate not found: certs\proxy.crt
    echo [INFO] Please generate certificates first:
    echo        cd ..\main_server
    echo        generate_cert.bat proxy
    echo.
)

if not exist "certs\ca.crt" (
    echo [WARNING] CA certificate not found: certs\ca.crt
    echo [INFO] Please copy CA certificate:
    echo        copy ..\main_server\certs\ca.crt certs\
    echo.
)

REM Start server based on mode
if /i "%MODE%"=="--dev" (
    echo Starting in DEVELOPMENT mode...
    echo Hot-reload enabled
    echo.
    uvicorn app:app --host 0.0.0.0 --port 8001 --reload --log-level debug
) else (
    echo Starting in PRODUCTION mode...
    echo.
    echo To run with TLS (recommended):
    echo   uvicorn app:app --host 0.0.0.0 --port 8001 ^
    echo     --ssl-keyfile certs/proxy.key ^
    echo     --ssl-certfile certs/proxy.crt ^
    echo     --ssl-ca-certs certs/ca.crt ^
    echo     --ssl-cert-reqs 1 ^
    echo     --workers 4
    echo.
    set /p START_TLS="Start with TLS? (yes/no, default: no): "
    
    if /i "!START_TLS!"=="yes" (
        echo.
        echo Starting with TLS and mutual authentication...
        uvicorn app:app --host 0.0.0.0 --port 8001 ^
            --ssl-keyfile certs/proxy.key ^
            --ssl-certfile certs/proxy.crt ^
            --ssl-ca-certs certs/ca.crt ^
            --ssl-cert-reqs 1 ^
            --workers 4 ^
            --log-level info
    ) else (
        echo.
        echo Starting without TLS (development only)...
        uvicorn app:app --host 0.0.0.0 --port 8001 --workers 4 --log-level info
    )
)

endlocal

