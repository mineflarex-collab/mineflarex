#!/usr/bin/env bash
# ============================================================================
#  MineFlareX Installer - Advanced VPS & Hosting Management
#  Run:  bash <(curl -s https://mineflarex.indevs.in/install.sh)
# ============================================================================
set -uo pipefail

MFX_VERSION="1.0.0"
BASE_URL="${MFX_BASE_URL:-https://mineflarex.indevs.in}"
BOT_REPO="${MFX_BOT_REPO:-https://github.com/mineflarex-collab/Bvm-v1bot.git}"
INSTALL_ROOT="/opt/mineflarex"
BOT_DIR="$INSTALL_ROOT/Bvm-v1bot"
STATE_DIR="/var/lib/mineflarex"
LOG_DIR="/var/log/mineflarex"

LOG_FILE=/dev/null
TMP=""
PM=""
VIRT=""
VIRT_LABEL=""
KEY=""
MSG=""
REDRAW=""
RESIZED=0
STAGE_TOTAL=0
STAGE_DONE=0
SPIN_OUT=""
SPIN_RC=0
CUR_KEY=""; CUR_TITLE=""; CUR_FN=""; CUR_INFO=()

# ----------------------------------------------------------------------------
#  Core helpers: logging, locale, theme, screen
# ----------------------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }

cleanup() {
  printf '\e[?25h\e[0m' 2>/dev/null
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

setup_locale() {
  UTF=0
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) UTF=1 ;;
  esac
  if (( ! UTF )) && locale -a 2>/dev/null | grep -qi '^c\.utf'; then
    export LC_ALL=C.UTF-8; UTF=1
  fi
  if (( UTF )); then
    TL='╔'; TR='╗'; BL='╚'; BR='╝'; H='═'; V='║'; ML='╠'; MR='╣'
    BLK='█'; BARF='█'; BARE='░'; OK='✔'; BAD='✘'; ARW='▶'; WRN='!'
    SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  else
    TL='+'; TR='+'; BL='+'; BR='+'; H='-'; V='|'; ML='+'; MR='+'
    BLK='#'; BARF='#'; BARE='-'; OK='OK'; BAD='XX'; ARW='>'; WRN='!'
    SPIN=('|' '/' '-' '\')
  fi
}

setup_theme() {
  # MFX_COLOR=true|256|16 forces a mode. Default: auto-detect.
  local mode="${MFX_COLOR:-auto}" tc=0 nc=0
  case "${COLORTERM:-}" in truecolor|24bit) tc=1 ;; esac
  nc=$(tput colors 2>/dev/null || echo 0)
  [[ $nc =~ ^[0-9]+$ ]] || nc=0
  if [ "$mode" = auto ]; then
    if (( tc )); then mode=true
    elif (( nc >= 256 )); then mode=256
    else mode=16; fi
  fi
  case "$mode" in
    true)
      P=$'\e[38;2;168;85;247m'
      SH=($'\e[38;2;233;213;254m' $'\e[38;2;216;180;254m' $'\e[38;2;192;132;252m' $'\e[38;2;168;85;247m' $'\e[38;2;147;51;234m')
      BGC=$'\e[48;2;0;0;0m'
      WHT=$'\e[97m'; DIM=$'\e[90m'; GRN=$'\e[38;5;83m'; RED=$'\e[38;5;203m'; YEL=$'\e[38;5;221m' ;;
    256)
      P=$'\e[38;5;135m'
      SH=($'\e[38;5;189m' $'\e[38;5;183m' $'\e[38;5;177m' $'\e[38;5;135m' $'\e[38;5;98m')
      BGC=$'\e[40m'
      WHT=$'\e[97m'; DIM=$'\e[90m'; GRN=$'\e[38;5;83m'; RED=$'\e[38;5;203m'; YEL=$'\e[38;5;221m' ;;
    *)  # basic 16-color terminals (no forced background)
      P=$'\e[95m'
      SH=($'\e[95m' $'\e[95m' $'\e[35m' $'\e[35m' $'\e[35m')
      BGC=""
      WHT=$'\e[97m'; DIM=$'\e[37m'; GRN=$'\e[92m'; RED=$'\e[91m'; YEL=$'\e[93m' ;;
  esac
  BLD=$'\e[1m'
  RST=$'\e[0m'"$BGC"
}

