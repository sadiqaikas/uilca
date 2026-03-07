#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python executable not found: $PYTHON_BIN"
  read -r -p "Press Enter to close..."
  exit 1
fi

if ! "$PYTHON_BIN" backend_launcher.py; then
  echo
  echo "Launcher exited with an error."
  read -r -p "Press Enter to close..."
  exit 1
fi
