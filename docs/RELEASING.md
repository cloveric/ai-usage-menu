# Release checklist

1. Update `CFBundleShortVersionString`, `CFBundleVersion` and `CHANGELOG.md`.
2. Run the public-file and secret audit before staging.
3. Run:

   ```bash
   swift run -c release CoreChecks
   ./scripts/build-app.sh
   codesign --verify --deep --strict "dist/AI 用量.app"
   ```

4. Confirm the built executable architecture with `file`.
5. Package the app with `ditto` and generate a SHA-256 checksum.
6. Inspect the exact Git tree; do not add `dist`, raw screenshots, caches or auth material.
7. Create a signed or annotated `vX.Y.Z` tag when signing infrastructure is available.
8. Publish release notes with requirements, privacy behavior, known limitations and checksum.
9. Verify the public archive can be downloaded and expanded.

Official releases must be created from a clean `main` commit. Do not publish artifacts built from an unreviewed dirty worktree.
