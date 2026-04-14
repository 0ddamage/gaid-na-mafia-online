#!/usr/bin/env bash
set -euo pipefail
CORE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$CORE_DIR/.." && pwd)"
PATCHER_JAR="$CORE_DIR/bin/repackgender-core.jar"
PATCHER_SIG="$CORE_DIR/bin/repackgender-core.jar.sig"
RELEASE_CERT="$CORE_DIR/keys/release-signing.cer"
RELEASE_MANIFEST="$CORE_DIR/release-manifest.txt"
RELEASE_MANIFEST_SIG="$CORE_DIR/release-manifest.txt.sig"
RELEASE_CERT_SHA256="fbf0ce154b5e4d873f5212bdef9aa3d7e61ac7ca496d1feadad47570b9a2e940"
SUPPORTED_CLEAN_SHA_FILE="$CORE_DIR/clean.sha256"
SUPPORTED_CLEAN_SHAS=()
PREFERRED_CLEAN_SHA=''
OS_NAME="${OS_NAME:?}"
MODE="${MODE:?}"
APP_ID="1906220"
GAME_RELATIVE_PATH="steamapps/common/Mafia Online/out-windows/MafiaOnline.jar"
FX_ENABLED=0
FX_CURSOR_HIDDEN=0
if [[ "$OS_NAME" == "macos" ]]; then
  STATE_DIR="$HOME/Library/Application Support/repackgender"
  DEFAULT_ROOTS=(
    "$HOME/Library/Application Support/Steam"
    "$HOME/Library/Application Support/com.valvesoftware.Steam"
    "$HOME/.steam/steam"
  )
else
  STATE_DIR="$HOME/.local/share/repackgender"
  DEFAULT_ROOTS=("$HOME/snap/steam/common/.local/share/Steam" "$HOME/.local/share/Steam" "$HOME/.steam/steam")
