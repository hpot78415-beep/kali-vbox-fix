#!/usr/bin/env bash
# ============================================================
# EWB Parrot Security OS VirtualBox Copy-Paste FULL Auto Fix
# Version: 4.0
# File   : fix-parrot-vbox-clipboard.sh
# Run    : bash fix-parrot-vbox-clipboard.sh
#
# Goal:
# Student only does ONE manual thing:
#   VirtualBox menu -> Devices -> Shared Clipboard -> Bidirectional
#   VirtualBox menu -> Devices -> Drag and Drop    -> Bidirectional
#
# Then run this script.
#
# This script will:
# - repair apt/dpkg
# - run apt update
# - run apt upgrade
# - install required tools
# - install VirtualBox Guest Additions packages from apt
# - if needed, use mounted VBox_GAs CD installer automatically
# - load vbox modules
# - fix /dev/vboxguest and /dev/vboxuser
# - restart VBoxClient clipboard/display/drag-drop services
# - create permanent reboot/login fixes
# - show simple student-friendly next steps
# ============================================================

set +e

VERSION="4.0"
FAILED=0
NEED_REBOOT=0
APT_UPDATED=0
INTERNET_OK=0
ISO_RUN=""
LOG="$HOME/ewb_parrot_vbox_clipboard_fix_$(date +%Y%m%d_%H%M%S).log"
MODE="full"

for arg in "$@"; do
  case "$arg" in
    --diagnose-only) MODE="diagnose" ;;
    --no-upgrade) MODE="no-upgrade" ;;
    --iso-only) MODE="iso-only" ;;
    --aggressive) MODE="aggressive" ;;
    --help|-h)
      echo "Usage:"
      echo "  bash fix-parrot-vbox-clipboard.sh"
      echo "  bash fix-parrot-vbox-clipboard.sh --no-upgrade"
      echo "  bash fix-parrot-vbox-clipboard.sh --iso-only"
      echo "  bash fix-parrot-vbox-clipboard.sh --aggressive"
      echo "  bash fix-parrot-vbox-clipboard.sh --diagnose-only"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use --help"
      exit 1
      ;;
  esac
done

exec > >(tee -a "$LOG") 2>&1

if [ -t 1 ]; then
  GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; BLUE="\033[34m"; CYAN="\033[36m"; RESET="\033[0m"
else
  GREEN=""; RED=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

