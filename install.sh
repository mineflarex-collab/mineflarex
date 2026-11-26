#!/usr/bin/env bash
# ============================================================================
#  MineFlareX Installer - Advanced VPS & Hosting Management
#  Run:  bash <(curl -s https://mineflarex.indevs.in/install.sh)
# ============================================================================
set -uo pipefail

MFX_VERSION="1.1.0"
BASE_URL="${MFX_BASE_URL:-https://mineflarex.indevs.in}"
BOT_REPO="${MFX_BOT_REPO:-https://github.com/mineflarex-collab/Bvm-v1bot.git}"
PANEL_ZIP_URL="${MFX_PANEL_ZIP:-$BASE_URL/minepanel.zip}"   # panel is installed from this single zip (no GitHub folders needed)
PANEL_REPO="${MFX_PANEL_REPO:-https://github.com/mineflarex-collab/mineflarex-panel.git}"   # <- your minePanel repo (project root = install.sh + server.js)
PANEL_HOME="${MFX_PANEL_HOME:-/opt/minepanel}"
INSTALL_ROOT="/opt/mineflarex"
PANEL_DIR="$INSTALL_ROOT/mineflarex-panel"
BOT_DIR="$INSTALL_ROOT/Bvm-v1bot"
BVMP_ZIP_URL="${MFX_BVMP_ZIP:-$BASE_URL/bvmpanel.zip}"   # BVM panel zip, hosted next to minepanel.zip (zip root must contain install.sh)
BVMP_DIR="$INSTALL_ROOT/Bvm-panel"
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
CUR_KEY=""; CUR_TITLE=""; CUR_FN=""; CUR_UPD=""; CUR_REI=""; CUR_USR=""; CUR_INFO=()
PANEL_WIPE=0
BOX_DELAY=0
BDG=""

# ----------------------------------------------------------------------------
#  Core helpers: logging, locale, theme, screen
# ----------------------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }

