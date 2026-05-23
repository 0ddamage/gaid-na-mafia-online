#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$ROOT_DIR/_core"
PATCHER_JAR="$CORE_DIR/bin/repackgender-core.jar"
PATCHER_SIG="$CORE_DIR/bin/repackgender-core.jar.sig"
RELEASE_CERT="$CORE_DIR/keys/release-signing.cer"
RELEASE_MANIFEST="$CORE_DIR/release-manifest.txt"
RELEASE_MANIFEST_SIG="$CORE_DIR/release-manifest.txt.sig"
STATE_DIR="$HOME/Library/Application Support/repackgender"
APP_ID="1906220"

section() {
  printf '\n===== %s =====\n' "$*"
}

kv() {
  printf '%s: %s\n' "$1" "${2:-}"
}

sha256_of() {
  if [[ ! -f "$1" ]]; then
    printf 'missing'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return 0
  fi
  printf 'no-sha-tool'
}

file_size() {
  if [[ ! -e "$1" ]]; then
    printf 'missing'
    return 0
  fi
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    stat -f '%z' "$1" 2>/dev/null || printf 'unknown'
  else
    stat -c '%s' "$1" 2>/dev/null || printf 'unknown'
  fi
}

file_mtime() {
  if [[ ! -e "$1" ]]; then
    printf 'missing'
    return 0
  fi
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S %z' "$1" 2>/dev/null || printf 'unknown'
  else
    stat -c '%y' "$1" 2>/dev/null || printf 'unknown'
  fi
}

tool_path() {
  command -v "$1" 2>/dev/null || printf 'missing'
}

parse_libraryfolders() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$file" | sed 's#\\\\#/#g'
}