pass(){ echo -e "${GREEN}[PASS]${RESET} $1"; }
fail(){ echo -e "${RED}[FAIL]${RESET} $1"; FAILED=1; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $1"; }
info(){ echo -e "${BLUE}[INFO]${RESET} $1"; }
step(){ echo -e "${CYAN}[STEP]${RESET} $1"; }
meaning(){ echo -e "${BLUE}Meaning:${RESET} $1"; }
action(){ echo -e "${YELLOW}Action:${RESET} $1"; }
section(){ echo; echo "===================================================="; echo "$1"; echo "===================================================="; }

can_change(){ [ "$MODE" != "diagnose" ]; }

run_cmd() {
  if ! can_change; then
    info "DIAGNOSE ONLY: skipped command: $*"
    return 0
  fi
  "$@"
}

intro() {
  clear
  echo "===================================================="
  echo " EWB Parrot VirtualBox Copy-Paste FULL Auto Fix v$VERSION"
  echo " Mode: $MODE"
  echo "===================================================="
  echo
  echo "Before this script can fully work, please manually set:"
  echo
  echo "  VirtualBox menu:"
  echo "  Devices -> Shared Clipboard -> Bidirectional"
  echo "  Devices -> Drag and Drop    -> Bidirectional"
  echo
  warn "This manual menu setting cannot be changed from inside Parrot."
  echo
  echo "This script will now check and fix Parrot-side problems automatically."
  echo
  info "Log file: $LOG"
  echo
}

require_normal_user() {
  if [ "$EUID" -eq 0 ]; then
    fail "Do not run this script using sudo."
    meaning "Some clipboard startup files must be created for the normal student user."
    action "Run exactly like this:"
    echo "  bash fix-parrot-vbox-clipboard.sh"
    exit 1
  fi
}

sudo_check() {
  section "1. SUDO CHECK"
  if ! command -v sudo >/dev/null 2>&1; then
    fail "sudo is missing"
    action "Use a Parrot user with sudo access."
    exit 1
  fi

  step "Checking sudo access. Password may be asked."
  sudo -v
  if [ $? -eq 0 ]; then
    pass "sudo access OK"
  else
    fail "sudo access failed"
    action "Enter correct password or use a sudo user."
    exit 1
  fi
}

system_checks() {
  section "2. SYSTEM CHECKS"
  echo "User          : $(whoami)"
  echo "Kernel        : $(uname -r)"
  echo "Session       : ${XDG_SESSION_TYPE:-unknown}"
  echo "Display       : ${DISPLAY:-not-set}"

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "OS            : ${PRETTY_NAME:-unknown}"
    if echo "${PRETTY_NAME:-} ${ID:-} ${NAME:-}" | grep -qi "parrot"; then
      pass "Parrot OS detected"
    else
      warn "Parrot OS not clearly detected"
      meaning "Script is built for Parrot, but may still work on Debian-based Linux."
    fi
  fi

  if [ -n "${DISPLAY:-}" ]; then
    pass "Graphical desktop DISPLAY found"
  else
    fail "DISPLAY missing"
    meaning "You are not running from the Parrot graphical desktop."
    action "Open Konsole/Terminal from Parrot desktop and run again."
  fi

  if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
    pass "X11 session detected"
  else
    warn "X11 not detected"
    meaning "VirtualBox clipboard works best with X11. Wayland may block clipboard."
    action "If clipboard fails, logout and choose X11/Xorg session."
  fi

  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt 2>/dev/null)
    echo "Virtualization: ${VIRT:-none}"
    if echo "$VIRT" | grep -qi "oracle\|virtualbox"; then
      pass "VirtualBox VM detected"
    else
      warn "VirtualBox not clearly detected"
      meaning "If this is VMware/Hyper-V, this script is not the correct fix."
    fi
  fi

  SPACE=$(df -Pm / | awk 'NR==2 {print $4}')
  echo "Free disk space: ${SPACE:-unknown} MB"
  if [ -n "$SPACE" ] && [ "$SPACE" -lt 1500 ]; then
    fail "Low disk space"
    action "Free disk space before running update/install."
  elif [ -n "$SPACE" ] && [ "$SPACE" -lt 3000 ]; then
    warn "Disk space is low. Update may take space."
  else
    pass "Disk space looks okay"
  fi
}

internet_check() {
  section "3. INTERNET AND DNS CHECK"
  if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    pass "Internet IP connectivity OK"
    INTERNET_OK=1
  else
    warn "Direct internet ping failed"
  fi

  if getent hosts deb.parrot.sh >/dev/null 2>&1 || getent hosts google.com >/dev/null 2>&1; then
    pass "DNS resolution OK"
    INTERNET_OK=1
  else
    warn "DNS resolution failed"
    meaning "Web names are not resolving. apt may fail."
  fi

  if [ "$INTERNET_OK" -eq 0 ]; then
    warn "Internet may not be working."
    action "Connect internet. If VBox_GAs CD is mounted, script will still try ISO method."
  fi
}

wait_for_apt() {
  if ! command -v fuser >/dev/null 2>&1; then
    return 0
  fi

  local waited=0
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    warn "APT/dpkg is busy. Waiting 10 seconds..."
    sleep 10
    waited=$((waited+10))
    if [ "$waited" -ge 180 ]; then
      warn "APT is busy for more than 3 minutes."
      action "Close Software Center/Updater or reboot, then run script again."
      break
    fi
  done
}

