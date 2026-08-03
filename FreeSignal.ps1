[CmdletBinding()]
param(
    [switch]$AutoStart,
    [switch]$SafeMode,
    [switch]$Emergency,
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:Version = '0.1.0'
$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:AppDirectory = Join-Path $Script:Root 'app'
$Script:ProfilesPath = Join-Path $Script:AppDirectory 'profiles.json'
$Script:SourcesPath = Join-Path $Script:AppDirectory 'engine-sources.json'
$Script:XamlPath = Join-Path $Script:AppDirectory 'MainWindow.xaml'
$Script:RussianXamlPath = Join-Path $Script:AppDirectory 'MainWindow.ru.xaml'
$Script:DataDirectory = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'FreeSignal' } else { Join-Path $Script:Root '.freesignal-data' }
$Script:EngineDirectory = Join-Path $Script:DataDirectory 'engine'
$Script:PreviousEngineDirectory = Join-Path $Script:DataDirectory 'engine.previous'
$Script:StatePath = Join-Path $Script:DataDirectory 'state.json'
$Script:LogDirectory = Join-Path $Script:DataDirectory 'logs'
$Script:LogPath = Join-Path $Script:LogDirectory ('freesignal-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
$Script:WatchdogScript = Join-Path $Script:AppDirectory 'Watchdog.ps1'
$Script:ManagedPidsPath = Join-Path $Script:DataDirectory 'managed-processes.json'
$Script:RuntimeStrategyPath = Join-Path $Script:DataDirectory 'runtime-strategy.cmd'
$Script:Profiles = @()
$Script:State = $null
$Script:Window = $null
$Script:Ui = @{}

function Initialize-FSDirectories {
    foreach ($path in @($Script:DataDirectory, $Script:LogDirectory)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Write-FSLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SECURITY')][string]$Level = 'INFO'
    )

    Initialize-FSDirectories
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Add-Content -LiteralPath $Script:LogPath -Value $line -Encoding UTF8
}

function New-FSDefaultState {
    return [ordered]@{
        schemaVersion = 1
        appVersion = $Script:Version
        selectedProfile = 'balanced'
        runningProfile = ''
        autoStart = $false
        language = 'auto'
        engine = [ordered]@{
            provider = ''
            version = ''
            sourceRepository = ''
            packageSha256 = ''
            installedAt = ''
            root = $Script:EngineDirectory
        }
        lastDiagnostics = @()
        lastOptimization = @()
        lastRollback = $null
    }
}

function ConvertTo-FSHashtable {
    param([Parameter(Mandatory = $true)]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) { $result[$key] = ConvertTo-FSHashtable $InputObject[$key] }
        return $result
    }
    if ($InputObject -is [PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) { $result[$property.Name] = ConvertTo-FSHashtable $property.Value }
        return $result
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) { $items += ,(ConvertTo-FSHashtable $item) }
        return $items
    }
    return $InputObject
}

function Get-FSState {
    Initialize-FSDirectories
    if (-not (Test-Path -LiteralPath $Script:StatePath)) {
        $state = New-FSDefaultState
        Save-FSState -State $state
        return $state
    }

    try {
        $raw = Get-Content -LiteralPath $Script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $state = ConvertTo-FSHashtable $raw
        if (-not $state.Contains('selectedProfile')) { $state.selectedProfile = 'balanced' }
        if (-not $state.Contains('runningProfile')) { $state.runningProfile = '' }
        if (-not $state.Contains('autoStart')) { $state.autoStart = $false }
        if (-not $state.Contains('language')) { $state.language = 'auto' }
        if (-not $state.Contains('engine')) { $state.engine = (New-FSDefaultState).engine }
        return $state
    }
    catch {
        $backup = $Script:StatePath + '.corrupt-' + (Get-Date -Format 'yyyyMMddHHmmss')
        Copy-Item -LiteralPath $Script:StatePath -Destination $backup -Force -ErrorAction SilentlyContinue
        Write-FSLog -Level 'ERROR' -Message ('State file was invalid and has been reset: {0}' -f $_.Exception.Message)
        $state = New-FSDefaultState
        Save-FSState -State $state
        return $state
    }
}

function Save-FSState {
    param([Parameter(Mandatory = $true)]$State)
    Initialize-FSDirectories
    $temp = $Script:StatePath + '.tmp'
    $State.appVersion = $Script:Version
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Script:StatePath -Force
}

function Get-FSProfiles {
    if (-not (Test-Path -LiteralPath $Script:ProfilesPath)) { throw 'profiles.json is missing.' }
    $data = Get-Content -LiteralPath $Script:ProfilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($data.profiles)
}

