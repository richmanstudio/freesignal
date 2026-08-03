param(
    [Parameter(Mandatory = $true)][string]$DataDirectory,
    [int]$IntervalSeconds = 12,
    [int]$FailureLimit = 3
)

$ErrorActionPreference = 'SilentlyContinue'
$pidPath = Join-Path $DataDirectory 'watchdog.pid'
$rollbackPath = Join-Path $DataDirectory 'rollback.json'
$stopPath = Join-Path $DataDirectory 'watchdog.stop'
Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue

function Test-GeneralConnectivity {
    foreach ($uri in @('https://www.msftconnecttest.com/connecttest.txt', 'https://example.com/')) {
        try {
            $request = [System.Net.HttpWebRequest]::Create($uri)
            $request.Method = 'GET'
            $request.Timeout = 6500
            $request.ReadWriteTimeout = 6500
            $request.UserAgent = 'FreeSignal-Watchdog/0.1'
            $response = $request.GetResponse()
            $status = [int]$response.StatusCode
            $response.Close()
            if ($status -ge 200 -and $status -lt 500) { return $true }
        }
        catch { }
    }
    return $false
}

$failures = 0
try {
    while (-not (Test-Path -LiteralPath $stopPath)) {
        Start-Sleep -Seconds $IntervalSeconds
        if (Test-GeneralConnectivity) {
            $failures = 0
            continue
        }

        $failures++
        if ($failures -lt $FailureLimit) { continue }

        $managedPath = Join-Path $DataDirectory 'managed-processes.json'
        if (Test-Path -LiteralPath $managedPath) {
            try {
                $managed = @(Get-Content -LiteralPath $managedPath -Raw -Encoding UTF8 | ConvertFrom-Json)
                foreach ($record in $managed) {
                    if (-not $record.id) { continue }
                    $process = Get-Process -Id ([int]$record.id) -ErrorAction SilentlyContinue
                    if ($null -eq $process -or $process.ProcessName -notin @('winws', 'winws2')) { continue }
                    if ($record.startedAt) {
                        try {
                            $actual = $process.StartTime.ToUniversalTime()
                            $expected = [DateTime]::Parse([string]$record.startedAt).ToUniversalTime()
                            if ([Math]::Abs(($actual - $expected).TotalSeconds) -gt 2) { continue }
                        }
                        catch { continue }
                    }
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
            }
            catch { }
            Remove-Item -LiteralPath $managedPath -Force -ErrorAction SilentlyContinue
        }
        $payload = [ordered]@{
            timestamp = (Get-Date).ToString('o')
            reason = 'General connectivity failed repeatedly after enabling the engine.'
            failures = $failures
            action = 'FreeSignal-managed engine processes were stopped automatically.'
        }
        $payload | ConvertTo-Json | Set-Content -LiteralPath $rollbackPath -Encoding UTF8
        break
    }
}
finally {
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
}
