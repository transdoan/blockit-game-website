#!/usr/bin/env bash
set -e

# simple wrapper to run doxygen from the engine root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v doxygen >/dev/null 2>&1; then
  echo "doxygen is not installed. please install it first." >&2
  exit 1
fi

doxygen Doxyfile
echo "docs generated in Docs/html"