function Get-FSProfile {
    param([Parameter(Mandatory = $true)][string]$Id)
    return $Script:Profiles | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Get-FSEffectiveLanguage {
    $preference = if ($Script:State -and $Script:State.Contains('language')) { [string]$Script:State.language } else { 'auto' }
    if ($preference -in @('ru', 'en')) { return $preference }
    try {
        if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru') { return 'ru' }
    }
    catch { }
    return 'en'
}

function Get-FSText {
    param([Parameter(Mandatory = $true)][string]$English, [Parameter(Mandatory = $true)][string]$Russian)
    return $(if ((Get-FSEffectiveLanguage) -eq 'ru') { $Russian } else { $English })
}

function Get-FSProfileDisplayName {
    param([Parameter(Mandatory = $true)]$Profile)
    if ((Get-FSEffectiveLanguage) -ne 'ru') { return [string]$Profile.name }
    $names = @{ balanced = 'Сбалансированный'; compatibility = 'Совместимость'; aggressive = 'Усиленный'; simple = 'Простой Fake'; experimental = 'Экспериментальный' }
    return $(if ($names.ContainsKey([string]$Profile.id)) { $names[[string]$Profile.id] } else { [string]$Profile.name })
}

function Test-FSAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Restart-FSAsAdministrator {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($AutoStart) { $arguments += '-AutoStart' }
    if ($SafeMode) { $arguments += '-SafeMode' }
    if ($Emergency) { $arguments += '-Emergency' }
    if ($SelfTest) { $arguments += '-SelfTest' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList ($arguments -join ' ') -Verb RunAs -WindowStyle Hidden -WorkingDirectory $Script:Root | Out-Null
}

function Get-FSManagedProcessRecords {
    if (-not (Test-Path -LiteralPath $Script:ManagedPidsPath)) { return @() }
    try {
        $records = Get-Content -LiteralPath $Script:ManagedPidsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($records)
    }
    catch {
        Write-FSLog -Level 'WARN' -Message ('Managed process file is invalid: {0}' -f $_.Exception.Message)
        Remove-Item -LiteralPath $Script:ManagedPidsPath -Force -ErrorAction SilentlyContinue
        return @()
    }
}

function Save-FSManagedProcesses {
    param([Parameter(Mandatory = $true)]$Processes)
    $records = @($Processes | ForEach-Object {
        $startedAt = ''
        try { $startedAt = $_.StartTime.ToUniversalTime().ToString('o') } catch { }
        [ordered]@{
            id = $_.Id
            name = $_.ProcessName
            startedAt = $startedAt
        }
    })
    $records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Script:ManagedPidsPath -Encoding UTF8
}

function Get-FSEngineProcess {
    $processes = New-Object System.Collections.Generic.List[object]
    foreach ($record in (Get-FSManagedProcessRecords)) {
        if (-not $record.id) { continue }
        $process = Get-Process -Id ([int]$record.id) -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        if ($process.ProcessName -notin @('winws', 'winws2')) { continue }
        if ($record.startedAt) {
            try {
                $actual = $process.StartTime.ToUniversalTime()
                $expected = [DateTime]::Parse([string]$record.startedAt).ToUniversalTime()
                if ([Math]::Abs(($actual - $expected).TotalSeconds) -gt 2) { continue }
            }
            catch { continue }
        }
        $processes.Add($process)
    }
    if ($processes.Count -eq 0) { Remove-Item -LiteralPath $Script:ManagedPidsPath -Force -ErrorAction SilentlyContinue }
    return @($processes)
}

function Get-FSForeignEngineProcess {
    $managedIds = @((Get-FSEngineProcess) | ForEach-Object { $_.Id })
    $all = @()
    foreach ($name in @('winws', 'winws2')) { $all += @(Get-Process -Name $name -ErrorAction SilentlyContinue) }
    return @($all | Where-Object { $managedIds -notcontains $_.Id })
}

function Test-FSEngineRunning {
    return (@(Get-FSEngineProcess).Count -gt 0)
}

function Test-FSEngineInstalled {
    if (-not (Test-Path -LiteralPath $Script:EngineDirectory)) { return $false }
    $winws = Join-Path $Script:EngineDirectory 'bin\winws.exe'
    $service = Join-Path $Script:EngineDirectory 'service.bat'
    return ((Test-Path -LiteralPath $winws) -and (Test-Path -LiteralPath $service))
}

function Stop-FSWatchdog {
    $stopPath = Join-Path $Script:DataDirectory 'watchdog.stop'
    Set-Content -LiteralPath $stopPath -Value 'stop' -Encoding ASCII -ErrorAction SilentlyContinue
    $pidPath = Join-Path $Script:DataDirectory 'watchdog.pid'
    if (Test-Path -LiteralPath $pidPath) {
        $watchdogPid = Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue
        if ($watchdogPid -match '^\d+$') {
            Stop-Process -Id ([int]$watchdogPid) -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $pidPath, $stopPath -Force -ErrorAction SilentlyContinue
}

function Start-FSWatchdog {
    Stop-FSWatchdog
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -DataDirectory "{1}"' -f $Script:WatchdogScript, $Script:DataDirectory
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $Script:Root | Out-Null
    Write-FSLog 'Connectivity watchdog started.'
}

function Stop-FSEngine {
    param([switch]$PreserveState, [switch]$Emergency)
    Stop-FSWatchdog
    $processes = if ($Emergency) {
        $all = @()
        foreach ($name in @('winws', 'winws2')) { $all += @(Get-Process -Name $name -ErrorAction SilentlyContinue) }
        @($all)
    }
    else { @(Get-FSEngineProcess) }
    foreach ($process in $processes) {
        try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch { Write-FSLog -Level 'WARN' -Message ('Unable to stop process {0}: {1}' -f $process.Id, $_.Exception.Message) }
    }
    Remove-Item -LiteralPath $Script:ManagedPidsPath, $Script:RuntimeStrategyPath -Force -ErrorAction SilentlyContinue
    if (-not $PreserveState) {
        $Script:State.runningProfile = ''
        Save-FSState -State $Script:State
    }
    Write-FSLog -Level $(if ($Emergency) { 'SECURITY' } else { 'INFO' }) -Message ('Engine stopped. Managed processes terminated: {0}; emergency={1}' -f $processes.Count, $Emergency)
}

function Resolve-FSStrategyPath {
    param([Parameter(Mandatory = $true)][string]$ProfileId)
    $profile = Get-FSProfile -Id $ProfileId
    if ($null -eq $profile) { throw "Unknown profile: $ProfileId" }
    $path = Join-Path $Script:EngineDirectory $profile.strategyFile
    if (-not (Test-Path -LiteralPath $path)) { throw ('Strategy file is missing: {0}' -f $profile.strategyFile) }
    return $path
}

function New-FSRuntimeStrategy {
    param(
        [Parameter(Mandatory = $true)][string]$StrategyPath,
        [Parameter(Mandatory = $true)][string]$ProfileId
    )
    $lines = @(Get-Content -LiteralPath $StrategyPath -Encoding UTF8)
    $startIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*start\s+"[^"]*"\s+/min\s+"%BIN%winws\.exe"') { $startIndex = $index; break }
    }
    if ($startIndex -lt 0) { throw 'The selected strategy does not contain a supported winws launch command.' }

    $commandLines = New-Object System.Collections.Generic.List[string]
    for ($index = $startIndex; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        $commandLines.Add($line)
        if (-not $line.TrimEnd().EndsWith('^')) { break }
    }
    $commandText = $commandLines -join "`r`n"
    if ($commandText -match '(?i)(powershell|pwsh|curl|wget|bitsadmin|certutil|mshta|reg\s|sc\s|netsh|taskkill|[&|<>])') {
        throw 'The strategy contains commands outside the allowed winws argument set.'
    }
    if ($commandText -notmatch '(?i)%BIN%winws\.exe') { throw 'The strategy launch target is not winws.exe.' }

    $bin = (Join-Path $Script:EngineDirectory 'bin') + '\'
    $lists = (Join-Path $Script:EngineDirectory 'lists') + '\'
    $wrapper = @(
        '@echo off',
        'chcp 65001 > nul',
        'set "NO_UPDATE_CHECK=1"',
        ('set "BIN={0}"' -f $bin),
        ('set "LISTS={0}"' -f $lists),
        'set "GameFilter=12"',
        'set "GameFilterTCP=12"',
        'set "GameFilterUDP=12"',
        'cd /d "%BIN%"',
        $commandText
    ) -join "`r`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Script:RuntimeStrategyPath, $wrapper, $utf8NoBom)
    Write-FSLog -Level 'SECURITY' -Message ('Generated sanitized runtime strategy for profile {0}; service.bat hooks were not executed.' -f $ProfileId)
    return $Script:RuntimeStrategyPath
}

function Start-FSEngine {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [switch]$SkipWatchdog
    )

    if (-not (Test-FSEngineInstalled)) { throw 'The Flowseal/zapret engine package is not installed.' }
    $strategyPath = Resolve-FSStrategyPath -ProfileId $ProfileId
    Stop-FSEngine -PreserveState

    $service = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') { throw 'A zapret Windows service is already running. Stop it before using FreeSignal standalone mode.' }
    $foreign = @(Get-FSForeignEngineProcess)
    if ($foreign.Count -gt 0) { throw 'Another winws/winws2 process is already running. FreeSignal will not stop or take ownership of external tools.' }

    $runtimeStrategy = New-FSRuntimeStrategy -StrategyPath $strategyPath -ProfileId $ProfileId
    Write-FSLog ('Starting profile {0} using sanitized command extracted from {1}' -f $ProfileId, [IO.Path]::GetFileName($strategyPath))
    $argumentList = '/d /c call "{0}"' -f $runtimeStrategy
    Start-Process -FilePath $env:ComSpec -ArgumentList $argumentList -WorkingDirectory $Script:EngineDirectory -WindowStyle Hidden | Out-Null

    $startedProcesses = @()
    for ($index = 0; $index -lt 24; $index++) {
        Start-Sleep -Milliseconds 250
        $startedProcesses = @()
        foreach ($name in @('winws', 'winws2')) { $startedProcesses += @(Get-Process -Name $name -ErrorAction SilentlyContinue) }
        if ($startedProcesses.Count -gt 0) { break }
    }
    if ($startedProcesses.Count -eq 0) { throw 'The engine process did not start. Run diagnostics and inspect the local logs.' }
    Save-FSManagedProcesses -Processes $startedProcesses

    $Script:State.selectedProfile = $ProfileId
    $Script:State.runningProfile = $ProfileId
    Save-FSState -State $Script:State
    if (-not $SkipWatchdog) { Start-FSWatchdog }
    return $true
}

function Test-FSArchiveSafety {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [long]$MaximumArchiveBytes = 314572800,
        [long]$MaximumExpandedBytes = 1073741824,
        [int]$MaximumEntries = 20000
    )
    $archiveFile = Get-Item -LiteralPath $ArchivePath -ErrorAction Stop
    if ($archiveFile.Length -gt $MaximumArchiveBytes) { throw 'The selected package exceeds the configured archive size limit.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archiveFile.FullName)
    try {
        if ($zip.Entries.Count -gt $MaximumEntries) { throw 'The archive contains too many entries.' }
        [long]$expandedBytes = 0
        foreach ($entry in $zip.Entries) {
            $name = [string]$entry.FullName
            if (-not $name) { continue }
            if ([IO.Path]::IsPathRooted($name) -or $name.Contains(':') -or $name -match '(^|[\\/])\.\.([\\/]|$)') {
                throw ('Unsafe archive path rejected: {0}' -f $name)
            }
            $expandedBytes += [long]$entry.Length
            if ($expandedBytes -gt $MaximumExpandedBytes) { throw 'The expanded package exceeds the configured size limit.' }
        }
    }
    finally { $zip.Dispose() }
    return $true
}

function Find-FSEngineRoot {
    param([Parameter(Mandatory = $true)][string]$ExtractedDirectory)
    $candidates = Get-ChildItem -LiteralPath $ExtractedDirectory -Filter 'service.bat' -File -Recurse -ErrorAction SilentlyContinue
    foreach ($candidate in $candidates) {
        $root = $candidate.Directory.FullName
        if (Test-Path -LiteralPath (Join-Path $root 'bin\winws.exe')) { return $root }
    }
    return $null
}

function Copy-FSUserLists {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    $relativePaths = @(
        'lists\list-general-user.txt',
        'lists\list-exclude-user.txt',
        'lists\ipset-all-user.txt',
        'lists\ipset-exclude-user.txt'
    )
    foreach ($relativePath in $relativePaths) {
        $source = Join-Path $SourceRoot $relativePath
        $destination = Join-Path $DestinationRoot $relativePath
        if (Test-Path -LiteralPath $source) {
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
}

function Install-FSEngineFromExtractedRoot {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$SourceRepository,
        [Parameter(Mandatory = $true)][string]$PackageSha256
    )

    $required = @('service.bat', 'bin\winws.exe')
    foreach ($relativePath in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $relativePath))) { throw "Engine package is missing $relativePath" }
    }

    Stop-FSEngine
    $staging = Join-Path $Script:DataDirectory ('engine.staging-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceRoot '*') -Destination $staging -Recurse -Force

    if (Test-Path -LiteralPath $Script:EngineDirectory) {
        Copy-FSUserLists -SourceRoot $Script:EngineDirectory -DestinationRoot $staging
        Remove-Item -LiteralPath $Script:PreviousEngineDirectory -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $Script:EngineDirectory -Destination $Script:PreviousEngineDirectory -Force
    }

    try {
        Move-Item -LiteralPath $staging -Destination $Script:EngineDirectory -Force
    }
    catch {
        if (Test-Path -LiteralPath $Script:PreviousEngineDirectory) {
            Move-Item -LiteralPath $Script:PreviousEngineDirectory -Destination $Script:EngineDirectory -Force -ErrorAction SilentlyContinue
        }
        throw
    }

    $criticalHashes = [ordered]@{}
    foreach ($relativePath in @('service.bat', 'bin\winws.exe', 'bin\WinDivert64.sys')) {
        $criticalPath = Join-Path $Script:EngineDirectory $relativePath
        if (Test-Path -LiteralPath $criticalPath) {
            $criticalHashes[$relativePath] = (Get-FileHash -LiteralPath $criticalPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $manifest = [ordered]@{
        provider = $Provider
        version = $Version
        sourceRepository = $SourceRepository
        packageSha256 = $PackageSha256
        installedAt = (Get-Date).ToString('o')
        criticalFileSha256 = $criticalHashes
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Script:EngineDirectory 'freesignal-engine.json') -Encoding UTF8

    $Script:State.engine.provider = $Provider
    $Script:State.engine.version = $Version
    $Script:State.engine.sourceRepository = $SourceRepository
    $Script:State.engine.packageSha256 = $PackageSha256
    $Script:State.engine.installedAt = $manifest.installedAt
    $Script:State.engine.root = $Script:EngineDirectory
    Save-FSState -State $Script:State
    Sync-FSUserListsToEngine
    Write-FSLog -Level 'SECURITY' -Message ('Engine installed from {0}; version={1}; sha256={2}' -f $SourceRepository, $Version, $PackageSha256)
}

function Install-FSLatestFlowsealEngine {
    $sources = Get-Content -LiteralPath $Script:SourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $source = $sources.sources | Where-Object { $_.id -eq 'flowseal' } | Select-Object -First 1
    if ($null -eq $source) { throw 'Flowseal engine source is not configured.' }

    Write-FSLog ('Requesting latest release metadata from {0}' -f $source.repository)
    $headers = @{ 'User-Agent' = 'FreeSignal/0.1'; 'Accept' = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri $source.releaseApi -Headers $headers -Method Get -TimeoutSec 25
    $asset = $release.assets | Where-Object { $_.name -match $source.assetPattern } | Select-Object -First 1
    if ($null -eq $asset) { $asset = $release.assets | Where-Object { $_.name -match $source.fallbackAssetPattern } | Select-Object -First 1 }
    if ($null -eq $asset) { throw 'The latest release does not contain a compatible ZIP asset.' }
    if (-not ([string]$asset.browser_download_url).StartsWith([string]$source.allowedDownloadPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The release asset URL does not belong to the configured official repository path.'
    }
    if ($asset.size -and ([long]$asset.size -gt [long]$source.maxAssetBytes)) { throw 'The release asset exceeds the configured size limit.' }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('freesignal-' + [Guid]::NewGuid().ToString('N'))
    $archive = Join-Path $tempRoot $asset.name
    $extract = Join-Path $tempRoot 'extract'
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    try {
        Write-FSLog ('Downloading official release asset: {0}' -f $asset.browser_download_url)
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $archive -UseBasicParsing -TimeoutSec 180
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        Test-FSArchiveSafety -ArchivePath $archive -MaximumArchiveBytes ([long]$source.maxAssetBytes) | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
        $engineRoot = Find-FSEngineRoot -ExtractedDirectory $extract
        if (-not $engineRoot) { throw 'The downloaded archive does not contain the expected Flowseal layout.' }
        Install-FSEngineFromExtractedRoot -SourceRoot $engineRoot -Provider 'flowseal' -Version $release.tag_name -SourceRepository $source.repository -PackageSha256 $hash
        return [ordered]@{ version = $release.tag_name; sha256 = $hash; asset = $asset.name }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Import-FSEngineArchive {
    param([Parameter(Mandatory = $true)][string]$ArchivePath)
    if (-not (Test-Path -LiteralPath $ArchivePath)) { throw 'Selected archive does not exist.' }
    if ([IO.Path]::GetExtension($ArchivePath) -ne '.zip') { throw 'Only ZIP archives are supported by the MVP importer.' }

    $hash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Test-FSArchiveSafety -ArchivePath $ArchivePath | Out-Null
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('freesignal-import-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $tempRoot -Force
        $engineRoot = Find-FSEngineRoot -ExtractedDirectory $tempRoot
        if (-not $engineRoot) { throw 'The archive does not contain service.bat and bin\winws.exe.' }
        $version = [IO.Path]::GetFileNameWithoutExtension($ArchivePath)
        Install-FSEngineFromExtractedRoot -SourceRoot $engineRoot -Provider 'manual-import' -Version $version -SourceRepository 'local file' -PackageSha256 $hash
        return $hash
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-FSEnginePackage {
    Stop-FSEngine
    Remove-Item -LiteralPath $Script:EngineDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Script:PreviousEngineDirectory -Recurse -Force -ErrorAction SilentlyContinue
    $Script:State.engine = (New-FSDefaultState).engine
    Save-FSState -State $Script:State
    Write-FSLog 'Engine package removed.'
}

function Get-FSPendingListPath {
    param([Parameter(Mandatory = $true)][ValidateSet('include', 'exclude')][string]$Kind)
    return Join-Path $Script:DataDirectory (if ($Kind -eq 'include') { 'list-general-user.txt' } else { 'list-exclude-user.txt' })
}

function Normalize-FSDomainList {
    param([string]$Text)
    $output = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split "`r?`n")) {
        $value = $line.Trim().ToLowerInvariant()
        if (-not $value -or $value.StartsWith('#')) { continue }
        $value = $value -replace '^https?://', ''
        $value = $value.Split('/')[0]
        if ($value -match '^[a-z0-9][a-z0-9.-]*[a-z0-9]$' -or $value -match '^[a-z0-9]$') {
            if (-not $output.Contains($value)) { $output.Add($value) }
        }
    }
    return @($output | Sort-Object)
}

function Save-FSUserLists {
    param([string]$IncludeText, [string]$ExcludeText)
    $include = Normalize-FSDomainList -Text $IncludeText
    $exclude = Normalize-FSDomainList -Text $ExcludeText
    Set-Content -LiteralPath (Get-FSPendingListPath -Kind 'include') -Value $include -Encoding UTF8
    Set-Content -LiteralPath (Get-FSPendingListPath -Kind 'exclude') -Value $exclude -Encoding UTF8
    Sync-FSUserListsToEngine
    Write-FSLog ('User domain lists saved: include={0}, exclude={1}' -f $include.Count, $exclude.Count)
    return [ordered]@{ include = $include.Count; exclude = $exclude.Count }
}

function Sync-FSUserListsToEngine {
    if (-not (Test-FSEngineInstalled)) { return }
    $listDirectory = Join-Path $Script:EngineDirectory 'lists'
    if (-not (Test-Path -LiteralPath $listDirectory)) { New-Item -ItemType Directory -Path $listDirectory -Force | Out-Null }
    $mappings = @{
        (Get-FSPendingListPath -Kind 'include') = (Join-Path $listDirectory 'list-general-user.txt')
        (Get-FSPendingListPath -Kind 'exclude') = (Join-Path $listDirectory 'list-exclude-user.txt')
    }
    foreach ($source in $mappings.Keys) {
        if (-not (Test-Path -LiteralPath $source)) { Set-Content -LiteralPath $source -Value @() -Encoding UTF8 }
        Copy-Item -LiteralPath $source -Destination $mappings[$source] -Force
    }
}

function Get-FSUserListText {
    param([Parameter(Mandatory = $true)][ValidateSet('include', 'exclude')][string]$Kind)
    $path = Get-FSPendingListPath -Kind $Kind
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

function Invoke-FSHttpProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Uri,
        [int]$TimeoutMilliseconds = 7500
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.Method = 'GET'
        $request.AllowAutoRedirect = $true
        $request.Timeout = $TimeoutMilliseconds
        $request.ReadWriteTimeout = $TimeoutMilliseconds
        $request.UserAgent = 'FreeSignal/0.1 Network Diagnostic'
        $response = $request.GetResponse()
        $status = [int]$response.StatusCode
        $response.Close()
        $timer.Stop()
        return [ordered]@{ name = $Name; ok = ($status -ge 200 -and $status -lt 500); status = $status; latencyMs = $timer.ElapsedMilliseconds; detail = "HTTP $status" }
    }
    catch {
        $timer.Stop()
        return [ordered]@{ name = $Name; ok = $false; status = 0; latencyMs = $timer.ElapsedMilliseconds; detail = $_.Exception.Message }
    }
}

function Invoke-FSServiceProbes {
    $results = New-Object System.Collections.Generic.List[object]
    $results.Add((Invoke-FSHttpProbe -Name 'Internet' -Uri 'https://www.msftconnecttest.com/connecttest.txt'))
    $results.Add((Invoke-FSHttpProbe -Name 'YouTube' -Uri 'https://www.youtube.com/generate_204'))
    $results.Add((Invoke-FSHttpProbe -Name 'Discord' -Uri 'https://discord.com/api/v10/gateway'))
    $results.Add((Invoke-FSHttpProbe -Name 'Telegram' -Uri 'https://telegram.org/'))
    return @($results)
}

function New-FSDiagnosticResult {
    param([string]$Name, [bool]$Ok, [string]$Detail, [string]$Level = 'info')
    return [ordered]@{ name = $Name; ok = $Ok; detail = $Detail; level = $Level; timestamp = (Get-Date).ToString('o') }
}

function Invoke-FSDiagnostics {
    $results = New-Object System.Collections.Generic.List[object]
    $results.Add((New-FSDiagnosticResult -Name 'Administrator access' -Ok (Test-FSAdministrator) -Detail (if (Test-FSAdministrator) { 'Running with elevated privileges.' } else { 'Administrator privileges are required to load WinDivert.' })))
    $results.Add((New-FSDiagnosticResult -Name 'Windows version' -Ok $true -Detail ([Environment]::OSVersion.VersionString)))
    $installed = Test-FSEngineInstalled
    $results.Add((New-FSDiagnosticResult -Name 'Engine package' -Ok $installed -Detail (if ($installed) { "Installed: $($Script:State.engine.provider) $($Script:State.engine.version)" } else { 'Not installed.' })))

    if ($installed) {
        $driverPath = Join-Path $Script:EngineDirectory 'bin\WinDivert64.sys'
        if (Test-Path -LiteralPath $driverPath) {
            try {
                $signature = Get-AuthenticodeSignature -LiteralPath $driverPath
                $signatureOk = ($signature.Status -eq 'Valid')
                $results.Add((New-FSDiagnosticResult -Name 'WinDivert driver signature' -Ok $signatureOk -Detail ("Status: {0}" -f $signature.Status) -Level (if ($signatureOk) { 'info' } else { 'warning' })))
            }
            catch { $results.Add((New-FSDiagnosticResult -Name 'WinDivert driver signature' -Ok $false -Detail $_.Exception.Message -Level 'warning')) }
        }
        else { $results.Add((New-FSDiagnosticResult -Name 'WinDivert driver' -Ok $false -Detail 'WinDivert64.sys is missing.' -Level 'error')) }
    }

    foreach ($domain in @('youtube.com', 'discord.com', 'telegram.org')) {
        try {
            $addresses = [Net.Dns]::GetHostAddresses($domain)
            $results.Add((New-FSDiagnosticResult -Name ("DNS: $domain") -Ok ($addresses.Count -gt 0) -Detail (($addresses | Select-Object -First 2) -join ', ')))
        }
        catch { $results.Add((New-FSDiagnosticResult -Name ("DNS: $domain") -Ok $false -Detail $_.Exception.Message -Level 'error')) }
    }

    $externalEngines = @(Get-FSForeignEngineProcess)
    $results.Add((New-FSDiagnosticResult -Name 'External zapret processes' -Ok ($externalEngines.Count -eq 0) -Detail (if ($externalEngines.Count) { 'Running process IDs: ' + (($externalEngines | ForEach-Object { $_.Id }) -join ', ') } else { 'No unmanaged winws/winws2 process detected.' }) -Level (if ($externalEngines.Count) { 'warning' } else { 'info' })))
    $zapretService = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    $serviceClear = ($null -eq $zapretService -or $zapretService.Status -eq 'Stopped')
    $results.Add((New-FSDiagnosticResult -Name 'zapret Windows service' -Ok $serviceClear -Detail (if ($null -eq $zapretService) { 'No service installed.' } else { 'Status: ' + $zapretService.Status }) -Level (if ($serviceClear) { 'info' } else { 'warning' })))

    $conflicts = @('goodbyedpi', 'clash', 'sing-box', 'xray', 'warp-svc')
    $activeConflicts = @()
    foreach ($name in $conflicts) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) { $activeConflicts += $name }
    }
    $results.Add((New-FSDiagnosticResult -Name 'Potential network conflicts' -Ok ($activeConflicts.Count -eq 0) -Detail (if ($activeConflicts.Count) { 'Running: ' + ($activeConflicts -join ', ') } else { 'No common conflicting processes detected.' }) -Level (if ($activeConflicts.Count) { 'warning' } else { 'info' })))

    foreach ($probe in (Invoke-FSServiceProbes)) {
        $results.Add((New-FSDiagnosticResult -Name ("Endpoint: $($probe.name)") -Ok $probe.ok -Detail ("$($probe.detail), $($probe.latencyMs) ms") -Level (if ($probe.ok) { 'info' } else { 'warning' })))
    }

    $Script:State.lastDiagnostics = @($results)
    Save-FSState -State $Script:State
    Write-FSLog ('Diagnostics completed: {0}/{1} checks passed.' -f (@($results | Where-Object { $_.ok }).Count), $results.Count)
    return @($results)
}

function Invoke-FSAutoOptimization {
    if (-not (Test-FSEngineInstalled)) { throw 'Install an engine package before automatic optimization.' }
    $baseline = Invoke-FSHttpProbe -Name 'Internet' -Uri 'https://www.msftconnecttest.com/connecttest.txt'
    if (-not $baseline.ok) { throw 'General internet connectivity is unavailable before testing profiles.' }

    $previous = $Script:State.runningProfile
    $scores = New-Object System.Collections.Generic.List[object]
    $candidates = @($Script:Profiles | Where-Object { $_.autoCandidate -eq $true })
    foreach ($profile in $candidates) {
        try {
            Start-FSEngine -ProfileId $profile.id -SkipWatchdog | Out-Null
            Start-Sleep -Seconds 2
            $probes = Invoke-FSServiceProbes
            $internet = $probes | Where-Object { $_.name -eq 'Internet' } | Select-Object -First 1
            if (-not $internet.ok) {
                Stop-FSEngine -PreserveState
                $scores.Add([ordered]@{ profile = $profile.id; ok = $false; score = -100000; passed = 0; latencyMs = 0; reason = 'General connectivity failed.' })
                continue
            }
            $passed = @($probes | Where-Object { $_.ok }).Count
            $latency = ($probes | Measure-Object -Property latencyMs -Sum).Sum
            $score = ($passed * 10000) - [int]$latency
            $scores.Add([ordered]@{ profile = $profile.id; ok = $true; score = $score; passed = $passed; latencyMs = $latency; reason = '' })
        }
        catch {
            $scores.Add([ordered]@{ profile = $profile.id; ok = $false; score = -100000; passed = 0; latencyMs = 0; reason = $_.Exception.Message })
        }
        finally {
            Stop-FSEngine -PreserveState
        }
    }

    $winner = $scores | Where-Object { $_.ok } | Sort-Object -Property score -Descending | Select-Object -First 1
    if ($null -eq $winner) {
        if ($previous) { try { Start-FSEngine -ProfileId $previous | Out-Null } catch {} }
        throw 'No tested profile preserved general connectivity.'
    }
    Start-FSEngine -ProfileId $winner.profile | Out-Null
    $Script:State.lastOptimization = @($scores)
    Save-FSState -State $Script:State
    Write-FSLog ('Automatic optimization selected {0} with score {1}.' -f $winner.profile, $winner.score)
    return [ordered]@{ winner = $winner; results = @($scores) }
}

function Set-FSAutoStart {
    param([Parameter(Mandatory = $true)][bool]$Enabled)
    $taskName = 'FreeSignal AutoStart'
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $rootFolder = $scheduler.GetFolder('\')
    if ($Enabled) {
        $task = $scheduler.NewTask(0)
        $task.RegistrationInfo.Description = 'Starts the user-selected FreeSignal profile after sign-in.'
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $task.Principal.UserId = $currentUser
        $task.Principal.RunLevel = 1
        $task.Settings.Enabled = $true
        $task.Settings.StartWhenAvailable = $true
        $task.Settings.DisallowStartIfOnBatteries = $false
        $task.Settings.StopIfGoingOnBatteries = $false
        $task.Settings.ExecutionTimeLimit = 'PT0S'
        $trigger = $task.Triggers.Create(9)
        $trigger.UserId = $currentUser
        $action = $task.Actions.Create(0)
        $action.Path = (Join-Path $PSHOME 'powershell.exe')
        $action.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AutoStart' -f $PSCommandPath
        $action.WorkingDirectory = $Script:Root
        [void]$rootFolder.RegisterTaskDefinition($taskName, $task, 6, $currentUser, $null, 3, $null)
    }
    else {
        try { $rootFolder.DeleteTask($taskName, 0) } catch { }
    }
    $Script:State.autoStart = $Enabled
    Save-FSState -State $Script:State
    Write-FSLog (if ($Enabled) { 'Auto-start task enabled.' } else { 'Auto-start task disabled.' })
}

function Export-FSSupportReport {
    $destination = Join-Path ([Environment]::GetFolderPath('Desktop')) ('FreeSignal-support-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $report = [ordered]@{
        generatedAt = (Get-Date).ToString('o')
        appVersion = $Script:Version
        operatingSystem = [Environment]::OSVersion.VersionString
        administrator = Test-FSAdministrator
        engineInstalled = Test-FSEngineInstalled
        engineRunning = Test-FSEngineRunning
        engine = $Script:State.engine
        selectedProfile = $Script:State.selectedProfile
        lastDiagnostics = $Script:State.lastDiagnostics
        lastOptimization = $Script:State.lastOptimization
        note = 'This report intentionally excludes browsing history, packet payloads and domain lists.'
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $destination -Encoding UTF8
    Write-FSLog ('Support report exported to {0}' -f $destination)
    return $destination
}

function Invoke-FSSelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($xamlCandidate in @($Script:XamlPath, $Script:RussianXamlPath)) {
        try { [xml](Get-Content -LiteralPath $xamlCandidate -Raw -Encoding UTF8) | Out-Null }
        catch { $failures.Add(([IO.Path]::GetFileName($xamlCandidate)) + ': ' + $_.Exception.Message) }
    }

    try {
        $profiles = Get-FSProfiles
        $ids = @($profiles | ForEach-Object { $_.id })
        if ($profiles.Count -lt 4) { $failures.Add('At least four profiles are required.') }
        if (($ids | Select-Object -Unique).Count -ne $ids.Count) { $failures.Add('Profile IDs must be unique.') }
        foreach ($profile in $profiles) {
            if (-not $profile.id -or -not $profile.name -or -not $profile.strategyFile) { $failures.Add('Every profile requires id, name and strategyFile.') }
            if ([IO.Path]::GetExtension([string]$profile.strategyFile) -ne '.bat') { $failures.Add("Profile $($profile.id) must point to a BAT strategy.") }
        }
    }
    catch { $failures.Add('profiles.json: ' + $_.Exception.Message) }

    try {
        $sources = Get-Content -LiteralPath $Script:SourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($sources.sources).Count -lt 3) { $failures.Add('Three engine sources/adapters are required.') }
        $flowseal = @($sources.sources | Where-Object { $_.id -eq 'flowseal' })
        if ($flowseal.Count -ne 1 -or -not $flowseal[0].allowedDownloadPrefix) { $failures.Add('Flowseal source requires a pinned download prefix.') }
    }
    catch { $failures.Add('engine-sources.json: ' + $_.Exception.Message) }

    try {
        $fixture = Join-Path $Script:DataDirectory 'selftest-strategy.bat'
        @(
            '@echo off',
            'call service.bat status_zapret',
            'set "BIN=C:\ignored\"',
            'start "zapret: fixture" /min "%BIN%winws.exe" --wf-tcp=443 ^',
            '--filter-tcp=443 --dpi-desync=multisplit'
        ) | Set-Content -LiteralPath $fixture -Encoding UTF8
        $runtime = New-FSRuntimeStrategy -StrategyPath $fixture -ProfileId 'selftest'
        $runtimeText = Get-Content -LiteralPath $runtime -Raw -Encoding UTF8
        if ($runtimeText -match '(?i)service\.bat|netsh|powershell') { $failures.Add('Sanitized runtime strategy retained a forbidden service hook.') }
        if ($runtimeText -notmatch '(?i)winws\.exe') { $failures.Add('Sanitized runtime strategy lost the winws command.') }
        Remove-Item -LiteralPath $fixture, $runtime -Force -ErrorAction SilentlyContinue
    }
    catch { $failures.Add('strategy sanitizer: ' + $_.Exception.Message) }

    $result = [ordered]@{
        ok = ($failures.Count -eq 0)
        version = $Script:Version
        profiles = @($Script:Profiles).Count
        failures = @($failures)
    }
    $result | ConvertTo-Json -Depth 5
    if ($failures.Count -gt 0) { exit 1 }
    exit 0
}

function Show-FSMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = 'FreeSignal',
        [ValidateSet('Info', 'Warning', 'Error')][string]$Type = 'Info'
    )
    $icon = switch ($Type) {
        'Warning' { [System.Windows.MessageBoxImage]::Warning }
        'Error' { [System.Windows.MessageBoxImage]::Error }
        default { [System.Windows.MessageBoxImage]::Information }
    }
    [System.Windows.MessageBox]::Show($Script:Window, $Message, $Title, [System.Windows.MessageBoxButton]::OK, $icon) | Out-Null
}

function Confirm-FSAction {
    param([Parameter(Mandatory = $true)][string]$Message, [string]$Title = 'FreeSignal')
    return ([System.Windows.MessageBox]::Show($Script:Window, $Message, $Title, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -eq [System.Windows.MessageBoxResult]::Yes)
}

function Set-FSBusy {
    param([bool]$Visible, [string]$Title = 'Working', [string]$Description = 'Please keep FreeSignal open.')
    if (-not $Script:Ui.ContainsKey('BusyOverlay')) { return }
    $Script:Ui.BusyTitle.Text = $Title
    $Script:Ui.BusyDescription.Text = $Description
    $Script:Ui.BusyOverlay.Visibility = if ($Visible) { 'Visible' } else { 'Collapsed' }
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Invoke-FSUiAction {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$BusyTitle = 'Working',
        [string]$BusyDescription = 'Please keep FreeSignal open.',
        [switch]$Refresh
    )
    Set-FSBusy -Visible $true -Title $BusyTitle -Description $BusyDescription
    try {
        & $Action
    }
    catch {
        Write-FSLog -Level 'ERROR' -Message $_.Exception.ToString()
        Show-FSMessage -Message $_.Exception.Message -Title 'FreeSignal error' -Type 'Error'
    }
    finally {
        Set-FSBusy -Visible $false
        if ($Refresh) { Refresh-FSUi }
    }
}

function Set-FSStatusVisual {
    param([bool]$Running)
    $accent = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#B6FF00'))
    $muted = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#565656'))
    if ($Running) {
        $Script:Ui.HeroStatusDot.Fill = $accent
        $Script:Ui.SidebarStatusDot.Fill = $accent
        $Script:Ui.HeroStatusText.Text = Get-FSText -English 'CONNECTION ACTIVE' -Russian 'ДОСТУП ВКЛЮЧЁН'
        $Script:Ui.HeroStatusDescription.Text = Get-FSText -English 'The selected local strategy is running. Traffic remains direct and the watchdog is monitoring general connectivity.' -Russian 'Выбранная локальная стратегия запущена. Трафик идёт напрямую, а защитный контроль проверяет общую доступность интернета.'
        $Script:Ui.MainToggleButton.Content = Get-FSText -English 'DISABLE CONNECTION' -Russian 'ВЫКЛЮЧИТЬ ДОСТУП'
        $Script:Ui.SidebarStatus.Text = Get-FSText -English 'ENGINE ACTIVE' -Russian 'ДВИЖОК АКТИВЕН'
        $Script:Ui.WatchdogText.Text = Get-FSText -English 'Monitoring' -Russian 'Контроль активен'
    }
    else {
        $Script:Ui.HeroStatusDot.Fill = $muted
        $Script:Ui.SidebarStatusDot.Fill = $muted
        $Script:Ui.HeroStatusText.Text = Get-FSText -English 'DISCONNECTED' -Russian 'ОТКЛЮЧЕНО'
        $Script:Ui.HeroStatusDescription.Text = if (Test-FSEngineInstalled) { Get-FSText -English 'Choose a profile and enable the local engine. No network settings are changed while disabled.' -Russian 'Выберите профиль и включите локальный движок. В отключённом состоянии FreeSignal не меняет сетевые настройки.' } else { Get-FSText -English 'Install the official engine package, then choose a profile or run automatic optimization.' -Russian 'Установите официальный пакет движка, затем выберите профиль или запустите автоматический подбор.' }
        $Script:Ui.MainToggleButton.Content = Get-FSText -English 'ENABLE CONNECTION' -Russian 'ВКЛЮЧИТЬ ДОСТУП'
        $Script:Ui.SidebarStatus.Text = Get-FSText -English 'ENGINE OFFLINE' -Russian 'ДВИЖОК ВЫКЛЮЧЕН'
        $Script:Ui.WatchdogText.Text = Get-FSText -English 'Standby' -Russian 'Ожидание'
    }
}

function Set-FSProbeUi {
    param([string]$Name, [string]$StatusName, [string]$DetailName)
    $entry = @($Script:State.lastDiagnostics | Where-Object { $_.name -eq "Endpoint: $Name" } | Select-Object -Last 1)
    if ($entry.Count -eq 0) {
        $Script:Ui[$StatusName].Text = Get-FSText -English 'Not checked' -Russian 'Не проверено'
        $Script:Ui[$DetailName].Text = Get-FSText -English 'Run diagnostics' -Russian 'Запустите диагностику'
        return
    }
    $item = $entry[0]
    $Script:Ui[$StatusName].Text = if ($item.ok) { Get-FSText -English 'Available' -Russian 'Доступен' } else { Get-FSText -English 'Unavailable' -Russian 'Недоступен' }
    $Script:Ui[$DetailName].Text = $item.detail
    $Script:Ui[$StatusName].Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString((if ($item.ok) { '#B6FF00' } else { '#FF7A7A' })))
}

function Refresh-FSUi {
    $running = Test-FSEngineRunning
    Set-FSStatusVisual -Running $running
    $profile = Get-FSProfile -Id $Script:State.selectedProfile
    $Script:Ui.ActiveProfileText.Text = if ($profile) { Get-FSProfileDisplayName -Profile $profile } else { $Script:State.selectedProfile }
    $Script:Ui.EngineProviderText.Text = if (Test-FSEngineInstalled) { "$($Script:State.engine.provider) $($Script:State.engine.version)" } else { Get-FSText -English 'Not installed' -Russian 'Не установлен' }
    $Script:Ui.SidebarVersion.Text = if (Test-FSEngineInstalled) { "$($Script:State.engine.provider) · $($Script:State.engine.version)" } else { Get-FSText -English 'No engine installed' -Russian 'Движок не установлен' }
    $Script:Ui.SettingsEngineText.Text = if (Test-FSEngineInstalled) { "$($Script:State.engine.provider) $($Script:State.engine.version) · SHA256 $(([string]$Script:State.engine.packageSha256).Substring(0, [Math]::Min(12, ([string]$Script:State.engine.packageSha256).Length)))…" } else { Get-FSText -English 'No package installed' -Russian 'Пакет не установлен' }
    $Script:Ui.AutoStartCheck.IsChecked = [bool]$Script:State.autoStart
    Set-FSProbeUi -Name 'YouTube' -StatusName 'YouTubeStatus' -DetailName 'YouTubeDetail'
    Set-FSProbeUi -Name 'Discord' -StatusName 'DiscordStatus' -DetailName 'DiscordDetail'
    Set-FSProbeUi -Name 'Internet' -StatusName 'InternetStatus' -DetailName 'InternetDetail'
}

function Show-FSPage {
    param([Parameter(Mandatory = $true)][string]$Name)
    $pageNames = @('Home', 'Profiles', 'Diagnostics', 'Domains', 'Logs', 'Settings')
    foreach ($pageName in $pageNames) {
        $Script:Ui[$pageName + 'Page'].Visibility = if ($pageName -eq $Name) { 'Visible' } else { 'Collapsed' }
        $Script:Ui['Nav' + $pageName].Tag = if ($pageName -eq $Name) { 'active' } else { '' }
    }
    if ($Name -eq 'Logs') { Refresh-FSLogs }
    if ($Name -eq 'Domains') { Load-FSDomainEditors }
    if ($Name -eq 'Settings') { Refresh-FSUi }
}

function Load-FSDomainEditors {
    $Script:Ui.IncludeDomainsText.Text = Get-FSUserListText -Kind 'include'
    $Script:Ui.ExcludeDomainsText.Text = Get-FSUserListText -Kind 'exclude'
}

function Refresh-FSLogs {
    if (Test-Path -LiteralPath $Script:LogPath) {
        $lines = Get-Content -LiteralPath $Script:LogPath -Tail 500 -Encoding UTF8
        $Script:Ui.LogsText.Text = $lines -join "`r`n"
        $Script:Ui.LogsText.ScrollToEnd()
    }
    else { $Script:Ui.LogsText.Text = 'No local activity has been logged yet.' }
}

function Render-FSDiagnostics {
    param([Parameter(Mandatory = $true)]$Results)
    $Script:Ui.DiagnosticsList.Items.Clear()
    foreach ($item in $Results) {
        $prefix = if ($item.ok) { '[PASS]' } elseif ($item.level -eq 'warning') { '[WARN]' } else { '[FAIL]' }
        [void]$Script:Ui.DiagnosticsList.Items.Add(("{0}  {1} — {2}" -f $prefix, $item.name, $item.detail))
    }
    $passed = @($Results | Where-Object { $_.ok }).Count
    $Script:Ui.DiagnosticsSummary.Text = "$passed of $($Results.Count) checks passed. Review warnings before enabling aggressive profiles."
}

function Handle-FSRollbackMarker {
    $rollbackPath = Join-Path $Script:DataDirectory 'rollback.json'
    if (-not (Test-Path -LiteralPath $rollbackPath)) { return }
    try {
        $rollback = Get-Content -LiteralPath $rollbackPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Remove-Item -LiteralPath $rollbackPath -Force
        $Script:State.runningProfile = ''
        $Script:State.lastRollback = ConvertTo-FSHashtable $rollback
        Save-FSState -State $Script:State
        Write-FSLog -Level 'SECURITY' -Message ('Watchdog rollback: {0}' -f $rollback.reason)
        Show-FSMessage -Title 'Automatic safety rollback' -Type 'Warning' -Message 'FreeSignal disabled the engine because general internet connectivity failed repeatedly. Open Diagnostics before trying another profile.'
    }
    catch { Remove-Item -LiteralPath $rollbackPath -Force -ErrorAction SilentlyContinue }
}

function Select-FSProfileFromUi {
    param([Parameter(Mandatory = $true)][string]$ProfileId)
    $profile = Get-FSProfile -Id $ProfileId
    if ($null -eq $profile) { return }
    $wasRunning = Test-FSEngineRunning
    $Script:State.selectedProfile = $ProfileId
    Save-FSState -State $Script:State
    if ($wasRunning) {
        Invoke-FSUiAction -BusyTitle 'Switching profile' -BusyDescription ("Applying $($profile.name) and starting the watchdog.") -Refresh -Action { Start-FSEngine -ProfileId $ProfileId | Out-Null }
    }
    else {
        Refresh-FSUi
        Show-FSPage -Name 'Home'
    }
}

function Initialize-FSWindow {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms

    $selectedXamlPath = if ((Get-FSEffectiveLanguage) -eq 'ru' -and (Test-Path -LiteralPath $Script:RussianXamlPath)) { $Script:RussianXamlPath } else { $Script:XamlPath }
    [xml]$xaml = Get-Content -LiteralPath $selectedXamlPath -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Script:Window = [Windows.Markup.XamlReader]::Load($reader)
    $iconPath = Join-Path $Script:Root 'assets\freesignal.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $icon = New-Object Windows.Media.Imaging.BitmapImage
        $icon.BeginInit()
        $icon.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $icon.UriSource = New-Object Uri($iconPath)
        $icon.EndInit()
        $Script:Window.Icon = $icon
    }

    $names = @(
        'TitleBar','MinimizeButton','CloseButton','NavHome','NavProfiles','NavDiagnostics','NavDomains','NavLogs','NavSettings',
        'HomePage','ProfilesPage','DiagnosticsPage','DomainsPage','LogsPage','SettingsPage','BusyOverlay','BusyTitle','BusyDescription',
        'SidebarStatusDot','SidebarStatus','SidebarVersion','EmergencyStopButton','HeroStatusDot','HeroStatusText','HeroStatusDescription',
        'MainToggleButton','AutoOptimizeButton','ActiveProfileText','EngineProviderText','WatchdogText','YouTubeStatus','YouTubeDetail',
        'DiscordStatus','DiscordDetail','InternetStatus','InternetDetail','ProfileBalanced','ProfileCompatibility','ProfileAggressive',
        'ProfileSimple','ProfileExperimental','RunDiagnosticsButton','DiagnosticsSummary','DiagnosticsList','IncludeDomainsText',
        'ExcludeDomainsText','ReloadDomainsButton','SaveDomainsButton','LogsText','OpenLogsButton','RefreshLogsButton','SettingsEngineText',
        'InstallEngineButton','ImportEngineButton','RemoveEngineButton','AutoStartCheck','OpenDataButton','ExportReportButton','LanguageCombo'
    )
    foreach ($name in $names) { $Script:Ui[$name] = $Script:Window.FindName($name) }
    $languageIndexes = @{ auto = 0; ru = 1; en = 2 }
    $languagePreference = [string]$Script:State.language
    $Script:Ui.LanguageCombo.SelectedIndex = $(if ($languageIndexes.ContainsKey($languagePreference)) { $languageIndexes[$languagePreference] } else { 0 })
    $Script:Ui.LanguageCombo.Add_SelectionChanged({
        $values = @('auto', 'ru', 'en')
        $selectedIndex = [int]$Script:Ui.LanguageCombo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $values.Count) { return }
        $Script:State.language = $values[$selectedIndex]
        Save-FSState -State $Script:State
        Show-FSMessage -Message (Get-FSText -English 'The interface language will change after FreeSignal is restarted.' -Russian 'Язык интерфейса изменится после перезапуска FreeSignal.')
    })

    $Script:Ui.TitleBar.Add_MouseLeftButtonDown({
        $eventArgs = $args[1]
        if ($eventArgs.ClickCount -eq 2) {
            $Script:Window.WindowState = if ($Script:Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
        }
        else { $Script:Window.DragMove() }
    })
    $Script:Ui.MinimizeButton.Add_Click({ $Script:Window.WindowState = 'Minimized' })
    $Script:Ui.CloseButton.Add_Click({ $Script:Window.Close() })

    foreach ($pageName in @('Home','Profiles','Diagnostics','Domains','Logs','Settings')) {
        $captured = $pageName
        $Script:Ui['Nav' + $pageName].Add_Click({ Show-FSPage -Name $captured }.GetNewClosure())
    }

    $Script:Ui.EmergencyStopButton.Add_Click({
        Invoke-FSUiAction -BusyTitle 'Stopping immediately' -BusyDescription 'Emergency stop terminates all winws/winws2 processes and the FreeSignal watchdog.' -Refresh -Action { Stop-FSEngine -Emergency }
    })
    $Script:Ui.MainToggleButton.Add_Click({
        if (Test-FSEngineRunning) {
            Invoke-FSUiAction -BusyTitle 'Disabling connection' -BusyDescription 'Stopping the local engine and watchdog.' -Refresh -Action { Stop-FSEngine }
        }
        elseif (-not (Test-FSEngineInstalled)) {
            Show-FSPage -Name 'Settings'
            Show-FSMessage -Message 'Install the official engine package before enabling a profile.' -Type 'Warning'
        }
        else {
            $profileId = [string]$Script:State.selectedProfile
            Invoke-FSUiAction -BusyTitle 'Enabling connection' -BusyDescription 'Starting the selected local strategy and safety watchdog.' -Refresh -Action { Start-FSEngine -ProfileId $profileId | Out-Null }
        }
    })
    $Script:Ui.AutoOptimizeButton.Add_Click({
        Invoke-FSUiAction -BusyTitle 'Testing safe profiles' -BusyDescription 'FreeSignal will switch profiles several times, verify general connectivity and keep the best result.' -Refresh -Action {
            $result = Invoke-FSAutoOptimization
            $winnerProfile = Get-FSProfile -Id $result.winner.profile
            Show-FSMessage -Message ("Automatic optimization selected {0}. Passed endpoints: {1}; aggregate latency: {2} ms." -f $winnerProfile.name, $result.winner.passed, $result.winner.latencyMs)
        }
    })

    $Script:Ui.ProfileBalanced.Add_Click({ Select-FSProfileFromUi -ProfileId 'balanced' })
    $Script:Ui.ProfileCompatibility.Add_Click({ Select-FSProfileFromUi -ProfileId 'compatibility' })
    $Script:Ui.ProfileAggressive.Add_Click({ Select-FSProfileFromUi -ProfileId 'aggressive' })
    $Script:Ui.ProfileSimple.Add_Click({ Select-FSProfileFromUi -ProfileId 'simple' })
    $Script:Ui.ProfileExperimental.Add_Click({
        if (Confirm-FSAction -Message 'The experimental profile may affect unrelated traffic. Continue?') { Select-FSProfileFromUi -ProfileId 'experimental' }
    })

    $Script:Ui.RunDiagnosticsButton.Add_Click({
        Invoke-FSUiAction -BusyTitle 'Running diagnostics' -BusyDescription 'Checking engine integrity, DNS, endpoints and common conflicts.' -Action {
            $results = Invoke-FSDiagnostics
            Render-FSDiagnostics -Results $results
            Refresh-FSUi
        }
    })
    $Script:Ui.ReloadDomainsButton.Add_Click({ Load-FSDomainEditors })
    $Script:Ui.SaveDomainsButton.Add_Click({
        Invoke-FSUiAction -BusyTitle 'Saving domain lists' -BusyDescription 'Normalizing entries and synchronizing them with the installed engine.' -Action {
            $result = Save-FSUserLists -IncludeText $Script:Ui.IncludeDomainsText.Text -ExcludeText $Script:Ui.ExcludeDomainsText.Text
            Load-FSDomainEditors
            Show-FSMessage -Message ("Saved $($result.include) included and $($result.exclude) excluded domains.")
        }
    })
    $Script:Ui.RefreshLogsButton.Add_Click({ Refresh-FSLogs })
    $Script:Ui.OpenLogsButton.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $Script:LogDirectory) | Out-Null })

    $Script:Ui.InstallEngineButton.Add_Click({
        Invoke-FSUiAction -BusyTitle 'Installing official engine' -BusyDescription 'Downloading the latest ZIP directly from Flowseal GitHub Releases, calculating SHA256 and validating its structure.' -Refresh -Action {
            $result = Install-FSLatestFlowsealEngine
            Show-FSMessage -Message ("Installed engine $($result.version).`nSHA256: $($result.sha256)")
        }
    })
    $Script:Ui.ImportEngineButton.Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = 'Select an official zapret ZIP package'
        $dialog.Filter = 'ZIP archives (*.zip)|*.zip'
        if ($dialog.ShowDialog($Script:Window)) {
            $selectedPath = $dialog.FileName
            Invoke-FSUiAction -BusyTitle 'Importing engine package' -BusyDescription 'Calculating SHA256, validating the expected layout and preserving user lists.' -Refresh -Action {
                $hash = Import-FSEngineArchive -ArchivePath $selectedPath
                Show-FSMessage -Message ("Engine package imported successfully.`nSHA256: $hash")
            }
        }
    })
    $Script:Ui.RemoveEngineButton.Add_Click({
        if (Confirm-FSAction -Message 'Remove the local engine package? FreeSignal settings and logs will be preserved.') {
            Invoke-FSUiAction -BusyTitle 'Removing engine' -BusyDescription 'Stopping local processes and deleting the imported engine package.' -Refresh -Action { Remove-FSEnginePackage }
        }
    })
    $Script:Ui.AutoStartCheck.Add_Click({
        $desired = [bool]$Script:Ui.AutoStartCheck.IsChecked
        try { Set-FSAutoStart -Enabled $desired }
        catch { $Script:Ui.AutoStartCheck.IsChecked = -not $desired; Show-FSMessage -Message $_.Exception.Message -Type 'Error' }
    })
    $Script:Ui.OpenDataButton.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $Script:DataDirectory) | Out-Null })
    $Script:Ui.ExportReportButton.Add_Click({
        try { $path = Export-FSSupportReport; Show-FSMessage -Message ("Support report exported to:`n$path") }
        catch { Show-FSMessage -Message $_.Exception.Message -Type 'Error' }
    })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(3)
    $timer.Add_Tick({ Handle-FSRollbackMarker; Refresh-FSUi })
    $timer.Start()

    Load-FSDomainEditors
    Refresh-FSUi
    Show-FSPage -Name 'Home'
    [void]$Script:Window.ShowDialog()
}

