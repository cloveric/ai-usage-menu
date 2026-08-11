# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses semantic versioning.

## [Unreleased]

## [0.1.1] - 2026-08-12

### Fixed

- Refresh Kimi's short-lived credential through the official CLI before retrying the structured API.
- Parse the newest complete Kimi terminal row when the final TUI redraw is partial.
- Stop presenting provider cache older than one hour as current quota.
- Remove direct access to Claude Code's legacy ACL Keychain item, which can display a password dialog even when Security.framework UI is disabled.
- Restore Claude Weekly, 5h, and Fable 5 through the credential-owning official CLI, with a 30-minute automatic throttle and immediate manual refresh.
- Keep the last Fable 5 value until its reset when one incremental terminal redraw omits that row.

### Added

- Redacted `UsageProbe --kimi-api` and `UsageProbe --claude-cli` diagnostics for quota windows.

## [0.1.0] - 2026-08-10

### Added

- Native macOS menu bar panel for Codex, Claude, and Kimi usage.
- Weekly and 5h quota lanes with reset-time formatting.
- Claude Fable 5 scoped weekly quota.
- Real macOS vibrancy backed by `NSVisualEffectView`.
- Lightweight OAuth/API-first refresh with bounded CLI recovery.
- One-hour cache and recent Codex session fallback.
- Strict duration-based window classification.
- Redacted diagnostics for OAuth, app-server, and local Codex windows.
- Fixture-driven visual preview and six core regression checks.

### Security

- Credentials are never stored in the application cache.
- Public repository assets use synthetic backgrounds and fixture data only.

[Unreleased]: https://github.com/cloveric/ai-usage-menu/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/cloveric/ai-usage-menu/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/cloveric/ai-usage-menu/releases/tag/v0.1.0