apt_repair_update_upgrade() {
  section "4. PACKAGE MANAGER REPAIR + UPDATE"

  wait_for_apt
  step "Repairing unfinished dpkg work..."
  run_cmd sudo dpkg --configure -a

  wait_for_apt
  step "Fixing broken packages..."
  run_cmd sudo apt --fix-broken install -y

  wait_for_apt
  step "Running apt update..."
  run_cmd sudo apt update
  if [ $? -eq 0 ]; then
    pass "apt update completed"
    APT_UPDATED=1
  else
    warn "apt update failed"
    meaning "Internet/repository issue may exist. Script will continue."
  fi

  if [ "$MODE" = "full" ] || [ "$MODE" = "aggressive" ]; then
    wait_for_apt
    step "Running apt upgrade. This can take time..."
    warn "Do not close terminal during upgrade."
    run_cmd sudo apt upgrade -y
    if [ $? -eq 0 ]; then
      pass "apt upgrade completed"
      NEED_REBOOT=1
    else
      warn "apt upgrade had errors. Script will continue."
    fi

    wait_for_apt
    step "Removing unused packages..."
    run_cmd sudo apt autoremove -y
  else
    warn "Skipping full upgrade because mode is $MODE"
  fi
}

apt_update_once() {
  if [ "$APT_UPDATED" -eq 1 ]; then
    return 0
  fi
  wait_for_apt
  run_cmd sudo apt update
  [ $? -eq 0 ] && APT_UPDATED=1
}

install_pkg() {
  local pkg="$1"
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    pass "$pkg installed"
    return 0
  fi

  if ! can_change; then
    warn "$pkg missing"
    return 1
  fi

  apt_update_once
  wait_for_apt
  step "Installing $pkg ..."
  sudo apt install -y "$pkg"
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    pass "$pkg installed"
  else
    warn "$pkg install failed or package unavailable"
    return 1
  fi
}

install_pkg_if_available() {
  local pkg="$1"
  apt-cache show "$pkg" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    install_pkg "$pkg"
  else
    warn "$pkg not found in repositories. Skipping."
  fi
}

install_headers() {
  section "5. KERNEL HEADERS CHECK"
  local exact="linux-headers-$(uname -r)"
  if dpkg-query -W -f='${Status}' "$exact" 2>/dev/null | grep -q "install ok installed"; then
    pass "$exact installed"
    return 0
  fi

  apt_update_once

  if apt-cache show "$exact" >/dev/null 2>&1; then
    install_pkg "$exact"
  else
    warn "$exact not available"
    meaning "Exact headers are missing from repo."
    action "Trying linux-headers-amd64 fallback."
    install_pkg_if_available linux-headers-amd64
  fi
}

install_required_tools() {
  section "6. INSTALL REQUIRED TOOLS"
  install_pkg build-essential
  install_pkg dkms
  install_pkg gcc
  install_pkg make
  install_pkg perl
  install_pkg xclip
  install_headers

  section "7. INSTALL VIRTUALBOX GUEST PACKAGES FROM APT"
  install_pkg_if_available virtualbox-guest-utils
  install_pkg_if_available virtualbox-guest-x11
  install_pkg_if_available virtualbox-guest-dkms
}

find_iso_installer() {
  ISO_RUN=""
  ISO_RUN=$(find /media "$HOME" /run/media /mnt -maxdepth 6 -type f -name "VBoxLinuxAdditions.run" 2>/dev/null | head -n 1)
  if [ -n "$ISO_RUN" ]; then
    pass "VBoxLinuxAdditions.run found: $ISO_RUN"
  else
    warn "VBoxLinuxAdditions.run not found"
    meaning "Guest Additions CD is not mounted."
    action "VirtualBox menu: Devices -> Insert Guest Additions CD image, then mount/open it."
  fi
}

run_iso_installer() {
  section "8. GUEST ADDITIONS ISO INSTALLER"
  find_iso_installer
  if [ -z "$ISO_RUN" ]; then
    warn "ISO installer not available. Skipping ISO install."
    return 1
  fi

  step "Running VBoxLinuxAdditions.run automatically..."
  warn "This may take a few minutes."
  chmod +x "$ISO_RUN" 2>/dev/null || true
  yes yes | run_cmd sudo sh "$ISO_RUN"

  if [ $? -eq 0 ]; then
    pass "ISO Guest Additions installer completed"
  else
    warn "ISO installer returned warnings/errors"
    meaning "Some warnings are normal. Reboot and run script again."
  fi
  NEED_REBOOT=1
}

