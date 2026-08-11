# Architecture

AI Usage Menu is split into a provider-independent core and a small native macOS presentation layer.

## Components

| Component | Responsibility |
|---|---|
| `AIUsageCore` | Provider reads, quota models, strict window selection, cache policy, local fallback and diagnostics |
| `AIUsageMenu` | SwiftUI menu UI, AppKit window configuration, system vibrancy and refresh lifecycle |
| `UsageProbe` | Redacted command-line diagnostics |
| `CoreChecks` | Hermetic regression checks for parsers, caching and window classification |

## Refresh path

1. `UsageStore` starts a refresh at launch and every 15 minutes; Claude CLI snapshots are reused for up to 30 minutes unless the user presses refresh.
2. `UsageService` reads Codex, Claude and Kimi concurrently.
3. Lightweight OAuth/API paths are preferred for Codex and Kimi; Claude uses its credential-owning CLI.
4. A provider timeout may return cache no older than one hour instead of blocking the UI indefinitely.
5. Claude quota reads and Kimi credential recovery are serialized so provider processes cannot multiply memory pressure.
6. Results are normalized into `ProviderUsage` and saved as a minimal `DashboardSnapshot`.

## Codex precedence

```text
live OAuth response
  └─ success: use only windows present in that authoritative response
  └─ failure: recent application cache
       └─ unavailable: recent local rate_limits snapshot
            └─ unavailable: codex app-server recovery
```

A successful Weekly-only response never receives a 5h value from history. This prevents an expired or account-mismatched local window from overriding live state.

## Claude credential boundary

The application process never queries `Claude Code-credentials`. An environment-provided OAuth token can use the lightweight API path; otherwise the official `claude` executable runs `/usage` in safe mode and returns quota metadata. Successful CLI snapshots are reused for 30 minutes to bound CPU and memory spikes, while the refresh button explicitly bypasses that interval. The child process is not kept alive.

## Kimi credential recovery

The normal Kimi path reads the structured usage API. Kimi Code access tokens are intentionally short-lived, so an expired local credential triggers one bounded official CLI `/usage` session. The service then re-reads the rotated credential and retries the API. Terminal text is used only if the API retry fails, and the parser searches backward for the newest complete TUI row rather than trusting a partial final redraw.

## Window identity

Payload fields such as `primary` and `secondary` are treated as transport slots, not semantic labels. `QuotaWindowSelector` recognizes only bounded durations. Unknown windows stay unknown rather than falling back to slot position.

## Glass implementation

The popup uses an `NSVisualEffectView` with behind-window blending. All window and root surfaces remain non-opaque/clear so macOS can sample and blur content behind the panel. A restrained tint improves contrast without replacing the material.

## Dependency boundary

The project links the `CodexBarCore` Swift package for provider authentication, protocol and PTY compatibility. Only the required core product is linked; the CodexBar application UI and updater are not embedded.
