# Backup Script for Message Broker System
# Creates backups of MySQL database and Redis data

param(
    [string]$BackupDir = "D:\backups\message_broker",
    [string]$DBName = "message_system",
    [string]$DBUser = "systemuser",
    [string]$DBPassword = "StrongPass123!",
    [int]$RetentionDays = 7
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $BackupDir $timestamp

Write-Host "=== Message Broker System Backup ===" -ForegroundColor Cyan
Write-Host "Timestamp: $timestamp" -ForegroundColor White
Write-Host "Backup Location: $backupPath" -ForegroundColor White
Write-Host ""

# Create backup directory
if (-not (Test-Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    Write-Host "Created backup directory." -ForegroundColor Green
}

# Backup MySQL database
Write-Host "`nBacking up MySQL database..." -ForegroundColor Yellow
$mysqlBackupFile = Join-Path $backupPath "mysql_$timestamp.sql"
$mysqlDumpCmd = "mysqldump -u $DBUser -p$DBPassword $DBName"

try {
    Invoke-Expression "$mysqlDumpCmd > `"$mysqlBackupFile`""
    
    # Compress backup
    Compress-Archive -Path $mysqlBackupFile -DestinationPath "$mysqlBackupFile.zip"
    Remove-Item $mysqlBackupFile
    
    Write-Host "MySQL backup completed: $mysqlBackupFile.zip" -ForegroundColor Green
} catch {
    Write-Host "ERROR: MySQL backup failed - $_" -ForegroundColor Red
}

# Backup Redis data (AOF and RDB files)
Write-Host "`nBacking up Redis data..." -ForegroundColor Yellow
$redisDataDir = "C:\ProgramData\Redis"

if (Test-Path $redisDataDir) {
    try {
        # Find AOF and RDB files
        $aofFile = Get-ChildItem -Path $redisDataDir -Filter "*.aof" -ErrorAction SilentlyContinue | Select-Object -First 1
        $rdbFile = Get-ChildItem -Path $redisDataDir -Filter "*.rdb" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        $redisBackupPath = Join-Path $backupPath "redis"
        New-Item -ItemType Directory -Path $redisBackupPath -Force | Out-Null
        
        if ($aofFile) {
            Copy-Item $aofFile.FullName -Destination $redisBackupPath
            Write-Host "Backed up Redis AOF file." -ForegroundColor Green
        }
        
        if ($rdbFile) {
            Copy-Item $rdbFile.FullName -Destination $redisBackupPath
            Write-Host "Backed up Redis RDB file." -ForegroundColor Green
        }
        
        # Compress Redis backup
        Compress-Archive -Path $redisBackupPath -DestinationPath "$redisBackupPath.zip"
        Remove-Item -Recurse -Force $redisBackupPath
        
        Write-Host "Redis backup completed: $redisBackupPath.zip" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Redis backup failed - $_" -ForegroundColor Red
    }
} else {
    Write-Host "WARNING: Redis data directory not found." -ForegroundColor Yellow
}

# Backup configuration files
Write-Host "`nBacking up configuration files..." -ForegroundColor Yellow
$configBackupPath = Join-Path $backupPath "config"
New-Item -ItemType Directory -Path $configBackupPath -Force | Out-Null

$projectRoot = Split-Path -Parent $PSScriptRoot

try {
    # Copy .env (without sensitive data)
    if (Test-Path "$projectRoot\.env") {
        Copy-Item "$projectRoot\.env" -Destination "$configBackupPath\.env.backup"
    }
    
    # Copy YAML configs
    Copy-Item "$projectRoot\proxy\config.yaml" -Destination "$configBackupPath\proxy_config.yaml" -ErrorAction SilentlyContinue
    Copy-Item "$projectRoot\worker\config.yaml" -Destination "$configBackupPath\worker_config.yaml" -ErrorAction SilentlyContinue
    Copy-Item "$projectRoot\monitoring\prometheus.yml" -Destination "$configBackupPath\prometheus.yml" -ErrorAction SilentlyContinue
    
    Write-Host "Configuration files backed up." -ForegroundColor Green
} catch {
    Write-Host "WARNING: Some configuration files could not be backed up - $_" -ForegroundColor Yellow
}

# Clean up old backups
Write-Host "`nCleaning up old backups (retention: $RetentionDays days)..." -ForegroundColor Yellow
$cutoffDate = (Get-Date).AddDays(-$RetentionDays)

Get-ChildItem -Path $BackupDir -Directory | Where-Object {
    $_.CreationTime -lt $cutoffDate
} | ForEach-Object {
    Write-Host "Removing old backup: $($_.Name)" -ForegroundColor Gray
    Remove-Item -Recurse -Force $_.FullName
}

Write-Host "`n=== Backup Complete ===" -ForegroundColor Cyan
Write-Host "Backup location: $backupPath" -ForegroundColor White
Write-Host ""

# Display backup size
$backupSize = (Get-ChildItem -Path $backupPath -Recurse | Measure-Object -Property Length -Sum).Sum
$backupSizeMB = [math]::Round($backupSize / 1MB, 2)
Write-Host "Total backup size: $backupSizeMB MB" -ForegroundColor White

