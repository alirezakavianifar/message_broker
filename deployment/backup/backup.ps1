#!/usr/bin/env pwsh
# Message Broker System - Backup Script
# Backs up: MySQL database, Redis data, certificates, configuration

param(
    [string]$BackupRoot = "C:\Backups\MessageBroker",
    [string]$AppRoot = "C:\MessageBroker",
    [int]$RetentionDays = 30,
    [switch]$CompressBackup = $true
)

$ErrorActionPreference = "Stop"

# Generate timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $BackupRoot "backup_$timestamp"

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Message Broker System - Backup" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

Write-Host "Backup Configuration:" -ForegroundColor Yellow
Write-Host "  Backup Directory: $backupDir"
Write-Host "  Source Directory: $AppRoot"
Write-Host "  Timestamp: $timestamp"
Write-Host "  Retention Days: $RetentionDays"
Write-Host "  Compression: $CompressBackup"
Write-Host ""

# Create backup directory
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Write-Host "  OK Created backup directory" -ForegroundColor Green

# Backup MySQL Database
Write-Host "`n[1/6] Backing up MySQL database..." -ForegroundColor Cyan
try {
    $dbFile = Join-Path $backupDir "database.sql"
    $env:MYSQL_PWD = "StrongPass123!"
    
    & mysqldump -u systemuser message_system --single-transaction --routines --triggers --events | Out-File -FilePath $dbFile -Encoding UTF8
    
    if (Test-Path $dbFile) {
        $size = (Get-Item $dbFile).Length / 1MB
        Write-Host "    OK Database backed up ($([math]::Round($size, 2)) MB)" -ForegroundColor Green
    }
} catch {
    Write-Host "    ERROR Failed to backup database: $_" -ForegroundColor Red
} finally {
    $env:MYSQL_PWD = $null
}

# Backup Redis AOF
Write-Host "`n[2/6] Backing up Redis data..." -ForegroundColor Cyan
try {
    # Trigger Redis save
    memurai-cli BGSAVE | Out-Null
    Start-Sleep -Seconds 2
    
    # Find Redis data directory
    $redisDataDir = "C:\Program Files\Memurai"
    $aofFile = Join-Path $redisDataDir "appendonly.aof"
    $rdbFile = Join-Path $redisDataDir "dump.rdb"
    
    $redisBackupDir = Join-Path $backupDir "redis"
    New-Item -ItemType Directory -Path $redisBackupDir -Force | Out-Null
    
    if (Test-Path $aofFile) {
        Copy-Item $aofFile $redisBackupDir -Force
        Write-Host "    OK AOF file backed up" -ForegroundColor Green
    }
    
    if (Test-Path $rdbFile) {
        Copy-Item $rdbFile $redisBackupDir -Force
        Write-Host "    OK RDB file backed up" -ForegroundColor Green
    }
} catch {
    Write-Host "    WARN Failed to backup Redis: $_" -ForegroundColor Yellow
}

# Backup Certificates
Write-Host "`n[3/6] Backing up certificates..." -ForegroundColor Cyan
try {
    $certsBackupDir = Join-Path $backupDir "certs"
    New-Item -ItemType Directory -Path $certsBackupDir -Force | Out-Null
    
    # Backup all certificate directories
    $certPaths = @(
        "$AppRoot\main_server\certs",
        "$AppRoot\proxy\certs",
        "$AppRoot\worker\certs",
        "$AppRoot\portal\certs",
        "$AppRoot\client-scripts\certs"
    )
    
    $certCount = 0
    foreach ($certPath in $certPaths) {
        if (Test-Path $certPath) {
            $componentName = Split-Path (Split-Path $certPath -Parent) -Leaf
            $destDir = Join-Path $certsBackupDir $componentName
            Copy-Item $certPath -Destination $destDir -Recurse -Force
            $certCount++
        }
    }
    
    Write-Host "    OK $certCount certificate directories backed up" -ForegroundColor Green
} catch {
    Write-Host "    WARN Failed to backup certificates: $_" -ForegroundColor Yellow
}

# Backup Configuration Files
Write-Host "`n[4/6] Backing up configuration..." -ForegroundColor Cyan
try {
    $configBackupDir = Join-Path $backupDir "config"
    New-Item -ItemType Directory -Path $configBackupDir -Force | Out-Null
    
    $configFiles = @(
        "$AppRoot\.env",
        "$AppRoot\proxy\config.yaml",
        "$AppRoot\worker\config.yaml",
        "$AppRoot\main_server\alembic.ini",
        "$AppRoot\monitoring\prometheus.yml"
    )
    
    $configCount = 0
    foreach ($configFile in $configFiles) {
        if (Test-Path $configFile) {
            Copy-Item $configFile -Destination $configBackupDir -Force
            $configCount++
        }
    }
    
    Write-Host "    OK $configCount configuration files backed up" -ForegroundColor Green
} catch {
    Write-Host "    WARN Failed to backup configuration: $_" -ForegroundColor Yellow
}

