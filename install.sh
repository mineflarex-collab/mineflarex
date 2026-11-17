#!/usr/bin/env bash
# ============================================================================
#  MineFlareX Installer - Advanced VPS & Hosting Management
#  Run:  bash <(curl -s https://mineflarex.indevs.in/install.sh)
# ============================================================================
set -uo pipefail

MFX_VERSION="1.0.0"
BASE_URL="${MFX_BASE_URL:-https://mineflarex.indevs.in}"
BOT_REPO="${MFX_BOT_REPO:-https://github.com/mineflarex-collab/Bvm-v1bot.git}"
PANEL_ZIP_URL="${MFX_PANEL_ZIP:-$BASE_URL/minepanel.zip}"   # panel is installed from this single zip (no GitHub folders needed)
PANEL_REPO="${MFX_PANEL_REPO:-https://github.com/mineflarex-collab/mineflarex-panel.git}"   # <- your minePanel repo (project root = install.sh + server.js)
PANEL_HOME="${MFX_PANEL_HOME:-/opt/minepanel}"
INSTALL_ROOT="/opt/mineflarex"
PANEL_DIR="$INSTALL_ROOT/mineflarex-panel"
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
FS=0
THEME_MODE=16
PREF_COLOR=""
PREF_UNI=""
BOOT_SOFT=0
BOOT_TOTAL=5
BOOT_DONE=0
SPL_BAR=0; SPL_STAT=0; SPL_CHK=0; SPL_N=0; SPL_PCT=0
CUR_KEY=""; CUR_TITLE=""; CUR_FN=""; CUR_UPD=""; CUR_INFO=()

# ----------------------------------------------------------------------------
#  Core helpers: logging, locale, theme, screen
# ----------------------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }

cleanup() {
  leave_fullscreen 2>/dev/null
  printf '\e[?25h\e[0m' 2>/dev/null
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

load_prefs() {   # saved choices from the T / U keys
  local f="$STATE_DIR/prefs" v
  [ -r "$f" ] || return 0
  v=$(sed -n 's/^COLOR=//p' "$f" 2>/dev/null | head -n1)
  [[ $v =~ ^(16|256|true|mono)$ ]] && PREF_COLOR=$v
  v=$(sed -n 's/^UNICODE=//p' "$f" 2>/dev/null | head -n1)
  [[ $v =~ ^[01]$ ]] && PREF_UNI=$v
  return 0
}

save_prefs() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  printf 'COLOR=%s\nUNICODE=%s\n' "${PREF_COLOR:-16}" "${PREF_UNI:-1}" >"$STATE_DIR/prefs" 2>/dev/null || true
}

setup_locale() {
  UTF=0
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) UTF=1 ;;
  esac
  if (( ! UTF )) && locale -a 2>/dev/null | grep -qi '^c\.utf'; then
    export LC_ALL=C.UTF-8; UTF=1
  fi
  case "${MFX_UNICODE:-$PREF_UNI}" in 0) UTF=0 ;; esac
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
  # Default = classic 8-color ANSI (30-37 + bold): works on EVERY terminal/SSH app.
  # Truecolor only when the terminal itself announces it (COLORTERM).
  # Force a mode:  MFX_COLOR=true | 256 | 16 | mono   (or press T inside the installer)
  local mode="${MFX_COLOR:-${PREF_COLOR:-auto}}"
  if [ "$mode" = auto ]; then
    if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-dumb}" = dumb ]; then mode=mono; else mode=16; fi
  fi
  case "$mode" in
    true)   # deep violet background + neon purple gradient
      P=$'\e[38;2;181;101;255m'
      SH=($'\e[38;2;221;200;255m' $'\e[38;2;196;150;255m' $'\e[38;2;181;101;255m' $'\e[38;2;157;64;245m' $'\e[38;2;131;40;220m')
      BGC=$'\e[48;2;10;5;22m'
      DIM=$'\e[38;2;160;145;200m'
      WHT=$'\e[38;5;83m'; GRN=$'\e[38;5;83m'; RED=$'\e[38;5;203m'; YEL=$'\e[38;5;221m' ;;
    256)
      P=$'\e[38;5;135m'
      SH=($'\e[38;5;189m' $'\e[38;5;183m' $'\e[38;5;177m' $'\e[38;5;141m' $'\e[38;5;135m')
      BGC=$'\e[40m'
      DIM=$'\e[38;5;103m'
      WHT=$'\e[38;5;83m'; GRN=$'\e[38;5;83m'; RED=$'\e[38;5;203m'; YEL=$'\e[38;5;221m' ;;
    mono)   # no colors at all (NO_COLOR / dumb terminals / user choice)
      P=""; SH=("" "" "" "" ""); BGC=""; DIM=""; WHT=""; GRN=""; RED=""; YEL="" ;;
    *)      # universal 8-color mode: ONLY plain 30-37 codes, no bold/bright
            # (some terminal themes turn bold/bright colors white)
      mode=16
      P=$'\e[35m'
      SH=($'\e[35m' $'\e[35m' $'\e[35m' $'\e[35m' $'\e[35m')
      BGC=$'\e[40m'
      DIM=$'\e[36m'
      WHT=$'\e[32m'; GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m' ;;
  esac
  THEME_MODE=$mode
  case "$mode" in 16) BLD="" ;; mono) BLD=$'\e[1m'; [ "${TERM:-dumb}" = dumb ] && BLD="" ;; *) BLD=$'\e[1m' ;; esac
  RST=$'\e[0m'"$BGC"
}

