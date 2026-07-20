# Security Policy

## Supported versions

Security fixes are provided for the latest stable release and the active release candidate.

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |
| Earlier development builds | No |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's **Report a vulnerability** private advisory flow at `https://github.com/bekircem/YeelightBar/security/advisories/new`.

Include the affected version, macOS version and architecture, reproduction steps, impact, and any suggested mitigation. Remove real IP addresses, device IDs, device names, signing credentials, and exported preference files.

You should receive an acknowledgement within 72 hours. A validated report will be triaged, fixed privately, and disclosed after an update is available. Please allow a reasonable remediation period before public disclosure.

## Scope note

The Yeelight LAN protocol is plaintext and unauthenticated. Network observation or bulb impersonation by an attacker already present on the local network is an upstream protocol limitation, not something this app can cryptographically eliminate. Bypasses of YeelightBar's local-address checks, explicit trust, endpoint-change approval, sandbox, import validation, or log redaction remain in scope.