update_dims() {
  local sz r c
  sz=$(stty size </dev/tty 2>/dev/null) || sz=""
  r=${sz% *}; c=${sz#* }
  [[ $r =~ ^[0-9]+$ ]] || r=24
  [[ $c =~ ^[0-9]+$ ]] || c=80
  ROWS=$r; COLS=$c
  W=$((COLS - 4)); (( W > 66 )) && W=66; (( W < 40 )) && W=40
  PAD=$(( (COLS - W) / 2 )); (( PAD < 0 )) && PAD=0
}

clear_screen() { printf '%s\e[H\e[2J\e[3J' "$RST"; }

rep() { local n=$2 s; (( n <= 0 )) && return 0; printf -v s '%*s' "$n" ''; printf '%s' "${s// /$1}"; }

# ----------------------------------------------------------------------------
#  Box drawing
# ----------------------------------------------------------------------------
box_top() { printf '%*s%s%s%s%s%s\n' "$PAD" '' "$P" "$TL" "$(rep "$H" $((W-2)))" "$TR" "$RST"; }
box_bot() { printf '%*s%s%s%s%s%s\n' "$PAD" '' "$P" "$BL" "$(rep "$H" $((W-2)))" "$BR" "$RST"; }
box_sep() { printf '%*s%s%s%s%s%s\n' "$PAD" '' "$P" "$ML" "$(rep "$H" $((W-2)))" "$MR" "$RST"; }

box_raw_l() {  # colored_text visible_len
  local txt=$1 sp=$(( W - 4 - $2 ))
  (( sp < 0 )) && sp=0
  printf '%*s%s%s%s %s%*s %s%s%s\n' "$PAD" '' "$P" "$V" "$RST" "$txt" "$sp" '' "$P" "$V" "$RST"
}
box_raw_c() {
  local txt=$1 vlen=$2 inner=$(( W - 2 )) lead trail
  lead=$(( (inner - vlen) / 2 )); (( lead < 0 )) && lead=0
  trail=$(( inner - vlen - lead )); (( trail < 0 )) && trail=0
  printf '%*s%s%s%s%*s%s%*s%s%s%s\n' "$PAD" '' "$P" "$V" "$RST" "$lead" '' "$txt" "$trail" '' "$P" "$V" "$RST"
}
box_blank() { box_raw_l "" 0; }
box_row()    { local t=${1:0:$((W-4))} c=${2:-$WHT}; box_raw_l "$c$t$RST" "${#t}"; }
box_center() { local t=${1:0:$((W-4))} c=${2:-$WHT}; box_raw_c "$c$t$RST" "${#t}"; }
box_kv() {     # key label desc
  local key=$1 lab desc=$3 room
  printf -v lab '%-16s' "$2"
  room=$(( W - 4 - ${#key} - 1 - ${#lab} - 1 ))
  desc=${desc:0:$(( room > 0 ? room : 0 ))}
  box_raw_l "${P}${BLD}${key}${RST} ${WHT}${lab}${RST} ${DIM}${desc}${RST}" $(( ${#key} + 1 + ${#lab} + 1 + ${#desc} ))
}

# ----------------------------------------------------------------------------
#  Logo / headers
# ----------------------------------------------------------------------------
glyph() {
  case $1 in
    M) G=("#   #" "## ##" "# # #" "#   #" "#   #") ;;
    I) G=("#####" "  #  " "  #  " "  #  " "#####") ;;
    N) G=("#   #" "##  #" "# # #" "#  ##" "#   #") ;;
    E) G=("#####" "#    " "#### " "#    " "#####") ;;
    F) G=("#####" "#    " "#### " "#    " "#    ") ;;
    L) G=("#    " "#    " "#    " "#    " "#####") ;;
    A) G=(" ### " "#   #" "#####" "#   #" "#   #") ;;
    R) G=("#### " "#   #" "#### " "#  # " "#   #") ;;
    X) G=("#   #" " # # " "  #  " " # # " "#   #") ;;
  esac
}