Initialize-FSDirectories
$Script:Profiles = Get-FSProfiles
$Script:State = Get-FSState

if ($SelfTest) { Invoke-FSSelfTest }

if ($SafeMode) {
    if (-not (Test-FSAdministrator)) { Restart-FSAsAdministrator; exit 0 }
    Stop-FSEngine -Emergency:$Emergency
    Write-Output $(if ($Emergency) { 'FreeSignal emergency mode: all winws/winws2 processes and watchdog stopped.' } else { 'FreeSignal safe mode: managed engine and watchdog stopped.' })
    exit 0
}

if ($AutoStart) {
    if (-not (Test-FSAdministrator)) { Restart-FSAsAdministrator; exit 0 }
    try {
        if (Test-FSEngineInstalled) { Start-FSEngine -ProfileId ([string]$Script:State.selectedProfile) | Out-Null }
    }
    catch { Write-FSLog -Level 'ERROR' -Message ('Auto-start failed: {0}' -f $_.Exception.Message); exit 1 }
    exit 0
}

if (-not (Test-FSAdministrator)) {
    Restart-FSAsAdministrator
    exit 0
}

try {
    Write-FSLog ('FreeSignal {0} UI started.' -f $Script:Version)
    Initialize-FSWindow
}
catch {
    Write-FSLog -Level 'ERROR' -Message $_.Exception.ToString()
    try { [System.Windows.MessageBox]::Show("FreeSignal could not start.`n`n$($_.Exception.Message)", 'FreeSignal', 'OK', 'Error') | Out-Null } catch { Write-Error $_ }
    exit 1
}
