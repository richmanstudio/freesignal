# Contributing to FreeSignal

FreeSignal should remain understandable to non-technical users and auditable by security-conscious users.

## Requirements

- Windows 10 or 11 for the WPF interface and engine integration.
- Windows PowerShell 5.1 or newer.
- Node.js 20+ for repository metadata tests.

## Checks

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\StaticTests.ps1
node .\tests\test_profiles.mjs
```

## Rules

- Never add code that disables antivirus, firewall or Windows security features.
- Never add hidden telemetry or remote command execution.
- Do not log URLs visited by the user or packet content.
- Downloads must use explicit allow-listed repositories and visible HTTPS URLs.
- Keep emergency stop independent from the main UI.
- Changes to engine startup, updater or watchdog logic require tests and threat-model review.
- Preserve third-party attribution and license notices.

## Pull requests

Explain the user problem, technical approach, safety impact and validation performed. UI changes should include a screenshot at 100% scaling and at least one test at 125% scaling.
