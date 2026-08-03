# Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│ FreeSignal WPF client                                       │
│ overview · profiles · diagnostics · domains · logs          │
└──────────────────────────────┬──────────────────────────────┘
                               │ explicit local actions
┌──────────────────────────────▼──────────────────────────────┐
│ PowerShell orchestration layer                              │
│ state · updater · ZIP safety · command sanitizer · startup  │
└───────────────┬───────────────────────────────┬──────────────┘
                │                               │
┌───────────────▼──────────────┐  ┌────────────▼──────────────┐
│ Engine package               │  │ Independent watchdog      │
│ winws · lists · strategies   │  │ general connectivity      │
│ service.bat is not executed  │  │ owned-process rollback    │
└───────────────┬──────────────┘  └───────────────────────────┘
                │ WinDivert / WFP
┌───────────────▼─────────────────────────────────────────────┐
│ Windows network stack                                      │
│ Traffic remains direct between applications and services.  │
└─────────────────────────────────────────────────────────────┘
```

## Data locations

Application source files are read-only after installation. Mutable state is stored in:

```text
%LOCALAPPDATA%\FreeSignal\
├── state.json
├── engine\
├── engine.previous\
├── list-general-user.txt
├── list-exclude-user.txt
├── logs\
├── managed-processes.json
├── runtime-strategy.cmd
└── rollback.json
```

## Engine adapters

The MVP automatically supports a Flowseal-compatible package containing:

```text
service.bat
bin\winws.exe
```

The source manifest also declares adapters for original zapret and zapret 2 packages. These are manual-import targets until stable Windows package-layout contracts are defined. The automatic Flowseal adapter treats `service.bat` only as a package-layout marker; it is never invoked.

## Profile model

Each profile maps a human-readable name to a strategy file supplied by the installed engine package. Before launch, FreeSignal locates one continued `start ... winws.exe` block, rejects shell-control characters and unrelated administrative commands, and builds a local wrapper with explicit `BIN`, `LISTS` and disabled GameFilter variables. The original strategy remains unchanged and its provenance remains visible.

## Failure behavior

- Starting a profile stops only process IDs previously registered by FreeSignal and refuses to take ownership while an external `winws`/`winws2` instance or active `zapret` service exists.
- The explicit Emergency Stop and `FreeSignal-SafeMode.cmd` can terminate all `winws`/`winws2` processes; the UI labels this destructive scope.
- The client never disables a firewall, antivirus product or DNS policy.
- Engine archives are constrained by URL prefix, compressed size, expanded size, entry count and path traversal checks.
- Engine updates are staged before the current package is moved.
- One previous package is retained locally.
- The watchdog checks a neutral general-connectivity endpoint.
- Three consecutive failures stop the engine and create a visible rollback marker.
