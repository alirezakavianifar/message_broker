#!/usr/bin/env pwsh
# Load Tests - Tests system under load

Write-Host "Running Load Tests..." -ForegroundColor Cyan
Write-Host ""

cd $PSScriptRoot
python load_test.py

if ($LASTEXITCODE -ne 0) {
    throw "Load tests failed"
}

