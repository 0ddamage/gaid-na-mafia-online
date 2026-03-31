#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${REPACKGENDER_NO_SELF_FIX:-}" ]]; then
  if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$ROOT_DIR" >/dev/null 2>&1 || true
  fi
  chmod +x "$ROOT_DIR"/macos/*.command "$ROOT_DIR"/linux/*.sh "$ROOT_DIR"/_core/shared/unix-common.sh >/dev/null 2>&1 || true
fi
exec env OS_NAME=macos MODE=install bash "$ROOT_DIR/_core/shared/unix-common.sh" "$@"
