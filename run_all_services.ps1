# run_all_services.ps1
# This script starts all four services of the Message Broker system.

$root = Get-Location
$venv_python = "$root\venv\Scripts\python.exe"

# Set common environment variables
$env:DATABASE_URL = "mysql+pymysql://systemuser:StrongPass123!@127.0.0.1/message_system"
$env:REDIS_HOST = "127.0.0.1"
$env:MAIN_SERVER_URL = "http://127.0.0.1:8000"
$env:MAIN_SERVER_VERIFY_SSL = "false"
$env:ENCRYPTION_KEY_PATH = "$root\main_server\secrets\encryption.key"
$env:JWT_SECRET = "SuperSecretJWTKey_ChangeInProduction"
$env:LOG_LEVEL = "INFO"

Write-Host "Starting Message Broker Services..." -ForegroundColor Cyan

# 1. Start Main Server
Write-Host "Launching Main Server on port 8000..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle = 'Main Server'; cd '$root\main_server'; & '$venv_python' -m uvicorn api:app --host 0.0.0.0 --port 8000"

# 2. Start Proxy
Write-Host "Launching Proxy on port 8001..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle = 'Proxy'; cd '$root\proxy'; & '$venv_python' -m uvicorn app:app --host 0.0.0.0 --port 8001"

# 3. Start Worker
Write-Host "Launching Worker..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle = 'Worker'; cd '$root\worker'; & '$venv_python' worker.py"

# 4. Start Portal
Write-Host "Launching Portal on port 5000..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle = 'Portal'; cd '$root\portal'; & '$venv_python' -m uvicorn app:app --host 0.0.0.0 --port 5000"

Write-Host "All services have been launched in separate windows." -ForegroundColor Cyan
