<p align="center">
  <img src="assets/freesignal-banner.svg" width="100%" alt="FreeSignal — local anti-DPI connection manager">
</p>

<p align="center">
  <strong>One clear control surface for the zapret ecosystem.</strong>
</p>

<p align="center">
  <a href="https://github.com/richmanstudio/freesignal/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/richmanstudio/freesignal/ci.yml?style=flat-square&label=CI&color=B6FF00&labelColor=080808" alt="CI"></a>
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-B6FF00?style=flat-square&labelColor=080808" alt="Windows 10 and 11">
  <img src="https://img.shields.io/badge/telemetry-none-B6FF00?style=flat-square&labelColor=080808" alt="No telemetry">
  <img src="https://img.shields.io/badge/client_license-MIT-B6FF00?style=flat-square&labelColor=080808" alt="MIT client license">
</p>

FreeSignal is an open-source Windows control client for installing, diagnosing and operating compatible **zapret** anti-DPI engine packages without forcing ordinary users to work with long command lines and dozens of batch files.

It is **not a VPN or hosted proxy**. FreeSignal does not run traffic relay servers, change the user's public IP, collect browsing history or create an account.

<p align="center">
  <img src="assets/dashboard-preview.svg" width="100%" alt="FreeSignal desktop dashboard preview">
</p>

## MVP capabilities

- Modern WPF desktop interface for Windows 10 and 11.
- Automatic Russian/English interface selection with a saved language preference.
- Console-free `FreeSignal.vbs` launcher and branded Windows icon.
- One-button enable/disable and independent emergency stop.
- Direct installation from the official Flowseal GitHub Releases API.
- Manual ZIP import for auditable/offline package workflows.
- SHA-256 fingerprint for every downloaded or imported archive.
- ZIP path-traversal, entry-count and expanded-size validation before extraction.
- Atomic package update with one retained rollback copy.
- Human-readable profiles mapped to visible strategy files.
- Sanitized runtime wrapper that extracts only the `winws.exe` launch block and never invokes the package service menu.
- Managed-process ownership: ordinary stop/watchdog actions never terminate another tool's `winws` process.
- Automatic profile benchmark with a general-connectivity safety gate.
- Separate watchdog process that stops the engine after repeated connectivity failure.
- DNS, service endpoint, driver signature and conflict diagnostics.
- User include/exclude domain lists.
- Visible Windows scheduled-task auto-start.
- Local operational logs and privacy-preserving support report.
- No telemetry, advertisement SDK or automatic antivirus exclusions.

## Quick start

Requirements:

- Windows 10 or Windows 11 x64;
- Windows PowerShell 5.1 or newer;
- administrator access for the packet-diversion driver.

```powershell
git clone https://github.com/richmanstudio/freesignal.git
cd freesignal
.\FreeSignal.vbs
```

`FreeSignal.cmd` remains available for troubleshooting from a terminal.

On the first launch:

1. Open **Settings**.
2. Select **Install / Update**.
3. Review the downloaded release version and SHA-256 fingerprint.
4. Return to **Overview** and select **Enable connection**.
5. Use **Auto optimize** when the default Balanced profile is not effective.

FreeSignal downloads the engine package directly from the repository declared in `app/engine-sources.json`. No DUONIQ server is involved.

## Profiles

| Profile | Purpose | Risk |
| --- | --- | --- |
| Balanced | Recommended daily YouTube/Discord/general profile | Low |
| Compatibility | Conservative alternative for provider-specific issues | Low |
| Aggressive | Stronger strategy for difficult DPI configurations | Medium |
| Simple Fake | Minimal strategy with fewer moving parts | Low |
| Experimental | Newest imported community strategy | High |

Profiles reference files in the installed package, such as `general.bat` or `general (ALT12).bat`. FreeSignal never modifies the source strategy. At runtime it validates the file, extracts only its continued `winws.exe` command block, substitutes local package paths and writes a temporary wrapper. Calls to `service.bat`, update checks and unrelated shell commands are excluded.

## Safety model

