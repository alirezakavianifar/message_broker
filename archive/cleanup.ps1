# Cleanup Script - Remove Unnecessary Files
# Removes temporary files, cache, duplicates, and other unnecessary items

param(
    [switch]$DryRun,  # Show what would be deleted without actually deleting
    [switch]$Force    # Skip confirmation prompts
)

$ErrorActionPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CLEANUP - REMOVE UNNECESSARY FILES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[DRY RUN] - No files will be deleted`n" -ForegroundColor Yellow
}

$itemsToDelete = @()
$itemsSkipped = @()

# ============================================================================
# 1. Archive/ZIP files
# ============================================================================

Write-Host "1. Checking for archive files..." -ForegroundColor Yellow
$zipFiles = Get-ChildItem -Path . -Filter "*.zip" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "*\venv\*" }
foreach ($file in $zipFiles) {
    $itemsToDelete += @{
        Path = $file.FullName
        Type = "Archive"
        Reason = "Backup/archive file"
    }
    Write-Host "  [FOUND] $($file.Name)" -ForegroundColor Cyan
}

# ============================================================================
# 2. Python cache files (__pycache__) in source directories only
# ============================================================================

Write-Host "`n2. Checking for Python cache files..." -ForegroundColor Yellow
$pycacheDirs = Get-ChildItem -Path . -Directory -Filter "__pycache__" -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notlike "*\venv\*" -and
    $_.FullName -notlike "*\.git\*"
}
foreach ($dir in $pycacheDirs) {
    $itemsToDelete += @{
        Path = $dir.FullName
        Type = "Directory"
        Reason = "Python cache directory"
    }
    Write-Host "  [FOUND] $($dir.FullName.Replace($PWD, '.'))" -ForegroundColor Cyan
}

# ============================================================================
# 3. Temporary config files
# ============================================================================

Write-Host "`n3. Checking for temporary config files..." -ForegroundColor Yellow
$tempConfigs = @(
    "main_server\certs\proxy_temp.cnf",
    "main_server\certs\worker_temp.cnf"
)
foreach ($config in $tempConfigs) {
    if (Test-Path $config) {
        $itemsToDelete += @{
            Path = (Resolve-Path $config).Path
            Type = "File"
            Reason = "Temporary configuration file"
        }
        Write-Host "  [FOUND] $config" -ForegroundColor Cyan
    }
}

# ============================================================================
# 4. Check for duplicate backup.ps1 files
# ============================================================================

Write-Host "`n4. Checking for duplicate files..." -ForegroundColor Yellow
$backup1 = "deployment\backup\backup.ps1"
$backup2 = "infra\backup.ps1"

if ((Test-Path $backup1) -and (Test-Path $backup2)) {
    Write-Host "  [FOUND] Duplicate backup.ps1 files:" -ForegroundColor Cyan
    Write-Host "    - $backup1" -ForegroundColor White
    Write-Host "    - $backup2" -ForegroundColor White
    Write-Host "  [INFO] Keeping $backup1 (deployment version), will remove $backup2" -ForegroundColor Yellow
    $itemsToDelete += @{
        Path = (Resolve-Path $backup2).Path
        Type = "File"
        Reason = "Duplicate backup script (deployment version kept)"
    }
}

# ============================================================================
# 5. Phase completion status files (may be outdated)
# ============================================================================

Write-Host "`n5. Checking for phase completion status files..." -ForegroundColor Yellow
$phaseFiles = @(
    "tests\PHASE8_COMPLETE.md",
    "deployment\PHASE9_COMPLETE.md",
    "docs\PHASE10_COMPLETE.md",
    "tests\EXECUTION_SUMMARY.md",
    "tests\INSTALL_LOG.md",
    "tests\STATUS.md",
    "tests\SETUP.md"
)
foreach ($file in $phaseFiles) {
    if (Test-Path $file) {
        Write-Host "  [FOUND] $file" -ForegroundColor Cyan
        Write-Host "    [SKIP] Keeping (may be useful documentation)" -ForegroundColor Gray
        $itemsSkipped += $file
    }
}

