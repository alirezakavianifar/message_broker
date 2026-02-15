# Script to verify all critical files are included in the package

$criticalFiles = @(
    # Configuration templates
    "env.template",
    "deployment\config\env.production.template",
    
    # Python source files
    "main_server\api.py",
    "main_server\database.py",
    "main_server\models.py",
    "main_server\encryption.py",
    "main_server\admin_cli.py",
    "proxy\app.py",
    "worker\worker.py",
    "portal\app.py",
    
    # Requirements files
    "main_server\requirements.txt",
    "proxy\requirements.txt",
    "worker\requirements.txt",
    "portal\requirements.txt",
    "client-scripts\requirements.txt",
    "tests\requirements.txt",
    
    # Database migration files
    "main_server\alembic.ini",
    "main_server\alembic\env.py",
    "main_server\alembic\script.py.mako",
    "main_server\alembic\versions\001_initial_schema.py",
    
    # Systemd service files
    "main_server\main_server.service",
    "proxy\proxy.service",
    "worker\worker.service",
    "portal\portal.service",
    
    # Shell scripts
    "run_migrations.sh",
    "create_admin.sh",
    
    # Configuration files
    "proxy\config.yaml",
    "worker\config.yaml",
    "main_server\schema.sql",
    "main_server\openapi.yaml",
    "proxy\openapi.yaml",
    
    # Documentation
    "LINUX_DEPLOYMENT_COMPLETE.md",
    "README.md",
    
    # Helper scripts
    "create_admin_user.py",
    "run_migrations.py",
    "check_admin_user.py"
)

Write-Host "Checking critical files..." -ForegroundColor Cyan

$missingFiles = @()
foreach ($file in $criticalFiles) {
    if (-not (Test-Path $file)) {
        $missingFiles += $file
        Write-Host "  [MISSING] $file" -ForegroundColor Red
    } else {
        Write-Host "  [OK] $file" -ForegroundColor Green
    }
}

if ($missingFiles.Count -eq 0) {
    Write-Host "`nAll critical files are present!" -ForegroundColor Green
} else {
    Write-Host "`nMissing files:" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

