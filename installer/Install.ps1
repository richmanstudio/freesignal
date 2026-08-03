[CmdletBinding()]
param(
    [string]$InstallDirectory = "$env:ProgramFiles\FreeSignal",
    [string]$Version = '0.1.0',
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -InstallDirectory "{1}" -Version "{2}"{3}' -f $PSCommandPath, $InstallDirectory, $Version, $(if ($NoLaunch) { ' -NoLaunch' } else { '' })
    Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    exit
}

$installedScript = Join-Path $InstallDirectory 'FreeSignal.ps1'
if (Test-Path -LiteralPath $installedScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installedScript -SafeMode 2>$null
}

New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
$items = @('FreeSignal.vbs', 'FreeSignal.cmd', 'FreeSignal-SafeMode.cmd', 'FreeSignal.ps1', 'app', 'assets', 'docs', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'SECURITY.md', 'README.md', 'installer')
foreach ($item in $items) {
    $source = Join-Path $sourceRoot $item
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $InstallDirectory -Recurse -Force }
}

$shell = New-Object -ComObject WScript.Shell
$startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\FreeSignal.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FreeSignal.lnk'
foreach ($shortcutPath in @($startMenu, $desktop)) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = ('"{0}"' -f (Join-Path $InstallDirectory 'FreeSignal.vbs'))
    $shortcut.WorkingDirectory = $InstallDirectory
    $shortcut.IconLocation = (Join-Path $InstallDirectory 'assets\freesignal.ico')
    $shortcut.Description = 'FreeSignal local anti-DPI connection manager'
    $shortcut.Save()
}

$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\FreeSignal'
New-Item -Path $uninstallKey -Force | Out-Null
$uninstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $InstallDirectory 'installer\Uninstall.ps1')
New-ItemProperty -Path $uninstallKey -Name DisplayName -Value 'FreeSignal' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name DisplayVersion -Value $Version -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name Publisher -Value 'DUONIQ' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $InstallDirectory -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name DisplayIcon -Value (Join-Path $InstallDirectory 'assets\freesignal.ico') -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name UninstallString -Value $uninstallCommand -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host "FreeSignal $Version installed to $InstallDirectory" -ForegroundColor Green
if (-not $NoLaunch) { Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"{0}"' -f (Join-Path $InstallDirectory 'FreeSignal.vbs')) }
