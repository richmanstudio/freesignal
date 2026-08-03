# Threat model

## Assets

- integrity of the Windows network stack;
- administrator privileges used to load a packet-diversion driver;
- authenticity and integrity of imported engine packages;
- availability of general internet connectivity;
- user privacy and domain-list contents.

## Trust boundaries

1. FreeSignal source and installed scripts.
2. GitHub API and release asset delivery.
3. Third-party engine archive.
4. Privileged WinDivert driver and engine process.
5. Community strategy and domain-list content.

## Threats and mitigations

### Malicious or replaced engine archive

Mitigations:

- automatic download is restricted to a hard-coded repository API and release-download URL prefix;
- the selected asset URL is written to local logs;
- SHA-256 is calculated and shown to the user;
- archive size, entry count, expanded size and path traversal are validated before extraction;
- package layout and critical-file SHA-256 hashes are recorded before installation;
- the update is staged and the previous package retained;
- no downloaded PowerShell script is executed by FreeSignal itself;
- imported batch files are not executed wholesale: only a validated `winws.exe` command block is copied to a generated local wrapper.

Residual risk: GitHub account or release compromise. Future releases should consume a DUONIQ-signed manifest with pinned hashes.

### Loss of connectivity

Mitigations:

- automatic optimization rejects profiles that break the neutral connectivity probe;
- an independent watchdog stops the engine after repeated failures;
- the watchdog validates PID, process name and process start time before stopping an owned process;
- `FreeSignal-SafeMode.cmd` does not depend on the GUI and is explicitly documented as a broad emergency action;
- the app does not make persistent DNS, proxy or firewall modifications.

### Excessive traffic interception

Mitigations:

- FreeSignal uses strategy files from the visible engine package but excludes package service/update hooks;
- risk levels are shown before selection;
- high-risk profiles require confirmation;
- custom include/exclude lists are user-controlled;
- no background profile change occurs outside explicit auto-optimization.

### Privacy leakage

Mitigations:

- no packet inspection is implemented in the client;
- operational logs contain actions and status only;
- support reports exclude domain lists and browsing data;
- no telemetry endpoint exists.

### Abuse of administrator privileges

Mitigations:

- elevation happens through the standard Windows UAC prompt;
- the client uses administrator access only for engine management and scheduled-task creation;
- no security product is disabled;
- no arbitrary remote command channel exists.

### Interference with other zapret tools

Mitigations:

- normal stop, profile switching and watchdog rollback use a persisted PID/start-time ownership record;
- startup is refused when an unmanaged `winws`/`winws2` process or active `zapret` service is detected;
- only the explicitly labeled Emergency Stop terminates all matching engine processes.