fi
CLEAN_JAR="$STATE_DIR/clean/client-clean.jar"
PATCHED_JAR="$STATE_DIR/build/client-patched.jar"
BACKUP_DIR="$STATE_DIR/backups"
LOG_DIR="$STATE_DIR/logs"
JAVA_RUNTIME_DIR="$STATE_DIR/runtime/java"
JAVA_BIN="${REPACKGENDER_JAVA_BIN:-java}"
msg() { printf '%s\n' "$*"; }
die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
load_supported_clean_shas() {
  local line cleaned
  [[ -f "$SUPPORTED_CLEAN_SHA_FILE" ]] || die "Не найден clean-хэш: $SUPPORTED_CLEAN_SHA_FILE"
  SUPPORTED_CLEAN_SHAS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    cleaned="$(printf '%s' "$line" | tr -d '\r' | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$cleaned" ]] && continue
    cleaned="$(printf '%s' "$cleaned" | tr 'A-F' 'a-f')"
    [[ "$cleaned" =~ ^[0-9a-f]{64}$ ]] || die "Некорректный SHA-256 в clean.sha256: $cleaned"
    SUPPORTED_CLEAN_SHAS+=("$cleaned")
  done <"$SUPPORTED_CLEAN_SHA_FILE"
  (( ${#SUPPORTED_CLEAN_SHAS[@]} > 0 )) || die 'clean.sha256 не содержит ни одного валидного SHA-256.'
  PREFERRED_CLEAN_SHA="${SUPPORTED_CLEAN_SHAS[0]}"
}
is_supported_clean_sha() {
  local hash="${1:-}" item
  [[ -n "$hash" ]] || return 1
  for item in "${SUPPORTED_CLEAN_SHAS[@]}"; do
    [[ "$hash" == "$item" ]] && return 0
  done
  return 1
}
is_preferred_clean_sha() {
  local hash="${1:-}"
  [[ -n "$hash" && -n "$PREFERRED_CLEAN_SHA" && "$hash" == "$PREFERRED_CLEAN_SHA" ]]
}
supported_clean_sha_list() {
  local out='' item
  for item in "${SUPPORTED_CLEAN_SHAS[@]}"; do
    if [[ -n "$out" ]]; then
      out="$out, $item"
    else
      out="$item"
    fi
  done
  printf '%s\n' "$out"
}
same_clean_sha() {
  local left="${1:-}" right="${2:-}"
  [[ -n "$left" && -n "$right" && "$left" == "$right" ]]
}
choose_target_clean_sha() {
  local live_sha="${1:-}" supplied_sha="${2:-}"
  if is_supported_clean_sha "$live_sha"; then
    printf '%s\n' "$live_sha"
    return 0
  fi
  if is_supported_clean_sha "$supplied_sha"; then
    printf '%s\n' "$supplied_sha"
    return 0
  fi
  printf '%s\n' "$PREFERRED_CLEAN_SHA"
}
is_target_clean_sha() {
  local hash="${1:-}" target_sha="${2:-}"
  same_clean_sha "$hash" "$target_sha"
}
set_window_title() {
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    printf '\033]0;%s\007' 'REPACKGENDER :: установка'
  fi
}
center_window_linux() {
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 0
  if command -v xdotool >/dev/null 2>&1; then
    local win geom width height screen_w screen_h pos_x pos_y
    win="$(xdotool getactivewindow 2>/dev/null || true)"
    [[ -n "$win" ]] || return 0
    geom="$(xdotool getwindowgeometry --shell "$win" 2>/dev/null || true)"
    [[ -n "$geom" ]] || return 0
    eval "$geom"
    read -r screen_w screen_h < <(xdotool getdisplaygeometry 2>/dev/null || printf '0 0\n')
    [[ "$screen_w" -gt 0 && "$screen_h" -gt 0 ]] || return 0
    pos_x=$(( (screen_w - WIDTH) / 2 ))
    pos_y=$(( (screen_h - HEIGHT) / 2 ))
    (( pos_x < 0 )) && pos_x=0
    (( pos_y < 0 )) && pos_y=0
    xdotool windowmove "$win" "$pos_x" "$pos_y" >/dev/null 2>&1 || true
  fi
}
center_window_macos() {
  command -v osascript >/dev/null 2>&1 || return 0
  osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
try
  set targetWidth to 1120
  set targetHeight to 760
  tell application "Finder"
    set desktopBounds to bounds of window of desktop
  end tell
  set screenWidth to item 3 of desktopBounds
  set screenHeight to item 4 of desktopBounds
  set leftPos to (screenWidth - targetWidth) div 2
  set topPos to (screenHeight - targetHeight) div 2
  if leftPos < 0 then set leftPos to 0
  if topPos < 24 then set topPos to 24
  set rightPos to leftPos + targetWidth
  set bottomPos to topPos + targetHeight
  if application "Terminal" is running then
    tell application "Terminal"
      if (count of windows) > 0 then
        set bounds of front window to {leftPos, topPos, rightPos, bottomPos}
      end if
    end tell
  end if
  if application "iTerm" is running then
    tell application "iTerm"
      if (count of windows) > 0 then
        tell current window
          set bounds to {leftPos, topPos, rightPos, bottomPos}
        end tell
      end if
    end tell
  end if
end try
APPLESCRIPT
}
center_window_if_possible() {
  [[ -n "${REPACKGENDER_NO_CENTER:-}" ]] && return 0
  [[ -t 0 && -t 1 ]] || return 0
  case "$OS_NAME" in
    macos) center_window_macos ;;
    linux) center_window_linux ;;
  esac
}
enable_fx_if_possible() {
  if [[ -n "${REPACKGENDER_NO_BANNER:-}" ]]; then
    FX_ENABLED=0
    return 0
  fi
  if [[ -t 0 && -t 1 && "${TERM:-}" != "dumb" ]]; then
    FX_ENABLED=1
  else
    FX_ENABLED=0
  fi
}
reset_fx() {
  if [[ "$FX_CURSOR_HIDDEN" -eq 1 ]]; then
    printf '\033[?25h'
    FX_CURSOR_HIDDEN=0
  fi
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '\033[0m'
  fi
}
color_line() {
  local color="$1"
  shift
  local text="$*"
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '\033[38;5;%sm%s\033[0m\n' "$color" "$text"
  else
    printf '%s\n' "$text"
  fi
}
accent_text() {
  local color="$1"
  shift
  local text="$*"
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '\033[38;5;%sm%s\033[0m' "$color" "$text"
  else
    printf '%s' "$text"
  fi
}
strong_text() {
  local color="$1"
  shift
  local text="$*"
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '\033[1;38;5;%sm%s\033[0m' "$color" "$text"
  else
    printf '%s' "$text"
  fi
}
banner_row_center() {
  local color="$1"
  local text="$2"
  local inner_width=74
  local text_len=${#text}
  local left_pad=0
  local right_pad=0
  if (( text_len < inner_width )); then
    left_pad=$(( (inner_width - text_len) / 2 ))
    right_pad=$(( inner_width - text_len - left_pad ))
  fi
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '\033[38;5;%sm||%*s%s%*s||\033[0m\n' "$color" "$left_pad" '' "$text" "$right_pad" ''
  else
    printf '||%*s%s%*s||\n' "$left_pad" '' "$text" "$right_pad" ''
  fi
}
banner_art_line() {
  local word="$1"
  local index="$2"
  case "$word:$index" in
    "ГЕНДЕР:0") printf ' ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗ ' ;;
    "ГЕНДЕР:1") printf '██╔════╝ ██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗' ;;
    "ГЕНДЕР:2") printf '██║  ███╗█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝' ;;
    "ГЕНДЕР:3") printf '██║   ██║██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗' ;;
    "ГЕНДЕР:4") printf '╚██████╔╝███████╗██║ ╚████║██████╔╝███████╗██║  ██║' ;;
    "ГЕНДЕР:5") printf ' ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝' ;;
    "REPACK:0") printf '██████╗ ███████╗██████╗  █████╗  ██████╗██╗  ██╗' ;;
    "REPACK:1") printf '██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝' ;;
    "REPACK:2") printf '██████╔╝█████╗  ██████╔╝███████║██║     █████╔╝ ' ;;
    "REPACK:3") printf '██╔══██╗██╔══╝  ██╔═══╝ ██╔══██║██║     ██╔═██╗ ' ;;
    "REPACK:4") printf '██║  ██║███████╗██║     ██║  ██║╚██████╗██║  ██╗' ;;
    "REPACK:5") printf '╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝' ;;
    *) printf '' ;;
  esac
}
render_banner_frame() {
  local word="$1"
  local accent_word="$2"
  local border="$3"
  local art_a="$4"
  local art_b="$5"
  local accent="$6"
  color_line "$border" '+==========================================================================+'
  banner_row_center "$border" ''
  banner_row_center "$art_a"  "$(banner_art_line "$word" 0)"
  banner_row_center "$art_b"  "$(banner_art_line "$word" 1)"
  banner_row_center "$art_a"  "$(banner_art_line "$word" 2)"
  banner_row_center "$art_b"  "$(banner_art_line "$word" 3)"
  banner_row_center "$art_a"  "$(banner_art_line "$word" 4)"
  banner_row_center "$art_b"  "$(banner_art_line "$word" 5)"
  banner_row_center "$border" ''
  banner_row_center "$accent" ">>>  $accent_word  <<<"
  banner_row_center "$border" ''
  banner_row_center "$border" ''
  color_line "$border" '+==========================================================================+'
}
show_banner() {
  enable_fx_if_possible
  set_window_title
  center_window_if_possible
  local line_count=12
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '\033[?25l'
    FX_CURSOR_HIDDEN=1
    local words=("ГЕНДЕР" "REPACK" "ГЕНДЕР" "REPACK" "ГЕНДЕР" "REPACK" "ГЕНДЕР")
    local accent_words=("REPACK" "ГЕНДЕР" "REPACK" "ГЕНДЕР" "REPACK" "ГЕНДЕР" "REPACK")
    local border=(214 220 227 51 45 87 226)
    local art_a=(229 220 229 51 229 45 229)
    local art_b=(229 220 229 51 229 45 229)
    local accent=(118 201 118 51 118 118 118)
    local i
    for i in "${!words[@]}"; do
      render_banner_frame "${words[$i]}" "${accent_words[$i]}" "${border[$i]}" "${art_a[$i]}" "${art_b[$i]}" "${accent[$i]}"
      if [[ "$i" -lt $((${#words[@]} - 1)) ]]; then
        sleep 0.15
        printf '\033[%dA\033[J' "$line_count"
      fi
    done
    printf '\033[?25h'
    FX_CURSOR_HIDDEN=0
  else
    render_banner_frame "REPACK" "ГЕНДЕР" 15 15 15 15
  fi
  printf '\n'
}
step_msg() {
  local label="$1"
  shift
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '%s %s\n' "$(strong_text 51 "[ ЭТАП $label ]")" "$*"
  else
    printf '[ЭТАП %s] %s\n' "$label" "$*"
  fi
}
info_msg() {
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '%s %s\n' "$(strong_text 220 '[ ИНФО ]')" "$*"
  else
    printf '[ИНФО] %s\n' "$*"
  fi
}
success_msg() {
  if [[ "$FX_ENABLED" -eq 1 ]]; then
    printf '%s %s\n' "$(strong_text 84 '[ ГОТОВО ]')" "$*"
  else
    printf '[ГОТОВО] %s\n' "$*"
  fi
}
pause_if_interactive() {
  if [[ -n "${REPACKGENDER_NO_PAUSE:-}" ]]; then
    return 0
  fi
  if [[ -t 0 && -t 1 ]]; then
    printf '\n'
    read -r -p 'Нажми Enter, чтобы закрыть окно...' _ || true
  fi
}
cleanup_exit() {
  local code=$?
  reset_fx
  pause_if_interactive
  exit "$code"
}
trap cleanup_exit EXIT
strip_quotes() {
  local v="$1"
  v="${v#\"}"
  v="${v%\"}"
  v="${v#\'}"
  v="${v%\'}"
  printf '%s' "$v"
}
normalize_input_path() {
  local v="$1"
  v="$(strip_quotes "$v")"
  v="${v//\\ / }"
  v="${v//\\(/(}"
  v="${v//\\)/)}"
  v="${v//\\[/[}"
  v="${v//\\]/]}"
  v="${v//\\\\/\\}"
  printf '%s' "$v"
}
require_java() {
  if use_compatible_java; then
    return 0
  fi
  install_local_java_runtime
  if use_compatible_java; then
    return 0
  fi
  die 'Не удалось подготовить Java 17+. Проверь интернет и запусти установку ещё раз.'
}
java_major_version() {
  local java_cmd="${1:-}"
  local version_line version major minor
  [[ -n "$java_cmd" ]] || return 1
  if [[ "$java_cmd" == */* ]]; then
    [[ -x "$java_cmd" ]] || return 1
  else
    command -v "$java_cmd" >/dev/null 2>&1 || return 1
  fi
  version_line="$("$java_cmd" -version 2>&1 | head -n1 || true)"
  [[ "$version_line" == *\"* ]] || return 1
  version="${version_line#*\"}"
  version="${version%%\"*}"
  IFS=. read -r major minor _ <<<"$version"
  if [[ "$major" == '1' ]]; then
    major="$minor"
  fi
  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$major"
}
use_compatible_java() {
  local candidate major detected_home
  if [[ -n "${REPACKGENDER_JAVA_BIN:-}" ]]; then
    major="$(java_major_version "$REPACKGENDER_JAVA_BIN" || true)"
    if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 17 )); then
      JAVA_BIN="$REPACKGENDER_JAVA_BIN"
      return 0
    fi
  fi
  for candidate in \
    "java" \
    "$JAVA_RUNTIME_DIR/bin/java" \
    "$JAVA_RUNTIME_DIR/Contents/Home/bin/java" \
    "/opt/homebrew/opt/openjdk/bin/java" \
    "/opt/homebrew/opt/openjdk@17/bin/java" \
    "/usr/local/opt/openjdk/bin/java" \
    "/usr/local/opt/openjdk@17/bin/java"; do
    major="$(java_major_version "$candidate" || true)"
    if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 17 )); then
      JAVA_BIN="$candidate"
      return 0
    fi
  done
  if [[ "$OS_NAME" == "macos" ]]; then
    if [[ -n "${JAVA_HOME:-}" ]]; then
      candidate="$JAVA_HOME/bin/java"
      major="$(java_major_version "$candidate" || true)"
      if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 17 )); then
        JAVA_BIN="$candidate"
        return 0
      fi
    fi
    if [[ -x "/usr/libexec/java_home" ]]; then
      detected_home="$(/usr/libexec/java_home -v 17+ 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
      if [[ -n "$detected_home" ]]; then
        candidate="$detected_home/bin/java"
        major="$(java_major_version "$candidate" || true)"
        if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 17 )); then
          JAVA_BIN="$candidate"
          return 0
        fi
      fi
    fi
    for candidate in \
      /Library/Java/JavaVirtualMachines/*/Contents/Home/bin/java \
      "$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home/bin/java; do
      [[ -x "$candidate" ]] || continue
      major="$(java_major_version "$candidate" || true)"
      if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 17 )); then
        JAVA_BIN="$candidate"
        return 0
      fi
    done
  fi
  return 1
}
download_file() {
  local url="$1"
  local target="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$target" "$url"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "$url"
    return 0
  fi
  die 'Не удалось скачать Java автоматически: не найден curl или wget.'
}
resolve_download_url() {
  local url="$1"
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsSI "$url" | tr -d '\r' | awk 'tolower($1) == "location:" {print $2; exit}'
}
resolve_java_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x64\n' ;;
    aarch64|arm64) printf 'aarch64\n' ;;
    *) return 1 ;;
  esac
}
install_local_java_runtime() {
  local arch os api_url archive_url checksum_url expected_sha actual_sha
  local temp_dir archive_file checksum_file extracted_dir extracted_home major
  for extracted_home in "$JAVA_RUNTIME_DIR/bin/java" "$JAVA_RUNTIME_DIR/Contents/Home/bin/java"; do
    if major="$(java_major_version "$extracted_home" || true)" && [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 17 )); then
      JAVA_BIN="$extracted_home"
      return 0
    fi
  done
  if [[ "$OS_NAME" == "macos" ]] && [[ -x "/usr/libexec/java_home" ]]; then
    extracted_home="$("/usr/libexec/java_home" -v 17+ 2>/dev/null || true)"
    if [[ -n "$extracted_home" ]]; then
      JAVA_BIN="$extracted_home/bin/java"
      return 0
    fi
  fi
  arch="$(resolve_java_arch)" || die 'Не удалось автоматически подготовить Java на этой системе.'
  case "$OS_NAME" in
    linux) os='linux' ;;
    macos) os='mac' ;;
    *) die 'Автоматическая подготовка Java поддерживается только на Linux и macOS.' ;;
  esac
  command -v curl >/dev/null 2>&1 || die 'Не удалось автоматически подготовить Java: не найден curl.'
  command -v tar >/dev/null 2>&1 || die 'Не удалось автоматически подготовить Java: не найден tar.'
  info_msg 'Java 17 или новее не найдена.'
  info_msg 'Сейчас попробую скачать и подготовить её автоматически. Это нужно только один раз.'
  mkdir -p "$(dirname "$JAVA_RUNTIME_DIR")"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/repackgender-java.XXXXXX")"
  archive_file="$temp_dir/java-runtime.tar.gz"
  checksum_file="$temp_dir/java-runtime.tar.gz.sha256.txt"
  api_url="https://api.adoptium.net/v3/binary/latest/17/ga/${os}/${arch}/jre/hotspot/normal/eclipse?project=jdk"
  archive_url="$(resolve_download_url "$api_url" || true)"
  if [[ -z "$archive_url" ]]; then
    rm -rf "$temp_dir"
    die 'Не удалось получить ссылку проверки для Java. Проверь интернет и запусти установку ещё раз.'
  fi
  if ! download_file "$api_url" "$archive_file"; then
    rm -rf "$temp_dir"
    die 'Не удалось автоматически подготовить Java. Проверь интернет и запусти установку ещё раз.'
  fi
  checksum_url="${archive_url}.sha256.txt"
  if ! download_file "$checksum_url" "$checksum_file"; then
    rm -rf "$temp_dir"
    die 'Не удалось проверить скачанную Java. Запусти установку ещё раз.'
  fi
  expected_sha="$(awk 'NR==1 {print $1}' "$checksum_file")"
  actual_sha="$(sha256_of "$archive_file")"
  [[ -n "$expected_sha" && "$actual_sha" == "$expected_sha" ]] || {
    rm -rf "$temp_dir"
    die 'Скачанная Java повреждена. Запусти установку ещё раз.'
  }
  if ! tar -xzf "$archive_file" -C "$temp_dir"; then
    rm -rf "$temp_dir"
    die 'Не удалось распаковать Java автоматически. Запусти установку ещё раз.'
  fi
  extracted_dir="$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
  extracted_home="$extracted_dir"
  if [[ -n "$extracted_home" && ! -x "$extracted_home/bin/java" && -x "$extracted_home/Contents/Home/bin/java" ]]; then
    extracted_home="$extracted_home/Contents/Home"
  fi
  [[ -n "$extracted_home" && -x "$extracted_home/bin/java" ]] || {
    rm -rf "$temp_dir"
    die 'Не удалось подготовить Java автоматически.'
  }
  rm -rf "$JAVA_RUNTIME_DIR"
  mv "$extracted_home" "$JAVA_RUNTIME_DIR"
  rm -rf "$temp_dir"
  JAVA_BIN="$JAVA_RUNTIME_DIR/bin/java"
}
require_openssl() {
  if ! command -v openssl >/dev/null 2>&1; then
    die 'Не найден openssl. Он нужен для проверки подписи release-бандла.'
  fi
}
verify_release_certificate() {
  [[ -f "$RELEASE_CERT" ]] || die "Не найден сертификат релиза: $RELEASE_CERT"
  [[ "$(sha256_of "$RELEASE_CERT")" == "$RELEASE_CERT_SHA256" ]] || die 'Сертификат релиза не совпал с ожидаемым отпечатком.'
}
verify_signed_file() {
  local target_file="$1"
  local signature_file="$2"
  local label="$3"
  [[ -f "$target_file" ]] || die "Не найден файл для проверки: $target_file"
  [[ -f "$signature_file" ]] || die "Не найден файл подписи для $label: $signature_file"
  local pubkey_tmp
  pubkey_tmp="$(mktemp "${TMPDIR:-/tmp}/repackgender-pubkey.XXXXXX")"
  if ! openssl x509 -inform DER -in "$RELEASE_CERT" -pubkey -noout >"$pubkey_tmp" 2>/dev/null; then
    rm -f "$pubkey_tmp"
    die 'Не удалось извлечь публичный ключ из сертификата релиза.'
  fi
  if ! openssl dgst -sha256 -verify "$pubkey_tmp" -signature "$signature_file" "$target_file" >/dev/null 2>&1; then
    rm -f "$pubkey_tmp"
    die "Подпись $label не прошла проверку. Установка остановлена."
  fi
  rm -f "$pubkey_tmp"
}
verify_release_manifest() {
  [[ -f "$RELEASE_MANIFEST" ]] || die "Не найден manifest релиза: $RELEASE_MANIFEST"
  [[ -f "$RELEASE_MANIFEST_SIG" ]] || die "Не найден файл подписи manifest релиза: $RELEASE_MANIFEST_SIG"
  verify_signed_file "$RELEASE_MANIFEST" "$RELEASE_MANIFEST_SIG" 'manifest релиза'
  local line expected_hash relative_path target_path actual_hash
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^([0-9a-f]{64})\ \ (.+)$ ]] || die "Некорректная строка в manifest релиза: $line"
    expected_hash="${BASH_REMATCH[1]}"
    relative_path="${BASH_REMATCH[2]}"
    [[ "$relative_path" != /* && "$relative_path" != *'..'* ]] || die "Небезопасный путь в manifest релиза: $relative_path"
    target_path="$ROOT_DIR/$relative_path"
    [[ -f "$target_path" ]] || die "В релизе отсутствует файл из manifest: $relative_path"
    actual_hash="$(sha256_of "$target_path")"
    [[ "$actual_hash" == "$expected_hash" ]] || die "Файл релиза изменён или повреждён: $relative_path"
  done <"$RELEASE_MANIFEST"
}
verify_patcher_release() {
  require_openssl
  [[ -f "$PATCHER_JAR" ]] || die "Не найден patcher jar: $PATCHER_JAR"
  [[ -f "$PATCHER_SIG" ]] || die "Не найден файл подписи patcher jar: $PATCHER_SIG"
  verify_release_certificate
  verify_signed_file "$PATCHER_JAR" "$PATCHER_SIG" 'patcher jar'
}
steam_is_running() {
  if [[ "$OS_NAME" == "macos" ]]; then
    pgrep -f '/Steam.app/' >/dev/null 2>&1
    return
  fi
  pgrep -x steam >/dev/null 2>&1 || pgrep -f steamwebhelper >/dev/null 2>&1
}
launch_steam_if_needed() {
  if [[ -n "${REPACKGENDER_NO_STEAM_START:-}" ]]; then
    return 0
  fi
  if steam_is_running; then
    return 0
  fi
  if [[ "$OS_NAME" == "macos" ]]; then
    if command -v open >/dev/null 2>&1; then
      open -a Steam >/dev/null 2>&1 || open 'steam://open/main' >/dev/null 2>&1 || true
    fi
    return 0
  fi
  if command -v steam >/dev/null 2>&1; then
    nohup steam >/dev/null 2>&1 &
    return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    nohup xdg-open 'steam://open/main' >/dev/null 2>&1 &
  fi
}
find_jar_holders() {
  local live_jar="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -t "$live_jar" 2>/dev/null | sort -u || true
    return 0
  fi
  if command -v fuser >/dev/null 2>&1; then
    fuser "$live_jar" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u || true
    return 0
  fi
  return 0
}
wait_for_game_release() {
  local live_jar="$1"
  local shown=0
  while true; do
    local holders
    holders="$(find_jar_holders "$live_jar")"
    [[ -z "$holders" ]] && break
    if [[ "$shown" -eq 0 ]]; then
      info_msg 'Игра сейчас запущена.'
      info_msg 'Закрой игру. Скрипт подождёт автоматически и продолжит сам.'
      shown=1
    fi
    sleep 2
  done
}
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return 0
  fi
  die 'Не найден инструмент для SHA-256 (sha256sum или shasum).'
}
parse_libraryfolders() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$file" | sed 's#\\\\#/#g'
}
find_live_jar() {
  local roots=() root lib candidate manifest
  for root in "${DEFAULT_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    roots+=("$root")
    while IFS= read -r lib; do
      [[ -n "$lib" ]] && roots+=("$lib")
    done < <(parse_libraryfolders "$root/steamapps/libraryfolders.vdf")
  done
  for root in "${roots[@]}"; do
    manifest="$root/steamapps/appmanifest_${APP_ID}.acf"
    for candidate in \
      "$root/$GAME_RELATIVE_PATH" \
      "$root/steamapps/common/Mafia Online/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Java/MafiaOnline.jar"; do
      if [[ -f "$manifest" && -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  done
  for root in "${roots[@]}"; do
    for candidate in \
      "$root/$GAME_RELATIVE_PATH" \
      "$root/steamapps/common/Mafia Online/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$root/steamapps/common/Mafia Online/Mafia Online.app/Contents/Java/MafiaOnline.jar"; do
      [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
  done
  return 1
}
prompt_path() {
  local label="$1"
  local value=''
  read -r -p "$label" value || true
  strip_quotes "$value"
}
resolve_game_path_input() {
  local input_path="${1:-}"
  local candidate
  input_path="$(normalize_input_path "$input_path")"
  [[ -n "$input_path" ]] || return 1
  if [[ -f "$input_path" ]]; then
    printf '%s\n' "$input_path"
    return 0
  fi
  if [[ -d "$input_path" ]]; then
    for candidate in \
      "$input_path/MafiaOnline.jar" \
      "$input_path/out-windows/MafiaOnline.jar" \
      "$input_path/Contents/Resources/MafiaOnline.jar" \
      "$input_path/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$input_path/Mafia Online.app/Contents/Java/MafiaOnline.jar" \
      "$input_path/Mafia Online/out-windows/MafiaOnline.jar" \
      "$input_path/Mafia Online/Contents/Resources/MafiaOnline.jar" \
      "$input_path/Mafia Online/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$input_path/Mafia Online/Mafia Online.app/Contents/Java/MafiaOnline.jar" \
      "$input_path/steamapps/common/Mafia Online/out-windows/MafiaOnline.jar" \
      "$input_path/steamapps/common/Mafia Online/Contents/Resources/MafiaOnline.jar" \
      "$input_path/steamapps/common/Mafia Online/Mafia Online.app/Contents/Resources/MafiaOnline.jar" \
      "$input_path/steamapps/common/Mafia Online/Mafia Online.app/Contents/Java/MafiaOnline.jar"; do
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi
  return 1
}
resolve_live_jar() {
  local live_jar="${1:-}"
  if live_jar="$(resolve_game_path_input "$live_jar" 2>/dev/null)"; then
    printf '%s\n' "$live_jar"
    return 0
  fi
  if live_jar="$(find_live_jar 2>/dev/null)"; then
    printf '%s\n' "$live_jar"
    return 0
  fi
  live_jar="$(prompt_path 'Не удалось найти игру автоматически. Перетащи сюда папку с игрой/файл или вставь путь вручную: ')"
  live_jar="$(resolve_game_path_input "$live_jar" 2>/dev/null || true)"
  [[ -n "$live_jar" && -f "$live_jar" ]] || die 'Не удалось найти игру Mafia Online.'
  printf '%s\n' "$live_jar"
}
find_supported_clean_backup() {
  local candidate
  [[ -d "$BACKUP_DIR" ]] || return 1
  while IFS= read -r candidate; do
    [[ -f "$candidate" ]] || continue
    if is_supported_clean_sha "$(sha256_of "$candidate")"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.jar' -print 2>/dev/null | sort -r)
  return 1
}
request_steam_validation() {
  if [[ -n "${REPACKGENDER_NO_STEAM_VALIDATE:-}" ]]; then
    return 1
  fi
  launch_steam_if_needed
  if [[ "$OS_NAME" == "macos" ]]; then
    command -v open >/dev/null 2>&1 || return 1
    open "steam://validate/$APP_ID" >/dev/null 2>&1 || return 1
    return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    nohup xdg-open "steam://validate/$APP_ID" >/dev/null 2>&1 &
    return 0
  fi
  if command -v steam >/dev/null 2>&1; then
    nohup steam "steam://validate/$APP_ID" >/dev/null 2>&1 &
    return 0
  fi
  return 1
}
wait_for_target_live_clean() {
  local live_jar="$1"
  local target_sha="$2"
  local timeout_sec="${3:-900}"
  local interval=5 elapsed=0 live_sha=''
  if (( timeout_sec <= 0 )); then
    return 1
  fi
  info_msg "Жду завершения проверки Steam (до ${timeout_sec} сек)..."
  while (( elapsed < timeout_sec )); do
    live_sha="$(sha256_of "$live_jar" 2>/dev/null || true)"
    if is_target_clean_sha "$live_sha" "$target_sha"; then
      info_msg 'Steam-проверка завершена: clean-хэш подтверждён.'
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  info_msg 'Steam-проверка не дала clean-хэш за отведённое время.'
  return 1
}
prepare_clean_jar() {
  local live_jar="$1"
  local supplied_clean="${2:-}"
  local resolved_clean='' supplied_sha='' live_sha='' backup_clean='' validate_timeout='' expected_shas='' target_sha=''
  load_supported_clean_shas
  mkdir -p "$(dirname "$CLEAN_JAR")" "$(dirname "$PATCHED_JAR")" "$BACKUP_DIR" "$LOG_DIR"
  live_sha="$(sha256_of "$live_jar")"
  resolved_clean="$(resolve_game_path_input "$supplied_clean" 2>/dev/null || true)"
  if [[ -f "$resolved_clean" ]]; then
    supplied_sha="$(sha256_of "$resolved_clean")"
  fi
  target_sha="$(choose_target_clean_sha "$live_sha" "$supplied_sha")"
  if [[ -f "$CLEAN_JAR" ]]; then
    if is_target_clean_sha "$(sha256_of "$CLEAN_JAR")" "$target_sha"; then
      return 0
    fi
    info_msg 'Локальная clean-копия устарела или изменена. Пересобираю clean автоматически.'
    rm -f "$CLEAN_JAR"
  fi
  if [[ -f "$resolved_clean" ]]; then
    if is_target_clean_sha "$supplied_sha" "$target_sha"; then
      cp -f "$resolved_clean" "$CLEAN_JAR"
      return 0
    fi
    info_msg 'Хэш указанного clean-файла отличается от списка поддерживаемых. Ищу clean автоматически.'
  fi
  if is_target_clean_sha "$live_sha" "$target_sha"; then
    cp -f "$live_jar" "$CLEAN_JAR"
    return 0
  fi
  while IFS= read -r backup_clean; do
    [[ -f "$backup_clean" ]] || continue
    if is_target_clean_sha "$(sha256_of "$backup_clean")" "$target_sha"; then
      info_msg 'Нашёл clean в локальных backup. Использую его автоматически.'
      cp -f "$backup_clean" "$CLEAN_JAR"
      return 0
    fi
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.jar' -print 2>/dev/null | sort -r)
  if [[ -n "${REPACKGENDER_ALLOW_UNSUPPORTED_CLEAN:-}" ]]; then
    info_msg 'Не удалось подтвердить поддерживаемый clean-хэш локально.'
    info_msg 'Режим совместимости включён: пропускаю ожидание Steam и использую текущий файл игры как clean-базу.'
    cp -f "$live_jar" "$CLEAN_JAR"
    return 0
  fi
  info_msg 'Не нашёл clean локально. Пробую запустить проверку файлов в Steam автоматически.'
  if request_steam_validation; then
    if [[ -n "${REPACKGENDER_STEAM_VALIDATE_TIMEOUT:-}" ]]; then
      validate_timeout="$REPACKGENDER_STEAM_VALIDATE_TIMEOUT"
    elif [[ "$OS_NAME" == "macos" ]]; then
      validate_timeout=60
    else
      validate_timeout=900
    fi
    if wait_for_target_live_clean "$live_jar" "$target_sha" "$validate_timeout"; then
      cp -f "$live_jar" "$CLEAN_JAR"
      return 0
    fi
  fi
  live_sha="$(sha256_of "$live_jar" 2>/dev/null || true)"
  expected_shas="$(supported_clean_sha_list)"
  die "Не удалось подготовить clean-клиент автоматически. Текущий SHA: ${live_sha:-unknown}. Поддерживаемые SHA: $expected_shas. Запусти в Steam «Проверить целостность файлов», дождись окончания и повтори установку. Для принудительного режима совместимости можно запустить с REPACKGENDER_ALLOW_UNSUPPORTED_CLEAN=1."
}
run_patcher() {
  local clean_jar="$1"
  local out_jar="$2"
  local log_file="$3"
  local rc=0
  local tmp_log="${log_file}.tmp"
  rm -f "$tmp_log" "$log_file"
  set +e
  "$JAVA_BIN" -jar "$PATCHER_JAR" "$clean_jar" "$out_jar" >"$tmp_log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    {
      printf 'Установка прервана на этапе патчера.\n'
      printf 'Код завершения: %s\n' "$rc"
      printf 'Подробный лог отключён в безопасном режиме.\n'
    } >"$log_file"
    rm -f "$tmp_log"
    msg ''
    msg 'Установка прервана.'
    msg "Лог сохранён: $log_file"
    exit "$rc"
  fi
  rm -f "$tmp_log" "$log_file"
}
cleanup_install_logs() {
  mkdir -p "$LOG_DIR"
  find "$LOG_DIR" -maxdepth 1 -type f -name 'install-*.log' -delete 2>/dev/null || true
  find "$LOG_DIR" -maxdepth 1 -type f -name 'install-*.log.tmp' -delete 2>/dev/null || true
}
install_patch() {
  local live_jar clean_arg ts backup_target patched_sha live_sha log_file steam_was_running
  show_banner
  require_java
  live_jar="$(resolve_live_jar "${1:-}")"
  clean_arg="${2:-}"
  steam_was_running=0
  if steam_is_running; then
    steam_was_running=1
  fi
  step_msg '1/5' 'Проверка подписи release-бандла...'
  verify_patcher_release
  step_msg '2/5' 'Подготовка clean-клиента...'
  wait_for_game_release "$live_jar"
  prepare_clean_jar "$live_jar" "$clean_arg"
  cleanup_install_logs
  ts="$(date +%Y%m%d-%H%M%S)"
  log_file="$LOG_DIR/install-$ts.log"
  step_msg '3/5' 'Сборка patched jar...'
  run_patcher "$CLEAN_JAR" "$PATCHED_JAR" "$log_file"
  step_msg '4/5' 'Создание резервной копии live-файла...'
  backup_target="$BACKUP_DIR/live-before-install-$ts.jar"
  cp -f "$live_jar" "$backup_target"
  step_msg '5/5' 'Замена клиента...'
  cp -f "$PATCHED_JAR" "$live_jar"
  patched_sha="$(sha256_of "$PATCHED_JAR")"
  live_sha="$(sha256_of "$live_jar")"
  rm -f "$PATCHED_JAR"
  msg ''
  success_msg 'Установка завершена.'
  info_msg "Файл игры: $live_jar"
  info_msg "Резервная копия: $backup_target"
  info_msg "SHA patched: $patched_sha"
  info_msg "SHA live:    $live_sha"
  if [[ "$steam_was_running" -eq 0 ]]; then
    launch_steam_if_needed
    info_msg 'Steam был закрыт. Я попробовал открыть его автоматически.'
  fi
}
restore_clean() {
  local live_jar ts backup_target live_sha clean_sha restore_source backup_clean
  show_banner
  live_jar="$(resolve_live_jar "${1:-}")"
  load_supported_clean_shas
  [[ -f "$CLEAN_JAR" ]] || die 'Локальная clean-копия не найдена. Восстанавливать нечего.'
  restore_source="$CLEAN_JAR"
  clean_sha="$(sha256_of "$restore_source")"
  if ! is_supported_clean_sha "$clean_sha"; then
    backup_clean="$(find_supported_clean_backup || true)"
    if [[ -n "$backup_clean" ]]; then
      restore_source="$backup_clean"
      clean_sha="$(sha256_of "$restore_source")"
      info_msg 'Локальная clean-копия устарела. Восстанавливаю актуальный clean из backup.'
    else
      die "Локальная clean-копия устарела. Запусти в Steam «Проверить целостность файлов», затем снова установку мода."
    fi
  fi
  mkdir -p "$BACKUP_DIR"
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_target="$BACKUP_DIR/live-before-restore-$ts.jar"
  cp -f "$live_jar" "$backup_target"
  cp -f "$restore_source" "$live_jar"
  live_sha="$(sha256_of "$live_jar")"
  msg ''
  success_msg 'Чистый клиент восстановлен.'
  info_msg "Файл игры: $live_jar"
  info_msg "Резервная копия: $backup_target"
  info_msg "SHA clean: $clean_sha"
  info_msg "SHA live:  $live_sha"
}
case "$MODE" in
  install) install_patch "${1:-}" "${2:-}" ;;
  restore) restore_clean "${1:-}" ;;
  *) die "Неизвестный режим: $MODE" ;;
esac