update_dims() {
  local sz r c
  sz=$(stty size </dev/tty 2>/dev/null) || sz=""
  r=${sz% *}; c=${sz#* }
  [[ $r =~ ^[0-9]+$ ]] && (( r > 0 )) || r=$(tput lines 2>/dev/null)
  [[ $c =~ ^[0-9]+$ ]] && (( c > 0 )) || c=$(tput cols 2>/dev/null)
  [[ $r =~ ^[0-9]+$ ]] && (( r > 0 )) || r=${LINES:-24}
  [[ $c =~ ^[0-9]+$ ]] && (( c > 0 )) || c=${COLUMNS:-80}
  [[ $r =~ ^[0-9]+$ ]] || r=24
  [[ $c =~ ^[0-9]+$ ]] || c=80
  ROWS=$r; COLS=$c
  W=$((COLS - 2)); (( W < 28 )) && W=28
  PAD=$(( (COLS - W) / 2 )); (( PAD < 0 )) && PAD=0
}

clear_screen() {   # [top_padding_lines]
  local v=${1:-0}
  printf '%s\e[H\e[2J\e[3J' "$RST"
  (( v > 0 )) && printf '%*s' "$v" '' | tr ' ' '\n'
  return 0
}

enter_fullscreen() {
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ "${MFX_FULLSCREEN:-1}" != 0 ]; then
    FS=1; printf '\e[?1049h%s\e[H\e[2J' "$RST"
  else
    FS=0
  fi
}
leave_fullscreen() { (( FS )) && printf '\e[0m\e[?25h\e[?1049l'; FS=0; return 0; }

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
glyph() {   # classic blocky font (ASCII fallback)
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

sglyph() {  # smooth line-art font, 3 rows
  case $1 in
    M) G=("╔╦╗" "║║║" "╩ ╩") ;;
    i) G=("╦" "║" "╩") ;;
    n) G=("╔╗╔" "║║║" "╝╚╝") ;;
    e) G=("╔═╗" "║╣ " "╚═╝") ;;
    F) G=("╔═╗" "╠╣ " "╚  ") ;;
    l) G=("╦  " "║  " "╩═╝") ;;
    a) G=("╔═╗" "╠═╣" "╩ ╩") ;;
    r) G=("╦═╗" "╠╦╝" "╩╚═") ;;
    X) G=("═╗ ╦" "╔╩╦╝" "╩ ╚═") ;;
  esac
}

