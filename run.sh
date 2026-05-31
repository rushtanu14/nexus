#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$ROOT_DIR/native-macos"
APP_PATH="$NATIVE_DIR/dist/Nexus.app"
OPEN_APP=1

case "${1:-}" in
  "")
    ;;
  "--no-open" | "build")
    OPEN_APP=0
    ;;
  "-h" | "--help")
    echo "Usage: ./run.sh [--no-open|build]"
    echo
    echo "Builds the native macOS app bundle and opens Nexus.app by default."
    echo "Use ./run.sh --no-open to build without launching the app."
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Usage: ./run.sh [--no-open|build]" >&2
    exit 64
    ;;
esac

"$NATIVE_DIR/scripts/build-app.sh"

if [[ "$OPEN_APP" == "1" ]]; then
  open "$APP_PATH"
else
  echo "Built $APP_PATH"
fi
