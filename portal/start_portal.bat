@echo off
REM Message Broker Portal - Windows Batch Startup Script

setlocal enabledelayedexpansion

REM Change to script directory
cd /d "%~dp0"

echo ================================================
echo Message Broker Portal - Starting
echo ================================================

REM Check if virtual environment exists
if not exist "..\venv\Scripts\activate.bat" (
    echo ERROR: Virtual environment not found at ..\venv
    echo Please run setup first: cd .. ; python -m venv venv ; venv\Scripts\activate ; pip install -r portal\requirements.txt
    pause
    exit /b 1
)

REM Activate virtual environment
echo Activating virtual environment...
call ..\venv\Scripts\activate.bat

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

REM Set default environment variables
if not defined MAIN_SERVER_URL set MAIN_SERVER_URL=https://localhost:8000
if not defined MAIN_SERVER_VERIFY_SSL set MAIN_SERVER_VERIFY_SSL=false
if not defined PORTAL_HOST set PORTAL_HOST=0.0.0.0
if not defined PORTAL_PORT set PORTAL_PORT=8080
if not defined SESSION_SECRET set SESSION_SECRET=change_this_session_secret_in_production
if not defined LOG_LEVEL set LOG_LEVEL=INFO
if not defined LOG_FILE_PATH set LOG_FILE_PATH=logs

REM Display configuration
echo.
echo Configuration:
echo   Main Server: %MAIN_SERVER_URL%
echo   Portal Host: %PORTAL_HOST%:%PORTAL_PORT%
echo   Log Level: %LOG_LEVEL%
echo   SSL Verification: %MAIN_SERVER_VERIFY_SSL%
echo.

REM Create logs directory
if not exist "logs" mkdir logs

REM Check if templates directory exists
if not exist "templates" (
    echo ERROR: templates directory not found
    echo Please ensure all portal files are present
    pause
    exit /b 1
)

echo ✓ Templates directory found

echo.
echo Starting portal...
echo Portal URL: http://localhost:%PORTAL_PORT%
echo Press Ctrl+C to stop
echo.
echo ================================================

REM Start the portal
uvicorn portal.app:app --host %PORTAL_HOST% --port %PORTAL_PORT% --log-level %LOG_LEVEL%

REM Capture exit code
set EXIT_CODE=%ERRORLEVEL%

echo.
echo ================================================
echo Portal stopped with exit code: %EXIT_CODE%
echo ================================================

if %EXIT_CODE% neq 0 (
    echo.
    echo Portal encountered an error. Check logs\portal.log for details.
    pause
)

endlocal
exit /b %EXIT_CODE%

