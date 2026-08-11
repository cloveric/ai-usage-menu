# Privacy

AI Usage Menu is designed to keep authentication and usage data on the user's Mac, except for the minimum provider requests required to retrieve current quota metadata.

## Data the application accesses

Depending on the providers enabled on the Mac, the application may access:

- the existing Codex OAuth login maintained by Codex CLI;
- quota output from the already authenticated official Claude Code CLI;
- the existing Kimi Code login or configured API endpoint;
- recent Codex session JSONL files, but only as a fallback after a live Codex request fails.

The application uses credentials in memory to contact the corresponding provider's usage endpoint. Credentials are not copied into the application's cache.

## Network requests

Normal refreshes contact only the configured provider endpoints used by Codex, Claude Code, and Kimi Code. This project does not operate a proxy, analytics endpoint, update-tracking endpoint, or account service.

Provider clients may follow their normal authentication refresh flow. Review the pinned `CodexBarCore` dependency and `Package.resolved` when auditing network behavior.

## Credential prompts

AI Usage Menu does not query the `Claude Code-credentials` Keychain item. Claude Code remains the credential owner: the application starts the official `claude` executable in safe mode, requests `/usage`, parses quota metadata, and terminates it. The application never asks for, receives, or stores the Mac login password.

Because Claude Code CLI startup is comparatively expensive, automatic refreshes reuse a successful Claude result for up to 30 minutes. A user-initiated refresh bypasses that interval. Terminal output is held in memory only for parsing and is not persisted.

Kimi Code access tokens are short-lived. When an existing Kimi login needs rotation, the application may briefly run the official `kimi` CLI, then re-read the locally updated credential and return to the structured usage API. The CLI is terminated after the refresh and its terminal output is not persisted.

## Local storage

The application stores a minimal snapshot at:

```text
~/Library/Application Support/AI Usage Menu/snapshot.json
```

The snapshot can contain:

- used percentage;
- quota window duration;
- reset time or reset description;
- provider/source label;
- connection and cache state;
- refresh time and a human-readable error message.

It is not intended to contain OAuth tokens, API keys, cookies, prompts, responses, or account identifiers.

## Codex session fallback

When a live Codex request fails and there is no sufficiently recent application cache, AI Usage Menu may inspect recent files under the active Codex home. The reader:

- considers only JSONL files modified within the last hour;
- reads at most the tail 2 MB from each of at most eight recent files;
- decodes only lines containing a `rate_limits` object;
- accepts only recognized Weekly and 5h durations;
- rejects expired or older snapshots;
- marks the result as stale/local data.

Conversation content is neither decoded into application models nor emitted by diagnostics.

## Telemetry

The project contains no analytics, advertising, crash-reporting, or behavioral telemetry SDK. GitHub may collect normal repository and release-download traffic under GitHub's own policies.

## Removing local data

Quit the application and remove the following folder if you want to delete its cached quota snapshot:

```text
~/Library/Application Support/AI Usage Menu/
```

This does not sign you out of Codex, Claude Code, or Kimi Code.

## Public screenshots

Repository screenshots and release artwork use fixture data and synthetic backgrounds. Raw maintainer desktop captures are intentionally excluded from version control.

## Questions

For a privacy question that does not include sensitive data, open a GitHub Discussion or Issue. For a potential vulnerability, follow [SECURITY.md](SECURITY.md).