# ============================================================================
# 6. Image/plan files (planning diagrams)
# ============================================================================

Write-Host "`n6. Checking for planning images..." -ForegroundColor Yellow
$planImages = Get-ChildItem -Path "image\plan" -File -ErrorAction SilentlyContinue
if ($planImages) {
    Write-Host "  [FOUND] $($planImages.Count) planning image(s)" -ForegroundColor Cyan
    Write-Host "    [SKIP] Keeping (may be useful reference)" -ForegroundColor Gray
    foreach ($img in $planImages) {
        $itemsSkipped += $img.FullName
    }
}

# ============================================================================
# 7. Log files in root (should be in logs/ directory)
# ============================================================================

Write-Host "`n7. Checking for stray log files..." -ForegroundColor Yellow
$logFiles = Get-ChildItem -Path . -Filter "*.log" -File -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notlike "*\venv\*" -and
    $_.FullName -notlike "*\logs\*"
}
foreach ($file in $logFiles) {
    $itemsToDelete += @{
        Path = $file.FullName
        Type = "File"
        Reason = "Log file (should be in logs/ directory)"
    }
    Write-Host "  [FOUND] $($file.Name)" -ForegroundColor Cyan
}

# ============================================================================
# 8. Compiled Python files (.pyc) in source directories
# ============================================================================

Write-Host "`n8. Checking for compiled Python files..." -ForegroundColor Yellow
$pycFiles = Get-ChildItem -Path . -Filter "*.pyc" -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notlike "*\venv\*" -and
    $_.FullName -notlike "*\.git\*"
}
foreach ($file in $pycFiles) {
    $itemsToDelete += @{
        Path = $file.FullName
        Type = "File"
        Reason = "Compiled Python file"
    }
}

if ($pycFiles.Count -gt 0) {
    Write-Host "  [FOUND] $($pycFiles.Count) .pyc file(s)" -ForegroundColor Cyan
}

# ============================================================================
# Summary and Deletion
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CLEANUP SUMMARY" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Items to delete: $($itemsToDelete.Count)" -ForegroundColor $(if ($itemsToDelete.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "Items skipped: $($itemsSkipped.Count)" -ForegroundColor Gray
Write-Host ""

if ($itemsToDelete.Count -eq 0) {
    Write-Host "[OK] No unnecessary files found to clean up!" -ForegroundColor Green
    exit 0
}

# Show what will be deleted
Write-Host "Files/Directories to be deleted:" -ForegroundColor Yellow
foreach ($item in $itemsToDelete) {
    $displayPath = $item.Path.Replace($PWD, '.')
    Write-Host "  - $displayPath" -ForegroundColor White
    Write-Host "    Reason: $($item.Reason)" -ForegroundColor Gray
}

# Confirm deletion
if (-not $Force -and -not $DryRun) {
    Write-Host "`nDo you want to delete these files? (y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "`n[INFO] Cleanup cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

# Perform deletion
if (-not $DryRun) {
    Write-Host "`nDeleting files..." -ForegroundColor Cyan
    $deleted = 0
    $errors = 0
    
    foreach ($item in $itemsToDelete) {
        try {
            if ($item.Type -eq "Directory") {
                Remove-Item -Path $item.Path -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -Path $item.Path -Force -ErrorAction Stop
            }
            $deleted++
            Write-Host "  [OK] Deleted: $($item.Path.Replace($PWD, '.'))" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to delete: $($item.Path.Replace($PWD, '.')) - $_" -ForegroundColor Red
            $errors++
        }
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  CLEANUP COMPLETE" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Deleted: $deleted" -ForegroundColor Green
    if ($errors -gt 0) {
        Write-Host "Errors: $errors" -ForegroundColor Red
    }
} else {
    Write-Host "`n[DRY RUN] Files would be deleted, but DryRun mode is enabled" -ForegroundColor Yellow
}

Write-Host ""