build_logo() {
  LOGO=(); local r ch line
  for r in 0 1 2 3 4; do
    line=""
    for ch in M I N E F L A R E X; do glyph "$ch"; line+="${G[r]} "; done
    line=${line% }
    LOGO+=("${line//\#/$BLK}")
  done
}

header_full() {
  clear_screen
  box_top
  box_blank
  if (( W >= 61 )); then
    local r
    for r in 0 1 2 3 4; do box_raw_c "${SH[r]}${BLD}${LOGO[r]}${RST}" 59; done
  else
    box_center "M I N E F L A R E X" "$P$BLD"
  fi
  box_blank
  box_center "Advanced VPS & Hosting Management" "$WHT"
  box_center "v$MFX_VERSION  |  mineflarex.indevs.in" "$DIM"
  box_sep
}

header_small() {
  clear_screen
  box_top
  box_center "M I N E F L A R E X" "$P$BLD"
  box_center "Advanced VPS & Hosting Management" "$DIM"
  box_sep
  box_center "$1" "$WHT$BLD"
  box_sep
}

# ----------------------------------------------------------------------------
#  Input helpers
# ----------------------------------------------------------------------------
read_key() {
  local k rc
  while true; do
    IFS= read -rsn1 -t 0.3 k </dev/tty; rc=$?
    if (( rc == 0 )); then KEY=$k; return 0
    elif (( rc > 128 )); then
      if (( RESIZED )); then
        RESIZED=0; update_dims
        [ -n "${REDRAW:-}" ] && "$REDRAW"
      fi
    else
      KEY=""; return 1
    fi
  done
}
drain_esc() { IFS= read -rsn2 -t 0.05 _ </dev/tty || true; }
press_any_key() { printf '\n%*s%sPress any key to continue...%s' "$PAD" '' "$DIM" "$RST"; read_key || exit 0; }
ask_yn() {
  printf '\n  %s?%s %s %s[y/N]%s ' "$YEL" "$RST" "$1" "$DIM" "$RST"
  read_key || exit 0
  printf '%s\n' "${KEY:-n}"
  [[ $KEY == [yY] ]]
}

# ----------------------------------------------------------------------------
#  Spinner / progress engine (progress % = completed real stages)
# ----------------------------------------------------------------------------
bar() { local pct=$1 w=${2:-20} f; f=$(( pct * w / 100 )); printf '%s%s%s%s%s' "$P" "$(rep "$BARF" "$f")" "$DIM" "$(rep "$BARE" $(( w - f )))" "$RST"; }

spin_run() {   # label cmd...   (cmd runs in background; stdout captured in SPIN_OUT)
  local label=$1; shift
  local outf pid i=0 pct
  outf=$(mktemp "$TMP/out.XXXXXX")
  printf '\e[?25l'
  "$@" >"$outf" 2>>"$LOG_FILE" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if (( STAGE_TOTAL > 0 )); then
      pct=$(( STAGE_DONE * 100 / STAGE_TOTAL ))
      printf '\r\e[K  %s%s%s %s  [%s] %s%3d%%%s' "$P" "${SPIN[i % ${#SPIN[@]}]}" "$RST" "$label" "$(bar "$pct")" "$WHT" "$pct" "$RST"
    else
      printf '\r\e[K  %s%s%s %s' "$P" "${SPIN[i % ${#SPIN[@]}]}" "$RST" "$label"
    fi
    i=$((i + 1)); sleep 0.1
  done
  wait "$pid"; SPIN_RC=$?
  SPIN_OUT=$(<"$outf"); rm -f "$outf"
  printf '\r\e[K\e[?25h'
  return "$SPIN_RC"
}

