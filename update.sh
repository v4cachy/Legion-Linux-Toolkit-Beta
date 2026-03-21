#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Legion Linux Toolkit — Updater  v0.6.1-BETA
# Pulls latest from GitHub then reinstalls all files.
# Usage: sudo bash update.sh
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
info() { echo -e "  ${CYAN}→${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "  ${RED}✗${NC}  $*"; exit 1; }

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

REPO_URL="https://github.com/v4cachy/legion-linux-toolkit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"

echo -e "\n${BOLD}╔══════════════════════════════════════════╗"
echo      "║   Legion Linux Toolkit — Updater         ║"
echo      "║              v0.6.1-BETA                 ║"
echo -e   "╚══════════════════════════════════════════╝"
echo -e "  Repo: ${CYAN}${REPO_URL}${NC}\n"

# ── 1. Pull from GitHub ───────────────────────────────────────────────────────
echo -e "${BOLD}[1/4] Pulling latest from GitHub…${NC}"

command -v git &>/dev/null || err "git not found — sudo pacman -S git"

if [[ -d "$SCRIPT_DIR/.git" ]]; then
    cd "$SCRIPT_DIR"
    git stash --quiet 2>/dev/null || true
    BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    git pull --ff-only origin main 2>&1 | while IFS= read -r line; do
        echo -e "     ${CYAN}git${NC}  $line"
    done
    AFTER=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    if [[ "$BEFORE" == "$AFTER" ]]; then
        ok "Already up to date"
    else
        echo ""
        info "Changes pulled:"
        git log --oneline "${BEFORE}..${AFTER}" 2>/dev/null | while IFS= read -r line; do
            echo -e "     ${GREEN}•${NC}  $line"
        done
        echo ""
    fi
else
    warn "Not a git repo — doing a fresh download…"
    TMPDIR=$(mktemp -d); trap "rm -rf $TMPDIR" EXIT
    info "Cloning from GitHub…"
    git clone --depth=1 "$REPO_URL" "$TMPDIR/legion-toolkit" 2>&1 \
        | grep -v "^$" | while IFS= read -r line; do
            echo -e "     ${CYAN}git${NC}  $line"
        done
    rsync -a --exclude='.git' "$TMPDIR/legion-toolkit/" "$SCRIPT_DIR/" \
        || cp -r "$TMPDIR/legion-toolkit/." "$SCRIPT_DIR/"
    ok "Files updated from GitHub"
fi

# ── 2. Stop running instances ─────────────────────────────────────────────────
echo -e "${BOLD}[2/4] Stopping running instances…${NC}"
pkill -f "legion-tray.py"    2>/dev/null && info "Stopped legion-tray"    || true
pkill -f "legion-gui.py"     2>/dev/null && info "Stopped legion-gui"     || true
pkill -f "legion-daemon.py"  2>/dev/null && info "Stopped legion-daemon"  || true
sleep 0.4

# ── 3. Install updated files ──────────────────────────────────────────────────
echo -e "${BOLD}[3/4] Installing updated files…${NC}"

install_file() {
    local src="$1" dst="$2" mode="${3:-644}"
    [[ -f "$src" ]] || { warn "Not found, skipping: $src"; return; }
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst" && chmod "$mode" "$dst"
    ok "$(basename "$src")  →  $dst"
}

mkdir -p /usr/lib/legion-toolkit

install_file "$SCRIPT_DIR/daemon/legion-daemon.py"           /usr/lib/legion-toolkit/legion-daemon.py       755
install_file "$SCRIPT_DIR/udev/udev-trigger.sh"              /usr/lib/legion-toolkit/udev-trigger.sh        755
install_file "$SCRIPT_DIR/tray/legion-gui.py"                /usr/lib/legion-toolkit/legion-gui.py          755
install_file "$SCRIPT_DIR/tray/legion-tray.py"               /usr/lib/legion-toolkit/legion-tray.py         755
install_file "$SCRIPT_DIR/tray/org.legion-toolkit.policy"    /usr/share/polkit-1/actions/org.legion-toolkit.policy  644
install_file "$SCRIPT_DIR/tray/legion-toolkit.desktop"       /etc/xdg/autostart/legion-toolkit.desktop      644
install_file "$SCRIPT_DIR/systemd/legion-toolkit.service"    /etc/systemd/system/legion-toolkit.service     644

[[ -f "$SCRIPT_DIR/scripts/legion-ctl" ]] && \
    install_file "$SCRIPT_DIR/scripts/legion-ctl" /usr/local/bin/legion-ctl 755

if [[ -f "$SCRIPT_DIR/udev/99-legion-toolkit.rules" ]]; then
    install_file "$SCRIPT_DIR/udev/99-legion-toolkit.rules" \
        /etc/udev/rules.d/99-legion-toolkit.rules 644
    udevadm control --reload-rules && udevadm trigger
    ok "udev rules reloaded"
fi

# ── 4. Restart daemon + tray ──────────────────────────────────────────────────
echo -e "${BOLD}[4/4] Restarting services…${NC}"

systemctl daemon-reload
systemctl is-enabled --quiet legion-toolkit.service 2>/dev/null && \
    systemctl restart legion-toolkit.service \
        && ok "legion-toolkit.service restarted" \
        || warn "Service restart failed — journalctl -u legion-toolkit.service"

if [[ -n "$REAL_USER" ]]; then
    REAL_UID=$(id -u "$REAL_USER")
    XDGRT="/run/user/${REAL_UID}"
    WAYLAND_DISP=$(ls "${XDGRT}/wayland-"* 2>/dev/null \
        | head -1 | xargs basename 2>/dev/null || echo "wayland-0")
    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$XDGRT" \
        WAYLAND_DISPLAY="$WAYLAND_DISP" \
        QT_QPA_PLATFORM="wayland" \
        nohup /usr/lib/legion-toolkit/legion-tray.py \
        > /tmp/legion-tray.log 2>&1 &
    sleep 0.8
    pgrep -f legion-tray.py > /dev/null \
        && ok "Tray started (user: $REAL_USER)" \
        || warn "Tray may not have started — check /tmp/legion-tray.log"
else
    warn "Could not detect desktop user — start tray manually:"
    echo -e "     ${CYAN}/usr/lib/legion-toolkit/legion-tray.py &${NC}"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ Update complete!${NC}"
VER=$(cd "$SCRIPT_DIR" 2>/dev/null && git describe --tags --always 2>/dev/null \
    || git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo -e "  Version : ${CYAN}${VER}${NC}"
echo    "  Tray log: /tmp/legion-tray.log"
echo -e "  Daemon  : journalctl -fu legion-toolkit.service\n"
