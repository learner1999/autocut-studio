#!/bin/bash
set -euo pipefail

APP_NAME="AutoCutStudio"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/AutoCutStudio"
LOG_FILE="/tmp/autocutstudio.log"
CLEAN_BUILD=0

if [[ "${1:-}" == "--clean" ]]; then
  CLEAN_BUILD=1
fi

echo "Starting AutoCut Studio..."
cd "$ROOT_DIR"
export AUTOCUT_REPO_ROOT="$ROOT_DIR"

if [[ "$CLEAN_BUILD" == "1" ]]; then
  rm -rf "$PACKAGE_DIR/.build"
fi

if "$ROOT_DIR/script/build_and_run.sh" --verify >"$LOG_FILE" 2>&1; then
  echo "AutoCut Studio is running."
  echo "Log: $LOG_FILE"
  exit 0
fi

if [[ "$CLEAN_BUILD" == "0" ]]; then
  echo "Normal launch failed. Retrying with a clean build..."
  rm -rf "$PACKAGE_DIR/.build"
  if "$ROOT_DIR/script/build_and_run.sh" --verify >"$LOG_FILE" 2>&1; then
    echo "AutoCut Studio is running after a clean build."
    echo "Log: $LOG_FILE"
    exit 0
  fi
fi

echo "AutoCut Studio failed to start. Last log:"
tail -n 80 "$LOG_FILE" 2>/dev/null || true
exit 1