check() {      # label cmd...  -> prints result line
  local label=$1; shift
  spin_run "$label" "$@"; local rc=$?
  local first=${SPIN_OUT%%$'\n'*}
  if (( rc == 0 )); then
    printf '  %s%s%s %s' "$GRN" "$OK" "$RST" "$label"
    [ -n "$first" ] && printf '  %s%s%s' "$DIM" "$first" "$RST"
    printf '\n'
  else
    printf '  %s%s%s %s\n' "$RED" "$BAD" "$RST" "$label"
  fi
  log "check '$label' rc=$rc ${first}"
  return "$rc"
}

show_error() {  # label rc
  printf '  %s%s%s %s%s failed%s (exit %s)\n' "$RED" "$BAD" "$RST" "$BLD" "$1" "$RST" "$2"
  printf '\n  %s%sERROR DETAILS%s\n' "$RED" "$BLD" "$RST"
  if [ -n "$SPIN_OUT" ]; then
    printf '%s\n' "$SPIN_OUT" | tail -n 5 | cut -c1-$((COLS - 6)) | sed "s/^/    ${RED}/;s/\$/${RST}/"
  fi
  if [ "$LOG_FILE" != /dev/null ] && [ -s "$LOG_FILE" ]; then
    printf '  %sLast log lines (%s):%s\n' "$DIM" "$LOG_FILE" "$RST"
    tail -n 6 "$LOG_FILE" | cut -c1-$((COLS - 6)) | sed "s/^/    ${DIM}/;s/\$/${RST}/"
  fi
  log "FAILED stage '$1' rc=$2 :: ${SPIN_OUT%%$'\n'*}"
}

stage() {      # label cmd...  (background, logged, real progress)
  local label=$1; shift
  log "STAGE $((STAGE_DONE + 1))/$STAGE_TOTAL: $label"
  spin_run "$label" "$@"; local rc=$?
  if (( rc == 0 )); then
    STAGE_DONE=$((STAGE_DONE + 1))
    local pct=$(( STAGE_DONE * 100 / STAGE_TOTAL ))
    printf '  %s%s%s %-34s [%s] %s%3d%%%s\n' "$GRN" "$OK" "$RST" "$label" "$(bar "$pct")" "$WHT" "$pct" "$RST"
    local first=${SPIN_OUT%%$'\n'*}
    [ -n "$first" ] && printf '    %s%s%s\n' "$DIM" "${first:0:$((COLS - 8))}" "$RST"
    return 0
  fi
  show_error "$label" "$rc"
  return 1
}

stage_fg() {   # label cmd...  (interactive, runs in foreground on the tty)
  local label=$1; shift
  log "STAGE(fg) $((STAGE_DONE + 1))/$STAGE_TOTAL: $label"
  printf '  %s%s%s %s %s(interactive - live output below)%s\n\n' "$P" "$ARW" "$RST" "$label" "$DIM" "$RST"
  "$@"; local rc=$?
  printf '\n'
  if (( rc == 0 )); then
    STAGE_DONE=$((STAGE_DONE + 1))
    printf '  %s%s%s %-34s [%s] %s100%%%s\n' "$GRN" "$OK" "$RST" "$label" "$(bar 100)" "$WHT" "$RST"
    return 0
  fi
  SPIN_OUT="Module exited with code $rc"
  show_error "$label" "$rc"
  return 1
}

# ----------------------------------------------------------------------------
#  Environment checks
# ----------------------------------------------------------------------------
detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then PM=apt
  elif command -v dnf >/dev/null 2>&1; then PM=dnf
  elif command -v yum >/dev/null 2>&1; then PM=yum
  else PM=""; return 1; fi
}

