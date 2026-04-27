#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill "$BACKEND_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

cd "$BACKEND_DIR"
python3 server.py > /tmp/reelon_backend.log 2>&1 &
BACKEND_PID=$!

echo "Backend started (pid=$BACKEND_PID) at http://localhost:8080"

cd "$ROOT_DIR"
flutter pub get
flutter run "$@" --dart-define=API_BASE_URL=http://localhost:8080
