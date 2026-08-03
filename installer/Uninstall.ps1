[CmdletBinding()]
param(
    [string]$InstallDirectory = "$env:ProgramFiles\FreeSignal",
    [switch]$RemoveUserData
)

$ErrorActionPreference = 'Stop'
function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -InstallDirectory "{1}"{2}' -f $PSCommandPath, $InstallDirectory, $(if ($RemoveUserData) { ' -RemoveUserData' } else { '' })
    Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    exit
}

$installedScript = Join-Path $InstallDirectory 'FreeSignal.ps1'
if (Test-Path -LiteralPath $installedScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installedScript -SafeMode 2>$null
}
Start-Process schtasks.exe -ArgumentList '/Delete /TN "FreeSignal AutoStart" /F' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
Remove-Item -LiteralPath (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\FreeSignal.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'FreeSignal.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\FreeSignal' -Recurse -Force -ErrorAction SilentlyContinue
Set-Location -LiteralPath $env:TEMP
Remove-Item -LiteralPath $InstallDirectory -Recurse -Force -ErrorAction SilentlyContinue
if ($RemoveUserData) { Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'FreeSignal') -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'FreeSignal has been removed.' -ForegroundColor Green