chk_env() {
  [ "$(uname -s)" = "Linux" ] || { echo "Unsupported OS: $(uname -s). A Linux VPS is required."; return 1; }
  if [ -n "${TERMUX_VERSION:-}" ] || [[ "${PREFIX:-}" == *com.termux* ]] || [ -d /data/data/com.termux ]; then
    echo "Termux detected - unsupported. Use a Linux VPS (Debian/Ubuntu/RHEL-based)."; return 1
  fi
  [ -n "$PM" ] || { echo "Unsupported distro: apt/dnf/yum not found."; return 1; }
  ( : </dev/tty ) 2>/dev/null || { echo "No interactive terminal (/dev/tty) available."; return 1; }
  (( BASH_VERSINFO[0] >= 4 )) || { echo "Bash 4+ required."; return 1; }
  echo "Linux + $PM"
}

chk_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Root required. Run 'sudo -i' first, then run the command again."; return 1; }
  echo "root"
}

detect_lxc() {
  local v
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    v=$(systemd-detect-virt --container 2>/dev/null || true)
    case $v in lxc|lxc-libvirt) return 0 ;; esac
  fi
  [ -r /run/systemd/container ] && grep -qi '^lxc' /run/systemd/container && return 0
  [ -r /proc/1/environ ] && tr '\0' '\n' </proc/1/environ 2>/dev/null | grep -qi '^container=lxc' && return 0
  [ -r /proc/1/cgroup ] && grep -qE '/lxc[./]|/lxc$' /proc/1/cgroup && return 0
  return 1
}

detect_kvm() {
  local v f
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    v=$(systemd-detect-virt --vm 2>/dev/null || true)
    case $v in kvm|qemu) return 0 ;; esac
  fi
  for f in /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name; do
    [ -r "$f" ] && grep -qiE 'qemu|kvm' "$f" && return 0
  done
  if grep -qw hypervisor /proc/cpuinfo 2>/dev/null && grep -qiE 'qemu|kvm' /proc/cpuinfo 2>/dev/null; then return 0; fi
  [ -c /dev/kvm ] && return 0
  return 1
}

chk_virt() {
  local out=""
  detect_lxc && out+="LXC "
  detect_kvm && out+="KVM "
  [ -n "$out" ] || return 1
  echo "$out"
}

ensure_deps() {
  local need=() c
  for c in curl sha256sum awk grep sed tar df mktemp stty tput head tail cut tr wc; do
    command -v "$c" >/dev/null 2>&1 || need+=("$c")
  done
  if (( ${#need[@]} == 0 )); then echo "all present"; return 0; fi
  log "Missing dependencies: ${need[*]}"
  (
    case $PM in
      apt) apt-get update -y && apt-get install -y curl coreutils gawk grep sed tar ncurses-bin ;;
      dnf) dnf install -y curl coreutils gawk grep sed tar ncurses ;;
      yum) yum install -y curl coreutils gawk grep sed tar ncurses ;;
    esac
  ) >>"$LOG_FILE" 2>&1 || { echo "Package install failed (see log)"; return 1; }
  for c in "${need[@]}"; do command -v "$c" >/dev/null 2>&1 || { echo "Could not install: $c"; return 1; }; done
  echo "installed: ${need[*]}"
}

chk_net() {
  curl --proto '=https' --tlsv1.2 -fsS --connect-timeout 6 --max-time 12 -o /dev/null https://github.com 2>/dev/null \
    && echo "online" || { echo "no internet access"; return 1; }
}

init_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null && chmod 750 "$LOG_DIR" 2>/dev/null
  LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
  : >"$LOG_FILE" 2>/dev/null || LOG_FILE="$TMP/install.log"
  chmod 640 "$LOG_FILE" 2>/dev/null
  log "MineFlareX v$MFX_VERSION started on $(uname -srm)"
}

boot_fail() {
  printf '\n  %s%sERROR:%s %s\n\n' "$RED" "$BLD" "$RST" "$1"
  log "BOOT FAIL: $1"
  exit 1
}

