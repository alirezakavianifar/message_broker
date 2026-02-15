# PowerShell script to package Message Broker for Linux deployment
# Excludes development files, logs, and Windows-specific files

$ErrorActionPreference = "Stop"

# Get project root directory
$projectRoot = $PSScriptRoot
if (-not $projectRoot) {
    $projectRoot = Get-Location
}

Write-Host "Packaging Message Broker for Linux deployment..." -ForegroundColor Green
Write-Host "Project root: $projectRoot" -ForegroundColor Cyan

# Create timestamp for zip filename
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$zipFileName = "message_broker_linux_$timestamp.zip"
$zipPath = Join-Path $projectRoot $zipFileName

# Files and directories to exclude
$excludePatterns = @(
    # Virtual environments
    "venv",
    ".venv",
    "env",
    ".env",
    "ENV",
    "env.bak",
    "venv.bak",
    
    # Python cache
    "__pycache__",
    "*.pyc",
    "*.pyo",
    "*.pyd",
    ".Python",
    "*.so",
    "*.egg-info",
    ".eggs",
    "dist",
    "build",
    
    # IDE
    ".vscode",
    ".idea",
    "*.swp",
    "*.swo",
    "*~",
    ".DS_Store",
    
    # Logs
    "logs",
    "*.log",
    "*.log.*",
    
    # Certificates and keys (sensitive)
    "*.key",
    "*.crt",
    "*.csr",
    "*.pem",
    "!ca.crt",  # Keep CA cert template if exists
    "crl",
    "secrets",
    "app_secrets",
    
    # Environment files (exclude actual .env but keep templates)
    ".env",
    ".env.local",
    # Note: .env.template and *.template files are explicitly included below
    
    # Database files
    "*.db",
    "*.sqlite",
    "*.sqlite3",
    
    # Monitoring data
    "prometheus_data",
    "grafana_data",
    
    # Backup files
    "*.bak",
    "*.backup",
    "*_temp.*",
    "*_temp_*",
    
    # OS files
    "Thumbs.db",
    "Desktop.ini",
    
    # Testing
    ".pytest_cache",
    ".coverage",
    "htmlcov",
    ".tox",
    
    # Existing zip files
    "*.zip",
    
    # Windows-specific files
    "*.bat",
    "*.ps1",
    "*.cmd",
    
    # Git
    ".git",
    ".gitignore",
    ".gitattributes",
    
    # Images (optional - comment out if you want to include)
    "image",
    
    # Temporary files
    "*.tmp",
    "*.temp",
    
    # Documentation - exclude Windows-specific and redundant docs
    # Keep only: README.md, LINUX_DEPLOYMENT_COMPLETE.md, component READMEs, docs/ folder
    "DEPLOY_TO_LINUX_README.md",
    "LINUX_DEPLOYMENT_GUIDE.md",  # Redundant with LINUX_DEPLOYMENT_COMPLETE.md
    "SETUP_REMOTE_DESKTOP.md",
    "REMOTE_DESKTOP_GUIDE.md",
    "OPEN_PORT_3389.md",
    "CLOUD_FIREWALL_GUIDE.md",
    "FIREWALL_FIX.md",
    "HOW_TO_CREATE_ADMIN_USER.md",
    "CREATE_ADMIN_USER.md",
    "DEPLOYMENT_GUIDE.md",  # Windows-focused
    "DEPLOYMENT_GUIDE_FA.md",
    "DEPLOYMENT_GUIDE_FA.html",
    "TESTING_GUIDE.md",
    "TESTING_GUIDE_FA.md",
    "TESTING_GUIDE_VERIFICATION.md",
    "TESTING_GUIDE.html",
    "PRODUCTION_READINESS_TESTS.md",
    "QUICK_START_GUIDE.md",  # Windows-focused
    "HOW_TO_RUN.md",  # Windows-focused
    "LOAD_BALANCING_GUIDE.md",
    "PACKAGE_README.md",
    "PACKAGE_VERIFICATION.md",
    "plan.md",
    "CHANGELOG.md",
    "RELEASE_NOTES.md",
    "API_SPECIFICATION.md",
    "DESIGN.md",
    "CONTRIBUTING.md",
    "TEST_EXECUTION_REPORT.md",
    "TEST_PLAN.md",
    "TEST_REPORT_TEMPLATE.md",
    "QA_CHECKLIST.md",
    "BUGS.md",
    "SETUP.md"  # In tests folder
)

# Directories to include (even if they might match exclude patterns)
$includeDirs = @(
    "main_server",
    "proxy",
    "worker",
    "portal",
    "client-scripts",
    "tests",
    "monitoring",
    "deployment",
    "docs",
    "infra"
)

Write-Host "`nCreating zip file: $zipFileName" -ForegroundColor Yellow