cleanup() {
  leave_fullscreen 2>/dev/null
  printf '\e[?25h\e[0m' 2>/dev/null
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

apt_update() {   # a broken third-party repo must not stop an install: retry once, then continue with cached indexes
  apt-get update -y >>"$LOG_FILE" 2>&1 && return 0
  log "apt-get update reported errors - retrying once"
  sleep 3
  apt-get update -y >>"$LOG_FILE" 2>&1 || log "apt-get update still reports errors (some repository failed) - continuing with cached indexes"
  return 0
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
    local _t='◆'
    if (( ${#_t} != 1 )); then
      locale -a 2>/dev/null | grep -qi '^c\.utf' && export LC_ALL=C.UTF-8
      _t='◆'; (( ${#_t} == 1 )) || UTF=0
    fi
  fi
  case "${MFX_UNICODE:-$PREF_UNI}" in 0) UTF=0 ;; esac
  if (( UTF )); then
    TL='╭'; TR='╮'; BL='╰'; BR='╯'; H='─'; V='│'; ML='├'; MR='┤'; DOT='●'; DOT0='○'
    BLK='█'; BARF='█'; BARE='░'; OK='✔'; BAD='✘'; ARW='▶'; WRN='!'
    SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  else
    TL='+'; TR='+'; BL='+'; BR='+'; H='-'; V='|'; ML='+'; MR='+'; DOT='*'; DOT0='-'
    BLK='#'; BARF='#'; BARE='-'; OK='OK'; BAD='XX'; ARW='>'; WRN='!'
    SPIN=('|' '/' '-' '\')
  fi
}

setup_theme() {
  # Fully automatic - nothing to choose. Best mode is detected from the terminal.
  # (Advanced) force a mode:  MFX_COLOR=true | 256 | 16 | mono
  local mode="${MFX_COLOR:-auto}"
  if [ "$mode" = auto ]; then
    if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-dumb}" = dumb ]; then mode=mono
    elif [[ ${COLORTERM:-} == *truecolor* || ${COLORTERM:-} == *24bit* ]]; then mode=true
    elif [[ ${TERM:-} == *256color* || ${TERM:-} == xterm* || ${TERM:-} == screen* || ${TERM:-} == tmux* ]]; then mode=256
    else mode=16; fi
  fi
  case "$mode" in
    true)   # purple background, white + lavender text (purple -> white mix)
      P=$'\e[38;2;214;188;255m'
      SH=($'\e[38;2;176;128;255m' $'\e[38;2;196;156;255m' $'\e[38;2;216;188;255m' $'\e[38;2;236;222;255m' $'\e[38;2;255;255;255m')
      BGC=$'\e[48;2;58;26;122m'
      DIM=$'\e[38;2;203;186;244m'
      WHT=$'\e[38;2;255;255;255m'; GRN=$'\e[38;2;140;255;196m'; RED=$'\e[38;2;255;140;170m'; YEL=$'\e[38;2;255;228;130m'
      BDG=$'\e[48;2;246;241;255m\e[38;2;88;40;190m' ;;
    256)
      P=$'\e[38;5;183m'
      SH=($'\e[38;5;141m' $'\e[38;5;147m' $'\e[38;5;183m' $'\e[38;5;189m' $'\e[38;5;255m')
      BGC=$'\e[48;5;54m'
      DIM=$'\e[38;5;189m'
      WHT=$'\e[38;5;255m'; GRN=$'\e[38;5;121m'; RED=$'\e[38;5;211m'; YEL=$'\e[38;5;229m'
      BDG=$'\e[48;5;255m\e[38;5;54m' ;;
    mono)
      P=""; SH=("" "" "" "" ""); BGC=""; DIM=""; WHT=""; GRN=""; RED=""; YEL=""; BDG=$'\e[7m' ;;
    *)      # old 8-color terminals: plain 30-37 codes only
      mode=16
      P=$'\e[37m'
      SH=($'\e[37m' $'\e[37m' $'\e[37m' $'\e[37m' $'\e[37m')
      BGC=$'\e[45m'
      DIM=$'\e[37m'
      WHT=$'\e[37m'; GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'
      BDG=$'\e[47m\e[35m' ;;
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
  W=$((COLS - 2)); (( W > 76 )) && W=76; (( W < 28 )) && W=28
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

box_tick() { [ "${BOX_DELAY:-0}" = 0 ] || sleep "$BOX_DELAY" 2>/dev/null || true; return 0; }
rep() { local n=$2 s; (( n <= 0 )) && return 0; printf -v s '%*s' "$n" ''; printf '%s' "${s// /$1}"; }

# ----------------------------------------------------------------------------
#  Box drawing
# ----------------------------------------------------------------------------
grad_line() {   # left_char fill_char right_char : pink -> cyan gradient border line
  local n=$(( W - 2 )) i out="" 
  out+="${SH[0]}$1"
  for (( i = 0; i < n; i++ )); do out+="${SH[$(( i * 5 / n ))]}$2"; done
  out+="${SH[4]}$3"
  printf '%*s%s%s\n' "$PAD" '' "$out" "$RST"; box_tick
}
box_top() { grad_line "$TL" "$H" "$TR"; }
box_bot() { grad_line "$BL" "$H" "$BR"; }
box_sep() { grad_line "$ML" "$H" "$MR"; }

box_raw_l() {  # colored_text visible_len
  local txt=$1 sp=$(( W - 4 - $2 ))
  (( sp < 0 )) && sp=0
  printf '%*s%s%s%s %s%*s %s%s%s\n' "$PAD" '' "$P" "$V" "$RST" "$txt" "$sp" '' "$P" "$V" "$RST"; box_tick
}
box_raw_c() {
  local txt=$1 vlen=$2 inner=$(( W - 2 )) lead trail
  lead=$(( (inner - vlen) / 2 )); (( lead < 0 )) && lead=0
  trail=$(( inner - vlen - lead )); (( trail < 0 )) && trail=0
  printf '%*s%s%s%s%*s%s%*s%s%s%s\n' "$PAD" '' "$P" "$V" "$RST" "$lead" '' "$txt" "$trail" '' "$P" "$V" "$RST"; box_tick
}
box_blank() { box_raw_l "" 0; }
box_row()    { local t=${1:0:$((W-4))} c=${2:-$WHT}; box_raw_l "$c$t$RST" "${#t}"; }
box_center() { local t=${1:0:$((W-4))} c=${2:-$WHT}; box_raw_c "$c$t$RST" "${#t}"; }
box_kv() {     # key label desc   (key shown as [n], digit in bright white)
  local key=$1 lab desc=$3 room k=${1//[\[\]]/}
  printf -v lab '%-18s' "$2"
  room=$(( W - 4 - ${#k} - 2 - 2 - ${#lab} - 1 ))
  desc=${desc:0:$(( room > 0 ? room : 0 ))}
  box_raw_l "${P}${BLD}[${WHT}${k}${P}]${RST}  ${WHT}${BLD}${lab}${RST} ${DIM}${desc}${RST}" $(( ${#k} + 2 + 2 + ${#lab} + 1 + ${#desc} ))
}
box_info() {   # label value   (aligned info row)
  local lab v
  printf -v lab '%-8s' "$1"
  v=${2:0:$(( W - 4 - 8 - 3 ))}
  box_raw_l "${P}${BLD}${lab}${RST} ${DIM}${V}${RST} ${WHT}${v}${RST}" $(( 8 + 3 + ${#v} ))
}
grad_text() {  # text -> gradient string (purple -> white)
  local t=$1 n=${#1} i c out="$BLD"
  for (( i = 0; i < n; i++ )); do
    c=${t:i:1}
    if [ "$c" = " " ]; then out+=" "; else out+="${SH[$(( i * 5 / n ))]}${c}"; fi
  done
  printf '%s%s' "$out" "$RST"
}
box_grad() { local t=${1:0:$((W-4))}; box_raw_c "$(grad_text "$t")" "${#t}"; }
draw_anim() { BOX_DELAY=0.018; "$1"; BOX_DELAY=0; }

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

sglyph() {  # bold half-block font, 3 rows
  case $1 in
    M) G=("█▀▄▀█" "█ ▀ █" "▀   ▀") ;;
    I) G=("▀█▀" " █ " "▄█▄") ;;
    N) G=("█▄ █" "█ ▀█" "▀  ▀") ;;
    E) G=("█▀▀" "█▀▀" "▀▀▀") ;;
    F) G=("█▀▀" "█▀▀" "▀  ") ;;
    L) G=("█  " "█  " "▀▀▀") ;;
    A) G=("▄▀▄" "█▀█" "▀ ▀") ;;
    R) G=("█▀▄" "█▀▄" "▀ ▀") ;;
    X) G=("▀▄▀" " █ " "▄▀▄") ;;
  esac
}

build_logo() {
  LOGO=(); LOGO_H=5; LOGO_W=59
  local r ch line i n c idx out
  if (( UTF )); then
    LOGO_H=3
    for r in 0 1 2; do
      line=""
      for ch in M I N E F L A R E X; do sglyph "$ch"; line+="${G[r]} "; done
      LOGO+=("${line% }")
    done
    LOGO_W=${#LOGO[0]}
    LOGO_RAW=("${LOGO[@]}")
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
  clear_screen "$(( (ROWS - (LOGO_H + 18)) / 2 ))"
  box_top
  box_blank
  if (( W >= LOGO_W + 4 )); then
    local r
    for (( r = 0; r < LOGO_H; r++ )); do box_raw_c "${LOGO[r]}${RST}" "$LOGO_W"; done
  else
    box_center "M I N E F L A R E X" "$P$BLD"
  fi
  box_blank
  box_center "ADVANCED VPS & HOSTING MANAGEMENT" "$WHT$BLD"
  box_center "v$MFX_VERSION  ·  mineflarex.indevs.in" "$DIM"
  (( UTF )) && box_center "◆  One command  ·  Full setup  ·  Zero stress  ◆" "$P"
  box_sep
}

header_small() {
  clear_screen
  box_top
  box_grad "M I N E F L A R E X"
  box_center "ADVANCED VPS & HOSTING MANAGEMENT" "$DIM"
  box_sep
  box_center "$( (( UTF )) && printf '◆  %s  ◆' "$1" || printf '%s' "$1")" "$WHT$BLD"
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
  for (( i = 0; i < f; i++ )); do out+="${SH[$(( i * 5 / f ))]}${BARF}"; done
  printf '%s%s%s%s' "$out" "$DIM" "$(rep "$BARE" $(( w - f )))" "$RST"
}

spin_run() {   # label cmd...   (cmd runs in background; stdout captured in SPIN_OUT)
  local label=$1; shift
  local outf pid i=0 pct t0=$SECONDS el
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
    el=$(( SECONDS - t0 )); (( el > 0 )) && printf ' %s%ss%s' "$DIM" "$el" "$RST"
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
      apt) apt_update && apt-get install -y curl coreutils gawk grep sed tar ncurses-bin ;;
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

logo_shine() {   # x [visible_columns]   (white highlight sweeping over the gradient logo)
  local x=$1 lim=${2:-9999} r line n i c out d
  for (( r = 0; r < LOGO_H; r++ )); do
    line=${LOGO_RAW[r]}; n=${#line}; out="$BLD"
    for (( i = 0; i < n; i++ )); do
      c=${line:i:1}
      if [ "$c" = " " ] || (( i >= lim )); then out+=" "; continue; fi
      d=$(( i - x )); (( d < 0 )) && d=$(( -d ))
      if (( d <= 2 )); then out+="${WHT}${c}"; else out+="${SH[$(( i * 5 / n ))]}${c}"; fi
    done
    spl_line $(( LOGO_ROW + r )) "$LOGO_W" "${out}${RST}"
  done
}

spl_type() {   # row text color   (typewriter, centered on its final width)
  local row=$1 t=$2 c=$3 col i
  col=$(( (COLS - ${#t}) / 2 + 1 )); (( col < 1 )) && col=1
  for (( i = 1; i <= ${#t}; i++ )); do
    printf '\e[%d;%dH%s%s%s' "$row" "$col" "$c" "${t:0:i}" "$RST"; sleep 0.011
  done
}

spl_grow() {   # row width   (gradient ruler that draws itself)
  local row=$1 w=$2 col i
  col=$(( (COLS - w) / 2 + 1 )); (( col < 1 )) && col=1
  for (( i = 0; i < w; i++ )); do
    printf '\e[%d;%dH%s%s%s' "$row" "$(( col + i ))" "${SH[$(( i * 5 / w ))]}" "$H" "$RST"; sleep 0.006
  done
}

splash_init() {
  local L=$LOGO_H total r i v rw
  (( COLS < LOGO_W + 4 )) && L=1
  total=$(( L + 12 ))
  r=$(( (ROWS - total) / 2 + 1 )); (( r < 1 )) && r=1
  clear_screen 0
  printf '\e[?25l'
  if (( L == LOGO_H )); then
    if (( UTF )); then
      LOGO_ROW=$r
      for (( i = 2; i <= LOGO_W + 2; i += 2 )); do logo_shine -99 "$i"; sleep 0.012; done   # reveal left -> right
      for (( i = -3; i < LOGO_W + 4; i += 2 )); do logo_shine "$i"; sleep 0.009; done        # shine sweep
      logo_shine 9999
    else
      for (( i = 0; i < L; i++ )); do spl_line $(( r + i )) "$LOGO_W" "${LOGO[i]}${RST}"; sleep 0.07; done
    fi
  else
    spl_line "$r" 19 "${P}${BLD}M I N E F L A R E X${RST}"
  fi
  r=$(( r + L + 1 ))
  spl_type "$r" "ADVANCED VPS & HOSTING MANAGEMENT" "${WHT}${BLD}"
  v="v$MFX_VERSION  ·  mineflarex.indevs.in"
  spl_line $(( r + 1 )) "${#v}" "${DIM}${v}${RST}"
  rw=$(( COLS - 8 )); (( rw > 40 )) && rw=40; (( rw < 12 )) && rw=12
  spl_grow $(( r + 2 )) "$rw"
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
  spl_line "$SPL_STAT" $(( ${#OK} + 1 + 14 )) "${GRN}${BLD}${OK}${RST} ${WHT}${BLD}Ready - let's go!${RST}"
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
      apt) apt_update && apt-get install -y git ;;
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
  [ -n "$CUR_REI" ] && box_kv "[4]" "Reinstall"  "Remove and install again from scratch"
  [ -n "$CUR_USR" ] && box_kv "[5]" "Users"      "Create / delete / view / reset password"
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

celebrate() {   # short sparkle burst on success
  (( UTF )) || return 0
  local i k line
  local sp=('✦' '✧' '★' '✺' '✹' '·')
  printf '\e[?25l'
  for i in 1 2 3 4 5 6; do
    line=""
    for (( k = 0; k < W - 2; k++ )); do
      if (( RANDOM % 7 == 0 )); then line+="${SH[RANDOM % 5]}${sp[RANDOM % 6]}"; else line+=" "; fi
    done
    printf '\r%*s%s%s' "$PAD" '' "$line" "$RST"; sleep 0.09
  done
  printf '\r\e[K\e[?25h'
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
    0) celebrate; box_top; box_center "$( (( UTF )) && printf "★ INSTALLATION COMPLETE ★" || printf "INSTALLATION COMPLETE")" "$GRN$BLD"; box_center "$CUR_TITLE installed successfully" "$WHT"
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

run_reinstall() {
  REDRAW=""
  header_small "$CUR_TITLE - REINSTALL"
  box_row "Log: $LOG_FILE" "$DIM"
  box_bot
  log "=== BEGIN $CUR_KEY reinstall ==="
  "$CUR_REI"; local rc=$?
  log "=== END $CUR_KEY reinstall rc=$rc ==="
  printf '\n'
  case $rc in
    0) celebrate; box_top; box_center "REINSTALL COMPLETE" "$GRN$BLD"; box_center "$CUR_TITLE was reinstalled successfully" "$WHT"
       box_row "Log: $LOG_FILE" "$DIM"; box_bot ;;
    2) printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST" ;;
    *) printf '  %s%sREINSTALL FAILED%s - see details above.\n  Log: %s\n' "$RED" "$BLD" "$RST" "$LOG_FILE" ;;
  esac
  press_any_key
}

module_menu() {  # key title install_fn [update_fn] [reinstall_fn] [users_fn]  (CUR_INFO set by caller)
  CUR_KEY=$1; CUR_TITLE=$2; CUR_FN=$3; CUR_UPD=${4:-}; CUR_REI=${5:-}; CUR_USR=${6:-}; MSG=""
  local first=1
  while true; do
    REDRAW=draw_module_menu
    if (( first )); then draw_anim draw_module_menu; first=0; else draw_module_menu; fi
    read_key || exit 0
    MSG=""
    case $KEY in
      1) confirm_install && run_install ;;
      2) view_log ;;
      3) if [ -n "$CUR_UPD" ]; then run_update; else MSG="Invalid option '3'. Use the numbers shown, B or 0."; fi ;;
      4) if [ -n "$CUR_REI" ]; then run_reinstall; else MSG="Invalid option '4'. Use the numbers shown, B or 0."; fi ;;
      5) if [ -n "$CUR_USR" ]; then "$CUR_USR"; else MSG="Invalid option '5'. Use the numbers shown, B or 0."; fi ;;
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
update_bvm_bot() {
  STAGE_TOTAL=5; STAGE_DONE=0
  if [ ! -d "$BOT_DIR/.git" ]; then
    printf '  %s%s%s BVM VPS BOT is not installed yet. Use [1] Start Install first.\n' "$YEL" "$WRN" "$RST"; return 1
  fi
  printf '  %sThe latest code is pulled (git pull); your bot data and config files are kept.%s\n' "$DIM" "$RST"
  printf '  %sIts install.sh runs again to apply the update.%s\n\n' "$DIM" "$RST"
  ask_yn "Update BVM VPS BOT now?" || return 2
  printf '\n'
  stage "Preflight: disk & network" preflight "https://github.com" || return 1
  stage "Checking git" ensure_git || return 1
  stage "Pulling latest Bvm-v1bot code" git_fetch_repo "$BOT_REPO" "$BOT_DIR" || return 1
  stage "Validating install.sh" validate_script "$BOT_DIR/install.sh" || return 1
  stage_fg "Running install.sh (apply update)" run_bot_installer || return 1
  mark_installed bvm-bot
  return 0
}
bvm_remove_copy() {   # backup the old folder (config/data may live in it), then delete it
  [ -d "$BOT_DIR" ] || { echo "no old copy found"; return 0; }
  local b="$STATE_DIR/bvm-bot-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  mkdir -p "$STATE_DIR" || return 1
  tar -czf "$b" -C "$(dirname "$BOT_DIR")" "$(basename "$BOT_DIR")" 2>>"$LOG_FILE" || { echo "backup failed - nothing was deleted"; return 1; }
  chmod 600 "$b"
  rm -rf "${BOT_DIR:?}" || return 1
  echo "old copy removed, backup: $b"
}
reinstall_bvm_bot() {
  STAGE_TOTAL=6; STAGE_DONE=0
  printf '  %sThis deletes %s, downloads the bot fresh and runs its install.sh again.%s\n' "$DIM" "$BOT_DIR" "$RST"
  printf '  %sA backup of the old folder is saved in %s first.%s\n\n' "$DIM" "$STATE_DIR" "$RST"
  ask_yn "Reinstall BVM VPS BOT now?" || return 2
  printf '\n'
  stage "Preflight: disk & network" preflight "https://github.com" || return 1
  stage "Checking git" ensure_git || return 1
  stage "Removing old copy (with backup)" bvm_remove_copy || return 1
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
            "Update : [3] pulls the latest code and re-applies it"
            "Reinst : [4] fresh copy (old folder is backed up)"
            "Needs  : root, git (auto-installed), internet")
  module_menu bvm-bot "BVM VPS BOT" install_bvm_bot update_bvm_bot reinstall_bvm_bot
}

# ============================================================================
#  MODULE BVM PANEL  (zip download -> install.sh)
# ============================================================================
bvmp_installed() { [ -f "$BVMP_DIR/install.sh" ]; }
bvmp_fetch_zip() {  # download bvmpanel.zip -> $BVMP_DIR (HTTPS only; files are overlaid, so config/data already there are kept)
  [[ $BVMP_ZIP_URL == https://* ]] || { echo "Refusing non-HTTPS zip URL: $BVMP_ZIP_URL"; return 1; }
  command -v unzip >/dev/null 2>&1 || { apt_update; apt-get install -y unzip >>"$LOG_FILE" 2>&1; }
  command -v unzip >/dev/null 2>&1 || { echo "unzip could not be installed (see log)"; return 1; }
  local tmp z src
  tmp=$(mktemp -d) || return 1
  z="$tmp/bvmpanel.zip"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --connect-timeout 10 --max-time 180 -o "$z" "$BVMP_ZIP_URL" \
    || { rm -rf "$tmp"; echo "Cannot download $BVMP_ZIP_URL"; return 1; }
  unzip -tq "$z" >/dev/null 2>&1 || { rm -rf "$tmp"; echo "Downloaded file is not a valid zip (wrong link?)"; return 1; }
  unzip -q "$z" -d "$tmp/x" || { rm -rf "$tmp"; echo "unzip failed"; return 1; }
  src="$tmp/x"
  if [ ! -f "$src/install.sh" ] && [ "$(find "$src" -mindepth 1 -maxdepth 1 | wc -l)" = 1 ]; then
    src=$(find "$src" -mindepth 1 -maxdepth 1 -type d | head -n1)
  fi
  [ -f "$src/install.sh" ] || { rm -rf "$tmp"; echo "install.sh not found in the zip root"; return 1; }
  mkdir -p "$BVMP_DIR" && cp -a "$src"/. "$BVMP_DIR"/ || { rm -rf "$tmp"; echo "copy failed"; return 1; }
  rm -rf "$tmp"
  echo "zip ok, $(find "$BVMP_DIR" -type f | wc -l) files"
}
run_bvmp_installer() {
  local rc
  ( cd "$BVMP_DIR" && chmod +x install.sh && env MFX_VIRT="$VIRT" MFX_LOG="$LOG_FILE" MFX_COLOR="$THEME_MODE" FORCE_COLOR=1 CLICOLOR_FORCE=1 ./install.sh </dev/tty )
  rc=$?
  return "$rc"
}
install_bvm_panel() {
  STAGE_TOTAL=4; STAGE_DONE=0
  if [ -e "$BVMP_DIR" ]; then
    printf '  %s%s%s Existing copy found: %s\n' "$YEL" "$WRN" "$RST" "$BVMP_DIR"
    ask_yn "Update it from the zip and re-run its install.sh? Existing files may change." || return 2
  fi
  printf '\n'
  stage "Preflight: disk & network" preflight "$BVMP_ZIP_URL" || return 1
  stage "Downloading BVM Panel (zip)" bvmp_fetch_zip || return 1
  stage "Validating install.sh" validate_script "$BVMP_DIR/install.sh" || return 1
  stage_fg "Running install.sh" run_bvmp_installer || return 1
  mark_installed bvm-panel
  return 0
}
update_bvm_panel() {
  STAGE_TOTAL=4; STAGE_DONE=0
  if ! bvmp_installed; then
    printf '  %s%s%s BVM PANEL is not installed yet. Use [1] Start Install first.\n' "$YEL" "$WRN" "$RST"; return 1
  fi
  printf '  %sThe latest zip is downloaded; your panel data and config files are kept.%s\n\n' "$DIM" "$RST"
  ask_yn "Update BVM PANEL now?" || return 2
  printf '\n'
  stage "Preflight: disk & network" preflight "$BVMP_ZIP_URL" || return 1
  stage "Downloading latest BVM Panel (zip)" bvmp_fetch_zip || return 1
  stage "Validating install.sh" validate_script "$BVMP_DIR/install.sh" || return 1
  stage_fg "Running install.sh (apply update)" run_bvmp_installer || return 1
  mark_installed bvm-panel
  return 0
}
bvmp_remove_copy() {   # backup the old folder, then delete it
  [ -d "$BVMP_DIR" ] || { echo "no old copy found"; return 0; }
  local b="$STATE_DIR/bvm-panel-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  mkdir -p "$STATE_DIR" || return 1
  tar -czf "$b" -C "$(dirname "$BVMP_DIR")" "$(basename "$BVMP_DIR")" 2>>"$LOG_FILE" || { echo "backup failed - nothing was deleted"; return 1; }
  chmod 600 "$b"
  rm -rf "${BVMP_DIR:?}" || return 1
  echo "old copy removed, backup: $b"
}
reinstall_bvm_panel() {
  STAGE_TOTAL=5; STAGE_DONE=0
  printf '  %sThis deletes %s, downloads the zip fresh and runs its install.sh again.%s\n' "$DIM" "$BVMP_DIR" "$RST"
  printf '  %sA backup of the old folder is saved in %s first.%s\n\n' "$DIM" "$STATE_DIR" "$RST"
  ask_yn "Reinstall BVM PANEL now?" || return 2
  printf '\n'
  stage "Preflight: disk & network" preflight "$BVMP_ZIP_URL" || return 1
  stage "Removing old copy (with backup)" bvmp_remove_copy || return 1
  stage "Downloading BVM Panel (zip)" bvmp_fetch_zip || return 1
  stage "Validating install.sh" validate_script "$BVMP_DIR/install.sh" || return 1
  stage_fg "Running install.sh" run_bvmp_installer || return 1
  mark_installed bvm-panel
  return 0
}
module_bvm_panel() {
  CUR_INFO=("BVM PANEL (web panel for the BVM VPS bot)"
            "Source : $BVMP_ZIP_URL"
            "Steps  : download zip, validate, run install.sh"
            "Update : [3] downloads the latest zip and re-applies it"
            "Reinst : [4] fresh copy (old folder is backed up)"
            "Needs  : root, unzip (auto-installed), internet")
  module_menu bvm-panel "BVM PANEL" install_bvm_panel update_bvm_panel reinstall_bvm_panel
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
  command -v unzip >/dev/null 2>&1 || { apt_update; apt-get install -y unzip >>"$LOG_FILE" 2>&1; }
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
  apt_update
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
    [[ $email =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { printf '  %sThat does not look like a valid email address.%s\n' "$YEL" "$RST"; continue; }
    printf '  %sPassword (10+ characters, letters + numbers):%s ' "$WHT" "$RST" >/dev/tty; IFS= read -rs pw </dev/tty;  printf '\n' >/dev/tty
    printf '  %sPassword again:%s ' "$WHT" "$RST" >/dev/tty;                            IFS= read -rs pw2 </dev/tty; printf '\n' >/dev/tty
    [ "$pw" = "$pw2" ] || { printf '  %sThe two passwords do not match. Try again.%s\n\n' "$YEL" "$RST"; continue; }
    if (( ${#pw} < 10 )) || [[ ! $pw =~ [A-Za-z] ]] || [[ ! $pw =~ [0-9] ]]; then
      printf '  %sPassword must be 10+ characters and contain both letters and numbers. Try again.%s\n\n' "$YEL" "$RST"; continue
    fi
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
  STAGE_TOTAL=7; STAGE_DONE=0
  if (( update )); then
    printf '  %s%s%s Mine Panel is already installed - this will UPDATE it.\n' "$YEL" "$WRN" "$RST"
    ask_yn "Update now? Your data, servers and admin login are kept." || return 2
  fi
  printf '\n'
  stage "Preflight: disk & network" preflight "$PANEL_ZIP_URL" || return 1
  stage "Checking system (Ubuntu / Debian)" panel_check_os || return 1
  stage "Downloading Mine Panel (zip)" panel_fetch_zip || return 1
  stage "Checking panel files" panel_check_src || return 1
  stage "Installing Node.js, Python, Java" panel_deps || return 1
  if (( update )); then
    STAGE_TOTAL=$(( STAGE_TOTAL + 1 ))
    stage "Backing up database" panel_backup || return 1
  fi
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

# ---- Reinstall: fresh code + service. Optionally wipes ALL data (database, users, servers, bots) ------------
panel_reinstall_remove() {   # stop + remove service and old code (data/.env are kept unless PANEL_WIPE=1)
  systemctl stop minepanel >>"$LOG_FILE" 2>&1 || true
  systemctl disable minepanel >>"$LOG_FILE" 2>&1 || true
  rm -f /etc/systemd/system/minepanel.service
  systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  if (( PANEL_WIPE )); then
    rm -rf "${PANEL_HOME:?}" || return 1
    rm -f "$STATE_DIR/mine-panel.installed"
    echo "panel and ALL data removed"
  else
    panel_snapshot || return 1
    local d; for d in src public scripts deploy tests; do rm -rf "${PANEL_HOME:?}/$d"; done
    echo "old code removed; data and .env kept"
  fi
}

reinstall_mine_panel() {
  STAGE_TOTAL=7; STAGE_DONE=0; PANEL_WIPE=0
  if ! panel_installed; then
    printf '  %s%s%s Mine Panel is not installed yet. Use [1] Start Install first.\n' "$YEL" "$WRN" "$RST"; return 1
  fi
  printf '  %sThe panel is removed and installed again from the latest zip.%s\n' "$DIM" "$RST"
  printf '  %sBy default your database, users, servers, bots and .env are kept.%s\n\n' "$DIM" "$RST"
  ask_yn "Reinstall Mine Panel now?" || return 2
  printf '\n  %sOptional: a COMPLETELY clean install (deletes users, servers, bots, database).%s' "$RED" "$RST"
  if ask_yn "Delete ALL panel data too?"; then
    ask_yn "Are you sure? This cannot be undone." || return 2
    PANEL_WIPE=1
  fi
  printf '\n'
  stage "Preflight: disk & network" preflight "$PANEL_ZIP_URL" || return 1
  stage "Downloading Mine Panel (zip)" panel_fetch_zip || return 1        # live panel is untouched until here
  stage "Checking panel files" panel_check_src || return 1
  stage "Installing Node.js, Python, Java" panel_deps || return 1
  stage "Removing old panel" panel_reinstall_remove || return 1
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

# ---- Users: create / delete / view ---------------------------------------------------------------------------
mp_users_prepare() {   # writes the helper next to the database (data/ is never replaced by updates)
  panel_installed || { printf '  %s%s%s Mine Panel is not installed yet. Install it first.\n' "$YEL" "$WRN" "$RST"; return 1; }
  [ -f "$PANEL_HOME/data/minepanel.db" ] || { printf '  %s%s%s Panel database not found yet - start the panel once, then try again.\n' "$YEL" "$WRN" "$RST"; return 1; }
  cat >"$PANEL_HOME/data/.mfx-users.js" <<'MFXJS'
// MineFlareX user helper - list / setrole / delete / copypass (schema is auto-detected)
const { DatabaseSync } = require('node:sqlite');
const [cmd, a1, a2] = process.argv.slice(2);
const db = new DatabaseSync(process.env.MFX_DB);
db.exec('PRAGMA busy_timeout = 5000');
db.exec('PRAGMA foreign_keys = ON');
const die = (m, c = 1) => { console.error(m); process.exit(c); };
const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r => r.name);
const ut = ['users', 'user', 'accounts'].find(t => tables.includes(t));
if (!ut) die('users table not found (tables: ' + tables.join(', ') + ')', 3);
const colsOf = t => db.prepare(`PRAGMA table_info("${t}")`).all().map(c => c.name);
const cols = colsOf(ut);
const pick = (...n) => n.find(x => cols.includes(x));
const cId = pick('id', 'user_id'), cEmail = pick('email', 'mail'), cUser = pick('username', 'name', 'user_name'),
      cRole = pick('role', 'user_role', 'type'), cAdm = pick('is_admin', 'admin', 'isAdmin');
if (!cId || !cEmail) die('could not find id/email columns in table ' + ut + ' (columns: ' + cols.join(', ') + ')', 3);
const isAdmin = r => cRole ? /admin/i.test(String(r[cRole] ?? '')) : cAdm ? !!r[cAdm] : false;
const roleOf = r => cRole || cAdm ? (isAdmin(r) ? 'admin' : 'user') : '-';
const all = () => db.prepare(`SELECT * FROM "${ut}" ORDER BY "${cId}"`).all();
const find = e => db.prepare(`SELECT * FROM "${ut}" WHERE lower("${cEmail}") = lower(?)`).get(e || '');

if (cmd === 'list') {
  for (const r of all()) console.log([r[cId], cUser ? r[cUser] : '-', r[cEmail], roleOf(r)].join('\t'));
} else if (cmd === 'setrole') {
  const r = find(a1); if (!r) die('No user with that email', 4);
  const admin = a2 === 'admin';
  if (cRole) {
    let val = 'admin';
    if (!admin) {
      const seen = db.prepare(`SELECT DISTINCT "${cRole}" v FROM "${ut}"`).all().map(x => String(x.v)).filter(v => !/admin/i.test(v));
      val = seen.includes('user') ? 'user' : (seen[0] || 'user');
    }
    db.prepare(`UPDATE "${ut}" SET "${cRole}" = ? WHERE "${cId}" = ?`).run(val, r[cId]);
  } else if (cAdm) {
    db.prepare(`UPDATE "${ut}" SET "${cAdm}" = ? WHERE "${cId}" = ?`).run(admin ? 1 : 0, r[cId]);
  } else die('no role/admin column found - cannot change the role', 6);
  console.log('role set to ' + a2);
} else if (cmd === 'delete') {
  const r = find(a1); if (!r) die('No user with that email', 4);
  if (isAdmin(r) && all().filter(isAdmin).length <= 1) die('Cannot delete the last admin account', 5);
  const id = r[cId];
  for (const t of tables) {                       // login sessions / tokens of this user
    if (t === ut || !/session|token|reset|remember|login/i.test(t)) continue;
    const c = colsOf(t).find(x => /^(user_?id|userid|user)$/i.test(x));
    if (c) { try { db.prepare(`DELETE FROM "${t}" WHERE "${c}" = ?`).run(id); } catch (e) {} }
  }
  try { db.prepare(`DELETE FROM "${ut}" WHERE "${cId}" = ?`).run(id); }
  catch (e) { die('Could not delete: this user still owns data (servers/bots). Delete those in the panel first. (' + e.message + ')', 7); }
  console.log('deleted ' + a1);
} else if (cmd === 'copypass') {                 // copy the password hash of temp user a1 onto user a2, then remove temp user a1
  const src = find(a1), dst = find(a2);
  if (!src) die('Temporary user not found', 4);
  if (!dst) die('No user with that email', 4);
  const pc = cols.filter(c => /pass|hash|salt/i.test(c) && ![cId, cEmail, cUser].includes(c) && !/(reset|token|expir|_at$|must|force|require)/i.test(c));
  if (!pc.length) die('password column not found in table ' + ut + ' (columns: ' + cols.join(', ') + ')', 6);
  db.prepare(`UPDATE "${ut}" SET ${pc.map(c => `"${c}" = ?`).join(', ')} WHERE "${cId}" = ?`).run(...pc.map(c => src[c]), dst[cId]);
  const clean = id => {                            // login sessions / tokens: old password must stop working everywhere
    for (const t of tables) {
      if (t === ut || !/session|token|reset|remember|login/i.test(t)) continue;
      const c = colsOf(t).find(x => /^(user_?id|userid|user)$/i.test(x));
      if (c) { try { db.prepare(`DELETE FROM "${t}" WHERE "${c}" = ?`).run(id); } catch (e) {} }
    }
  };
  clean(dst[cId]); clean(src[cId]);
  const done = [];
  for (const c of cols) {                          // lockout counters / lock times on the user row (15-min login limit)
    if (!/(fail|attempt|lock|block|throttl)/i.test(c) || [cId, cEmail, cUser, cRole].includes(c)) continue;
    const isTime = /(_at$|until|expir|time|date)/i.test(c);
    for (const v of (isTime ? [null, 0] : [0, null])) {
      try { db.prepare(`UPDATE "${ut}" SET "${c}" = ? WHERE "${cId}" = ?`).run(v, dst[cId]); done.push(c); break; } catch (e) {}
    }
  }
  for (const t of tables) {                        // separate login-attempt / rate-limit tables
    if (t === ut || !/(attempt|throttl|rate.?limit|lockout|login_fail|failed)/i.test(t)) continue;
    for (const c of colsOf(t)) {
      if (!/^(user_?id|userid|user|email|identifier|username|key|account)$/i.test(c)) continue;
      const em = String(dst[cEmail]).toLowerCase();
      for (const [w, a] of [[`"${c}" = ?`, dst[cId]], [`lower(CAST("${c}" AS TEXT)) = ?`, em], [`lower(CAST("${c}" AS TEXT)) LIKE ?`, '%' + em + '%']]) {
        try { db.prepare(`DELETE FROM "${t}" WHERE ${w}`).run(a); done.push(t); } catch (e) {}
      }
    }
  }
  try { db.prepare(`DELETE FROM "${ut}" WHERE "${cId}" = ?`).run(src[cId]); }
  catch (e) { die('Password changed, but the temporary helper user could not be removed (' + a1 + '): ' + e.message, 7); }
  console.log('password updated for ' + a2 + (done.length ? ' | login limit cleared: ' + [...new Set(done)].join(', ') : ''));
} else die('unknown command', 2);
MFXJS
  chown minepanel:minepanel "$PANEL_HOME/data/.mfx-users.js" 2>/dev/null
  chmod 600 "$PANEL_HOME/data/.mfx-users.js"
}
mp_users_run() { ( cd "$PANEL_HOME" && runuser -u minepanel -- env MFX_DB="$PANEL_HOME/data/minepanel.db" node $PANEL_NODE_FLAGS "$PANEL_HOME/data/.mfx-users.js" "$@" 2>&1 ); }

mp_users_show() {   # prints the user table
  local out line id un em ro n=0
  out=$(mp_users_run list) || { printf '  %s%s%s\n' "$RED" "$(printf '%s' "$out" | tail -n1)" "$RST"; return 1; }
  printf '  %s%-5s %-18s %-32s %s%s\n' "$P$BLD" "ID" "USERNAME" "EMAIL" "ROLE" "$RST"
  while IFS=$'\t' read -r id un em ro; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    printf '  %-5s %-18s %-32s %s\n' "${id:0:5}" "${un:0:18}" "${em:0:32}" "$ro"
  done <<<"$out"
  (( n )) || printf '  %sNo users yet.%s\n' "$DIM" "$RST"
  printf '\n  %sTotal: %d%s\n' "$DIM" "$n" "$RST"
}

mp_user_view() { mp_users_prepare || return 1; mp_users_show; }

mp_user_create() {
  mp_users_prepare || return 1
  [ -r /dev/tty ] || { echo "no terminal available"; return 1; }
  local admin=0 email pw user out try role=user
  printf '  %s%sCreate a new user%s\n\n' "$P" "$BLD" "$RST"
  ask_yn "Should this user be an ADMIN?" && { admin=1; role=admin; }
  printf '\n'
  while true; do
    printf '  %sEmail (gmail):%s ' "$WHT" "$RST" >/dev/tty; IFS= read -r email </dev/tty
    email=$(printf '%s' "$email" | tr -d '[:space:]')
    [ -n "$email" ] || { printf '  %sEmail is required.%s\n' "$YEL" "$RST"; continue; }
    [[ $email =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { printf '  %sThat does not look like a valid email address.%s\n' "$YEL" "$RST"; continue; }
    if mp_users_run list | cut -f3 | grep -qix -- "$email"; then printf '  %sThis email already has an account.%s\n' "$YEL" "$RST"; continue; fi
    printf '  %sPassword (10+ characters, letters + numbers):%s ' "$WHT" "$RST" >/dev/tty; IFS= read -rs pw </dev/tty; printf '\n' >/dev/tty
    if (( ${#pw} < 10 )) || [[ ! $pw =~ [A-Za-z] ]] || [[ ! $pw =~ [0-9] ]]; then
      printf '  %sPassword must be 10+ characters and contain both letters and numbers. Try again.%s\n\n' "$YEL" "$RST"; continue
    fi
    user=$(printf '%s' "${email%%@*}" | tr -c 'A-Za-z0-9_-' '_'); user=${user:0:20}
    [ "${#user}" -ge 3 ] || user="user${RANDOM}"
    for try in 1 2 3; do
      if out=$( cd "$PANEL_HOME" && runuser -u minepanel -- env ADMIN_PASSWORD="$pw" node $PANEL_NODE_FLAGS scripts/create-admin.js "$email" "$user" 2>&1 ); then
        if (( ! admin )); then
          if ! out=$(mp_users_run setrole "$email" user); then
            mp_users_run delete "$email" >/dev/null 2>&1   # never leave an unwanted admin behind
            printf '  %s%s%s\n  %sCould not make the account a normal user, so it was removed.%s\n' "$RED" "$(printf '%s' "$out" | tail -n1)" "$RST" "$RED" "$RST"
            return 1
          fi
        fi
        printf '  %s%s%s User created: %s  (%s)\n' "$GRN" "$OK" "$RST" "$email" "$role"
        return 0
      fi
      if printf '%s' "$out" | grep -qi 'taken'; then user="${user:0:15}$((RANDOM % 9000 + 1000))"; continue; fi
      break
    done
    printf '  %s%s%s\n\n' "$YEL" "$(printf '%s' "$out" | tail -n1)" "$RST"
    return 1
  done
}

mp_user_delete() {
  mp_users_prepare || return 1
  [ -r /dev/tty ] || { echo "no terminal available"; return 1; }
  local email out
  mp_users_show || return 1
  printf '\n  %sEmail of the user to delete (empty = cancel):%s ' "$WHT" "$RST" >/dev/tty; IFS= read -r email </dev/tty
  email=$(printf '%s' "$email" | tr -d '[:space:]')
  [ -n "$email" ] || { printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST"; return 2; }
  mp_users_run list | cut -f3 | grep -qix -- "$email" || { printf '  %s%s%s No user with that email.\n' "$YEL" "$WRN" "$RST"; return 1; }
  ask_yn "Delete $email permanently?" || { printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST"; return 2; }
  if out=$(mp_users_run delete "$email"); then
    printf '  %s%s%s User deleted: %s\n' "$GRN" "$OK" "$RST" "$email"; return 0
  fi
  printf '  %s%s%s\n' "$RED" "$(printf '%s' "$out" | tail -n1)" "$RST"; return 1
}

mp_user_resetpw() {
  mp_users_prepare || return 1
  [ -r /dev/tty ] || { echo "no terminal available"; return 1; }
  local email pw pw2 tuser tmail out id un em ro n=0 sel
  local -a EM=() RO=()
  out=$(mp_users_run list) || { printf '  %s%s%s\n' "$RED" "$(printf '%s' "$out" | tail -n1)" "$RST"; return 1; }
  printf '  %sSelect the user:%s\n\n' "$P$BLD" "$RST"
  while IFS=$'\t' read -r id un em ro; do
    [ -n "$em" ] || continue
    n=$((n + 1)); EM[$n]=$em; RO[$n]=$ro
    printf '  %s%2d%s  %s  %s(%s)%s\n' "$WHT$BLD" "$n" "$RST" "$em" "$DIM" "$ro" "$RST"
  done <<<"$out"
  (( n )) || { printf '  %sNo users yet.%s\n' "$DIM" "$RST"; return 1; }
  while true; do
    printf '\n  %sEnter number 1-%d (empty = cancel):%s ' "$WHT" "$n" "$RST" >/dev/tty; IFS= read -r sel </dev/tty
    sel=$(printf '%s' "$sel" | tr -d '[:space:]')
    [ -n "$sel" ] || { printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST"; return 2; }
    [[ $sel =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= n )) && break
    printf '  %sInvalid number.%s\n' "$YEL" "$RST"
  done
  email=${EM[$sel]}
  printf '\n  %sSelected: %s%s\n\n' "$DIM" "$email" "$RST"
  while true; do
    printf '  %sNew password (10+ characters, letters + numbers, empty = cancel):%s ' "$WHT" "$RST" >/dev/tty; IFS= read -rs pw </dev/tty; printf '\n' >/dev/tty
    [ -n "$pw" ] || { printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST"; return 2; }
    if (( ${#pw} < 10 )) || [[ ! $pw =~ [A-Za-z] ]] || [[ ! $pw =~ [0-9] ]]; then
      printf '  %sPassword must be 10+ characters and contain both letters and numbers. Try again.%s\n\n' "$YEL" "$RST"; continue
    fi
    printf '  %sConfirm new password:%s ' "$WHT" "$RST" >/dev/tty; IFS= read -rs pw2 </dev/tty; printf '\n' >/dev/tty
    [ "$pw" = "$pw2" ] || { printf '  %sThe two passwords do not match. Try again.%s\n\n' "$YEL" "$RST"; continue; }
    break
  done
  ask_yn "Reset password for $email? (y/n)" || { printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST"; return 2; }
  # The panel's own create-admin.js hashes the password (so the hash format always matches the panel);
  # that hash is copied to the real user and the temporary helper user is removed again.
  tuser="mfxr${RANDOM}${RANDOM}"; tmail="${tuser}@example.com"
  if ! out=$( cd "$PANEL_HOME" && runuser -u minepanel -- env ADMIN_PASSWORD="$pw" node $PANEL_NODE_FLAGS scripts/create-admin.js "$tmail" "$tuser" 2>&1 ); then
    printf '  %s%s%s\n' "$RED" "$(printf '%s' "$out" | tail -n1)" "$RST"; return 1
  fi
  if out=$(mp_users_run copypass "$tmail" "$email"); then
    printf '  %s%s%s Password reset for: %s\n' "$GRN" "$OK" "$RST" "$email"
    printf '  %s%s%s\n' "$DIM" "$(printf '%s' "$out" | tail -n1)" "$RST"
    printf '  %sThe user was logged out everywhere and the 15-minute login limit was cleared.%s\n' "$DIM" "$RST"
    if systemctl is-active --quiet minepanel 2>/dev/null; then
      printf '\n  %sIf the panel still shows "too many attempts", the limit lives in the panel memory.%s\n' "$DIM" "$RST"
      if ask_yn "Restart the panel now to clear it? (data is kept; running servers may stop briefly)"; then
        systemctl restart minepanel && printf '  %s%s%s Panel restarted.\n' "$GRN" "$OK" "$RST" \
          || printf '  %s%s%s Could not restart the panel.\n' "$YEL" "$WRN" "$RST"
      fi
    fi
    return 0
  fi
  mp_users_run delete "$tmail" >/dev/null 2>&1   # never leave the temporary user behind
  printf '  %s%s%s\n' "$RED" "$(printf '%s' "$out" | tail -n1)" "$RST"; return 1
}

run_user_action() {  # title fn
  REDRAW=""
  header_small "$1"
  box_bot
  printf '\n'
  "$2"
  press_any_key
}

draw_users_menu() {
  header_small "MINE PANEL - USERS"
  box_row "Panel : $(panel_installed && echo installed || echo 'not installed')" "$DIM"
  box_sep
  box_kv "[1]" "Create" "New user (admin yes/no, gmail, password)"
  box_kv "[2]" "Delete" "Delete a user by email"
  box_kv "[3]" "View"   "List all users"
  box_kv "[4]" "Reset Password" "Set a new password for a user"
  box_kv "[0]" "Back"   "Back to Mine Panel menu"
  box_bot
  [ -n "$MSG" ] && printf '\n%*s%s%s%s\n' "$PAD" '' "$RED" "$MSG" "$RST"
  printf '\n%*s%sSelect option:%s ' "$PAD" '' "$P$BLD" "$RST"
}

module_panel_users() {
  MSG=""; local first=1
  while true; do
    REDRAW=draw_users_menu
    if (( first )); then draw_anim draw_users_menu; first=0; else draw_users_menu; fi
    read_key || exit 0
    MSG=""
    case $KEY in
      1) run_user_action "USERS - CREATE" mp_user_create ;;
      2) run_user_action "USERS - DELETE" mp_user_delete ;;
      3) run_user_action "USERS - VIEW"   mp_user_view ;;
      4) run_user_action "USERS - RESET PASSWORD" mp_user_resetpw ;;
      0|b|B) return 0 ;;
      q|Q) do_exit ;;
      $'\e') drain_esc; MSG="Invalid input. Use 1, 2, 3, 4 or 0." ;;
      "") MSG="Please press 1, 2, 3, 4 or 0." ;;
      *) MSG="Invalid option '${KEY//[^[:print:]]/?}'. Use 1, 2, 3, 4 or 0." ;;
    esac
  done
}

module_mine_panel() {
  CUR_INFO=("Mine Panel (Minecraft + Bot hosting)"
            "Source : $PANEL_ZIP_URL"
            "Steps  : download zip, install Node/Python/Java, start panel"
            "Last   : asks the admin email + password"
            "Update : menu [3] keeps all your data"
            "Reinst : [4] fresh install (data kept unless you choose to wipe)"
            "Users  : [5] create / delete / view / reset password")
  module_menu mine-panel "MINE PANEL" install_mine_panel update_mine_panel reinstall_mine_panel module_panel_users
}

# ============================================================================
#  MODULE 3: CLOUDFLARE TUNNEL  (install cloudflared + connect with token / uninstall)
# ============================================================================
CF_TOKEN=""
cf_installed()      { command -v cloudflared >/dev/null 2>&1; }
cf_service_exists() { [ -f /etc/systemd/system/cloudflared.service ]; }

cf_status() {
  if cf_service_exists; then
    if systemctl is-active --quiet cloudflared 2>/dev/null; then echo "installed - tunnel running"
    else echo "installed - tunnel NOT running"; fi
  elif cf_installed; then
    if pgrep -x cloudflared >/dev/null 2>&1; then echo "cloudflared installed - tunnel running (no systemd)"
    else echo "cloudflared installed - no tunnel connected"; fi
  else echo "not installed"; fi
}

cf_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l|armv8l|armhf) echo arm ;;
    armv6l) echo arm ;;
    i386|i686) echo 386 ;;
    *) echo "" ;;
  esac
}

# Fallback: download the official binary straight from GitHub releases (no apt key needed)
cf_install_bin() {
  local arch url
  arch=$(cf_arch); [ -n "$arch" ] || { echo "unsupported CPU: $(uname -m)"; return 1; }
  url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 15 "$url" -o /usr/local/bin/cloudflared.new \
    || { rm -f /usr/local/bin/cloudflared.new; echo "cannot download cloudflared binary"; return 1; }
  chmod 0755 /usr/local/bin/cloudflared.new && mv -f /usr/local/bin/cloudflared.new /usr/local/bin/cloudflared || return 1
  cf_installed || { echo "cloudflared binary not in PATH (/usr/local/bin)"; return 1; }
}

cf_install_pkg() {   # official Cloudflare package repo (apt / dnf / yum), binary fallback
  export DEBIAN_FRONTEND=noninteractive
  local ok=0
  case $PM in
    apt)
      # Cloudflare rotated its signing key: current one is cloudflare-public-v2.gpg
      # (old cloudflare-main.gpg makes 'apt-get update' fail with a signature error).
      if mkdir -p --mode=0755 /usr/share/keyrings \
         && curl --proto '=https' --tlsv1.2 -fsSL --retry 2 https://pkg.cloudflare.com/cloudflare-public-v2.gpg \
              -o /usr/share/keyrings/cloudflare-public-v2.gpg \
         && printf 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main\n' \
              >/etc/apt/sources.list.d/cloudflared.list; then
        rm -f /usr/share/keyrings/cloudflare-main.gpg
        # update may print errors for unrelated broken repos - only the install result matters
        apt_update
        apt-get install -y cloudflared >>"$LOG_FILE" 2>&1 && ok=1
      fi
      if (( ! ok )); then
        log "cloudflared apt install failed - removing repo and using GitHub binary"
        rm -f /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-public-v2.gpg
        apt_update
      fi
      ;;
    dnf|yum)
      curl --proto '=https' --tlsv1.2 -fsSL --retry 2 https://pkg.cloudflare.com/cloudflared.repo \
        -o /etc/yum.repos.d/cloudflared.repo \
        && "$PM" install -y cloudflared >>"$LOG_FILE" 2>&1 && ok=1
      (( ok )) || { log "cloudflared rpm install failed - using GitHub binary"; rm -f /etc/yum.repos.d/cloudflared.repo; }
      ;;
  esac
  if ! cf_installed; then
    cf_install_bin || return 1
  fi
  cf_installed || { echo "cloudflared still missing after install"; return 1; }
  echo "cloudflared $(cloudflared --version 2>/dev/null | awk '{print $3}')"
}

# Asks for the tunnel token. You can paste ONLY the token, or the whole command
# Cloudflare shows you (sudo cloudflared service install <token>) - the token is picked out.
cf_ask_token() {
  [ -r /dev/tty ] || { echo "no terminal available"; return 1; }
  local raw tok
  printf '  %s%sPaste your Cloudflare Tunnel token%s\n' "$P" "$BLD" "$RST"
  printf '  %s(Zero Trust > Networks > Tunnels > your tunnel > Install connector)%s\n' "$DIM" "$RST"
  printf '  %s(token OR the full "sudo cloudflared service install ..." command - input is hidden; empty = cancel)%s\n\n' "$DIM" "$RST"
  while true; do
    printf '  %sToken:%s ' "$WHT" "$RST" >/dev/tty
    IFS= read -rs raw </dev/tty; printf '\n' >/dev/tty
    tok=$(printf '%s' "$raw" | awk '{print $NF}')
    [ -n "$tok" ] || { printf '  %sNo token entered - cancelled.%s\n' "$YEL" "$RST"; return 1; }
    if [[ $tok =~ ^[A-Za-z0-9_=+/-]{40,}$ ]]; then
      CF_TOKEN=$tok
      printf '  %s%s%s Token received (%s characters)\n' "$GRN" "$OK" "$RST" "${#tok}"
      return 0
    fi
    printf '  %sThat does not look like a Cloudflare tunnel token. Copy it again and retry.%s\n\n' "$YEL" "$RST"
  done
}

cf_has_systemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }

cf_service_install() {
  [ -n "${CF_TOKEN:-}" ] || { echo "no token provided"; return 1; }
  local out
  if cf_has_systemd; then
    if cf_service_exists; then cloudflared service uninstall >>"$LOG_FILE" 2>&1 || true; fi
    if ! out=$(cloudflared service install "$CF_TOKEN" 2>&1); then
      out=${out//"$CF_TOKEN"/***}                      # never show / log the token
      log "cloudflared service install failed: ${out##*$'\n'}"
      echo "service install failed: ${out##*$'\n'}"; return 1
    fi
    systemctl enable cloudflared >>"$LOG_FILE" 2>&1 || true
    systemctl restart cloudflared >>"$LOG_FILE" 2>&1 || systemctl start cloudflared >>"$LOG_FILE" 2>&1 || true
    echo "cloudflared service installed"
  else
    # No systemd (some containers / LXC): run the tunnel directly in the background
    pkill -x cloudflared >/dev/null 2>&1 || true
    mkdir -p /var/log
    setsid nohup cloudflared tunnel --no-autoupdate run --token "$CF_TOKEN" \
      >>/var/log/cloudflared.log 2>&1 </dev/null &
    disown 2>/dev/null || true
    log "no systemd - started cloudflared in background (log: /var/log/cloudflared.log)"
    echo "no systemd: tunnel started in background (will not auto-start after reboot)"
  fi
}

cf_verify() {
  local i
  for i in $(seq 1 25); do
    if cf_has_systemd; then
      systemctl is-active --quiet cloudflared 2>/dev/null && { echo "cloudflared service is running"; return 0; }
    else
      pgrep -x cloudflared >/dev/null 2>&1 && { echo "cloudflared is running (no systemd)"; return 0; }
    fi
    sleep 1
  done
  if cf_has_systemd; then echo "service not running - see: journalctl -u cloudflared -n 50 --no-pager"
  else echo "tunnel not running - see: tail -n 50 /var/log/cloudflared.log"; fi
  return 1
}

cf_open_hint() {
  printf '\n  %s%sFinish in the Cloudflare dashboard%s\n' "$P" "$BLD" "$RST"
  printf '  %sZero Trust > Networks > Tunnels > your tunnel > Public Hostname > Add:%s\n' "$DIM" "$RST"
  printf '  %sService HTTP -> localhost:%s   (this is the Mine Panel port)%s\n' "$DIM" "$PANEL_PORT" "$RST"
  printf '  %sLogs: journalctl -u cloudflared -f%s\n' "$DIM" "$RST"
}

install_cloudflare() {
  STAGE_TOTAL=5; STAGE_DONE=0; CF_TOKEN=""
  if cf_service_exists; then
    printf '  %s%s%s A Cloudflare tunnel service already exists on this VPS.\n' "$YEL" "$WRN" "$RST"
    ask_yn "Replace it with a new token?" || return 2
  fi
  printf '\n'
  stage    "Preflight: disk & network"  preflight "https://pkg.cloudflare.com/cloudflare-public-v2.gpg" || return 1
  stage    "Installing cloudflared"     cf_install_pkg || return 1
  stage_fg "Tunnel token"               cf_ask_token   || { CF_TOKEN=""; return 1; }
  stage    "Connecting tunnel (service)" cf_service_install || { CF_TOKEN=""; return 1; }
  CF_TOKEN=""
  stage    "Verifying tunnel"           cf_verify || return 1
  mark_installed cloudflare
  cf_open_hint
  return 0
}

reinstall_cloudflare() {
  STAGE_TOTAL=8; STAGE_DONE=0; CF_TOKEN=""
  if ! cf_installed && ! cf_service_exists; then
    printf '  %s%s%s Cloudflare is not installed yet. Use [1] Install first.\n' "$YEL" "$WRN" "$RST"; return 1
  fi
  printf '  %sThis removes cloudflared and the tunnel service, then installs everything again.%s\n' "$DIM" "$RST"
  printf '  %sYou need your Cloudflare tunnel token (asked first, before anything is removed).%s\n' "$DIM" "$RST"
  ask_yn "Reinstall Cloudflare now?" || return 2
  printf '\n'
  stage    "Preflight: disk & network"   preflight "https://pkg.cloudflare.com/cloudflare-public-v2.gpg" || return 1
  stage_fg "Tunnel token"                cf_ask_token   || { CF_TOKEN=""; return 1; }
  stage    "Removing tunnel service"     cf_service_remove || { CF_TOKEN=""; return 1; }
  stage    "Removing cloudflared"        cf_pkg_remove     || { CF_TOKEN=""; return 1; }
  stage    "Cleaning repo and config"    cf_clean          || { CF_TOKEN=""; return 1; }
  stage    "Installing cloudflared"      cf_install_pkg    || { CF_TOKEN=""; return 1; }
  stage    "Connecting tunnel (service)" cf_service_install || { CF_TOKEN=""; return 1; }
  CF_TOKEN=""
  stage    "Verifying tunnel"            cf_verify || return 1
  mark_installed cloudflare
  cf_open_hint
  return 0
}

cf_service_remove() {
  if cf_service_exists; then
    if cf_installed; then cloudflared service uninstall >>"$LOG_FILE" 2>&1 || true; fi
    systemctl stop cloudflared >>"$LOG_FILE" 2>&1 || true
    systemctl disable cloudflared >>"$LOG_FILE" 2>&1 || true
    rm -f /etc/systemd/system/cloudflared.service /etc/systemd/system/cloudflared-update.service /etc/systemd/system/cloudflared-update.timer
    systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
    echo "tunnel service removed"
  else
    pkill -x cloudflared >/dev/null 2>&1 && echo "background tunnel stopped" || echo "no tunnel service found"
  fi
}

cf_pkg_remove() {
  export DEBIAN_FRONTEND=noninteractive
  case $PM in
    apt)     apt-get remove -y cloudflared >>"$LOG_FILE" 2>&1 || { echo "package removal failed (see log)"; return 1; } ;;
    dnf|yum) "$PM" remove -y cloudflared >>"$LOG_FILE" 2>&1   || { echo "package removal failed (see log)"; return 1; } ;;
  esac
  rm -f /usr/local/bin/cloudflared   # manual installs
  echo "cloudflared removed"
}

cf_clean() {
  rm -f /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-main.gpg /usr/share/keyrings/cloudflare-public-v2.gpg /etc/yum.repos.d/cloudflared.repo /var/log/cloudflared.log
  rm -rf /etc/cloudflared
  rm -f "$STATE_DIR/cloudflare.installed"
  echo "repo, key and /etc/cloudflared cleaned"
}

uninstall_cloudflare() {
  STAGE_TOTAL=3; STAGE_DONE=0
  if ! cf_installed && ! cf_service_exists; then
    printf '  %s%s%s Cloudflare is not installed - nothing to remove.\n' "$YEL" "$WRN" "$RST"; return 1
  fi
  printf '  %sThis stops the tunnel and removes cloudflared, its service and /etc/cloudflared.%s\n' "$DIM" "$RST"
  printf '  %sYour sites/panel stay on the VPS but will no longer be reachable through the tunnel.%s\n' "$DIM" "$RST"
  ask_yn "Uninstall Cloudflare now?" || return 2
  printf '\n'
  stage "Removing tunnel service"     cf_service_remove || return 1
  stage "Removing cloudflared"        cf_pkg_remove     || return 1
  stage "Cleaning repo and config"    cf_clean          || return 1
  return 0
}

run_cf_action() {  # title fn success_message
  REDRAW=""
  header_small "$1"
  box_row "Log: $LOG_FILE" "$DIM"
  box_bot
  log "=== BEGIN $1 ==="
  "$2"; local rc=$?
  log "=== END $1 rc=$rc ==="
  printf '\n'
  case $rc in
    0) box_top; box_center "$3" "$GRN$BLD"; box_row "Log: $LOG_FILE" "$DIM"; box_bot ;;
    2) printf '  %s%s Cancelled - nothing was changed.%s\n' "$YEL" "$WRN" "$RST" ;;
    *) printf '  %s%sFAILED%s - see details above.\n  Log: %s\n' "$RED" "$BLD" "$RST" "$LOG_FILE" ;;
  esac
  press_any_key
}

draw_cf_menu() {
  header_small "CLOUDFLARE TUNNEL"
  box_row "Status : $(cf_status)" "$DIM"
  box_row "Needs  : root, internet, Cloudflare tunnel token" "$DIM"
  box_sep
  box_kv "[1]" "Install"   "Install cloudflared + connect with token"
  box_kv "[2]" "Uninstall" "Remove cloudflared and the tunnel"
  box_kv "[3]" "Reinstall" "Remove everything and install again"
  box_kv "[B]" "Back"      "Back to Main Menu"
  box_bot
  [ -n "$MSG" ] && printf '\n%*s%s%s%s\n' "$PAD" '' "$RED" "$MSG" "$RST"
  printf '\n%*s%sSelect option:%s ' "$PAD" '' "$P$BLD" "$RST"
}

module_cloudflare() {
  MSG=""; local first=1
  while true; do
    REDRAW=draw_cf_menu
    if (( first )); then draw_anim draw_cf_menu; first=0; else draw_cf_menu; fi
    read_key || exit 0
    MSG=""
    case $KEY in
      1) run_cf_action "CLOUDFLARE - INSTALL"   install_cloudflare   "CLOUDFLARE INSTALLED & CONNECTED" ;;
      2) run_cf_action "CLOUDFLARE - UNINSTALL" uninstall_cloudflare "CLOUDFLARE UNINSTALLED" ;;
      3) run_cf_action "CLOUDFLARE - REINSTALL" reinstall_cloudflare "CLOUDFLARE REINSTALLED & CONNECTED" ;;
      b|B) return 0 ;;
      0|q|Q) do_exit ;;
      $'\e') drain_esc; MSG="Invalid input. Use 1, 2, 3 or B." ;;
      "") MSG="Please press 1, 2, 3 or B." ;;
      *) MSG="Invalid option '${KEY//[^[:print:]]/?}'. Use 1, 2, 3 or B." ;;
    esac
  done
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
  box_blank
  box_grad "WELCOME TO MINEFLAREX"
  box_blank
  box_info "System" "$os"
  box_info "CPU" "$cpu core(s)"
  box_info "Memory" "$ram"
  box_info "Disk" "$disk free"
  box_info "Virt" "${VIRT_LABEL:-none}"
  box_info "Log" "$LOG_FILE"
  box_blank
  box_center "Fast  ·  Secure  ·  One-command setup" "$P"
  box_bot
  printf '\n\n'
  welcome_prompt 0
}

welcome_prompt() {   # frame  (pulses between dim and bright)
  local t="Press any key to open the main menu" c
  if (( $1 % 2 )); then c="$WHT$BLD"; else c="$DIM"; fi
  printf '\r\e[K%*s%s%s%s' "$(( PAD + (W - ${#t}) / 2 ))" '' "$c" "$t" "$RST"
}

wait_key_pulse() {   # waits for a key while the prompt pulses; handles terminal resize
  local i=0 k rc
  while true; do
    IFS= read -rsn1 -t 0.45 k </dev/tty; rc=$?
    if (( rc == 0 )); then KEY=$k; return 0
    elif (( rc > 128 )); then
      if (( RESIZED )); then RESIZED=0; update_dims; screen_welcome; fi
      i=$(( i + 1 )); welcome_prompt "$i"
    else KEY=""; return 1; fi
  done
}

mm_status() {  # label text state(1 ok / 2 warn / 0 off)
  local lab dot c txt=$2
  printf -v lab '%-14s' "$1"
  case $3 in 1) c=$GRN; dot=$DOT ;; 2) c=$YEL; dot=$DOT ;; *) c=$DIM; dot=$DOT0 ;; esac
  box_raw_l "${DIM}${lab}${RST}${c}${dot} ${txt}${RST}" $(( 14 + ${#dot} + 1 + ${#txt} ))
}

draw_main_menu() {
  header_full
  box_blank
  box_grad "SELECT AN OPTION"
  box_blank
  local i1="" i2="" i3="" i4="" i0="" st
  if (( UTF )); then i1="◆ "; i2="▣ "; i3="❖ "; i4="◉ "; i0="✕ "; fi
  box_kv "[1]" "${i1}BVM VPS BOT"   "VPS automation bot"
  box_kv "[2]" "${i2}MINE PANEL"    "Minecraft + Bot hosting panel"
  box_kv "[3]" "${i3}BVM PANEL"     "Web panel for the BVM bot"
  box_kv "[4]" "${i4}CLOUDFLARE"    "Tunnel (install / reinstall / uninstall)"
  box_blank
  box_sep
  if [ -d "$BOT_DIR/.git" ]; then mm_status "BVM VPS BOT" "installed" 1; else mm_status "BVM VPS BOT" "not installed" 0; fi
  if panel_installed; then
    if systemctl is-active --quiet minepanel 2>/dev/null; then mm_status "MINE PANEL" "running" 1; else mm_status "MINE PANEL" "installed - stopped" 2; fi
  else mm_status "MINE PANEL" "not installed" 0; fi
  if bvmp_installed; then mm_status "BVM PANEL" "installed" 1; else mm_status "BVM PANEL" "not installed" 0; fi
  st=$(cf_status)
  case $st in *"not installed"*) mm_status "CLOUDFLARE" "not installed" 0 ;; *"tunnel running"*) mm_status "CLOUDFLARE" "tunnel running" 1 ;; *) mm_status "CLOUDFLARE" "$st" 2 ;; esac
  box_sep
  box_kv "[0]" "${i0}EXIT" ""
  box_row "Just press the number - no Enter needed" "$DIM"
  box_bot
  [ -n "$MSG" ] && printf '\n%*s%s%s%s\n' "$PAD" '' "$RED" "$MSG" "$RST"
  printf '\n%*s%sEnter choice [1-4, 0=Exit]:%s ' "$PAD" '' "$P$BLD" "$RST"
}