resolve_game_jar() {
  local input="${1:-}" root lib candidate manifest
  if [[ -n "$input" ]]; then
    input="${input%\"}"
    input="${input#\"}"
    input="${input%\'}"
    input="${input#\'}"
    if [[ -f "$input" ]]; then
      printf '%s\n' "$input"
      return 0
    fi
    for candidate in \
      "$input/MafiaOnline.jar" \
      "$input/Contents/Resources/MafiaOnline.jar" \
      "$input/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$input/Mafia Online.app/Contents/Java/MafiaOnline.jar"; do
      [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
  fi

  local roots=()
  for root in \
    "$HOME/Library/Application Support/Steam" \
    "$HOME/Library/Application Support/com.valvesoftware.Steam" \
    "$HOME/.steam/steam"; do
    [[ -d "$root" ]] || continue
    roots+=("$root")
    while IFS= read -r lib; do
      [[ -n "$lib" ]] && roots+=("$lib")
    done < <(parse_libraryfolders "$root/steamapps/libraryfolders.vdf")
  done

  for root in "${roots[@]}"; do
    manifest="$root/steamapps/appmanifest_${APP_ID}.acf"
    for candidate in \
      "$root/steamapps/common/Mafia Online/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Java/MafiaOnline.jar"; do
      [[ -f "$manifest" && -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
  done

  for root in "${roots[@]}"; do
    for candidate in \
      "$root/steamapps/common/Mafia Online/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Java/MafiaOnline.jar"; do
      [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
  done
  return 1
}

find_java() {
  local live_jar="${1:-}" game_dir candidate
  if [[ -n "${REPACKGENDER_JAVA_BIN:-}" && -x "${REPACKGENDER_JAVA_BIN:-}" ]]; then
    printf '%s\n' "$REPACKGENDER_JAVA_BIN"
    return 0
  fi
  if command -v java >/dev/null 2>&1; then
    command -v java
    return 0
  fi
  if [[ -n "$live_jar" ]]; then
    game_dir="$(dirname "$live_jar")"
    for candidate in \
      "$game_dir/jre/bin/java" \
      "$game_dir/jre/Contents/Home/bin/java" \
      "$game_dir/../jre/bin/java" \
      "$game_dir/../jre/Contents/Home/bin/java"; do
      [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
  fi
  return 1
}

section "diagnostic header"
kv "timestamp" "$(date '+%Y-%m-%d %H:%M:%S %z')"
kv "root" "$ROOT_DIR"
kv "user" "$(id -un 2>/dev/null || whoami 2>/dev/null || printf unknown)"
kv "shell" "${SHELL:-unknown}"
kv "pwd" "$(pwd)"

section "system"
kv "uname" "$(uname -a 2>/dev/null || printf unknown)"
kv "arch" "$(uname -m 2>/dev/null || printf unknown)"
if command -v sw_vers >/dev/null 2>&1; then
  sw_vers
fi
kv "xattr" "$(tool_path xattr)"
kv "openssl" "$(tool_path openssl)"
kv "python3" "$(tool_path python3)"
kv "unzip" "$(tool_path unzip)"
kv "zip" "$(tool_path zip)"
kv "java" "$(tool_path java)"
if command -v java >/dev/null 2>&1; then
  java -version 2>&1 | sed 's/^/java-version: /'
fi

section "release files"
for path in \
  "$PATCHER_JAR" \
  "$PATCHER_SIG" \
  "$RELEASE_CERT" \
  "$RELEASE_MANIFEST" \
  "$RELEASE_MANIFEST_SIG" \
  "$CORE_DIR/clean.sha256" \
  "$CORE_DIR/bin/repackgender-core-v246-patched.jar"; do
  kv "$path size" "$(file_size "$path")"
  kv "$path sha256" "$(sha256_of "$path")"
done

section "clean sha list"
if [[ -f "$CORE_DIR/clean.sha256" ]]; then
  nl -ba "$CORE_DIR/clean.sha256"
else
  printf 'clean.sha256 missing\n'
fi

section "release signatures"
if command -v openssl >/dev/null 2>&1 && [[ -f "$RELEASE_CERT" ]]; then
  pubkey_tmp="$(mktemp "${TMPDIR:-/tmp}/repackgender-diag-pubkey.XXXXXX")"
  if openssl x509 -inform DER -in "$RELEASE_CERT" -pubkey -noout >"$pubkey_tmp" 2>/dev/null; then
    openssl dgst -sha256 -verify "$pubkey_tmp" -signature "$PATCHER_SIG" "$PATCHER_JAR" 2>&1 | sed 's/^/patcher-signature: /'
    openssl dgst -sha256 -verify "$pubkey_tmp" -signature "$RELEASE_MANIFEST_SIG" "$RELEASE_MANIFEST" 2>&1 | sed 's/^/manifest-signature: /'
  else
    printf 'could not extract pubkey from release cert\n'
  fi
  rm -f "$pubkey_tmp"
else
  printf 'openssl or release cert missing; signature check skipped\n'
fi

section "manifest hash check"
if [[ -f "$RELEASE_MANIFEST" ]]; then
  manifest_fail=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    expected="${line%%  *}"
    rel="${line#*  }"
    target="$ROOT_DIR/$rel"
    actual="$(sha256_of "$target")"
    if [[ "$actual" == "$expected" ]]; then
      printf 'OK %s\n' "$rel"
    else
      printf 'BAD %s expected=%s actual=%s\n' "$rel" "$expected" "$actual"
      manifest_fail=1
    fi
  done <"$RELEASE_MANIFEST"
  kv "manifest_hash_result" "$([[ "$manifest_fail" -eq 0 ]] && printf OK || printf BAD)"
else
  printf 'manifest missing\n'
fi

section "hidden v300 payload"
if command -v python3 >/dev/null 2>&1 && [[ -f "$PATCHER_JAR" && -f "$RELEASE_CERT" ]]; then
  python3 - "$PATCHER_JAR" "$RELEASE_CERT" <<'PY'
import base64
import hashlib
import sys
import zipfile

jar_path, cert_path = sys.argv[1], sys.argv[2]
cert = open(cert_path, "rb").read()
entry = "META-INF/.x/" + hashlib.sha256(
    base64.b64encode(cert)
    + b"repackgender:20260331:c"
    + b"payload/MafiaOnline.jar"
    + bytes([0x51])
).hexdigest()[:28] + ".bin"
try:
    with zipfile.ZipFile(jar_path) as jar:
        info = jar.getinfo(entry)
        print(f"payload_entry: {entry}")
        print(f"payload_entry_size: {info.file_size}")
except Exception as exc:
    print(f"payload_entry_error: {exc}")
PY
else
  printf 'python3/core/cert missing; hidden payload check skipped\n'
fi

section "game jar"
live_jar="$(resolve_game_jar "${1:-}" || true)"
if [[ -z "$live_jar" ]]; then
  printf 'game_jar: not found automatically; pass path as first argument if needed\n'
else
  kv "game_jar" "$live_jar"
  kv "game_jar_size" "$(file_size "$live_jar")"
  kv "game_jar_mtime" "$(file_mtime "$live_jar")"
  kv "game_jar_sha256" "$(sha256_of "$live_jar")"
  if command -v unzip >/dev/null 2>&1; then
    unzip -tqq "$live_jar" >/dev/null 2>&1
    kv "game_jar_zip_test_rc" "$?"
    kv "game_jar_entry_count" "$(unzip -Z1 "$live_jar" 2>/dev/null | wc -l | tr -d '[:space:]')"
    printf 'selected_entries:\n'
    unzip -Z1 "$live_jar" 2>/dev/null \
      | grep -E '^(META-INF/MANIFEST.MF|libgdx64\.dylib|libgdxarm64\.dylib|liblwjgl\.dylib|openal\.dylib|macos/|Audio/TownMusic\.ogg|comicbd\.ttf|com/kartuzov/mafiaonline/(x1|x2|SvPanelRuntime|UiTextInputRuntime).*)$' \
      | sed -n '1,160p'
  fi
fi

section "app files"
if [[ -n "${live_jar:-}" ]]; then
  game_res_dir="$(dirname "$live_jar")"
  game_root="$(cd "$game_res_dir/.." 2>/dev/null && pwd || true)"
  for path in \
    "$game_res_dir/startup-crash.log" \
    "$game_res_dir/match-night-live.log" \
    "$game_res_dir/mn.log" \
    "$game_res_dir/jre/bin/java" \
    "$game_res_dir/jre/Contents/Home/bin/java" \
    "$game_root/MacOS/MafiaOnline"; do
    kv "$path size" "$(file_size "$path")"
    kv "$path mtime" "$(file_mtime "$path")"
    if [[ -f "$path" ]]; then
      kv "$path sha256" "$(sha256_of "$path")"
    fi
  done
  if command -v file >/dev/null 2>&1 && [[ -f "$game_root/MacOS/MafiaOnline" ]]; then
    file "$game_root/MacOS/MafiaOnline" 2>&1 | sed 's/^/file-launcher: /'
  fi
fi

section "recent installer state"
for dir in "$STATE_DIR/backups" "$STATE_DIR/logs" "$STATE_DIR/clean" "$STATE_DIR/build"; do
  printf 'dir: %s\n' "$dir"
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 1 -type f -print 2>/dev/null \
      | while IFS= read -r path; do
          printf '%s size=%s mtime=%s sha256=%s\n' "$path" "$(file_size "$path")" "$(file_mtime "$path")" "$(sha256_of "$path")"
        done \
      | sort | tail -n 30
  else
    printf 'missing\n'
  fi
done

section "recent logs"
for log in \
  "${live_jar:+$(dirname "$live_jar")/startup-crash.log}" \
  "$STATE_DIR"/logs/install-*.log; do
  [[ -f "$log" ]] || continue
  printf '\n--- %s ---\n' "$log"
  tail -n 120 "$log"
done

section "patcher dry-run"
if [[ -n "${live_jar:-}" && -f "$live_jar" ]]; then
  java_bin="$(find_java "$live_jar" || true)"
  if [[ -z "$java_bin" ]]; then
    printf 'java_for_dry_run: not found\n'
  else
    kv "java_for_dry_run" "$java_bin"
    dry_dir="$(mktemp -d "${TMPDIR:-/tmp}/repackgender-diag-dryrun.XXXXXX")"
    dry_out="$dry_dir/patched.jar"
    dry_log="$dry_dir/patcher.log"
    REPACKGENDER_PATCHER_ALLOW_UNSUPPORTED_CLEAN=1 "$java_bin" -jar "$PATCHER_JAR" "$live_jar" "$dry_out" >"$dry_log" 2>&1
    dry_rc="$?"
    kv "dry_run_rc" "$dry_rc"
    kv "dry_run_output_size" "$(file_size "$dry_out")"
    kv "dry_run_output_sha256" "$(sha256_of "$dry_out")"
    printf 'dry_run_log:\n'
    sed -n '1,220p' "$dry_log"
    if [[ -f "$dry_out" && "$(command -v unzip || true)" != "" ]]; then
      printf 'dry_run_selected_entries:\n'
      unzip -Z1 "$dry_out" 2>/dev/null \
        | grep -E '^(libgdx64\.dylib|libgdxarm64\.dylib|macos/|Audio/TownMusic\.ogg|comicbd\.ttf|com/kartuzov/mafiaonline/(x1|x2|SvPanelRuntime|UiTextInputRuntime).*)$' \
        | sed -n '1,160p'
    fi
    rm -rf "$dry_dir"
  fi
else
  printf 'dry-run skipped: game jar not found\n'
fi

section "done"
printf 'Copy everything from the first diagnostic header line through this done line.\n'
