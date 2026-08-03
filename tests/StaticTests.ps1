$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$failures = New-Object System.Collections.Generic.List[string]

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'FreeSignal.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
foreach ($error in $errors) { $failures.Add("FreeSignal.ps1:$($error.Extent.StartLineNumber): $($error.Message)") }

$watchdogTokens = $null
$watchdogErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'app\Watchdog.ps1'), [ref]$watchdogTokens, [ref]$watchdogErrors) | Out-Null
foreach ($error in $watchdogErrors) { $failures.Add("Watchdog.ps1:$($error.Extent.StartLineNumber): $($error.Message)") }

foreach ($xamlName in @('MainWindow.xaml', 'MainWindow.ru.xaml')) {
    try { [xml](Get-Content -LiteralPath (Join-Path $root ('app\' + $xamlName)) -Raw -Encoding UTF8) | Out-Null }
    catch { $failures.Add("${xamlName}: $($_.Exception.Message)") }
}

$selfTestOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'FreeSignal.ps1') -SelfTest | Out-String
if ($LASTEXITCODE -ne 0) { $failures.Add("Self-test failed: $selfTestOutput") }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'PowerShell syntax, XAML and application self-test passed.' -ForegroundColor Green