boot() {
  header_full
  box_center "Initializing MineFlareX..." "$P"
  box_bot
  printf '\n'
  check "Checking environment"      chk_env  || boot_fail "$SPIN_OUT"
  check "Checking root permission"  chk_root || boot_fail "$SPIN_OUT"
  init_log

  # Virtualization is only detected silently (no error, no display).
  VIRT=""
  detect_lxc && VIRT="lxc"
  detect_kvm && VIRT+="${VIRT:++}kvm"
  VIRT_LABEL="${VIRT^^}"
  log "Virtualization (info only): ${VIRT:-none}"

  check "Checking dependencies" ensure_deps || boot_fail "$SPIN_OUT"
  if ! check "Checking network" chk_net; then
    printf '    %s%s Network check failed - downloads may fail later%s\n' "$YEL" "$WRN" "$RST"
  fi
  sleep 0.6
}

# ----------------------------------------------------------------------------
#  Download / validation primitives (HTTPS only)
# ----------------------------------------------------------------------------
preflight() {  # url
  local avail
  avail=$(df -Pk / | awk 'NR==2{print $4}')
  (( avail >= 1048576 )) || { echo "Low disk space: $((avail / 1024)) MB free (need 1024 MB)"; return 1; }
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --connect-timeout 8 --max-time 20 \
       -r 0-1023 -o /dev/null "$1" || { echo "Cannot reach source: $1"; return 1; }
  echo "disk $((avail / 1024)) MB free, source reachable"
}

validate_script() {
  local f=$1 size first err re='^#!.*(bash|sh)'
  [ -s "$f" ] || { echo "Downloaded file is empty"; return 1; }
  size=$(wc -c <"$f" | tr -d ' ')
  (( size <= 2097152 )) || { echo "Script too large (${size} bytes)"; return 1; }
  first=$(head -n1 "$f" | tr -d '\r')
  [[ $first =~ $re ]] || { echo "Missing shell shebang (got: ${first:0:40})"; return 1; }
  if grep -qiE '<(!doctype|html|head|body)' "$f"; then echo "File looks like HTML, not a script"; return 1; fi
  if ! err=$(bash -n "$f" 2>&1); then echo "Syntax check failed: ${err%%$'\n'*}"; return 1; fi
  echo "valid script, ${size} bytes, sha256 $(sha256sum "$f" | cut -c1-12)..."
}

mark_installed() { mkdir -p "$STATE_DIR" && printf '%s installed %s\n' "$(date '+%F %T')" "$1" >>"$STATE_DIR/$1.installed"; }

ensure_git() {
  if command -v git >/dev/null 2>&1; then echo "git $(git --version | awk '{print $3}')"; return 0; fi
  (
    case $PM in
      apt) apt-get update -y && apt-get install -y git ;;
      dnf) dnf install -y git ;;
      yum) yum install -y git ;;
    esac
  ) >>"$LOG_FILE" 2>&1 || { echo "git installation failed (see log)"; return 1; }
  command -v git >/dev/null 2>&1 || { echo "git still missing after install"; return 1; }
  echo "git installed"
}

