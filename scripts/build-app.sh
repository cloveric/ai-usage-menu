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
swift build -c release --product AIUsageMenu
BIN_DIR="$(swift build -c release --show-bin-path)"

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

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