FreeSignal is a privileged network utility, so the project uses explicit guardrails:

```text
profile start
    ↓
validate and sanitize winws command
    ↓
record owned process ID + start time
    ↓
start independent watchdog
    ↓
probe general connectivity
    ↓ repeated failure
stop only FreeSignal-owned process and show rollback warning
```

The client never:

- disables Microsoft Defender or another antivirus;
- adds security exclusions;
- installs a hidden remote-control service;
- executes the imported package's service menu or update-check hooks;
- modifies Windows proxy or firewall rules;
- logs packet bodies or the URLs a user visits;
- downloads executable scripts from an arbitrary URL.

See [Threat model](docs/THREAT_MODEL.md) and [Security policy](SECURITY.md).

## Engine ecosystem

FreeSignal is independent from the projects it can orchestrate:

| Component | Role | License |
| --- | --- | --- |
| `bol-van/zapret` | Original anti-DPI engine | MIT |
| `bol-van/zapret2` | Next-generation programmable engine | MIT |
| `Flowseal/zapret-discord-youtube` | Windows strategies and distribution | MIT |
| WinDivert | Windows packet diversion driver | LGPL v3 or GPL v2 / commercial option |

The source repository does not bundle those binaries. Redistribution of a combined release must preserve all relevant third-party notices and license obligations. See [Third-party notices](THIRD_PARTY_NOTICES.md).

## Repository structure

```text
FreeSignal.ps1             application logic and WPF event wiring
FreeSignal.vbs             console-free desktop launcher
FreeSignal.cmd             terminal/troubleshooting launcher
FreeSignal-SafeMode.cmd    explicit emergency stop for all winws processes
app/MainWindow.xaml        English desktop interface
app/MainWindow.ru.xaml     Russian desktop interface
app/Watchdog.ps1           connectivity rollback process
app/profiles.json          human-readable strategy mapping
app/engine-sources.json    explicit engine adapter sources
installer/                 install and uninstall scripts
tests/                     syntax, metadata and safety checks
docs/                      architecture, threat model and release process
```

## Install to Program Files

From an elevated PowerShell terminal:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\installer\Install.ps1
```

Uninstall while preserving user data:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:ProgramFiles\FreeSignal\installer\Uninstall.ps1"
```

The portable release also works directly from an extracted folder.

## Validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\StaticTests.ps1
node .\tests\test_profiles.mjs
```

CI parses the PowerShell AST and both XAML interfaces on Windows, runs the sanitizer self-test, validates profile metadata on Node.js, and produces a portable release ZIP with an internal file manifest and external SHA-256 checksum. See the [Windows test matrix](docs/TEST_MATRIX.md).

## Current MVP boundaries

- Windows x64 only.
- Automatic package installation currently targets the Flowseal-compatible layout.
- Original zapret and zapret 2 are declared as manual adapter targets until stable Windows package-layout contracts are finalized.
- The automatic adapter currently disables Flowseal GameFilter expansion (`GameFilter*=12`) to avoid unexpectedly intercepting broad game-port ranges.
- HTTP probes cannot fully validate Discord voice or every QUIC path; they provide a practical first-pass health signal.
- The source has not yet been code-signed. Windows may display a publisher warning for release scripts.

These limitations are explicit. FreeSignal does not claim that one strategy works for every provider.

## Roadmap

- Signed DUONIQ engine manifest with pinned third-party hashes.
- Native service broker with a restricted IPC protocol.
- Windows installer signing and reproducible builds.
- Dedicated Discord voice/STUN and QUIC diagnostics.
- Community strategy registry with review, provenance and compatibility scoring.
- zapret 2 Lua profile adapter.
- Windows ARM64.
- English and Russian interface localization.

## Attribution

FreeSignal is built by **DUONIQ** and stands on years of work by the zapret, Flowseal and WinDivert maintainers. It is not affiliated with Discord, Google, YouTube, Telegram, Microsoft or an internet provider.

```text
DIRECT ACCESS / ZERO RELAY / LOCAL CONTROL
```