# Backup Encryption Keys
Write-Host "`n[5/6] Backing up encryption keys..." -ForegroundColor Cyan
try {
    $keysDir = Join-Path $AppRoot "secrets"
    if (Test-Path $keysDir) {
        $keysBackupDir = Join-Path $backupDir "secrets"
        Copy-Item $keysDir -Destination $keysBackupDir -Recurse -Force
        Write-Host "    OK Encryption keys backed up" -ForegroundColor Green
    } else {
        Write-Host "    WARN Secrets directory not found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    WARN Failed to backup encryption keys: $_" -ForegroundColor Yellow
}

# Backup Recent Logs (last 7 days)
Write-Host "`n[6/6] Backing up recent logs..." -ForegroundColor Cyan
try {
    $logsBackupDir = Join-Path $backupDir "logs"
    New-Item -ItemType Directory -Path $logsBackupDir -Force | Out-Null
    
    $logsDir = Join-Path $AppRoot "logs"
    $cutoffDate = (Get-Date).AddDays(-7)
    
    if (Test-Path $logsDir) {
        Get-ChildItem $logsDir -File | Where-Object { $_.LastWriteTime -gt $cutoffDate } | ForEach-Object {
            Copy-Item $_.FullName -Destination $logsBackupDir -Force
        }
        
        $logCount = (Get-ChildItem $logsBackupDir).Count
        Write-Host "    OK $logCount log files backed up" -ForegroundColor Green
    }
} catch {
    Write-Host "    WARN Failed to backup logs: $_" -ForegroundColor Yellow
}

# Create backup manifest
Write-Host "`nCreating backup manifest..." -ForegroundColor Cyan
$manifest = @{
    BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    BackupVersion = "1.0"
    AppRoot = $AppRoot
    Components = @(
        "MySQL Database",
        "Redis Data",
        "Certificates",
        "Configuration Files",
        "Encryption Keys",
        "Application Logs"
    )
    Files = (Get-ChildItem $backupDir -Recurse -File).Count
    TotalSize = [math]::Round((Get-ChildItem $backupDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
}

$manifestFile = Join-Path $backupDir "manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Out-File $manifestFile -Encoding UTF8
Write-Host "  OK Manifest created" -ForegroundColor Green

# Compress backup if requested
if ($CompressBackup) {
    Write-Host "`nCompressing backup..." -ForegroundColor Cyan
    try {
        $zipFile = "$backupDir.zip"
        Compress-Archive -Path $backupDir -DestinationPath $zipFile -CompressionLevel Optimal -Force
        
        $zipSize = (Get-Item $zipFile).Length / 1MB
        Write-Host "  OK Backup compressed ($([math]::Round($zipSize, 2)) MB)" -ForegroundColor Green
        
        # Remove uncompressed backup
        Remove-Item $backupDir -Recurse -Force
        Write-Host "  OK Original backup removed" -ForegroundColor Green
    } catch {
        Write-Host "  WARN Failed to compress backup: $_" -ForegroundColor Yellow
    }
}

# Clean up old backups
Write-Host "`nCleaning up old backups..." -ForegroundColor Cyan
try {
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $oldBackups = Get-ChildItem $BackupRoot -Directory | Where-Object { $_.Name -like "backup_*" -and $_.CreationTime -lt $cutoffDate }
    $oldZips = Get-ChildItem $BackupRoot -File -Filter "backup_*.zip" | Where-Object { $_.CreationTime -lt $cutoffDate }
    
    $removedCount = 0
    
    foreach ($old in $oldBackups) {
        Remove-Item $old.FullName -Recurse -Force
        $removedCount++
    }
    
    foreach ($old in $oldZips) {
        Remove-Item $old.FullName -Force
        $removedCount++
    }
    
    if ($removedCount -gt 0) {
        Write-Host "  OK Removed $removedCount old backup(s)" -ForegroundColor Green
    } else {
        Write-Host "  OK No old backups to remove" -ForegroundColor Gray
    }
} catch {
    Write-Host "  WARN Failed to clean up old backups: $_" -ForegroundColor Yellow
}

# Summary
Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "Backup Complete" -ForegroundColor Green
Write-Host "================================================================`n" -ForegroundColor Green

Write-Host "Backup Details:" -ForegroundColor Cyan
Write-Host "  Location: $(if ($CompressBackup) { "$backupDir.zip" } else { $backupDir })"
Write-Host "  Files: $($manifest.Files)"
Write-Host "  Size: $($manifest.TotalSize) MB"
Write-Host "  Components: $($manifest.Components.Count)"
Write-Host ""

Write-Host "Components Backed Up:" -ForegroundColor Cyan
$manifest.Components | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
Write-Host ""

Write-Host "To restore this backup, run:" -ForegroundColor Yellow
Write-Host "  .\restore.ps1 -BackupPath $(if ($CompressBackup) { "$backupDir.zip" } else { $backupDir })" -ForegroundColor White
Write-Host ""

