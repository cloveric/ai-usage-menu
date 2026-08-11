# Security policy

## Supported versions

Security fixes are provided for the latest published release.

| Version | Supported |
|---|:---:|
| 0.1.x | ✓ |
| Older / unreleased snapshots | — |

## Reporting a vulnerability

Use GitHub's private vulnerability reporting flow:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Include affected version, reproduction steps, impact, and a minimal proof of concept.

Do not open a public Issue containing credentials, full authentication files, cookies, unredacted session logs, private paths, or account identifiers.

If private vulnerability reporting is temporarily unavailable, open a public Issue containing only a request for a private contact channel. Do not include vulnerability details in that Issue.

## Security model

- Provider credentials remain in their original local stores and are not serialized by AI Usage Menu.
- The application never queries Claude Code's Keychain item; the credential-owning official CLI returns quota metadata.
- The application requests quota metadata only; it does not send prompts or generate provider traffic for the purpose of measuring usage.
- Local Codex session fallback is read-only, bounded, time-limited, and marked stale.
- Release builds are ad-hoc signed but not notarized. Verify release checksums and source before running software from any mirror.
- Dependencies are pinned in `Package.resolved` and reviewed through Dependabot updates.

## Disclosure

Please allow a reasonable period for triage and remediation before public disclosure. Confirmed reports will be credited unless anonymity is requested.
