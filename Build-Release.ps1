[CmdletBinding()]
param([string]$Version = '0.1.1')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\StaticTests.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Static tests failed.' }
node (Join-Path $root 'tests\test_profiles.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Node tests failed.' }

$dist = Join-Path $root 'dist'
$stage = Join-Path $dist "FreeSignal-$Version"
Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$exclude = @('.git', '.github', 'dist', 'demo', 'tests')
Get-ChildItem -LiteralPath $root | Where-Object {
    ($exclude -notcontains $_.Name) -and ($_.Name -notlike '*-trigger.txt')
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stage -Recurse -Force
}
Set-Content -LiteralPath (Join-Path $stage 'VERSION') -Value $Version -Encoding ASCII
$manifestLines = Get-ChildItem -LiteralPath $stage -File -Recurse | Where-Object { $_.Name -ne 'MANIFEST.sha256' } | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
    $fileHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$fileHash  $relative"
}
Set-Content -LiteralPath (Join-Path $stage 'MANIFEST.sha256') -Value $manifestLines -Encoding ASCII
$zip = Join-Path $dist "FreeSignal-$Version-windows-x64.zip"
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($zip + '.sha256') -Value "$hash  $([IO.Path]::GetFileName($zip))" -Encoding ASCII
Write-Host "Created $zip" -ForegroundColor Green
Write-Host "SHA256 $hash"
