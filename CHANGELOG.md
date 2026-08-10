# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses semantic versioning.

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

[0.1.0]: https://github.com/cloveric/ai-usage-menu/releases/tag/v0.1.0
