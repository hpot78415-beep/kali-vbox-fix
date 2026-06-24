#!/usr/bin/env bash
# ============================================================
# EWB Kali VirtualBox Copy-Paste Auto Fix
# File: fix-vbox-clipboard.sh
# Run : bash fix-vbox-clipboard.sh
#
# Supports:
# - Kali / Debian / Ubuntu based guests
# - VirtualBox Guest Additions package check
# - Missing /dev/vboxguest and /dev/vboxuser fix
# - VBoxClient clipboard restart
# - Permanent reboot fix
# - Autostart fix after login
# - Clear PASS / FAIL report
#
# Important:
# This script fixes Kali/Linux guest-side issues.
# VirtualBox host-side menu must still be manually set:
# Devices -> Shared Clipboard -> Bidirectional
# Devices -> Drag and Drop    -> Bidirectional
# ============================================================

set +e

VERSION="2.0"
MODE="safe"
LOG="$HOME/ewb_vbox_clipboard_fix_$(date +%Y%m%d_%H%M%S).log"

for arg in "$@"; do
  case "$arg" in
    --aggressive) MODE="aggressive" ;;
    --diagnose-only) MODE="diagnose" ;;
    --help|-h)
      echo "Usage: bash fix-vbox-clipboard.sh [--aggressive] [--diagnose-only]"
      echo
      echo "Default safe mode fixes common clipboard issues."
      echo "--aggressive removes conflicting ISO Guest Additions and reinstalls distro packages."
      echo "--diagnose-only checks and prints report without changing system."
      exit 0
      ;;
  esac
done

exec > >(tee -a "$LOG") 2>&1

if [ -t 1 ]; then
  GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; BLUE="\033[34m"; RESET="\033[0m"; BOLD="\033[1m"
else
  GREEN=""; RED=""; YELLOW=""; BLUE=""; RESET=""; BOLD=""
fi

pass(){ echo -e "${GREEN}[PASS]${RESET} $1"; }
fail(){ echo -e "${RED}[FAIL]${RESET} $1"; FAILED=1; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $1"; }
info(){ echo -e "${BLUE}[INFO]${RESET} $1"; }
section(){ echo; echo "---------- $1 ----------"; }

FAILED=0
NEED_REBOOT=0
APT_UPDATED=0

run_cmd() {
  if [ "$MODE" = "diagnose" ]; then
    info "DIAGNOSE ONLY: skipped command: $*"
    return 0
  fi
  "$@"
}

require_not_root() {
  if [ "$EUID" -eq 0 ]; then
    fail "Do not run this script using sudo."
    echo
    echo "Correct:"
    echo "bash fix-vbox-clipboard.sh"
    echo
    echo "Wrong:"
    echo "sudo bash fix-vbox-clipboard.sh"
    exit 1
  fi
}

wait_for_apt() {
  if command -v fuser >/dev/null 2>&1; then
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
      warn "APT/dpkg is busy. Waiting 10 seconds..."
      sleep 10
    done
  fi
}

apt_update_once() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    wait_for_apt
    info "Running apt update..."
    run_cmd sudo apt update
    APT_UPDATED=1
  fi
}

install_pkg_if_missing() {
  local pkg="$1"
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    local ver
    ver=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
    pass "$pkg installed - $ver"
    return 0
  fi

  if [ "$MODE" = "diagnose" ]; then
    warn "$pkg missing"
    return 1
  fi

  apt_update_once
  info "Installing missing package: $pkg"
  wait_for_apt
  sudo apt install -y "$pkg"
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    pass "$pkg installed successfully"
    return 0
  else
    fail "$pkg installation failed"
    return 1
  fi
}

install_pkg_if_available() {
  local pkg="$1"
  apt-cache show "$pkg" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    warn "$pkg not available in current repositories. Skipping."
    return 0
  fi
  install_pkg_if_missing "$pkg"
}