remove_conflicts() {
  section "AGGRESSIVE CLEANUP"
  if ls /opt/VBoxGuestAdditions-* >/dev/null 2>&1; then
    warn "Old ISO Guest Additions found. Removing..."
    run_cmd sudo /opt/VBoxGuestAdditions-*/uninstall.sh 2>/dev/null || true
  fi

  wait_for_apt
  step "Purging guest packages for clean reinstall..."
  run_cmd sudo apt purge -y virtualbox-guest-utils virtualbox-guest-x11 virtualbox-guest-dkms
  run_cmd sudo apt autoremove -y
  NEED_REBOOT=1
}

guest_additions_strategy() {
  if [ "$MODE" = "aggressive" ]; then
    remove_conflicts
  fi

  if [ "$MODE" = "iso-only" ]; then
    install_required_tools
    run_iso_installer
    return
  fi

  install_required_tools

  if command -v VBoxClient >/dev/null 2>&1; then
    pass "VBoxClient command found"
  else
    warn "VBoxClient missing after apt install"
    action "Trying ISO Guest Additions installer if mounted."
    run_iso_installer
  fi
}

module_check() {
  section "9. VIRTUALBOX MODULE CHECK"
  if lsmod | grep -q "^vboxguest"; then
    pass "vboxguest module loaded"
  else
    warn "vboxguest module not loaded. Trying modprobe..."
    run_cmd sudo modprobe vboxguest 2>/dev/null || true
  fi

  if lsmod | grep -q "^vboxguest"; then
    pass "vboxguest active"
  else
    warn "vboxguest still not active"
    action "Trying ISO installer once, then reboot is required."
    run_iso_installer
    run_cmd sudo modprobe vboxguest 2>/dev/null || true
  fi

  if lsmod | grep -q "^vboxguest"; then
    pass "vboxguest active now"
  else
    fail "vboxguest module not active"
    meaning "Guest Additions driver is not active yet."
    action "Run sudo reboot, then run this script again."
    NEED_REBOOT=1
  fi

  echo
  echo "Loaded VirtualBox/display modules:"
  lsmod | grep -E "vbox|vmwgfx|drm" || true
}

restart_services() {
  section "10. RESTART VIRTUALBOX SERVICES"
  if systemctl list-unit-files | grep -q "virtualbox-guest-utils.service"; then
    step "Restarting virtualbox-guest-utils.service..."
    run_cmd sudo systemctl restart virtualbox-guest-utils.service 2>/dev/null || true
    systemctl status virtualbox-guest-utils.service --no-pager -l 2>/dev/null | sed -n '1,12p'
  else
    warn "virtualbox-guest-utils.service not found"
  fi
}

