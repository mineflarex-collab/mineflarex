#!/bin/bash
# ============================================================
#  Bvm Vps V1 — Installer
#  Sets up LXD/LXC, Python deps, systemd service for bot.py
# ============================================================

set -e

# ---------- Colors ----------
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; BLU='\033[0;34m'
MAG='\033[0;35m'; CYN='\033[0;36m'; WHT='\033[0;32m'; NC='\033[0m'

rainbow_line() {
    local text="$1"
    local colors=("$RED" "$YEL" "$GRN" "$CYN" "$BLU" "$MAG")
    local i=0
    for (( j=0; j<${#text}; j++ )); do
        c=${colors[$((i % 6))]}
        printf '%b%s%b' "$c" "${text:$j:1}" "$NC"
        i=$((i+1))
    done
    echo ""
}

ascii_banner() {
    rainbow_line '######   ##     ## ##     ##'
    rainbow_line '##   ##  ##     ## ###   ###'
    rainbow_line '##   ##  ##     ## #### ####'
    rainbow_line '######   ##     ## ## ### ##'
    rainbow_line '##   ##   ##   ##  ##     ##'
    rainbow_line '##   ##    ## ##   ##     ##'
    rainbow_line '######      ###    ##     ##'
    echo ""
    rainbow_line '         BVM V1'
    echo ""
    rainbow_line '  ~ Made by MineFlareX ~'
    echo ""
}

banner() {
    clear
    ascii_banner
    echo -e "${WHT}  ─────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${CYN}Fully Automated LXC/LXD VPS Discord Bot Installer${NC}"
    echo -e "  ${CYN}Ubuntu & Debian supported | Fast setup${NC}"
    echo -e "  ${MAG}Made by MineFlareX${NC}  |  ${BLU}github.com/mineflarex-collab/Bvm-v1bot${NC}"
    echo -e "${WHT}  ─────────────────────────────────────────────────────────────${NC}\n"
}

step()  { echo -e "${GRN}[+]${NC} $1"; }
warn()  { echo -e "${YEL}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }

need_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Please run this script as root (sudo ./install.sh)"
        exit 1
    fi
}

# ---------- OS selection ----------
choose_os() {
    echo -e "${WHT}Select your OS:${NC}"
    echo -e "  ${YEL}1)${NC} Ubuntu"
    echo -e "  ${YEL}2)${NC} Debian"
    echo -e "  ${YEL}3)${NC} Update bot ${GRN}(keeps all data, token & VPS list)${NC}"
    read -rp "$(echo -e "${CYN}Enter choice [1-3]: ${NC}")" OS_CHOICE
}

# ---------- Update (option 3) ----------
# Replaces only bot.py and restarts the service. vps.db, the systemd service
# file (token / admin id) and all LXC containers are never touched.
INSTALL_DIR="${BVM_INSTALL_DIR:-/root}"
SERVICE_FILE="${BVM_SERVICE_FILE:-/etc/systemd/system/bot.service}"

update_bot() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ ! -f "$SERVICE_FILE" ] || [ ! -f "$INSTALL_DIR/bot.py" ]; then
        err "No existing installation found. Run option 1 or 2 first."
        exit 1
    fi

    # 1) Pull the latest code if this folder is a git clone (best effort)
    if [ -d "$SCRIPT_DIR/.git" ] && command -v git >/dev/null 2>&1; then
        step "Fetching latest code from GitHub..."
        GIT_OUT="$(git -C "$SCRIPT_DIR" pull --ff-only 2>&1)"; GIT_RC=$?
        echo -e "${GRN}${GIT_OUT}${NC}"
        if [ "$GIT_RC" -ne 0 ]; then
            warn "git pull failed - continuing with the local bot.py in $SCRIPT_DIR"
        fi
    else
        warn "Not a git clone - using the bot.py that is next to install.sh"
    fi

    if [ ! -f "$SCRIPT_DIR/bot.py" ]; then
        err "bot.py not found next to install.sh."
        exit 1
    fi

    # 2) Make sure the new file is valid Python before touching anything
    step "Checking new bot.py for errors..."
    if ! SYNTAX_ERR=$(python3 -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$SCRIPT_DIR/bot.py" 2>&1); then
        echo "$SYNTAX_ERR" | tail -n 3
        err "New bot.py has a syntax error. Update cancelled - your bot was NOT changed."
        exit 1
    fi

    # 3) Back up data and the current bot.py
    BACKUP_DIR="$INSTALL_DIR/update-backups/$(date +%Y%m%d-%H%M%S)"
    step "Backing up data to $BACKUP_DIR ..."
    mkdir -p "$BACKUP_DIR"
    cp -a "$INSTALL_DIR/bot.py" "$BACKUP_DIR/bot.py"
    for f in "$INSTALL_DIR"/vps.db "$INSTALL_DIR"/vps.db-wal "$INSTALL_DIR"/vps.db-shm; do
        [ -f "$f" ] && cp -a "$f" "$BACKUP_DIR/"
    done

    # 4) Make sure dependencies exist (does not upgrade what is installed)
    step "Checking Python dependencies..."
    pip3 install -q discord.py requests 2>/dev/null || warn "Could not verify pip packages (continuing)"

    # 5) Swap bot.py and restart
    prepare_host_modules 2>/dev/null || true
    step "Installing new bot.py..."
    cp "$SCRIPT_DIR/bot.py" "$INSTALL_DIR/bot.py"

    step "Restarting bot service..."
    systemctl daemon-reload
    systemctl restart bot
    sleep 6

    if systemctl is-active --quiet bot; then
        echo -e "\n${WHT}────────────────────────────────────────${NC}"
        echo -e "${GRN}  Update complete! Bot is running.${NC}"
        echo -e "${WHT}────────────────────────────────────────${NC}"
        echo -e "  ${CYN}Data kept:${NC}    vps.db, token, admin ID, all VPS"
        echo -e "  ${CYN}Backup:${NC}       $BACKUP_DIR"
        echo -e "  ${CYN}Logs:${NC}         journalctl -u bot -f"
        echo -e "${WHT}────────────────────────────────────────${NC}\n"
    else
        err "Bot failed to start with the new code - rolling back to the old version..."
        cp -a "$BACKUP_DIR/bot.py" "$INSTALL_DIR/bot.py"
        systemctl restart bot
        err "Rolled back. Check the error with: journalctl -u bot -n 50 --no-pager"
        exit 1
    fi
}

install_lxd_ubuntu() {
    step "Updating system (Ubuntu)..."
    apt update && apt upgrade -y

    step "Installing LXC utilities..."
    apt install lxc lxc-utils -y

    step "Installing snapd..."
    apt install snapd -y
    systemctl enable --now snapd.socket

    step "Installing LXD via snap..."
    snap install lxd

    step "Adding $SUDO_USER to lxd group..."
    usermod -aG lxd "${SUDO_USER:-$USER}" || true

    step "Initializing LXD (auto/minimal config)..."
    lxd init --auto

    step "Installing bridge/uidmap utilities..."
    apt update
    apt install lxc lxc-utils bridge-utils uidmap -y
}

install_lxd_debian() {
    step "Updating system (Debian)..."
    apt update && apt upgrade -y

    step "Installing snapd..."
    apt install snapd -y
    systemctl enable --now snapd.socket

    step "Linking snap directory..."
    ln -sf /var/lib/snapd/snap /snap

    step "Installing LXD via snap..."
    snap install lxd

    step "Adding $SUDO_USER to lxd group..."
    usermod -aG lxd "${SUDO_USER:-$USER}" || true

    step "Initializing LXD (auto/minimal config)..."
    lxd init --auto
}

install_python_stack() {
    step "Installing Python 3 / pip..."
    apt install python3-pip -y

    step "Allowing pip to break system packages (PEP 668 override)..."
    mkdir -p ~/.config/pip
    echo -e "[global]\nbreak-system-packages = true" > ~/.config/pip/pip.conf

    step "Installing Python dependencies (discord.py, requests)..."
    pip3 install -U discord.py requests
}

deploy_bot() {
    step "Deploying bot.py to /root ..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/bot.py" ]; then
        cp "$SCRIPT_DIR/bot.py" /root/bot.py
    else
        err "bot.py not found next to install.sh. Place it in the same folder and re-run."
        exit 1
    fi
}

configure_env() {
    echo -e "\n${WHT}────────── Bot Configuration ──────────${NC}"
    read -rp "$(echo -e "${CYN}Enter your Discord Bot Token: ${NC}")" DISCORD_TOKEN
    read -rp "$(echo -e "${CYN}Enter your Main Admin Discord ID: ${NC}")" MAIN_ADMIN_ID

    if [ -z "$DISCORD_TOKEN" ] || [ -z "$MAIN_ADMIN_ID" ]; then
        err "Token and Admin ID cannot be empty."
        exit 1
    fi
}

create_service() {
    step "Creating systemd service..."
    cat > /etc/systemd/system/bot.service <<EOF
[Unit]
Description=IPMI SUPERMICRO BOT
After=network.target

[Service]
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/bot.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=DISCORD_TOKEN=${DISCORD_TOKEN}
Environment=MAIN_ADMIN_ID=${MAIN_ADMIN_ID}
Environment=BOT_NAME=Bvm-v1

[Install]
WantedBy=multi-user.target
EOF

    step "Reloading systemd daemon..."
    systemctl daemon-reload

    step "Starting bot service..."
    systemctl restart bot

    step "Enabling bot service on boot..."
    systemctl enable bot
}

final_message() {
    echo -e "\n${WHT}────────────────────────────────────────${NC}"
    echo -e "${GRN}  Installation complete!${NC}"
    echo -e "${WHT}────────────────────────────────────────${NC}"
    echo -e "  ${CYN}Service name:${NC} bot.service"
    echo -e "  ${CYN}Status:${NC}       systemctl status bot"
    echo -e "  ${CYN}Logs:${NC}         journalctl -u bot -f"
    echo -e "  ${CYN}Restart:${NC}      systemctl restart bot"
    echo -e "${WHT}────────────────────────────────────────${NC}\n"
}

# ---------- Host kernel modules (Docker / Pterodactyl / Tailscale inside VPS) ----------
prepare_host_modules() {
    step "Loading kernel modules (Docker / Wings / snap / Tailscale / KVM support)..."
    MODS="tun overlay br_netfilter bridge veth loop squashfs fuse ip_tables ip6_tables iptable_nat iptable_filter iptable_mangle nf_nat nf_conntrack xt_conntrack xt_MASQUERADE xt_addrtype xt_mark nfnetlink vxlan netlink_diag vhost_net kvm kvm_intel kvm_amd"
    : > /etc/modules-load.d/bvm.conf
    for m in $MODS; do
        if modprobe "$m" 2>/dev/null; then echo "$m" >> /etc/modules-load.d/bvm.conf; fi
    done
    if [ ! -c /dev/net/tun ]; then
        mkdir -p /dev/net && mknod /dev/net/tun c 10 200 2>/dev/null && chmod 666 /dev/net/tun || true
    fi
    [ -c /dev/fuse ] || { mknod /dev/fuse c 10 229 2>/dev/null && chmod 666 /dev/fuse; } || true
    [ -c /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null || true
    for i in 0 1 2 3 4 5 6 7; do [ -b /dev/loop$i ] || mknod /dev/loop$i b 7 $i 2>/dev/null || true; done
}

main() {
    banner
    need_root
    choose_os

    case "$OS_CHOICE" in
        1) install_lxd_ubuntu ;;
        2) install_lxd_debian ;;
        3) update_bot; exit 0 ;;
        *) err "Invalid choice. Exiting."; exit 1 ;;
    esac

    prepare_host_modules
    install_python_stack
    deploy_bot
    configure_env
    create_service
    final_message
}

main "$@"