create_vbox_device() {
  local dev="$1"
  local minor
  minor=$(awk -v d="$dev" '$2==d {print $1}' /proc/misc)

  if [ -z "$minor" ]; then
    fail "/proc/misc does not contain $dev. vboxguest module may not be registered."
    return 1
  fi

  if [ -e "/dev/$dev" ]; then
    pass "/dev/$dev already exists"
  else
    warn "/dev/$dev missing. Creating device node..."
    run_cmd sudo rm -f "/dev/$dev"
    run_cmd sudo mknod -m 666 "/dev/$dev" c 10 "$minor"
  fi

  run_cmd sudo chmod 666 "/dev/$dev" 2>/dev/null || true

  if [ -e "/dev/$dev" ]; then
    pass "/dev/$dev ready"
    ls -l "/dev/$dev"
  else
    fail "/dev/$dev still missing"
  fi
}

start_vbox_clients() {
  if [ -z "${DISPLAY:-}" ]; then
    fail "DISPLAY is not set. Start Kali desktop GUI and run script again."
    return 1
  fi

  run_cmd killall VBoxClient 2>/dev/null || true
  sleep 1

  if command -v VBoxClient >/dev/null 2>&1; then
    run_cmd VBoxClient --clipboard &
    run_cmd VBoxClient --draganddrop &
    run_cmd VBoxClient --display &
    run_cmd VBoxClient --seamless &
    sleep 3
  else
    fail "VBoxClient command not found"
    return 1
  fi

  echo "Running VBoxClient processes:"
  pgrep -a VBoxClient || true

  if pgrep -a VBoxClient | grep -q "clipboard"; then
    pass "VBoxClient clipboard service running"
  else
    fail "VBoxClient clipboard service not running"
  fi

  if pgrep -a VBoxClient | grep -q "draganddrop"; then
    pass "VBoxClient drag-and-drop service running"
  else
    warn "VBoxClient drag-and-drop service not running"
  fi
}

create_permanent_fix() {
  section "PERMANENT REBOOT FIX"

  info "Creating udev rule for VirtualBox guest device permissions..."
  echo 'KERNEL=="vboxguest", MODE="0666"
KERNEL=="vboxuser", MODE="0666"' | run_cmd sudo tee /etc/udev/rules.d/60-ewb-vboxguest.rules >/dev/null

  run_cmd sudo udevadm control --reload-rules 2>/dev/null || true
  run_cmd sudo udevadm trigger 2>/dev/null || true

  info "Creating system device fix script..."
  run_cmd sudo tee /usr/local/bin/ewb-fix-vbox-devices.sh >/dev/null <<'EOF'
#!/bin/bash
modprobe vboxguest 2>/dev/null || true
for d in vboxguest vboxuser; do
  m=$(awk -v d="$d" '$2==d {print $1}' /proc/misc)
  if [ -n "$m" ]; then
    rm -f /dev/$d
    mknod -m 666 /dev/$d c 10 $m
    chmod 666 /dev/$d
  fi
done
EOF

  run_cmd sudo chmod +x /usr/local/bin/ewb-fix-vbox-devices.sh

  info "Creating systemd service for boot..."
  run_cmd sudo tee /etc/systemd/system/ewb-fix-vbox-devices.service >/dev/null <<'EOF'
[Unit]
Description=EWB Fix VirtualBox guest device nodes
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ewb-fix-vbox-devices.sh

[Install]
WantedBy=multi-user.target
EOF

  run_cmd sudo systemctl daemon-reload
  run_cmd sudo systemctl enable ewb-fix-vbox-devices.service >/dev/null
  run_cmd sudo systemctl start ewb-fix-vbox-devices.service

  if systemctl is-enabled ewb-fix-vbox-devices.service >/dev/null 2>&1; then
    pass "Boot device auto-fix service enabled"
  else
    warn "Boot device auto-fix service not enabled"
  fi
}

