Write-Host "Stopping Message Broker Services..." -ForegroundColor Yellow

# Ports used by the system
$ports = @(8000, 8001, 8080, 5000)

foreach ($port in $ports) {
    $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($connections) {
        $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
        foreach ($p_id in $pids) {
            try {
                $proc = Get-Process -Id $p_id -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Host "Stopping process on port $port (PID: $p_id, Name: $($proc.Name))..."
                    Stop-Process -Id $p_id -Force
                }
            }
            catch {
                Write-Host "Could not stop process $p_id: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Kill any remaining worker.py processes that might not be bound to a specific port
$pythonProcs = Get-Process -Name "python" -ErrorAction SilentlyContinue
if ($pythonProcs) {
    foreach ($proc in $pythonProcs) {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
            if ($cmdLine -like "*worker.py*") {
                Write-Host "Stopping worker process (PID: $($proc.Id))..."
                Stop-Process -Id $proc.Id -Force
            }
        }
        catch {}
    }
}

Write-Host "All Message Broker services stopped." -ForegroundColor Green
