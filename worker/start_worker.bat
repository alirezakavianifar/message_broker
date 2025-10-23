@echo off
REM Message Broker Worker - Windows Batch Startup Script
REM This script starts the worker process with proper environment

setlocal enabledelayedexpansion

REM Change to script directory
cd /d "%~dp0"

echo ================================================
echo Message Broker Worker - Starting
echo ================================================

REM Check if virtual environment exists
if not exist "..\venv\Scripts\activate.bat" (
    echo ERROR: Virtual environment not found at ..\venv
    echo Please run setup first: cd .. ^&^& python -m venv venv ^&^& venv\Scripts\activate ^&^& pip install -r worker\requirements.txt
    pause
    exit /b 1
)

REM Activate virtual environment
echo Activating virtual environment...
call ..\venv\Scripts\activate.bat

REM Check if .env file exists
if not exist "..\.env" (
    echo WARNING: .env file not found. Using default configuration.
    echo Consider creating .env file from .env.template
)

REM Load environment variables from .env if exists
if exist "..\.env" (
    echo Loading environment variables from .env...
    for /f "usebackq tokens=1,* delims==" %%a in ("..\.env") do (
        set "line=%%a"
        if not "!line:~0,1!"=="#" (
            if not "%%b"=="" (
                set "%%a=%%b"
            )
        )
    )
)

REM Set default environment variables if not already set
if not defined REDIS_HOST set REDIS_HOST=localhost
if not defined REDIS_PORT set REDIS_PORT=6379
if not defined REDIS_DB set REDIS_DB=0
if not defined REDIS_PASSWORD set REDIS_PASSWORD=
if not defined MAIN_SERVER_URL set MAIN_SERVER_URL=https://localhost:8000
if not defined WORKER_ID set WORKER_ID=worker-%RANDOM%
if not defined WORKER_CONCURRENCY set WORKER_CONCURRENCY=4
if not defined WORKER_RETRY_INTERVAL set WORKER_RETRY_INTERVAL=30
if not defined WORKER_MAX_ATTEMPTS set WORKER_MAX_ATTEMPTS=10000
if not defined WORKER_METRICS_ENABLED set WORKER_METRICS_ENABLED=true
if not defined WORKER_METRICS_PORT set WORKER_METRICS_PORT=9100
if not defined LOG_LEVEL set LOG_LEVEL=INFO
if not defined LOG_FILE_PATH set LOG_FILE_PATH=logs

REM Display configuration
echo.
echo Configuration:
echo   Redis: %REDIS_HOST%:%REDIS_PORT%
echo   Main Server: %MAIN_SERVER_URL%
echo   Worker ID: %WORKER_ID%
echo   Concurrency: %WORKER_CONCURRENCY%
echo   Retry Interval: %WORKER_RETRY_INTERVAL%s
echo   Max Attempts: %WORKER_MAX_ATTEMPTS%
echo   Metrics Port: %WORKER_METRICS_PORT%
echo   Log Level: %LOG_LEVEL%
echo.

REM Check if Redis is running
echo Checking Redis connection...
python -c "import redis; r = redis.Redis(host='%REDIS_HOST%', port=%REDIS_PORT%, db=%REDIS_DB%, password='%REDIS_PASSWORD%' if '%REDIS_PASSWORD%' else None); r.ping(); print('✓ Redis is running')" 2>nul
if errorlevel 1 (
    echo WARNING: Cannot connect to Redis at %REDIS_HOST%:%REDIS_PORT%
    echo Make sure Redis is running: redis-server --service-start
    pause
    exit /b 1
)

REM Check if certificates exist
if not exist "certs\worker.crt" (
    echo ERROR: Worker certificate not found at certs\worker.crt
    echo Please generate certificates first using main_server\generate_cert.bat worker
    pause
    exit /b 1
)

if not exist "certs\worker.key" (
    echo ERROR: Worker key not found at certs\worker.key
    echo Please generate certificates first using main_server\generate_cert.bat worker
    pause
    exit /b 1
)

if not exist "certs\ca.crt" (
    echo ERROR: CA certificate not found at certs\ca.crt
    echo Please copy CA certificate from main_server\certs\ca.crt
    pause
    exit /b 1
)

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir logs

echo.
echo Starting worker...
echo Press Ctrl+C to stop
echo.
echo ================================================

REM Start the worker
python worker.py

REM Capture exit code
set EXIT_CODE=%ERRORLEVEL%

echo.
echo ================================================
echo Worker stopped with exit code: %EXIT_CODE%
echo ================================================

if %EXIT_CODE% neq 0 (
    echo.
    echo Worker encountered an error. Check logs\worker.log for details.
    pause
)

endlocal
exit /b %EXIT_CODE%