create_user_autostart() {
  section "USER LOGIN AUTOSTART FIX"

  info "Creating VBoxClient autostart script..."
  run_cmd sudo tee /usr/local/bin/ewb-start-vboxclient.sh >/dev/null <<'EOF'
#!/bin/bash
/usr/local/bin/ewb-fix-vbox-devices.sh 2>/dev/null || true

if [ -n "$DISPLAY" ]; then
  pgrep -u "$USER" -f "VBoxClient --clipboard" >/dev/null || VBoxClient --clipboard >/dev/null 2>&1 &
  pgrep -u "$USER" -f "VBoxClient --draganddrop" >/dev/null || VBoxClient --draganddrop >/dev/null 2>&1 &
  pgrep -u "$USER" -f "VBoxClient --display" >/dev/null || VBoxClient --display >/dev/null 2>&1 &
  pgrep -u "$USER" -f "VBoxClient --seamless" >/dev/null || VBoxClient --seamless >/dev/null 2>&1 &
fi
EOF

  run_cmd sudo chmod +x /usr/local/bin/ewb-start-vboxclient.sh

  mkdir -p "$HOME/.config/autostart"

  cat > "$HOME/.config/autostart/ewb-vboxclient.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=EWB VirtualBox Clipboard Service
Comment=Start VirtualBox clipboard and drag-drop service
Exec=/usr/local/bin/ewb-start-vboxclient.sh
OnlyShowIn=XFCE;GNOME;KDE;LXDE;MATE;
X-GNOME-Autostart-enabled=true
EOF

  if [ -f "$HOME/.config/autostart/ewb-vboxclient.desktop" ]; then
    pass "User autostart created"
  else
    warn "User autostart not created"
  fi
}

aggressive_reinstall() {
  section "AGGRESSIVE REPAIR MODE"

  warn "Aggressive mode will remove conflicting Guest Additions and reinstall distro packages."
  warn "This is useful when normal mode fails."

  if ls /opt/VBoxGuestAdditions-* >/dev/null 2>&1; then
    warn "ISO Guest Additions found under /opt. Removing..."
    run_cmd sudo /opt/VBoxGuestAdditions-*/uninstall.sh 2>/dev/null || true
  else
    pass "No ISO Guest Additions found under /opt"
  fi

  apt_update_once

  warn "Purging VirtualBox guest packages..."
  run_cmd sudo apt purge -y virtualbox-guest-x11 virtualbox-guest-utils virtualbox-guest-dkms
  run_cmd sudo apt autoremove -y

  info "Reinstalling VirtualBox guest packages..."
  run_cmd sudo apt install -y linux-headers-amd64 virtualbox-guest-x11 virtualbox-guest-utils xclip

  if apt-cache show virtualbox-guest-dkms >/dev/null 2>&1; then
    run_cmd sudo apt install -y virtualbox-guest-dkms
  fi

  NEED_REBOOT=1
}

clear
echo "===================================================="
echo " EWB Kali VirtualBox Copy-Paste Auto Fix v$VERSION"
echo " Mode: $MODE"
echo "===================================================="
echo
info "Log file: $LOG"
echo
echo "Before testing, VirtualBox top menu should be:"
echo "  Devices -> Shared Clipboard -> Bidirectional"
echo "  Devices -> Drag and Drop    -> Bidirectional"
echo

require_not_root

section "BASIC CHECKS"
echo "User          : $(whoami)"
echo "Hostname      : $(hostname)"
echo "Kernel        : $(uname -r)"
echo "Session type  : ${XDG_SESSION_TYPE:-unknown}"
echo "Display       : ${DISPLAY:-not-set}"
echo "Shell         : ${SHELL:-unknown}"
echo

if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo "OS            : ${PRETTY_NAME:-unknown}"
fi

if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
  pass "Desktop session is X11"
else
  warn "Session is not X11. If clipboard fails, logout and choose X11/Xorg/XFCE."
fi

if command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT=$(systemd-detect-virt 2>/dev/null)
  echo "Virtualization: ${VIRT:-none}"
  if echo "$VIRT" | grep -qi "oracle\|virtualbox"; then
    pass "VirtualBox VM detected"
  else
    warn "This does not look like VirtualBox. Script may not help on VMware/Hyper-V."
  fi
fi

if ! command -v apt >/dev/null 2>&1; then
  fail "APT not found. This script supports Kali/Debian/Ubuntu based systems."
  exit 1
fi

if [ "$MODE" = "aggressive" ]; then
  aggressive_reinstall
fi

section "PACKAGE CHECKS"
install_pkg_if_missing linux-headers-amd64
install_pkg_if_missing virtualbox-guest-utils
install_pkg_if_missing virtualbox-guest-x11
install_pkg_if_missing xclip
install_pkg_if_available virtualbox-guest-dkms

