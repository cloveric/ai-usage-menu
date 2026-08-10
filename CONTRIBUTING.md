# Contributing

Thank you for helping improve AI Usage Menu.

## Development requirements

- macOS 14 or later
- Swift 6.2 or later
- Command Line Tools
- Local provider logins only when running optional live probes

## Local checks

```bash
swift build -c release
swift run -c release CoreChecks
```

Build the application bundle with:

```bash
./scripts/build-app.sh
```

Live provider probes are optional and must never be included verbatim in a Pull Request if they contain account metadata.

## Pull requests

Keep each Pull Request focused. Include:

- the user-visible problem and intended behavior;
- implementation notes where behavior is non-obvious;
- validation performed;
- screenshots for UI changes, using fixture data and a synthetic background;
- privacy and resource-impact notes for new data sources.

## Window classification rules

Never assume payload position identifies a quota window. Classify by the reported duration:

- approximately 300 minutes: 5h;
- approximately 10,080 minutes: Weekly;
- unknown, daily, or monthly windows must not be relabeled as either one.

Missing provider data must remain visibly unavailable. Do not estimate a quota denominator from token counts or inherit an expired window.

## Privacy checklist

Before committing:

- remove tokens, cookies, account IDs, emails, usernames, and private paths;
- do not commit `.build`, `dist`, local caches, session logs, or auth files;
- do not commit raw desktop screenshots;
- use `DashboardSnapshot.designFixture()` for visual material;
- inspect `git diff --cached` and the exact file list.

## Code style

- Follow the existing Swift formatting and naming style.
- Prefer small, testable parsing helpers.
- Keep UI work on the main actor and provider work off the UI path.
- Preserve cancellation and bounded timeouts for network or CLI operations.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