main_menu() {
  header_full
  box_center "$( (( UTF )) && printf "◈  SELECT AN INSTALLATION  ◈" || printf "SELECT AN INSTALLATION")" "$P$BLD"
  box_blank
  local i1="" i2="" i3="" i4="" i0=""
  if (( UTF )); then i1="◆ "; i2="▣ "; i3="❖ "; i4="◉ "; i0="✕ "; fi
  box_kv "[1]" "${i1}BVM VPS BOT"   "VPS automation bot"
  box_kv "[2]" "${i2}MINE PANEL"    "Minecraft + Bot hosting panel"
  box_kv "[3]" "${i3}BVM PANEL"     "Web panel for the BVM bot"
  box_kv "[4]" "${i4}CLOUDFLARE"    "Cloudflare tunnel (install / reinstall / uninstall)"
  box_blank
  box_kv "[0]" "${i0}EXIT" ""
  box_blank
  box_row "Just press the number - no Enter needed" "$DIM"
  box_bot
  [ -n "$MSG" ] && printf '\n%*s%s%s%s\n' "$PAD" '' "$RED" "$MSG" "$RST"
  printf '\n%*s%sEnter choice [1-4, 0=Exit]:%s ' "$PAD" '' "$P$BLD" "$RST"
}

main_menu() {
  MSG=""; local first=1
  while true; do
    STAGE_TOTAL=0; STAGE_DONE=0
    REDRAW=draw_main_menu
    if (( first )); then draw_anim draw_main_menu; first=0; else draw_main_menu; fi
    read_key || exit 0
    MSG=""
    case $KEY in
      1) module_bvm_bot ;;
      2) module_mine_panel ;;
      3) module_bvm_panel ;;
      4) module_cloudflare ;;
      0|q|Q) do_exit ;;
      $'\e') drain_esc; MSG="Invalid input. Please press 1, 2, 3, 4 or 0." ;;
      "") MSG="Please press 1, 2, 3, 4 or 0." ;;
      *) MSG="Invalid option '${KEY//[^[:print:]]/?}'. Please press 1, 2, 3, 4 or 0." ;;
    esac
  done
}

# ----------------------------------------------------------------------------
main() {
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  trap 'RESIZED=1' WINCH
  setup_locale
  setup_theme
  update_dims
  enter_fullscreen          # theme colors + black full screen from the very first moment
  # Pick a writable temp dir: $TMPDIR, /tmp, /var/tmp, $PREFIX/tmp (Termux), $HOME - first one that works
  TMP=""
  for _d in "${TMPDIR:-}" /tmp /var/tmp "${PREFIX:-}/tmp" "$HOME"; do
    [ -n "$_d" ] || continue
    [ -d "$_d" ] || mkdir -p "$_d" 2>/dev/null || continue
    [ -w "$_d" ] || continue
    TMP=$(mktemp -d "$_d/mineflarex.XXXXXX" 2>/dev/null) && break
    TMP=""
  done
  [ -n "$TMP" ] || { leave_fullscreen; echo "mktemp failed: no writable temp directory (tried TMPDIR, /tmp, /var/tmp, HOME)"; exit 1; }
  build_logo
  detect_pm || true
  boot
  REDRAW=screen_welcome
  BOX_DELAY=0.02; screen_welcome; BOX_DELAY=0
  wait_key_pulse || exit 0
  main_menu
}

main "$@"