section "VIRTUALBOX MODULE CHECK"

if lsmod | grep -q "^vboxguest"; then
  pass "vboxguest module already loaded"
else
  warn "vboxguest module not loaded. Trying modprobe..."
  run_cmd sudo modprobe vboxguest 2>/dev/null || true
fi

if lsmod | grep -q "^vboxguest"; then
  pass "vboxguest module active"
else
  fail "vboxguest module is not active"
  NEED_REBOOT=1
fi

echo
echo "Current VirtualBox related modules:"
lsmod | grep -E "vbox|vmwgfx" || true

section "SERVICE CHECK"

if systemctl list-unit-files | grep -q "virtualbox-guest-utils.service"; then
  info "Restarting virtualbox-guest-utils.service..."
  run_cmd sudo systemctl restart virtualbox-guest-utils.service 2>/dev/null || true
  systemctl status virtualbox-guest-utils.service --no-pager -l 2>/dev/null | sed -n '1,12p'
else
  warn "virtualbox-guest-utils.service not found"
fi

section "DEVICE NODE FIX"
create_vbox_device vboxguest
create_vbox_device vboxuser

create_permanent_fix
create_user_autostart

section "START CLIPBOARD SERVICES"
start_vbox_clients

section "INTERNAL CLIPBOARD TEST"
TEST_TEXT="EWB_KALI_TO_WINDOWS_TEST_$(date +%H%M%S)"

if command -v xclip >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  echo "$TEST_TEXT" | xclip -selection clipboard
  sleep 1
  CLIP_OUT=$(xclip -selection clipboard -o 2>/dev/null || true)

  if [ "$CLIP_OUT" = "$TEST_TEXT" ]; then
    pass "Kali internal X11 clipboard is working"
    echo
    echo "===================================================="
    echo " STUDENT TEST:"
    echo " 1. Open Windows Notepad"
    echo " 2. Press Ctrl + V"
    echo
    echo " Expected paste text:"
    echo " $TEST_TEXT"
    echo "===================================================="
  else
    fail "Kali internal clipboard is not holding test text"
  fi
else
  fail "Cannot test clipboard. xclip or DISPLAY missing."
fi

section "FINAL REPORT"

if [ -e /dev/vboxguest ]; then pass "/dev/vboxguest exists"; else fail "/dev/vboxguest missing"; fi
if [ -e /dev/vboxuser ]; then pass "/dev/vboxuser exists"; else fail "/dev/vboxuser missing"; fi
if pgrep -a VBoxClient | grep -q "clipboard"; then pass "VBoxClient clipboard running"; else fail "VBoxClient clipboard not running"; fi

echo
if [ "$NEED_REBOOT" -eq 1 ]; then
  warn "Reboot is recommended because packages/modules changed."
  echo "Run:"
  echo "  sudo reboot"
  echo "After reboot, run again if needed:"
  echo "  bash fix-vbox-clipboard.sh"
fi

echo
echo "If Windows -> Kali works but Kali -> Windows does not:"
echo "  VirtualBox VM top menu:"
echo "  Devices -> Shared Clipboard -> Guest to Host"
echo "  Test Windows Notepad Ctrl + V"
echo "  Then change back:"
echo "  Devices -> Shared Clipboard -> Bidirectional"
echo
echo "Terminal shortcuts:"
echo "  Kali Terminal Copy  : Ctrl + Shift + C"
echo "  Kali Terminal Paste : Ctrl + Shift + V"
echo "  Normal Kali apps    : Ctrl + C / Ctrl + V"
echo
echo "Troubleshooting modes:"
echo "  Normal fix      : bash fix-vbox-clipboard.sh"
echo "  Aggressive fix  : bash fix-vbox-clipboard.sh --aggressive"
echo "  Diagnose only   : bash fix-vbox-clipboard.sh --diagnose-only"
echo
info "Full log saved at: $LOG"

if [ "$FAILED" -eq 0 ]; then
  echo
  pass "Guest-side setup looks correct."
  exit 0
else
  echo
  warn "Some checks failed. Read the log above."
  warn "If normal mode failed, run:"
  echo "  bash fix-vbox-clipboard.sh --aggressive"
  exit 2
fi
