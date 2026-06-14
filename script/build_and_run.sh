#!/bin/bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AutoCutStudio"
BUNDLE_ID="com.local.AutoCutStudio"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/AutoCutStudio"
APP_LOG_FILE="${AUTOCUT_STUDIO_APP_LOG:-/tmp/autocutstudio-app.log}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR"
BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_NAME"

/usr/bin/xattr -cr "$PACKAGE_DIR/.build" 2>/dev/null || true
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$BUILD_BINARY" >/dev/null 2>&1 || true

wait_for_app() {
  for _ in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

open_app() {
  cd "$ROOT_DIR"
  AUTOCUT_REPO_ROOT="$ROOT_DIR" nohup "$BUILD_BINARY" >"$APP_LOG_FILE" 2>&1 &
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    cd "$ROOT_DIR"
    AUTOCUT_REPO_ROOT="$ROOT_DIR" lldb -- "$BUILD_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    wait_for_app
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
