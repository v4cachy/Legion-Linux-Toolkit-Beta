#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Legion Linux Toolkit — Update Script
# Run from your project root:  sudo bash update.sh
# Or without sudo (will prompt via pkexec where needed):  bash update.sh
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET}  $*"; }
info() { echo -e "  ${CYAN}→${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
fail() { echo -e "  ${RED}✗${RESET}  $*"; exit 1; }

# ── Must run as root ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${BOLD}Legion Toolkit Updater${RESET}"
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# ── Project root = directory containing this script ──────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "\n${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Legion Linux Toolkit — Updater         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo -e "  Project: ${CYAN}${SCRIPT_DIR}${RESET}\n"

# ── Destination paths ─────────────────────────────────────────────────────────
LIB_DIR="/usr/lib/legion-toolkit"
BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
UDEV_DIR="/etc/udev/rules.d"
POLKIT_DIR="/usr/share/polkit-1/actions"
AUTOSTART_DIR="/etc/xdg/autostart"

# ── Helper: install file with permission ─────────────────────────────────────
install_file() {
    local src="$1" dst="$2" mode="${3:-644}"
    if [[ ! -f "$src" ]]; then
        warn "Source not found, skipping: $src"
        return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chmod "$mode" "$dst"
    ok "$(basename "$src")  →  $dst"
}

# ── 1. Stop running instances ─────────────────────────────────────────────────
echo -e "${BOLD}[1/5] Stopping running instances…${RESET}"
pkill -f "legion-tray.py"  2>/dev/null && info "Stopped legion-tray"   || true
pkill -f "legion-gui.py"   2>/dev/null && info "Stopped legion-gui"    || true
pkill -f "legion-daemon.py" 2>/dev/null && info "Stopped legion-daemon" || true
sleep 0.5

# ── 2. Copy core files ────────────────────────────────────────────────────────
echo -e "\n${BOLD}[2/5] Installing files…${RESET}"

mkdir -p "$LIB_DIR"

# Daemon
install_file "$SCRIPT_DIR/daemon/legion-daemon.py" \
             "$LIB_DIR/legion-daemon.py" 755

# GUI + Tray
install_file "$SCRIPT_DIR/tray/legion-gui.py"  "$LIB_DIR/legion-gui.py"  755
install_file "$SCRIPT_DIR/tray/legion-tray.py" "$LIB_DIR/legion-tray.py" 755

# CLI
if [[ -f "$SCRIPT_DIR/scripts/legion-ctl" ]]; then
    install_file "$SCRIPT_DIR/scripts/legion-ctl" "$BIN_DIR/legion-ctl" 755
fi

# Polkit policy
if [[ -f "$SCRIPT_DIR/tray/org.legion-toolkit.policy" ]]; then
    install_file "$SCRIPT_DIR/tray/org.legion-toolkit.policy" \
                 "$POLKIT_DIR/org.legion-toolkit.policy" 644
fi

# Desktop autostart
if [[ -f "$SCRIPT_DIR/tray/legion-toolkit.desktop" ]]; then
    install_file "$SCRIPT_DIR/tray/legion-toolkit.desktop" \
                 "$AUTOSTART_DIR/legion-toolkit.desktop" 644
fi

# Udev rules
if [[ -f "$SCRIPT_DIR/udev/99-legion-toolkit.rules" ]]; then
    install_file "$SCRIPT_DIR/udev/99-legion-toolkit.rules" \
                 "$UDEV_DIR/99-legion-toolkit.rules" 644
fi
if [[ -f "$SCRIPT_DIR/udev/udev-trigger.sh" ]]; then
    install_file "$SCRIPT_DIR/udev/udev-trigger.sh" \
                 "$LIB_DIR/udev-trigger.sh" 755
fi

# ── 3. Reload udev + systemd ──────────────────────────────────────────────────
echo -e "\n${BOLD}[3/5] Reloading udev rules…${RESET}"
udevadm control --reload-rules && udevadm trigger
ok "udev rules reloaded"

echo -e "\n${BOLD}[4/5] Reloading systemd service…${RESET}"
if [[ -f "$SCRIPT_DIR/systemd/legion-toolkit.service" ]]; then
    install_file "$SCRIPT_DIR/systemd/legion-toolkit.service" \
                 "$SYSTEMD_DIR/legion-toolkit.service" 644
    systemctl daemon-reload
    systemctl restart legion-toolkit.service && \
        ok "legion-toolkit.service restarted" || \
        warn "Service restart failed — check: journalctl -u legion-toolkit.service"
else
    # Service file not in project — just restart if it exists
    if systemctl is-active --quiet legion-toolkit.service; then
        systemctl restart legion-toolkit.service
        ok "legion-toolkit.service restarted"
    fi
fi

# ── 5. Restart tray (as the current real user, not root) ─────────────────────
echo -e "\n${BOLD}[5/5] Restarting tray…${RESET}"

# Find the logged-in desktop user
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"

if [[ -z "$REAL_USER" ]]; then
    warn "Could not determine desktop user — start tray manually:"
    echo "    /usr/lib/legion-toolkit/legion-tray.py &"
else
    # Run tray as the real user with their environment
    REAL_UID=$(id -u "$REAL_USER")
    XDGRT="/run/user/${REAL_UID}"
    WAYLAND_DISP=$(ls "${XDGRT}/wayland-"* 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "wayland-0")

    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$XDGRT" \
        WAYLAND_DISPLAY="$WAYLAND_DISP" \
        QT_QPA_PLATFORM="wayland" \
        nohup /usr/lib/legion-toolkit/legion-tray.py \
        >/tmp/legion-tray.log 2>&1 &

    sleep 0.8
    if pgrep -f legion-tray.py > /dev/null; then
        ok "Tray started (user: $REAL_USER)"
    else
        warn "Tray may not have started — check /tmp/legion-tray.log"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}✓ Update complete!${RESET}"
echo -e "  Log: ${CYAN}/tmp/legion-tray.log${RESET}"
echo -e "  Daemon: ${CYAN}journalctl -fu legion-toolkit.service${RESET}\n"
