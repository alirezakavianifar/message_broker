#!/usr/bin/env pwsh
# Integration Tests - Tests end-to-end workflows

Write-Host "Running Integration Tests..." -ForegroundColor Cyan
Write-Host ""

cd $PSScriptRoot
python integration_test.py

if ($LASTEXITCODE -ne 0) {
    throw "Integration tests failed"
}