git_fetch_repo() {  # repo dir  (clone if absent, fast-forward pull if it is already a git checkout)
  local repo=$1 dir=$2
  [[ $repo == https://* ]] || { echo "Refusing non-HTTPS repo: $repo"; return 1; }
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only >>"$LOG_FILE" 2>&1 || { echo "git pull failed (local changes?) in $dir"; return 1; }
  elif [ -e "$dir" ]; then
    echo "$dir exists and is not a git checkout - not touching it"; return 1
  else
    mkdir -p "$(dirname "$dir")"
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$repo" "$dir" >>"$LOG_FILE" 2>&1 \
      || { echo "git clone failed (repo private or unreachable?): $repo"; return 1; }
  fi
  echo "commit $(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
}

run_bot_installer() {
  ( cd "$BOT_DIR" && chmod +x install.sh && env MFX_VIRT="$VIRT" MFX_LOG="$LOG_FILE" ./install.sh </dev/tty )
}

# ----------------------------------------------------------------------------
#  Generic module menu engine
# ----------------------------------------------------------------------------
draw_module_menu() {
  header_small "$CUR_TITLE"
  local l
  for l in "${CUR_INFO[@]}"; do box_row "$l" "$DIM"; done
  box_sep
  box_kv "[1]" "Start Install"  "Begin installation"
  box_kv "[2]" "View Log"       "Show recent log lines"
  box_kv "[B]" "Back"           "Back to Main Menu"
  box_kv "[0]" "Exit"           ""
  box_bot
  [ -n "$MSG" ] && printf '\n%*s%s%s%s\n' "$PAD" '' "$RED" "$MSG" "$RST"
  printf '\n%*s%sSelect option:%s ' "$PAD" '' "$P$BLD" "$RST"
}

confirm_install() {
  REDRAW=""
  header_small "$CUR_TITLE - CONFIRM"
  local l
  for l in "${CUR_INFO[@]}"; do box_row "$l" "$WHT"; done
  box_sep
  box_row "Log file: $LOG_FILE" "$DIM"
  box_bot
  ask_yn "Proceed with installation of $CUR_TITLE?"
}

run_install() {
  REDRAW=""
  header_small "$CUR_TITLE - INSTALLING"
  box_row "Log: $LOG_FILE" "$DIM"
  box_bot
  log "=== BEGIN $CUR_KEY ==="
  "$CUR_FN"; local rc=$?
  log "=== END $CUR_KEY rc=$rc ==="
  printf '\n'
  case $rc in
    0) box_top; box_center "INSTALLATION COMPLETE" "$GRN$BLD"; box_center "$CUR_TITLE installed successfully" "$WHT"
       box_row "Log: $LOG_FILE" "$DIM"; box_bot ;;
    2) printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST" ;;
    *) printf '  %s%sINSTALLATION FAILED%s - see details above.\n  Log: %s\n' "$RED" "$BLD" "$RST" "$LOG_FILE" ;;
  esac
  press_any_key
}

view_log() {
  REDRAW=""
  header_small "INSTALLATION LOG"
  box_bot
  printf '\n'
  tail -n 25 "$LOG_FILE" 2>/dev/null | cut -c1-$((COLS - 4)) | sed 's/^/  /'
  press_any_key
}

do_exit() {
  clear_screen
  box_top; box_center "Thanks for using MineFlareX" "$P$BLD"; box_center "Log: $LOG_FILE" "$DIM"; box_bot
  printf '\n'
  exit 0
}

module_menu() {  # key title install_fn   (CUR_INFO set by caller)
  CUR_KEY=$1; CUR_TITLE=$2; CUR_FN=$3; MSG=""
  while true; do
    REDRAW=draw_module_menu
    draw_module_menu
    read_key || exit 0
    MSG=""
    case $KEY in
      1) confirm_install && run_install ;;
      2) view_log ;;
      b|B) return 0 ;;
      0|q|Q) do_exit ;;
      $'\e') drain_esc; MSG="Invalid input. Use 1, 2, B or 0." ;;
      "") MSG="Please press 1, 2, B or 0." ;;
      *) MSG="Invalid option '${KEY//[^[:print:]]/?}'. Use 1, 2, B or 0." ;;
    esac
  done
}

