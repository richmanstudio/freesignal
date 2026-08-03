# Security policy

FreeSignal controls a privileged network process. Security and transparency take priority over convenience.

## Supported version

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## Security principles

- No telemetry, advertising SDK or analytics endpoint.
- No collection of browsing history, packet payloads or credentials.
- No automatic antivirus exclusions and no instructions that disable endpoint protection.
- Engine downloads are limited to the explicitly configured GitHub repository.
- Every downloaded/imported archive receives a local SHA-256 fingerprint.
- Engine updates use a staging directory and retain one rollback copy.
- Authentication headers and network payloads are never logged by the client.
- A watchdog stops engine processes if general connectivity repeatedly fails.
- The emergency-stop launcher works independently of the graphical interface.

## Reporting a vulnerability

Do not publish an exploit or sensitive report in a public issue. Contact the maintainer through the security contact shown on the GitHub profile and include:

- affected version;
- reproduction steps;
- expected and actual behavior;
- whether administrator access is required;
- any relevant logs with personal information removed.

## Out of scope

FreeSignal cannot guarantee that a third-party engine binary or community strategy is safe. Use official project releases, inspect checksums and review the third-party licenses before redistribution.