build_logo() {
  LOGO=(); LOGO_H=5; LOGO_W=59
  local r ch line i n c idx out
  if (( UTF )); then
    LOGO_H=3
    for r in 0 1 2; do
      line=""
      for ch in M i n e F l a r e X; do sglyph "$ch"; line+="${G[r]} "; done
      LOGO+=("${line% }")
    done
    LOGO_W=${#LOGO[0]}
    for r in 0 1 2; do          # left-to-right purple gradient
      line=${LOGO[r]}; n=${#line}; out="$BLD"
      for (( i = 0; i < n; i++ )); do
        c=${line:i:1}
        if [ "$c" = " " ]; then out+=" "; else out+="${SH[$(( i * 5 / n ))]}${c}"; fi
      done
      LOGO[r]="$out"
    done
  else
    for r in 0 1 2 3 4; do
      line=""
      for ch in M I N E F L A R E X; do glyph "$ch"; line+="${G[r]} "; done
      line=${line% }
      LOGO+=("${SH[r]}${BLD}${line//\#/$BLK}")
    done
  fi
}

header_full() {
  clear_screen "$(( (ROWS - (LOGO_H + 17)) / 2 ))"
  box_top
  box_blank
  if (( W >= LOGO_W + 4 )); then
    local r
    for (( r = 0; r < LOGO_H; r++ )); do box_raw_c "${LOGO[r]}${RST}" "$LOGO_W"; done
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
bar() {   # pct [width]  - purple gradient fill
  local pct=$1 w=${2:-20} f i out=""
  f=$(( pct * w / 100 ))
  for (( i = 0; i < f; i++ )); do out+="${SH[$(( 4 - i * 5 / w ))]}${BARF}"; done
  printf '%s%s%s%s' "$out" "$DIM" "$(rep "$BARE" $(( w - f )))" "$RST"
}

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

# ----------------------------------------------------------------------------
#  Loading screen (full screen, real progress)
# ----------------------------------------------------------------------------
spl_line() {   # row visible_len colored_text   (centered, full-line repaint)
  local pad=$(( (COLS - $2) / 2 ))
  (( pad < 0 )) && pad=0
  printf '\e[%d;1H\e[2K%*s%s%s' "$1" "$pad" '' "$3" "$RST"
}

spl_bar() {    # pct
  local pct=$1 bw=$(( COLS - 14 )) f
  (( bw > 48 )) && bw=48; (( bw < 16 )) && bw=16
  f=$(( pct * bw / 100 ))
  spl_line "$SPL_BAR" $(( bw + 5 )) "$(printf '%s %s%3d%%%s' "$(bar "$pct" "$bw")" "$WHT$BLD" "$pct" "$RST")"
}

spl_bar_to() { # target pct (smooth animation)
  local t=$1
  while (( SPL_PCT < t )); do
    SPL_PCT=$(( SPL_PCT + 2 )); (( SPL_PCT > t )) && SPL_PCT=$t
    spl_bar "$SPL_PCT"; sleep 0.012
  done
}

spl_status() { # glyph text
  spl_line "$SPL_STAT" $(( ${#2} + 2 )) "${P}${BLD}$1${RST} ${WHT}$2${RST}"
}

spl_check() {  # rc label detail
  local rc=$1 label=$2 detail=$3 bw=$(( COLS - 6 )) col mark c lab room
  (( bw > 58 )) && bw=58
  col=$(( (COLS - bw) / 2 + 1 )); (( col < 1 )) && col=1
  if (( rc == 0 )); then mark=$OK; c=$GRN
  elif (( BOOT_SOFT )); then mark=$WRN; c=$YEL
  else mark=$BAD; c=$RED; fi
  printf -v lab '%-26s' "$label"
  room=$(( bw - ${#mark} - 1 - 26 - 1 )); (( room < 0 )) && room=0
  detail=${detail:0:$room}
  printf '\e[%d;1H\e[2K\e[%d;%dH%s%s%s %s%s%s %s%s%s' \
    "$(( SPL_CHK + SPL_N ))" "$(( SPL_CHK + SPL_N ))" "$col" \
    "$c" "$mark" "$RST" "$WHT" "$lab" "$RST" "$DIM" "$detail" "$RST"
  SPL_N=$(( SPL_N + 1 ))
}

splash_init() {
  local L=$LOGO_H total r i v rw out
  (( COLS < LOGO_W + 4 )) && L=1
  total=$(( L + 12 ))
  r=$(( (ROWS - total) / 2 + 1 )); (( r < 1 )) && r=1
  clear_screen 0
  printf '\e[?25l'
  if (( L == LOGO_H )); then
    for (( i = 0; i < L; i++ )); do spl_line $(( r + i )) "$LOGO_W" "${LOGO[i]}${RST}"; sleep 0.07; done
  else
    spl_line "$r" 19 "${P}${BLD}M I N E F L A R E X${RST}"
  fi
  r=$(( r + L + 1 ))
  spl_line "$r" 33 "${WHT}Advanced VPS & Hosting Management${RST}"
  v="v$MFX_VERSION  |  mineflarex.indevs.in"
  spl_line $(( r + 1 )) "${#v}" "${DIM}${v}${RST}"
  rw=$(( COLS - 8 )); (( rw > 40 )) && rw=40; (( rw < 12 )) && rw=12
  out=""
  for (( i = 0; i < rw; i++ )); do out+="${SH[$(( i * 5 / rw ))]}${H}"; done
  spl_line $(( r + 2 )) "$rw" "$out"
  SPL_BAR=$(( r + 3 )); SPL_STAT=$(( r + 4 )); SPL_CHK=$(( r + 6 ))
  SPL_PCT=0; SPL_N=0
  spl_bar 0
}

boot_step() {  # label cmd...   (runs in background, spinner + real progress)
  local label=$1; shift
  local outf pid i=0 frames=0 rc first
  outf=$(mktemp "$TMP/out.XXXXXX")
  "$@" >"$outf" 2>>"$LOG_FILE" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null || (( frames < 6 )); do
    spl_status "${SPIN[i % ${#SPIN[@]}]}" "$label"
    i=$(( i + 1 )); frames=$(( frames + 1 )); sleep 0.07
  done
  wait "$pid"; rc=$?
  SPIN_OUT=$(<"$outf"); rm -f "$outf"
  first=${SPIN_OUT%%$'\n'*}
  log "boot '$label' rc=$rc ${first}"
  if (( rc != 0 && BOOT_SOFT )); then first="offline"; fi
  spl_check "$rc" "$label" "$first"
  BOOT_DONE=$(( BOOT_DONE + 1 ))
  spl_bar_to $(( BOOT_DONE * 100 / BOOT_TOTAL ))
  return "$rc"
}

chk_sys() { ( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux} ($(uname -m))" ); }

boot_fail() {
  leave_fullscreen
  printf '\n  %s%sERROR:%s %s\n\n' "$RED" "$BLD" $'\e[0m' "$1"
  log "BOOT FAIL: $1"
  exit 1
}

boot() {
  BOOT_TOTAL=5; BOOT_DONE=0
  splash_init
  boot_step "Checking environment"     chk_env  || boot_fail "$SPIN_OUT"
  boot_step "Checking root permission" chk_root || boot_fail "$SPIN_OUT"
  init_log
  # Virtualization is detected silently (info only - never an error, never shown)
  VIRT=""
  detect_lxc && VIRT="lxc"
  detect_kvm && VIRT+="${VIRT:++}kvm"
  VIRT_LABEL="${VIRT^^}"
  log "Virtualization (info only): ${VIRT:-none}"
  boot_step "Detecting system"         chk_sys  || true
  boot_step "Checking dependencies"    ensure_deps || boot_fail "$SPIN_OUT"
  BOOT_SOFT=1
  boot_step "Checking network"         chk_net  || log "network check failed - downloads may fail later"
  BOOT_SOFT=0
  spl_line "$SPL_STAT" $(( ${#OK} + 1 + 5 )) "${GRN}${BLD}${OK}${RST} ${WHT}${BLD}Ready${RST}"
  sleep 0.7
  printf '\e[?25h'
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
  # The bot's own install.sh draws white text (1;37m): temporarily make it green, then restore the file
  local rc
  ( cd "$BOT_DIR" && sed -i 's/\\033\[1;37m/\\033[0;32m/g' install.sh )
  ( cd "$BOT_DIR" && chmod +x install.sh && env MFX_VIRT="$VIRT" MFX_LOG="$LOG_FILE" MFX_COLOR="$THEME_MODE" FORCE_COLOR=1 CLICOLOR_FORCE=1 ./install.sh </dev/tty )
  rc=$?
  ( cd "$BOT_DIR" && git checkout -- install.sh 2>/dev/null )
  return "$rc"
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
  [ -n "$CUR_UPD" ] && box_kv "[3]" "Update"     "Update to the latest version (data is kept)"
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
  leave_fullscreen
  printf '\n  %s%sThanks for using MineFlareX%s\n  Log: %s\n\n' "$P" "$BLD" $'\e[0m' "$LOG_FILE"
  exit 0
}

run_update() {
  REDRAW=""
  header_small "$CUR_TITLE - UPDATE"
  box_row "Log: $LOG_FILE" "$DIM"
  box_bot
  log "=== BEGIN $CUR_KEY update ==="
  "$CUR_UPD"; local rc=$?
  log "=== END $CUR_KEY update rc=$rc ==="
  printf '\n'
  case $rc in
    0) box_top; box_center "UPDATE COMPLETE" "$GRN$BLD"; box_center "$CUR_TITLE is up to date. Your data was kept." "$WHT"
       box_row "Log: $LOG_FILE" "$DIM"; box_bot ;;
    2) printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST" ;;
    *) printf '  %s%sUPDATE FAILED%s - see details above. Your data is untouched.\n  Log: %s\n' "$RED" "$BLD" "$RST" "$LOG_FILE" ;;
  esac
  press_any_key
}

module_menu() {  # key title install_fn [update_fn]  (CUR_INFO set by caller)
  CUR_KEY=$1; CUR_TITLE=$2; CUR_FN=$3; CUR_UPD=${4:-}; MSG=""
  while true; do
    REDRAW=draw_module_menu
    draw_module_menu
    read_key || exit 0
    MSG=""
    case $KEY in
      1) confirm_install && run_install ;;
      2) view_log ;;
      3) if [ -n "$CUR_UPD" ]; then run_update; else MSG="Invalid option '3'. Use 1, 2, B or 0."; fi ;;
      b|B) return 0 ;;
      0|q|Q) do_exit ;;
      $'\e') drain_esc; MSG="Invalid input. Use the numbers shown, B or 0." ;;
      "") MSG="Please press a number shown, B or 0." ;;
      *) MSG="Invalid option '${KEY//[^[:print:]]/?}'. Use the numbers shown, B or 0." ;;
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
#  MODULE 2: MINE PANEL  (everything happens in THIS installer: clone -> install -> admin email + password)
# ============================================================================
PANEL_NODE_FLAGS="--disable-warning=ExperimentalWarning"
PANEL_PORT=3000
panel_installed() { [ -f /etc/systemd/system/minepanel.service ] && [ -d "$PANEL_HOME" ]; }
panel_admin_exists() { [ -f "$PANEL_HOME/data/.admin-created" ]; }

panel_check_os() {
  [ "$PM" = apt ] || { echo "Mine Panel supports Ubuntu / Debian (apt) only."; return 1; }
  echo "apt (Ubuntu / Debian)"
}

panel_fetch_zip() {  # download minepanel.zip -> $PANEL_DIR (HTTPS only; keeps nothing but the files)
  [[ $PANEL_ZIP_URL == https://* ]] || { echo "Refusing non-HTTPS zip URL: $PANEL_ZIP_URL"; return 1; }
  command -v unzip >/dev/null 2>&1 || { apt-get update -y >>"$LOG_FILE" 2>&1; apt-get install -y unzip >>"$LOG_FILE" 2>&1; }
  command -v unzip >/dev/null 2>&1 || { echo "unzip could not be installed (see log)"; return 1; }
  local tmp z src
  tmp=$(mktemp -d) || return 1
  z="$tmp/panel.zip"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --connect-timeout 10 --max-time 180 -o "$z" "$PANEL_ZIP_URL" \
    || { rm -rf "$tmp"; echo "Cannot download $PANEL_ZIP_URL"; return 1; }
  unzip -tq "$z" >/dev/null 2>&1 || { rm -rf "$tmp"; echo "Downloaded file is not a valid zip (wrong link?)"; return 1; }
  unzip -q "$z" -d "$tmp/x" || { rm -rf "$tmp"; echo "unzip failed"; return 1; }
  src="$tmp/x"
  # zip may contain one top folder (e.g. minepanel-auth/): use it as the root
  if [ ! -f "$src/server.js" ] && [ "$(find "$src" -mindepth 1 -maxdepth 1 | wc -l)" = 1 ]; then
    src=$(find "$src" -mindepth 1 -maxdepth 1 -type d | head -n1)
  fi
  [ -f "$src/server.js" ] || { rm -rf "$tmp"; echo "server.js not found in the zip"; return 1; }
  rm -rf "$PANEL_DIR"   # staging copy only: the live panel lives in $PANEL_HOME and is untouched here
  mkdir -p "$PANEL_DIR" && cp -a "$src"/. "$PANEL_DIR"/ || { rm -rf "$tmp"; echo "copy failed"; return 1; }
  rm -rf "$tmp"
  echo "zip ok, $(find "$PANEL_DIR" -type f | wc -l) files"
}

panel_check_src() {
  [ -f "$PANEL_DIR/server.js" ] && [ -f "$PANEL_DIR/package.json" ] \
    || { echo "server.js not found in the root of $PANEL_REPO - put the panel files in the zip root"; return 1; }
  echo "panel files found"
}

panel_deps() {   # Node.js 22 + Python 3 (Python bots) + Java (Minecraft)
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >>"$LOG_FILE" 2>&1 || { echo "apt update failed (see log)"; return 1; }
  apt-get install -y curl ca-certificates gnupg openssl python3 python3-pip python3-venv >>"$LOG_FILE" 2>&1 \
    || { echo "could not install base packages (see log)"; return 1; }
  apt-get install -y openjdk-21-jre-headless >>"$LOG_FILE" 2>&1 \
    || apt-get install -y openjdk-17-jre-headless >>"$LOG_FILE" 2>&1 \
    || log "Java could not be installed automatically"
  local ok=0
  if command -v node >/dev/null 2>&1; then
    node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)' && ok=1
  fi
  if [ "$ok" = 0 ]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x 2>>"$LOG_FILE" | bash - >>"$LOG_FILE" 2>&1 || { echo "Node.js repository setup failed (see log)"; return 1; }
    apt-get install -y nodejs >>"$LOG_FILE" 2>&1 || { echo "Node.js install failed (see log)"; return 1; }
  fi
  echo "node $(node -v), $(python3 --version 2>&1 | awk '{print $2}')"
}

panel_files() {  # copy the panel to /opt/minepanel; the live .env and data/ (database, servers, bots) are never touched
  id minepanel >/dev/null 2>&1 || useradd --system --create-home --home-dir "$PANEL_HOME" --shell /usr/sbin/nologin minepanel || return 1
  mkdir -p "$PANEL_HOME" || return 1
  ( cd "$PANEL_DIR" && tar --exclude=.git --exclude=node_modules --exclude=./.env --exclude=./data -cf - . ) \
    | ( cd "$PANEL_HOME" && tar -xf - ) || { echo "copy failed"; return 1; }
  mkdir -p "$PANEL_HOME/data/servers"
  if [ ! -f "$PANEL_HOME/.env" ]; then
    cp "$PANEL_HOME/deploy/env.production.example" "$PANEL_HOME/.env" || return 1
    # Works on any address Cloudflare gives it. BASE_URL is only used for password-reset links.
    sed -i "s|https://panel.example.com|http://localhost:$PANEL_PORT|; s|__GENERATED__|$(openssl rand -hex 32)|" "$PANEL_HOME/.env"
    chmod 600 "$PANEL_HOME/.env"
  fi
  chown -R minepanel:minepanel "$PANEL_HOME"
  echo "installed in $PANEL_HOME"
}

panel_backup() {
  local b="$PANEL_HOME/update-backups/$(date +%Y%m%d-%H%M%S)" f
  mkdir -p "$b" || return 1
  for f in "$PANEL_HOME"/data/minepanel.db "$PANEL_HOME"/data/minepanel.db-wal "$PANEL_HOME"/data/minepanel.db-shm; do [ -f "$f" ] && cp -a "$f" "$b/"; done
  echo "backup: $b"
}

panel_service() {
  cp "$PANEL_HOME/deploy/minepanel.service" /etc/systemd/system/minepanel.service || return 1
  systemctl daemon-reload
  systemctl enable minepanel >/dev/null 2>&1
  systemctl restart minepanel || { echo "systemctl restart failed"; return 1; }
  local i
  for i in $(seq 1 25); do
    curl -fsS "http://127.0.0.1:$PANEL_PORT/healthz" >/dev/null 2>&1 && { echo "panel running on 127.0.0.1:$PANEL_PORT"; return 0; }
    sleep 1
  done
  echo "panel did not start - see: journalctl -u minepanel -n 50 --no-pager"; return 1
}

# Last step: asks for the admin email + password on the terminal and creates the account.
panel_admin() {
  [ -r /dev/tty ] || { echo "no terminal available"; return 1; }
  local email pw pw2 user out try
  printf '  %s%sCreate your admin account%s\n  %s(you will sign in to the panel with this email and password)%s\n\n' "$P" "$BLD" "$RST" "$DIM" "$RST"
  while true; do
    printf '  %sAdmin email (gmail):%s ' "$WHT" "$RST" >/dev/tty;                       IFS= read -r email </dev/tty
    email=$(printf '%s' "$email" | tr -d '[:space:]')
    [ -n "$email" ] || { printf '  %sEmail is required.%s\n' "$YEL" "$RST"; continue; }
    printf '  %sPassword (10+ characters, letters + numbers):%s ' "$WHT" "$RST" >/dev/tty; IFS= read -rs pw </dev/tty;  printf '\n' >/dev/tty
    printf '  %sPassword again:%s ' "$WHT" "$RST" >/dev/tty;                            IFS= read -rs pw2 </dev/tty; printf '\n' >/dev/tty
    [ "$pw" = "$pw2" ] || { printf '  %sThe two passwords do not match. Try again.%s\n\n' "$YEL" "$RST"; continue; }
    user=$(printf '%s' "${email%%@*}" | tr -c 'A-Za-z0-9_-' '_'); user=${user:0:20}
    [ "${#user}" -ge 3 ] || user="admin"
    for try in 1 2 3; do
      if out=$( cd "$PANEL_HOME" && runuser -u minepanel -- env ADMIN_PASSWORD="$pw" node $PANEL_NODE_FLAGS scripts/create-admin.js "$email" "$user" 2>&1 ); then
        : > "$PANEL_HOME/data/.admin-created"; chown minepanel:minepanel "$PANEL_HOME/data/.admin-created" 2>/dev/null
        printf '  %s%s%s Admin account ready: %s\n' "$GRN" "$OK" "$RST" "$email"
        return 0
      fi
      if printf '%s' "$out" | grep -qi 'taken'; then user="${user:0:15}$((RANDOM % 9000 + 1000))"; continue; fi   # username used: add digits
      break
    done
    printf '  %s%s%s\n\n' "$YEL" "$(printf '%s' "$out" | tail -n1)" "$RST"
  done
}

panel_open_hint() {
  printf '\n  %s%sOpen the panel through Cloudflare%s\n' "$P" "$BLD" "$RST"
  printf '  %sThe panel runs on http://localhost:%s . In your Cloudflare tunnel add a public hostname:%s\n' "$DIM" "$PANEL_PORT" "$RST"
  printf '  %sService HTTP -> localhost:%s  (Zero Trust > Networks > Tunnels). No domain? Free temporary link:%s\n' "$DIM" "$PANEL_PORT" "$RST"
  printf '    %scloudflared tunnel --url http://localhost:%s%s\n' "$WHT" "$PANEL_PORT" "$RST"
  printf '  %sMinecraft players connect to VPS-IP:25565  (ufw allow 25565/tcp)%s\n' "$DIM" "$RST"
  printf '  %sLogs: journalctl -u minepanel -f%s\n' "$DIM" "$RST"
}

# ---- Update: new code from the zip; database, .env, servers and bots (data/) are never touched --------
panel_stop() {
  systemctl stop minepanel >>"$LOG_FILE" 2>&1 || { echo "could not stop the panel service"; return 1; }
  echo "panel stopped (running servers stop with it and come back when it starts)"
}

panel_snapshot() {   # whole data/ + .env + current code -> update-backups/<time>/   (made while the panel is stopped)
  local b="$PANEL_HOME/update-backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$b" "$STATE_DIR" || return 1
  ( cd "$PANEL_HOME" && tar --exclude=./update-backups --exclude=./data/servers -cf "$b/state.tar" . ) \
    || { echo "backup failed - nothing was changed"; return 1; }
  chmod 600 "$b/state.tar"
  PANEL_LAST_BACKUP="$b"; printf '%s\n' "$b" >"$STATE_DIR/panel-last-backup" 2>/dev/null
  # keep only the 5 newest backups
  ls -1dt "$PANEL_HOME"/update-backups/*/ 2>/dev/null | tail -n +6 | xargs -r rm -rf
  echo "backup: $b"
}

panel_stop_backup() { panel_stop && panel_snapshot; }

panel_update_files() {  # replace code only; .env and data/ stay exactly as they are
  local d
  for d in src public scripts deploy tests; do rm -rf "${PANEL_HOME:?}/$d"; done
  ( cd "$PANEL_DIR" && tar --exclude=.git --exclude=node_modules --exclude=./.env --exclude=./data -cf - . ) \
    | ( cd "$PANEL_HOME" && tar -xf - ) || { echo "copy failed"; return 1; }
  chown -R minepanel:minepanel "$PANEL_HOME" 2>/dev/null
  echo "new code in place; data and .env kept"
}

panel_rollback() {  # put the code from the pre-update backup back (data/ was never changed, so it is left as is)
  local b; b=$(cat "$STATE_DIR/panel-last-backup" 2>/dev/null)
  [ -f "$b/state.tar" ] || return 1
  local d; for d in src public scripts deploy tests; do rm -rf "${PANEL_HOME:?}/$d"; done
  ( cd "$PANEL_HOME" && tar -xf "$b/state.tar" --exclude=./.env --exclude=./data ) || return 1
  chown -R minepanel:minepanel "$PANEL_HOME" 2>/dev/null
  systemctl restart minepanel >>"$LOG_FILE" 2>&1
}

update_mine_panel() {
  STAGE_TOTAL=6; STAGE_DONE=0
  if ! panel_installed; then
    printf '  %s%s%s Mine Panel is not installed yet. Use [1] Start Install first.\n' "$YEL" "$WRN" "$RST"; return 1
  fi
  printf '  %sYour database, users, servers, bots, files and .env are kept.%s\n' "$DIM" "$RST"
  printf '  %sThe panel restarts for a few seconds (running servers restart with it).%s\n\n' "$DIM" "$RST"
  ask_yn "Update Mine Panel now?" || return 2
  printf '\n'
  stage "Preflight: disk & network" preflight "$PANEL_ZIP_URL" || return 1
  stage "Downloading new version (zip)" panel_fetch_zip || return 1          # live panel is still untouched here
  stage "Installing Node.js, Python, Java (if missing)" panel_deps || return 1
  stage "Stopping panel + backup (database, .env)" panel_stop_backup || { systemctl start minepanel >/dev/null 2>&1; return 1; }
  stage "Installing new code" panel_update_files || { panel_rollback; return 1; }
  if ! stage "Starting panel service" panel_service; then
    printf '  %s%s%s New version did not start - restoring the previous code...\n' "$YEL" "$WRN" "$RST"
    panel_rollback && printf '  %s%s%s Previous version restored. Your data was never changed.\n' "$GRN" "$OK" "$RST"
    return 1
  fi
  mark_installed mine-panel
  panel_open_hint
  return 0
}

install_mine_panel() {
  local update=0
  panel_installed && update=1
  STAGE_TOTAL=8; STAGE_DONE=0
  if [ -e "$PANEL_DIR" ] || (( update )); then
    printf '  %s%s%s Mine Panel is already installed - this will UPDATE it.\n' "$YEL" "$WRN" "$RST"
    ask_yn "Update now? Your data, servers and admin login are kept." || return 2
  fi
  printf '\n'
  stage "Preflight: disk & network" preflight "$PANEL_ZIP_URL" || return 1
  stage "Checking system (Ubuntu / Debian)" panel_check_os || return 1
  stage "Downloading Mine Panel (zip)" panel_fetch_zip || return 1
  stage "Checking panel files" panel_check_src || return 1
  stage "Installing Node.js, Python, Java" panel_deps || return 1
  (( update )) && { stage "Backing up database" panel_backup || return 1; }
  stage "Installing panel files" panel_files || return 1
  stage "Starting panel service" panel_service || return 1
  if panel_admin_exists; then
    printf '  %s%s%s %-34s %skept (already exists)%s\n' "$GRN" "$OK" "$RST" "Admin account" "$DIM" "$RST"
  else
    STAGE_TOTAL=$(( STAGE_TOTAL + 1 ))
    stage_fg "Admin account (email + password)" panel_admin || return 1
  fi
  mark_installed mine-panel
  panel_open_hint
  return 0
}

module_mine_panel() {
  CUR_INFO=("Mine Panel (Minecraft + Bot hosting)"
            "Source : $PANEL_ZIP_URL"
            "Steps  : download zip, install Node/Python/Java, start panel"
            "Last   : asks the admin email + password"
            "Update : menu [3] keeps all your data")
  module_menu mine-panel "MINE PANEL" install_mine_panel update_mine_panel
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
  box_blank
  box_row "Display looks wrong?  T = change colors   U = ASCII symbols" "$DIM"
  box_bot
  printf '\n%*s%sPress any key to open the main menu...%s' "$PAD" '' "$DIM" "$RST"
}

color_check() {   # first run only: ask whether this SSH client really shows colors
  [ -n "${MFX_COLOR:-}" ] && return 0
  [ -n "$PREF_COLOR" ] && return 0
  [ -n "${NO_COLOR:-}" ] && return 0
  [ "${TERM:-dumb}" = dumb ] && return 0
  local r t1 t2 t3
  r=$(( (ROWS - 9) / 2 + 1 )); (( r < 1 )) && r=1
  t1="DISPLAY CHECK"
  t2="Do you see colors on the line below?"
  t3="PURPLE  GREEN  YELLOW  RED"
  clear_screen 0
  spl_line "$r" "${#t1}" "${P}${BLD}${t1}${RST}"
  spl_line $(( r + 2 )) "${#t2}" "${WHT}${t2}${RST}"
  spl_line $(( r + 4 )) "${#t3}" "${P}PURPLE${RST}  ${GRN}GREEN${RST}  ${YEL}YELLOW${RST}  ${RED}RED${RST}"
  spl_line $(( r + 6 )) 38 "${WHT}Y = yes, I see colors${RST}"
  spl_line $(( r + 7 )) 38 "${WHT}N = no, everything is white${RST}"
  REDRAW=""
  read_key || return 0
  case $KEY in
    y|Y) PREF_COLOR=16 ;;
    *)   PREF_COLOR=mono ;;
  esac
  setup_theme; build_logo; save_prefs
  clear_screen 0
}

cycle_theme() {   # T key: 16 -> 256 -> true -> mono
  local order=(16 256 true mono) i next=0
  for i in "${!order[@]}"; do [ "${order[i]}" = "$THEME_MODE" ] && next=$(( (i + 1) % ${#order[@]} )); done
  PREF_COLOR=${order[next]}; unset MFX_COLOR
  setup_theme; build_logo; save_prefs
}

toggle_unicode() {   # U key: Unicode <-> plain ASCII symbols
  if (( UTF )); then PREF_UNI=0; else PREF_UNI=1; fi
  unset MFX_UNICODE
  setup_locale; setup_theme; build_logo; save_prefs
}

draw_main_menu() {
  header_full
  box_center "SELECT AN INSTALLATION" "$WHT$BLD"
  box_blank
  box_kv "[1]" "BVM VPS BOT"   "VPS automation bot"
  box_kv "[2]" "MINE PANEL"    "Minecraft + Bot hosting panel"
  box_blank
  box_kv "[0]" "EXIT" ""
  box_blank
  box_row "T = colors (now: $THEME_MODE)   U = Unicode/ASCII symbols" "$DIM"
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
      2) module_mine_panel ;;
      0|q|Q) do_exit ;;
      t|T) cycle_theme ;;
      u|U) toggle_unicode ;;
      $'\e') drain_esc; MSG="Invalid input. Please press 1, 2 or 0." ;;
      "") MSG="Please press 1, 2 or 0." ;;
      *) MSG="Invalid option '${KEY//[^[:print:]]/?}'. Please press 1, 2 or 0." ;;
    esac
  done
}

# ----------------------------------------------------------------------------
main() {
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  trap 'RESIZED=1' WINCH
  load_prefs
  setup_locale
  setup_theme
  update_dims
  enter_fullscreen          # theme colors + black full screen from the very first moment
  TMP=$(mktemp -d /tmp/mineflarex.XXXXXX) || { leave_fullscreen; echo "mktemp failed"; exit 1; }
  build_logo
  detect_pm || true
  color_check
  boot
  REDRAW=screen_welcome
  screen_welcome
  while true; do
    read_key || exit 0
    case $KEY in
      t|T) cycle_theme; screen_welcome ;;
      u|U) toggle_unicode; screen_welcome ;;
      *) break ;;
    esac
  done
  main_menu
}

main "$@"