# ============================================================================
#  MODULE 1: BVM VPS BOT  (git clone -> install.sh)
# ============================================================================
install_bvm_bot() {
  STAGE_TOTAL=5; STAGE_DONE=0
  if [ -e "$BOT_DIR" ]; then
    printf '  %s%s%s Existing copy found: %s\n' "$YEL" "$WRN" "$RST" "$BOT_DIR"
    ask_yn "Update it (git pull) and re-run its install.sh? Existing files may change." || return 2
  fi
  printf '\n'
  stage "Preflight: disk & network" preflight "https://github.com" || return 1
  stage "Checking git" ensure_git || return 1
  stage "Fetching Bvm-v1bot repository" git_fetch_repo "$BOT_REPO" "$BOT_DIR" || return 1
  stage "Validating install.sh" validate_script "$BOT_DIR/install.sh" || return 1
  stage_fg "Running install.sh" run_bot_installer || return 1
  mark_installed bvm-bot
  return 0
}
module_bvm_bot() {
  CUR_INFO=("BVM VPS bot (Discord)"
            "Repo   : github.com/mineflarex-collab/Bvm-v1bot"
            "Steps  : git clone, validate, run install.sh"
            "Needs  : root, git (auto-installed), internet")
  module_menu bvm-bot "BVM VPS BOT" install_bvm_bot
}

# ============================================================================
#  OPTION 2: UPCOMING (placeholder - panel not released yet)
# ============================================================================
draw_upcoming() {
  header_small "UPCOMING"
  box_center "COMING SOON" "$P$BLD"
  box_blank
  box_row "This panel has not been released yet." "$WHT"
  box_row "Stay tuned for updates from MineFlareX." "$DIM"
  box_bot
  printf '\n%*s%sPress any key to go back...%s' "$PAD" '' "$DIM" "$RST"
}
module_upcoming() {
  REDRAW=draw_upcoming
  draw_upcoming
  read_key || exit 0
}

# ----------------------------------------------------------------------------
#  Welcome + main menu
# ----------------------------------------------------------------------------
screen_welcome() {
  header_full
  local os cpu ram disk
  os=$( (. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}") )
  cpu=$(nproc 2>/dev/null || echo "?")
  ram=$(awk '/MemTotal/{printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null)
  disk=$(df -Ph / | awk 'NR==2{print $4}')
  box_center "Welcome to MineFlareX" "$P$BLD"
  box_blank
  box_row "OS      : $os" "$WHT"
  box_row "CPU     : $cpu core(s)    RAM: $ram    Free disk: $disk" "$WHT"
  box_row "Log     : $LOG_FILE" "$DIM"
  box_bot
  printf '\n%*s%sPress any key to open the main menu...%s' "$PAD" '' "$DIM" "$RST"
}

draw_main_menu() {
  header_full
  box_center "SELECT AN INSTALLATION" "$WHT$BLD"
  box_blank
  box_kv "[1]" "BVM VPS BOT"   "VPS automation bot"
  box_kv "[2]" "UPCOMING"      "Coming soon - not released"
  box_blank
  box_kv "[0]" "EXIT" ""
  box_bot
  [ -n "$MSG" ] && printf '\n%*s%s%s%s\n' "$PAD" '' "$RED" "$MSG" "$RST"
  printf '\n%*s%sEnter choice [1-2, 0=Exit]:%s ' "$PAD" '' "$P$BLD" "$RST"
}

main_menu() {
  MSG=""
  while true; do
    STAGE_TOTAL=0; STAGE_DONE=0
    REDRAW=draw_main_menu
    draw_main_menu
    read_key || exit 0
    MSG=""
    case $KEY in
      1) module_bvm_bot ;;
      2) module_upcoming ;;
      0|q|Q) do_exit ;;
      $'\e') drain_esc; MSG="Invalid input. Please press 1, 2 or 0." ;;
      "") MSG="Please press 1, 2 or 0." ;;
      *) MSG="Invalid option '${KEY//[^[:print:]]/?}'. Please press 1, 2 or 0." ;;
    esac
  done
}

# ----------------------------------------------------------------------------
main() {
  TMP=$(mktemp -d /tmp/mineflarex.XXXXXX) || { echo "mktemp failed"; exit 1; }
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  trap 'RESIZED=1' WINCH
  setup_locale
  setup_theme
  update_dims
  build_logo
  detect_pm || true
  boot
  REDRAW=screen_welcome
  screen_welcome
  read_key || exit 0
  main_menu
}

main "$@"
