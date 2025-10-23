@echo off
REM Message Broker Main Server - Windows Batch Startup Script

setlocal enabledelayedexpansion

REM Change to script directory
cd /d "%~dp0"

echo ================================================
echo Message Broker Main Server - Starting
echo ================================================

REM Check if virtual environment exists
if not exist "..\venv\Scripts\activate.bat" (
    echo ERROR: Virtual environment not found at ..\venv
    echo Please run setup first: cd .. ; python -m venv venv ; venv\Scripts\activate ; pip install -r main_server\requirements.txt
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
if not defined DATABASE_URL set DATABASE_URL=mysql+pymysql://systemuser:StrongPass123!@localhost/message_system
if not defined MAIN_SERVER_HOST set MAIN_SERVER_HOST=0.0.0.0
if not defined MAIN_SERVER_PORT set MAIN_SERVER_PORT=8000
if not defined LOG_LEVEL set LOG_LEVEL=INFO
if not defined METRICS_ENABLED set METRICS_ENABLED=true
if not defined JWT_SECRET set JWT_SECRET=change_this_secret_in_production
if not defined ENCRYPTION_KEY_PATH set ENCRYPTION_KEY_PATH=secrets/encryption.key
if not defined LOG_FILE_PATH set LOG_FILE_PATH=logs

REM Display configuration
echo.
echo Configuration:
echo   Database: %DATABASE_URL%
echo   Host: %MAIN_SERVER_HOST%:%MAIN_SERVER_PORT%
echo   Log Level: %LOG_LEVEL%
echo   Metrics: %METRICS_ENABLED%
echo.

REM Check database connection
echo Checking database connection...
python -c "import pymysql; import os; url = os.environ.get('DATABASE_URL', 'mysql+pymysql://systemuser:StrongPass123!@localhost/message_system'); parts = url.split('//')[1].split('@'); creds = parts[0].split(':'); host_db = parts[1].split('/'); host = host_db[0].split(':')[0]; port = int(host_db[0].split(':')[1]) if ':' in host_db[0] else 3306; db = host_db[1].split('?')[0]; conn = pymysql.connect(host=host, port=port, user=creds[0], password=creds[1], database=db); conn.close(); print('✓ Database connection successful')" 2>nul
if errorlevel 1 (
    echo WARNING: Cannot connect to database
    echo Please check database configuration and ensure MySQL is running
    pause
)

REM Check if certificates exist
if not exist "certs\server.crt" (
    echo ERROR: Server certificate not found at certs\server.crt
    echo Please generate certificates first using init_ca.bat
    pause
    exit /b 1
)

if not exist "certs\server.key" (
    echo ERROR: Server key not found at certs\server.key
    echo Please generate certificates first using init_ca.bat
    pause
    exit /b 1
)

if not exist "certs\ca.crt" (
    echo ERROR: CA certificate not found at certs\ca.crt
    echo Please initialize CA first using init_ca.bat
    pause
    exit /b 1
)

echo ✓ All certificates found

REM Create necessary directories
if not exist "logs" mkdir logs
if not exist "secrets" mkdir secrets

REM Check/create encryption key
if not exist "%ENCRYPTION_KEY_PATH%" (
    echo Generating encryption key...
    python -c "from cryptography.fernet import Fernet; import os; os.makedirs(os.path.dirname('%ENCRYPTION_KEY_PATH%'), exist_ok=True); open('%ENCRYPTION_KEY_PATH%', 'wb').write(Fernet.generate_key()); print('✓ Encryption key generated')"
)

echo.
echo Starting main server...
echo API Documentation: https://localhost:%MAIN_SERVER_PORT%/docs
echo Health Check: https://localhost:%MAIN_SERVER_PORT%/health
echo Metrics: https://localhost:%MAIN_SERVER_PORT%/metrics
echo Press Ctrl+C to stop
echo.
echo ================================================

REM Start the server with TLS
uvicorn main_server.api:app --host %MAIN_SERVER_HOST% --port %MAIN_SERVER_PORT% --ssl-keyfile certs/server.key --ssl-certfile certs/server.crt --ssl-ca-certs certs/ca.crt --log-level %LOG_LEVEL%

REM Capture exit code
set EXIT_CODE=%ERRORLEVEL%

echo.
echo ================================================
echo Main server stopped with exit code: %EXIT_CODE%
echo ================================================

if %EXIT_CODE% neq 0 (
    echo.
    echo Server encountered an error. Check logs\main_server.log for details.
    pause
)

endlocal
exit /b %EXIT_CODE%

