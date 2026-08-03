$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$failures = New-Object System.Collections.Generic.List[string]
$mainScriptPath = Join-Path $root 'FreeSignal.ps1'

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
foreach ($error in $errors) { $failures.Add("FreeSignal.ps1:$($error.Extent.StartLineNumber): $($error.Message)") }

$watchdogTokens = $null
$watchdogErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'app\Watchdog.ps1'), [ref]$watchdogTokens, [ref]$watchdogErrors) | Out-Null
foreach ($error in $watchdogErrors) { $failures.Add("Watchdog.ps1:$($error.Extent.StartLineNumber): $($error.Message)") }

foreach ($xamlName in @('MainWindow.xaml', 'MainWindow.ru.xaml')) {
    try { [xml](Get-Content -LiteralPath (Join-Path $root ('app\' + $xamlName)) -Raw -Encoding UTF8) | Out-Null }
    catch { $failures.Add("${xamlName}: $($_.Exception.Message)") }
}

# Windows PowerShell 5.1 treats `(if (...) { ... })` as a command invocation at runtime.
# The subexpression form `$(if (...) { ... })` is required in argument/value positions.
$mainScriptText = Get-Content -LiteralPath $mainScriptPath -Raw -Encoding UTF8
$unsupportedInlineIf = [regex]::Matches($mainScriptText, '(?m)(?<!\$)\(if\s*\(')
if ($unsupportedInlineIf.Count -gt 0) {
    $failures.Add("FreeSignal.ps1 contains $($unsupportedInlineIf.Count) unsupported inline if expression(s). Use `$(if (...)) instead.")
}

$selfTestOutput = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File $mainScriptPath -SelfTest | Out-String
if ($LASTEXITCODE -ne 0) { $failures.Add("Direct self-test failed: $selfTestOutput") }

$launcherOutput = & cscript.exe //nologo (Join-Path $root 'FreeSignal.vbs') --self-test 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { $failures.Add("FreeSignal.vbs launcher self-test failed with exit code $LASTEXITCODE`: $launcherOutput") }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'PowerShell syntax, XAML, inline-expression compatibility and VBS launcher self-test passed.' -ForegroundColor Green
