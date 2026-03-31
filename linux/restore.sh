#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec env OS_NAME=linux MODE=restore bash "$ROOT_DIR/_core/shared/unix-common.sh" "$@"