make_device() {
  local dev="$1"
  local minor
  minor=$(awk -v d="$dev" '$2==d {print $1}' /proc/misc)

  if [ -z "$minor" ]; then
    fail "/proc/misc missing $dev"
    meaning "VirtualBox module has not registered $dev."
    NEED_REBOOT=1
    return 1
  fi

  if [ ! -e "/dev/$dev" ]; then
    warn "/dev/$dev missing. Creating..."
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

fix_devices() {
  section "11. FIX VIRTUALBOX DEVICE FILES"
  make_device vboxguest
  make_device vboxuser
}

create_permanent_fixes() {
  section "12. CREATE PERMANENT FIXES"
  if can_change; then
    echo 'KERNEL=="vboxguest", MODE="0666"
KERNEL=="vboxuser", MODE="0666"' | sudo tee /etc/udev/rules.d/60-ewb-vboxguest.rules >/dev/null

    sudo tee /usr/local/bin/ewb-fix-vbox-devices.sh >/dev/null <<'BOOTFIX'
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
BOOTFIX
    sudo chmod +x /usr/local/bin/ewb-fix-vbox-devices.sh

    sudo tee /etc/systemd/system/ewb-fix-vbox-devices.service >/dev/null <<'SERVICEFIX'
[Unit]
Description=EWB Fix VirtualBox guest device nodes for Parrot
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ewb-fix-vbox-devices.sh

[Install]
WantedBy=multi-user.target
SERVICEFIX
    sudo systemctl daemon-reload
    sudo systemctl enable ewb-fix-vbox-devices.service >/dev/null
    sudo systemctl start ewb-fix-vbox-devices.service

    sudo tee /usr/local/bin/ewb-start-vboxclient.sh >/dev/null <<'STARTCLIENT'
#!/bin/bash
/usr/local/bin/ewb-fix-vbox-devices.sh 2>/dev/null || true
if [ -n "$DISPLAY" ]; then
  pgrep -u "$USER" -f "VBoxClient --clipboard" >/dev/null || VBoxClient --clipboard >/dev/null 2>&1 &
  pgrep -u "$USER" -f "VBoxClient --draganddrop" >/dev/null || VBoxClient --draganddrop >/dev/null 2>&1 &
  pgrep -u "$USER" -f "VBoxClient --display" >/dev/null || VBoxClient --display >/dev/null 2>&1 &
  pgrep -u "$USER" -f "VBoxClient --seamless" >/dev/null || VBoxClient --seamless >/dev/null 2>&1 &
fi
STARTCLIENT
    sudo chmod +x /usr/local/bin/ewb-start-vboxclient.sh

    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/ewb-vboxclient.desktop" <<'AUTOSTART'
[Desktop Entry]
Type=Application
Name=EWB VirtualBox Clipboard Service
Comment=Start VirtualBox clipboard and drag-drop service
Exec=/usr/local/bin/ewb-start-vboxclient.sh
OnlyShowIn=XFCE;GNOME;KDE;LXDE;MATE;
X-GNOME-Autostart-enabled=true
AUTOSTART
  fi

  systemctl is-enabled ewb-fix-vbox-devices.service >/dev/null 2>&1 && pass "Boot device fix enabled" || warn "Boot device fix not enabled"
  [ -f "$HOME/.config/autostart/ewb-vboxclient.desktop" ] && pass "Login VBoxClient autostart created" || warn "Login autostart not created"
}

start_vbox_clients() {
  section "13. START CLIPBOARD, DISPLAY, DRAG-DROP SERVICES"

  if ! command -v VBoxClient >/dev/null 2>&1; then
    fail "VBoxClient not found"
    action "Reboot and run script again. If still missing, mount Guest Additions CD and run --iso-only."
    return 1
  fi

  step "Stopping old VBoxClient processes..."
  run_cmd killall VBoxClient 2>/dev/null || true
  sleep 1

  if command -v VBoxClient-all >/dev/null 2>&1; then
    step "Starting VBoxClient-all..."
    run_cmd VBoxClient-all >/tmp/ewb-vboxclient-all.log 2>&1 &
    sleep 2
  fi

  step "Starting individual VBoxClient services..."
  run_cmd VBoxClient --clipboard >/tmp/ewb-vbox-clipboard.log 2>&1 &
  run_cmd VBoxClient --draganddrop >/tmp/ewb-vbox-dnd.log 2>&1 &
  run_cmd VBoxClient --display >/tmp/ewb-vbox-display.log 2>&1 &
  run_cmd VBoxClient --seamless >/tmp/ewb-vbox-seamless.log 2>&1 &
  sleep 3

  echo "Running VBoxClient processes:"
  pgrep -a VBoxClient || true

  pgrep -a VBoxClient | grep -q "clipboard" && pass "Clipboard service running" || fail "Clipboard service NOT running"
  pgrep -a VBoxClient | grep -q "display" && pass "Display resize service running" || warn "Display service not clearly running"
  pgrep -a VBoxClient | grep -q "draganddrop" && pass "Drag-and-drop service running" || warn "Drag-and-drop service not clearly running"
}

try_screen_resize() {
  section "14. SCREEN RESIZE HELPER"
  if command -v xrandr >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    CURRENT=$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')
    if [ -n "$CURRENT" ]; then
      step "Trying xrandr auto resize on $CURRENT ..."
      xrandr --output "$CURRENT" --auto 2>/dev/null || true
      pass "Screen resize helper executed"
    else
      warn "No connected display found via xrandr"
    fi
  else
    warn "xrandr/DISPLAY unavailable. Cannot test screen resize from script."
  fi

  action "Also enable manually: VirtualBox menu -> View -> Auto-resize Guest Display"
}

clipboard_test() {
  section "15. PARROT TO WINDOWS CLIPBOARD TEST"
  if ! command -v xclip >/dev/null 2>&1; then
    fail "xclip missing"
    return 1
  fi

  TEST_TEXT="EWB_PARROT_TO_WINDOWS_TEST_$(date +%H%M%S)"
  echo "$TEST_TEXT" | xclip -selection clipboard
  sleep 1
  OUT=$(xclip -selection clipboard -o 2>/dev/null || true)

  if [ "$OUT" = "$TEST_TEXT" ]; then
    pass "Parrot internal clipboard has the test text"
    echo
    echo "===================================================="
    echo " FINAL TEST"
    echo "===================================================="
    echo "Open Windows Notepad and press Ctrl + V"
    echo
    echo "Expected text:"
    echo "$TEST_TEXT"
    echo "===================================================="
    echo
    warn "If Windows Notepad does not paste it, problem is VirtualBox HOST menu direction."
    action "Try: Devices -> Shared Clipboard -> Guest to Host, test once, then set back to Bidirectional."
  else
    fail "Parrot internal clipboard test failed"
  fi
}

final_report() {
  section "FINAL STUDENT RESULT"
  [ -e /dev/vboxguest ] && pass "/dev/vboxguest exists" || fail "/dev/vboxguest missing"
  [ -e /dev/vboxuser ] && pass "/dev/vboxuser exists" || fail "/dev/vboxuser missing"
  pgrep -a VBoxClient | grep -q "clipboard" && pass "VBoxClient clipboard running" || fail "VBoxClient clipboard not running"

  echo
  warn "Manual settings to check:"
  echo "  Devices -> Shared Clipboard -> Bidirectional"
  echo "  Devices -> Drag and Drop    -> Bidirectional"
  echo "  View    -> Auto-resize Guest Display"
  echo

  if [ "$NEED_REBOOT" -eq 1 ]; then
    warn "Reboot is recommended because packages/modules changed."
    echo "Run:"
    echo "  sudo reboot"
    echo
    echo "After reboot, run:"
    echo "  cd ~/kali-vbox-fix"
    echo "  bash fix-parrot-vbox-clipboard.sh --no-upgrade"
  fi

  echo
  echo "If Parrot -> Windows copy still fails:"
  echo "  1. Devices -> Shared Clipboard -> Guest to Host"
  echo "  2. Open Windows Notepad"
  echo "  3. Press Ctrl + V"
  echo "  4. Then set back to Bidirectional"
  echo
  echo "Terminal shortcuts:"
  echo "  Parrot terminal copy  : Ctrl + Shift + C"
  echo "  Parrot terminal paste : Ctrl + Shift + V"
  echo "  Normal apps           : Ctrl + C / Ctrl + V"
  echo
  info "Full log saved here: $LOG"
  echo "Send this log to trainer if issue continues."
  echo

  if [ "$FAILED" -eq 0 ]; then
    pass "Parrot guest-side setup looks correct."
    exit 0
  else
    warn "Some guest-side checks failed."
    echo "Try:"
    echo "  bash fix-parrot-vbox-clipboard.sh --aggressive"
    echo "  sudo reboot"
    exit 2
  fi
}

main() {
  intro
  require_normal_user
  sudo_check
  system_checks
  internet_check
  apt_repair_update_upgrade
  guest_additions_strategy
  module_check
  restart_services
  fix_devices
  create_permanent_fixes
  start_vbox_clients
  try_screen_resize
  clipboard_test
  final_report
}

main
