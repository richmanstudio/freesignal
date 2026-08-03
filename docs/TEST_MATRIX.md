# Windows MVP test matrix

The release candidate must be exercised on clean virtual machines before a signed public installer is published.

| Area | Windows 10 x64 | Windows 11 x64 | Expected result |
| --- | --- | --- | --- |
| Portable launch | Required | Required | UAC appears once; WPF window opens without a console window |
| RU/EN interface | Required | Required | System-language selection works; manual preference applies after restart |
| Official engine install | Required | Required | GitHub asset URL is allow-listed; ZIP is validated; SHA-256 is stored |
| Manual ZIP import | Required | Required | Valid Flowseal layout imports; traversal/oversize fixtures are rejected |
| Balanced profile | Required | Required | Sanitized wrapper launches one owned `winws.exe` process |
| Profile switch | Required | Required | Old owned PID stops; new PID/start time is recorded |
| External process protection | Required | Required | Existing unmanaged `winws.exe` causes a visible refusal, not termination |
| Active zapret service | Required | Required | Standalone launch is refused with a diagnostic message |
| Watchdog rollback | Required | Required | Three failed general-connectivity rounds stop only the owned process |
| Emergency stop | Required | Required | Explicit action stops all `winws`/`winws2` processes |
| Domain lists | Required | Required | Include/exclude lists persist through engine update |
| Auto-start | Required | Required | Visible highest-privilege logon task starts selected profile |
| Update rollback | Required | Required | Previous package remains in `engine.previous` after successful replacement |
| Install/uninstall | Required | Required | Shortcuts and Apps & Features entry are created and removed |
| Preserve user data | Required | Required | Standard uninstall keeps `%LOCALAPPDATA%\FreeSignal` |
| Full removal | Required | Required | `-RemoveUserData` removes application data after stopping the engine |

## Negative security fixtures

- ZIP entry containing `../` or `..\`.
- ZIP with more than 20,000 entries.
- ZIP whose declared expanded size exceeds 1 GiB.
- Strategy containing `powershell`, `netsh`, `reg`, shell pipes or redirection.
- Strategy that launches an executable other than `%BIN%winws.exe`.
- PID record whose process start time does not match the live process.

No release is called production-ready until this matrix passes on both supported Windows versions.
