#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Legion Linux Toolkit — Uninstaller
# Removes everything that install.sh placed on the system.
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
info() { echo -e "  ${CYAN}→${NC}  $*"; }

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

echo -e "\n${BOLD}╔══════════════════════════════════════════╗"
echo      "║   Legion Linux Toolkit — Uninstaller     ║"
echo -e   "╚══════════════════════════════════════════╝${NC}\n"

# Confirm
read -rp "  This will remove Legion Linux Toolkit completely. Continue? [y/N] " ans
[[ "${ans,,}" == "y" ]] || { echo "  Cancelled."; exit 0; }
echo ""

# ── 1. Kill running processes ─────────────────────────────────────────────────
info "Stopping running instances…"
pkill -f "legion-tray.py"   2>/dev/null && ok "legion-tray stopped"   || true
pkill -f "legion-gui.py"    2>/dev/null && ok "legion-gui stopped"    || true
pkill -f "legion-daemon.py" 2>/dev/null && ok "legion-daemon stopped" || true
sleep 0.3

# ── 2. Disable and remove systemd service ────────────────────────────────────
info "Removing systemd service…"
systemctl stop    legion-toolkit.service  2>/dev/null || true
systemctl disable legion-toolkit.service  2>/dev/null || true
rm -f /etc/systemd/system/legion-toolkit.service
systemctl daemon-reload
ok "Service removed"

# ── 3. Remove udev rules ──────────────────────────────────────────────────────
info "Removing udev rules…"
rm -f /etc/udev/rules.d/99-legion-toolkit.rules
rm -f /etc/udev/rules.d/99-legion-rgb.rules        # RGB udev rule (if added)
udevadm control --reload-rules && udevadm trigger
ok "udev rules removed and reloaded"

# ── 4. Remove installed files ─────────────────────────────────────────────────
info "Removing installed files…"

# Main library directory
rm -rf /usr/lib/legion-toolkit
ok "/usr/lib/legion-toolkit removed"

# CLI
rm -f /usr/local/bin/legion-ctl
ok "legion-ctl removed"

# Polkit policy
rm -f /usr/share/polkit-1/actions/org.legion-toolkit.policy
ok "Polkit policy removed"

# Autostart desktop entry
rm -f /etc/xdg/autostart/legion-toolkit.desktop
ok "Autostart entry removed"

# Log file
rm -f /var/log/legion-toolkit.log
ok "Log file removed"

# Runtime socket (if still present)
rm -f /run/legion-toolkit.sock
ok "Runtime socket removed"

# ── 5. Remove user config (optional) ─────────────────────────────────────────
echo ""
read -rp "  Remove per-user config (~/.config/legion-toolkit)? [y/N] " ans2
if [[ "${ans2,,}" == "y" ]]; then
    # Remove for all users that have it
    for homedir in /home/*/; do
        cfg="${homedir}.config/legion-toolkit"
        if [[ -d "$cfg" ]]; then
            rm -rf "$cfg"
            ok "Removed $cfg"
        fi
    done
    # Also root
    [[ -d /root/.config/legion-toolkit ]] && rm -rf /root/.config/legion-toolkit && ok "Removed /root/.config/legion-toolkit"
else
    warn "User config kept at ~/.config/legion-toolkit"
fi

echo -e "\n${GREEN}${BOLD}✓ Legion Linux Toolkit completely removed.${NC}\n"
