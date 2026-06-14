#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$ROOT_DIR/script/start_app.sh" --clean

echo
echo "AutoCut Studio started with a clean build. You can close this window."
read -r -n 1 -s -p "Press any key to close..."
echo