# Create temporary directory for packaging
$tempDir = Join-Path $env:TEMP "message_broker_package_$timestamp"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # Copy files, excluding patterns
    Write-Host "Copying files..." -ForegroundColor Cyan
    
    # Function to check if path should be excluded
    function Should-Exclude {
        param([string]$path)
        
        $relativePath = $path.Replace($projectRoot, "").TrimStart("\", "/")
        
        # Always include template files
        if ($relativePath -like "*.template" -or $relativePath -like "*template*") {
            return $false
        }
        
        # Always include essential documentation
        $essentialDocs = @(
            "README.md",
            "LINUX_DEPLOYMENT_COMPLETE.md"
        )
        $fileName = Split-Path -Leaf $relativePath
        if ($essentialDocs -contains $fileName) {
            return $false
        }
        
        # Always include component READMEs and docs folder
        if ($relativePath -like "*/README.md" -or $relativePath -like "docs/*") {
            return $false
        }
        
        foreach ($pattern in $excludePatterns) {
            if ($pattern.StartsWith("!")) {
                # Negation pattern - don't exclude
                continue
            }
            
            if ($pattern.Contains("*")) {
                # Wildcard pattern
                $regexPattern = $pattern -replace '\*', '.*' -replace '\.', '\.'
                if ($relativePath -match $regexPattern) {
                    return $true
                }
            } else {
                # Exact match - check both filename and full path
                if ($relativePath -eq $pattern -or 
                    $relativePath -like "*\$pattern" -or 
                    $relativePath -like "*/$pattern" -or
                    $fileName -eq $pattern) {
                    return $true
                }
            }
        }
        
        return $false
    }
    
    # Copy files recursively
    function Copy-FileTree {
        param(
            [string]$source,
            [string]$destination,
            [string]$relativePath = ""
        )
        
        $items = Get-ChildItem -Path $source -Force
        
        foreach ($item in $items) {
            $itemRelativePath = if ($relativePath) { "$relativePath\$($item.Name)" } else { $item.Name }
            
            if (Should-Exclude -path $itemRelativePath) {
                Write-Host "  Excluding: $itemRelativePath" -ForegroundColor DarkGray
                continue
            }
            
            $destPath = Join-Path $destination $item.Name
            
            if ($item.PSIsContainer) {
                # Directory
                if (-not (Test-Path $destPath)) {
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                }
                Copy-FileTree -source $item.FullName -destination $destPath -relativePath $itemRelativePath
            } else {
                # File
                Copy-Item -Path $item.FullName -Destination $destPath -Force
                Write-Host "  Including: $itemRelativePath" -ForegroundColor DarkGreen
            }
        }
    }
    
    # Copy root files first
    $rootFiles = Get-ChildItem -Path $projectRoot -File -Force | Where-Object {
        $name = $_.Name
        -not (Should-Exclude -path $name)
    }
    
    foreach ($file in $rootFiles) {
        Copy-Item -Path $file.FullName -Destination $tempDir -Force
        Write-Host "  Including: $($file.Name)" -ForegroundColor DarkGreen
    }
    
    # Copy directories
    foreach ($dir in $includeDirs) {
        $sourceDir = Join-Path $projectRoot $dir
        if (Test-Path $sourceDir) {
            $destDir = Join-Path $tempDir $dir
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Copy-FileTree -source $sourceDir -destination $destDir -relativePath $dir
        }
    }
    
    # Copy other directories that might exist
    $otherDirs = Get-ChildItem -Path $projectRoot -Directory -Force | Where-Object {
        $name = $_.Name
        $name -notin $includeDirs -and -not (Should-Exclude -path $name)
    }
    
    foreach ($dir in $otherDirs) {
        $destDir = Join-Path $tempDir $dir.Name
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Copy-FileTree -source $dir.FullName -destination $destDir -relativePath $dir.Name
    }
    
    # Create zip file
    Write-Host "`nCompressing files..." -ForegroundColor Cyan
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    # Use .NET compression for better control
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    
    $zipSize = (Get-Item $zipPath).Length / 1MB
    Write-Host "`nPackage created successfully!" -ForegroundColor Green
    Write-Host "  File: $zipFileName" -ForegroundColor Cyan
    Write-Host "  Size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Cyan
    Write-Host "  Location: $zipPath" -ForegroundColor Cyan
    
} finally {
    # Cleanup temporary directory
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
}

Write-Host "`nDone! The package is ready for Linux deployment." -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Transfer $zipFileName to your Linux server" -ForegroundColor White
Write-Host "2. Extract: unzip $zipFileName -d /opt/message_broker" -ForegroundColor White
Write-Host "3. Follow LINUX_DEPLOYMENT_COMPLETE.md for installation" -ForegroundColor White

