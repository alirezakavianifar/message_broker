#!/usr/bin/env pwsh
# Security Tests - Tests security features

Write-Host "Running Security Tests..." -ForegroundColor Cyan
Write-Host ""

cd $PSScriptRoot
python security_test.py

if ($LASTEXITCODE -ne 0) {
    throw "Security tests failed"
}

