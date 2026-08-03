# Changelog

## 0.1.1 — Windows launcher fix

- Fixed startup failure where Windows PowerShell 5.1 treated inline `if` blocks as commands.
- Replaced unsupported inline condition syntax across UI, diagnostics, domain lists and auto-start logging.
- Rebuilt `FreeSignal.vbs` with explicit Windows PowerShell path, STA mode, safe quoting and error handling.
- Added a real `cscript.exe FreeSignal.vbs --self-test` CI regression test.
- Kept UTF-8 BOM compatibility for Cyrillic source under Windows PowerShell 5.1.
- Excluded CI workflows, tests and temporary trigger files from portable release archives.

## 0.1.0 — MVP

- Added Windows WPF desktop client in the DUONIQ visual language.
- Added direct installation from official Flowseal GitHub Releases.
- Added manual ZIP import with SHA-256 fingerprinting and layout validation.
- Added atomic engine replacement with one local rollback copy.
- Added Balanced, Compatibility, Aggressive, Simple Fake and Experimental profiles.
- Added automatic profile benchmarking with general-connectivity protection.
- Added independent watchdog and emergency stop.
- Added endpoint, DNS, driver-signature and conflict diagnostics.
- Added include/exclude domain editors.
- Added Windows scheduled-task auto-start.
- Added local operational logs and privacy-preserving support report.
- Added installer, uninstaller, CI and release packaging scripts.
