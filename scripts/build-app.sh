#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AI 用量"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"

case "$APP_DIR" in
    "$PROJECT_DIR"/dist/*.app) ;;
    *)
        echo "拒绝清理意外路径：$APP_DIR" >&2
        exit 1
        ;;
esac

cd "$PROJECT_DIR"
TASK_TEMP_ROOT="${TMPDIR:-/tmp}"
TASK_TEMP_ROOT="${TASK_TEMP_ROOT%/}"
SCRATCH_DIR="$(mktemp -d "$TASK_TEMP_ROOT/ai-usage-menu-build.XXXXXX")"

cleanup_scratch() {
    case "$SCRATCH_DIR" in
        "$TASK_TEMP_ROOT"/ai-usage-menu-build.*) rm -rf "$SCRATCH_DIR" ;;
        *) echo "拒绝清理意外构建目录：$SCRATCH_DIR" >&2 ;;
    esac
}
trap cleanup_scratch EXIT

# Dependencies are built in an isolated, non-personal path so SwiftPM's runtime
# resource fallback cannot embed the developer's home directory in the app.
swift build --scratch-path "$SCRATCH_DIR" -c release --product AIUsageMenu -Xswiftc -gnone
BIN_DIR="$(swift build --scratch-path "$SCRATCH_DIR" -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
install -m 755 "$BIN_DIR/AIUsageMenu" "$APP_DIR/Contents/MacOS/AIUsageMenu"
install -m 644 "$PROJECT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$PROJECT_DIR/Sources/AIUsageMenu/Resources/codex-mark.png" "$APP_DIR/Contents/Resources/codex-mark.png"
install -m 644 "$PROJECT_DIR/Sources/AIUsageMenu/Resources/claude-mark.png" "$APP_DIR/Contents/Resources/claude-mark.png"
install -m 644 "$PROJECT_DIR/Sources/AIUsageMenu/Resources/kimi-mark.png" "$APP_DIR/Contents/Resources/kimi-mark.png"
install -m 644 "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
install -m 644 "$PROJECT_DIR/Support/CodexBar-LICENSE" "$APP_DIR/Contents/Resources/CodexBar-LICENSE"

while IFS= read -r bundle; do
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print)

# Release binaries should not disclose the build machine's source paths.
strip -S -x "$APP_DIR/Contents/MacOS/AIUsageMenu"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
