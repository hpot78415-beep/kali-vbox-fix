#!/usr/bin/env bash
# ============================================================
# EWB Parrot Security OS VirtualBox Copy-Paste COMPLETE Auto Fix
# File: fix-parrot-vbox-clipboard.sh
# Run : bash fix-parrot-vbox-clipboard.sh
#
# Goal:
# Student should only set VirtualBox menu to Bidirectional and run this script.
#
# Modes:
#   bash fix-parrot-vbox-clipboard.sh
#   bash fix-parrot-vbox-clipboard.sh --repair-all
#   bash fix-parrot-vbox-clipboard.sh --update-system
#   bash fix-parrot-vbox-clipboard.sh --iso-only
#   bash fix-parrot-vbox-clipboard.sh --aggressive
#   bash fix-parrot-vbox-clipboard.sh --diagnose-only
# ============================================================

set +e

VERSION="3.0"
MODE="safe"
FAILED=0
NEED_REBOOT=0
INTERNET_OK=0
APT_UPDATED=0
ISO_RUN=""
LOG="$HOME/ewb_parrot_vbox_clipboard_fix_$(date +%Y%m%d_%H%M%S).log"

for arg in "$@"; do
  case "$arg" in
    --repair-all) MODE="repair-all" ;;
    --update-system) MODE="update-system" ;;
    --iso-only) MODE="iso-only" ;;
    --aggressive) MODE="aggressive" ;;
    --diagnose-only) MODE="diagnose" ;;
    --help|-h)
      echo "Usage:"
      echo "  bash fix-parrot-vbox-clipboard.sh"
      echo "  bash fix-parrot-vbox-clipboard.sh --repair-all"
      echo "  bash fix-parrot-vbox-clipboard.sh --update-system"
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
meaning(){ echo -e "${BLUE}Simple meaning:${RESET} $1"; }
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

show_intro() {
  clear
  echo "===================================================="
  echo " EWB Parrot VirtualBox Copy-Paste COMPLETE Fix v$VERSION"
  echo " Mode: $MODE"
  echo "===================================================="
  echo
  echo "This script will try to fix everything from Parrot side:"
  echo "  1. Check internet and package manager"
  echo "  2. Repair broken apt/dpkg issues"
  echo "  3. Install required tools and VirtualBox guest packages"
  echo "  4. If needed, run Guest Additions from mounted VBox_GAs CD"
  echo "  5. Fix missing VirtualBox device files"
  echo "  6. Start copy-paste background services"
  echo "  7. Create permanent fixes after reboot"
  echo "  8. Show final test instructions"
  echo
  warn "Student must manually set this in VirtualBox menu:"
  echo "  Devices -> Shared Clipboard -> Bidirectional"
  echo "  Devices -> Drag and Drop    -> Bidirectional"
  echo
  warn "This script cannot click VirtualBox menu settings from inside Parrot."
  echo
  info "Log file: $LOG"
  echo
}

require_not_root() {
  if [ "$EUID" -eq 0 ]; then
    fail "Do not run this script using sudo."
    meaning "Clipboard autostart must be created for the normal student user, not root."
    action "Run:"
    echo "  bash fix-parrot-vbox-clipboard.sh"
    exit 1
  fi
}

check_sudo() {
  section "SUDO CHECK"
  if command -v sudo >/dev/null 2>&1; then
    pass "sudo command found"
  else
    fail "sudo command not found"
    action "Login as a user with sudo access."
    exit 1
  fi

  step "Checking sudo password/access..."
  sudo -v
  if [ $? -eq 0 ]; then
    pass "sudo access working"
  else
    fail "sudo access failed"
    action "Enter correct password or use a user with sudo permissions."
    exit 1
  fi
}

wait_for_apt() {
  step "Checking if apt/dpkg is busy..."
  if ! command -v fuser >/dev/null 2>&1; then
    warn "fuser not found. Skipping apt lock check."
    return 0
  fi

  local waited=0
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    warn "APT/dpkg is busy."
    meaning "Another update/install process is running."
    action "Waiting 10 seconds automatically..."
    sleep 10
    waited=$((waited+10))
    if [ "$waited" -ge 180 ]; then
      warn "APT is busy for more than 3 minutes."
      action "Close Software Center/Updater or reboot, then run script again."
      break
    fi
  done
}

basic_checks() {
  section "BASIC SYSTEM CHECKS"
  echo "User          : $(whoami)"
  echo "Hostname      : $(hostname)"
  echo "Kernel        : $(uname -r)"
  echo "Session type  : ${XDG_SESSION_TYPE:-unknown}"
  echo "Display       : ${DISPLAY:-not-set}"
  echo "Shell         : ${SHELL:-unknown}"

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "OS            : ${PRETTY_NAME:-unknown}"
    if echo "${PRETTY_NAME:-} ${ID:-} ${NAME:-}" | grep -qi "parrot"; then
      pass "Parrot OS detected"
    else
      warn "This does not clearly look like Parrot OS"
      meaning "Script may still work on Debian-based systems, but it is designed for Parrot."
    fi
  fi

  if [ -n "${DISPLAY:-}" ]; then
    pass "GUI desktop display found"
  else
    fail "DISPLAY is missing"
    meaning "You are not running inside graphical Parrot desktop."
    action "Open Terminal/Konsole from Parrot desktop and run again."
  fi

  if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
    pass "X11 session detected"
  else
    warn "X11 session not detected"
    meaning "Clipboard works best in X11. Wayland may block clipboard integration."
    action "If copy-paste fails, logout and select X11/Xorg session."
  fi

  if command -v systemd-detect-virt >/dev/null 2>&1; then
    local virt
    virt=$(systemd-detect-virt 2>/dev/null)
    echo "Virtualization: ${virt:-none}"
    if echo "$virt" | grep -qi "oracle\|virtualbox"; then
      pass "VirtualBox VM detected"
    else
      warn "VirtualBox was not clearly detected"
      meaning "If this is VMware/Hyper-V, this script is not the correct fix."
    fi
  fi

  if command -v apt >/dev/null 2>&1; then
    pass "APT package manager found"
  else
    fail "APT not found"
    meaning "This script supports Parrot/Debian-based systems only."
    exit 1
  fi
}

check_disk_space() {
  section "DISK SPACE CHECK"
  local avail
  avail=$(df -Pm / | awk 'NR==2 {print $4}')
  echo "Available root disk space: ${avail:-unknown} MB"

  if [ -z "$avail" ]; then
    warn "Could not calculate disk space"
    return 0
  fi

  if [ "$avail" -lt 1000 ]; then
    fail "Very low disk space"
    meaning "Installation/update can fail."
    action "Free disk space and run again."
  elif [ "$avail" -lt 2500 ]; then
    warn "Disk space is low"
    meaning "Normal fix may work, but update/repair-all may fail."
  else
    pass "Disk space is enough"
  fi
}

check_internet() {
  section "INTERNET AND DNS CHECK"

  step "Checking direct internet using IP..."
  if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    pass "Internet IP connectivity working"
    INTERNET_OK=1
  else
    warn "Direct internet check failed"
    meaning "Parrot could not reach 1.1.1.1."
  fi

  step "Checking DNS..."
  if getent hosts deb.parrot.sh >/dev/null 2>&1 || getent hosts google.com >/dev/null 2>&1; then
    pass "DNS resolution working"
    INTERNET_OK=1
  else
    warn "DNS check failed"
    meaning "Parrot cannot convert website names to IP addresses."
    action "Reconnect internet or change DNS if apt fails."
  fi

  if [ "$INTERNET_OK" -eq 0 ]; then
    warn "Internet may not be working"
    meaning "APT package installation may fail. ISO Guest Additions method may still work if CD is mounted."
  fi
}

repair_package_manager() {
  section "PACKAGE MANAGER REPAIR"

  wait_for_apt

  step "Completing unfinished package operations..."
  if can_change; then
    sudo dpkg --configure -a
    [ $? -eq 0 ] && pass "dpkg configure completed" || warn "dpkg configure returned error"
  else
    info "DIAGNOSE ONLY: skipped dpkg --configure -a"
  fi

  wait_for_apt

  step "Fixing broken dependencies..."
  if can_change; then
    sudo apt --fix-broken install -y
    [ $? -eq 0 ] && pass "Broken dependency repair completed" || warn "apt --fix-broken returned error"
  else
    info "DIAGNOSE ONLY: skipped apt --fix-broken install"
  fi
}

apt_update_once() {
  if [ "$APT_UPDATED" -eq 1 ]; then
    return 0
  fi

  section "APT UPDATE"
  wait_for_apt
  step "Updating package list..."
  meaning "This downloads package information. It is needed before install."

  if can_change; then
    sudo apt update
    if [ $? -eq 0 ]; then
      pass "apt update completed"
      APT_UPDATED=1
    else
      warn "apt update failed"
      meaning "Internet or repository issue may exist."
      action "Script will continue and try ISO method if available."
    fi
  else
    info "DIAGNOSE ONLY: skipped apt update"
  fi
}

update_system() {
  section "OPTIONAL SYSTEM UPDATE"
  warn "This can take time depending on internet speed."
  warn "Do not turn off VM during update."

  apt_update_once
  wait_for_apt

  if can_change; then
    sudo apt upgrade -y
    [ $? -eq 0 ] && pass "System upgrade completed" || warn "System upgrade had errors"
    sudo apt autoremove -y
    NEED_REBOOT=1
  else
    info "DIAGNOSE ONLY: skipped apt upgrade"
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

  if ! can_change; then
    warn "$pkg missing"
    return 1
  fi

  apt_update_once
  wait_for_apt
  step "Installing package: $pkg"
  sudo apt install -y "$pkg"

  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    pass "$pkg installed successfully"
    return 0
  else
    warn "$pkg installation failed"
    meaning "APT could not install this package. Internet/repo issue may exist."
    return 1
  fi
}

install_pkg_if_available() {
  local pkg="$1"
  apt-cache show "$pkg" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    warn "$pkg not available in repositories. Skipping."
    return 0
  fi
  install_pkg_if_missing "$pkg"
}

install_headers() {
  section "KERNEL HEADER CHECK"
  local exact="linux-headers-$(uname -r)"

  if dpkg-query -W -f='${Status}' "$exact" 2>/dev/null | grep -q "install ok installed"; then
    pass "$exact installed"
    return 0
  fi

  if ! can_change; then
    warn "$exact missing"
    return 1
  fi

  apt_update_once

  if apt-cache show "$exact" >/dev/null 2>&1; then
    install_pkg_if_missing "$exact"
  else
    warn "$exact not found"
    meaning "Exact kernel headers are not available in repo."
    action "Trying linux-headers-amd64 fallback."
    install_pkg_if_available linux-headers-amd64
  fi
}

install_required_packages() {
  section "REQUIRED TOOLS AND GUEST PACKAGES"

  install_pkg_if_missing build-essential
  install_pkg_if_missing dkms
  install_pkg_if_missing gcc
  install_pkg_if_missing make
  install_pkg_if_missing perl
  install_headers
  install_pkg_if_missing xclip

  step "Installing VirtualBox Guest packages from apt..."
  install_pkg_if_available virtualbox-guest-utils
  install_pkg_if_available virtualbox-guest-x11
  install_pkg_if_available virtualbox-guest-dkms
}

find_guest_additions_iso() {
  section "GUEST ADDITIONS ISO DETECTION"

  ISO_RUN=""

  local candidates
  candidates=$(find /media "$HOME" /run/media /mnt -maxdepth 5 -type f -name "VBoxLinuxAdditions.run" 2>/dev/null | head -n 1)

  if [ -n "$candidates" ]; then
    ISO_RUN="$candidates"
    pass "Guest Additions ISO installer found"
    echo "Installer path: $ISO_RUN"
  else
    warn "VBoxLinuxAdditions.run not found"
    meaning "Guest Additions CD is not mounted/opened."
    action "In VirtualBox menu, click:"
    echo "  Devices -> Insert Guest Additions CD image"
    echo "Then open/mount VBox_GAs and run this script again."
  fi
}

run_iso_guest_additions() {
  section "ISO GUEST ADDITIONS INSTALLATION"

  find_guest_additions_iso

  if [ -z "$ISO_RUN" ]; then
    warn "Skipping ISO installation because VBoxLinuxAdditions.run was not found."
    return 1
  fi

  step "Installing Guest Additions from mounted ISO..."
  meaning "This is like manually running sudo ./VBoxLinuxAdditions.run, but automated."
  warn "This may take a few minutes."

  if can_change; then
    chmod +x "$ISO_RUN" 2>/dev/null || true
    yes yes | sudo sh "$ISO_RUN"

    if [ $? -eq 0 ]; then
      pass "ISO Guest Additions installer completed"
    else
      warn "ISO installer returned an error code"
      meaning "Some warnings are normal, but if copy-paste fails, reboot and run repair-all."
    fi

    NEED_REBOOT=1
  else
    info "DIAGNOSE ONLY: skipped ISO installer"
  fi
}

guest_additions_strategy() {
  section "GUEST ADDITIONS SMART INSTALL STRATEGY"

  if [ "$MODE" = "iso-only" ]; then
    run_iso_guest_additions
    return
  fi

  install_required_packages

  if command -v VBoxClient >/dev/null 2>&1; then
    pass "VBoxClient command exists after apt package check"
  else
    warn "VBoxClient still missing after apt package check"
    meaning "APT method did not provide the VirtualBox clipboard tool."
    action "Trying mounted Guest Additions ISO method."
    run_iso_guest_additions
  fi
}

remove_conflicting_guest_additions() {
  section "CONFLICT CLEANUP"

  if ls /opt/VBoxGuestAdditions-* >/dev/null 2>&1; then
    warn "Existing ISO Guest Additions found under /opt"
    meaning "Old Guest Additions can conflict with new installation."
    if can_change; then
      sudo /opt/VBoxGuestAdditions-*/uninstall.sh 2>/dev/null || true
      pass "Tried to uninstall old ISO Guest Additions"
    fi
  else
    pass "No old ISO Guest Additions found under /opt"
  fi

  if can_change; then
    step "Purging apt VirtualBox guest packages for clean reinstall..."
    sudo apt purge -y virtualbox-guest-x11 virtualbox-guest-utils virtualbox-guest-dkms
    sudo apt autoremove -y
  fi
}

module_check_and_load() {
  section "VIRTUALBOX MODULE CHECK"

  if lsmod | grep -q "^vboxguest"; then
    pass "vboxguest module already loaded"
  else
    warn "vboxguest module not loaded"
    meaning "Parrot communication driver for VirtualBox is not active."
    action "Trying to load it automatically."
    run_cmd sudo modprobe vboxguest 2>/dev/null || true
  fi

  if lsmod | grep -q "^vboxguest"; then
    pass "vboxguest module active"
  else
    warn "vboxguest module still not active"
    meaning "Guest Additions may need reboot or reinstall."
    action "Script will try ISO method if available, then ask for reboot."
    run_iso_guest_additions
    run_cmd sudo modprobe vboxguest 2>/dev/null || true
  fi

  if lsmod | grep -q "^vboxguest"; then
    pass "vboxguest module active now"
  else
    fail "vboxguest module could not be activated"
    meaning "VirtualBox Guest Additions are not properly active yet."
    action "Reboot, then run this script again. If still fails, use --aggressive."
    NEED_REBOOT=1
  fi

  echo
  echo "VirtualBox related modules:"
  lsmod | grep -E "vbox|vmwgfx" || true
}

restart_guest_service() {
  section "VIRTUALBOX GUEST SERVICE"

  if systemctl list-unit-files | grep -q "virtualbox-guest-utils.service"; then
    step "Restarting virtualbox-guest-utils.service..."
    run_cmd sudo systemctl restart virtualbox-guest-utils.service 2>/dev/null || true
    systemctl status virtualbox-guest-utils.service --no-pager -l 2>/dev/null | sed -n '1,12p'
  else
    warn "virtualbox-guest-utils.service not found"
    meaning "Not all systems use this service name. VBoxClient may still work."
  fi
}

create_vbox_device() {
  local dev="$1"
  local minor
  minor=$(awk -v d="$dev" '$2==d {print $1}' /proc/misc)

  if [ -z "$minor" ]; then
    fail "/proc/misc does not contain $dev"
    meaning "VirtualBox kernel module has not registered this device."
    action "Reboot or use --aggressive if issue continues."
    return 1
  fi

  if [ -e "/dev/$dev" ]; then
    pass "/dev/$dev already exists"
  else
    warn "/dev/$dev missing"
    meaning "Parrot has VirtualBox support, but communication device file is missing."
    action "Creating it automatically."
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

fix_device_nodes() {
  section "VIRTUALBOX DEVICE FILE FIX"
  create_vbox_device vboxguest
  create_vbox_device vboxuser
}

create_permanent_fixes() {
  section "PERMANENT FIX AFTER REBOOT"

  step "Creating udev permission rule..."
  if can_change; then
    echo 'KERNEL=="vboxguest", MODE="0666"
KERNEL=="vboxuser", MODE="0666"' | sudo tee /etc/udev/rules.d/60-ewb-vboxguest.rules >/dev/null
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
  fi

  step "Creating boot device-fix script..."
  if can_change; then
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
  fi

  if systemctl is-enabled ewb-fix-vbox-devices.service >/dev/null 2>&1; then
    pass "Boot auto-fix service enabled"
  else
    warn "Boot auto-fix service not enabled"
  fi

  step "Creating user login VBoxClient autostart..."
  if can_change; then
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

  [ -f "$HOME/.config/autostart/ewb-vboxclient.desktop" ] && pass "User login autostart created" || warn "User login autostart not created"
}

start_clipboard_services() {
  section "START COPY-PASTE SERVICES"

  if [ -z "${DISPLAY:-}" ]; then
    fail "DISPLAY missing"
    action "Open Parrot Terminal from GUI desktop and run again."
    return 1
  fi

  if ! command -v VBoxClient >/dev/null 2>&1; then
    fail "VBoxClient not found"
    meaning "Guest Additions user tool is still missing."
    action "Run ISO method or aggressive repair."
    return 1
  fi

  step "Stopping old VBoxClient processes..."
  run_cmd killall VBoxClient 2>/dev/null || true
  sleep 1

  step "Starting Shared Clipboard service..."
  run_cmd VBoxClient --clipboard &
  sleep 1

  step "Starting Drag-and-Drop service..."
  run_cmd VBoxClient --draganddrop &
  sleep 1

  step "Starting display helper services..."
  run_cmd VBoxClient --display &
  run_cmd VBoxClient --seamless &
  sleep 3

  echo "Running VBoxClient processes:"
  pgrep -a VBoxClient || true

  pgrep -a VBoxClient | grep -q "clipboard" && pass "Clipboard service running" || fail "Clipboard service not running"
  pgrep -a VBoxClient | grep -q "draganddrop" && pass "Drag-and-drop service running" || warn "Drag-and-drop service not running"
}

clipboard_test() {
  section "FINAL CLIPBOARD TEST"

  local test_text
  local clip_out
  test_text="EWB_PARROT_TO_WINDOWS_TEST_$(date +%H%M%S)"

  if ! command -v xclip >/dev/null 2>&1; then
    fail "xclip missing"
    action "Run repair-all mode."
    return 1
  fi

  if [ -z "${DISPLAY:-}" ]; then
    fail "DISPLAY missing"
    return 1
  fi

  echo "$test_text" | xclip -selection clipboard
  sleep 1
  clip_out=$(xclip -selection clipboard -o 2>/dev/null || true)

  if [ "$clip_out" = "$test_text" ]; then
    pass "Parrot internal clipboard is working"
    echo
    echo "===================================================="
    echo " STUDENT TEST NOW"
    echo "===================================================="
    echo "1. Open Windows Notepad"
    echo "2. Press Ctrl + V"
    echo
    echo "Expected paste text:"
    echo "$test_text"
    echo "===================================================="
  else
    fail "Parrot internal clipboard test failed"
    meaning "Parrot clipboard itself did not store test text."
    action "Reboot and run script again."
  fi
}

final_report() {
  section "FINAL STUDENT RESULT"

  echo "Status checklist:"
  [ -e /dev/vboxguest ] && pass "/dev/vboxguest exists" || fail "/dev/vboxguest missing"
  [ -e /dev/vboxuser ] && pass "/dev/vboxuser exists" || fail "/dev/vboxuser missing"
  pgrep -a VBoxClient | grep -q "clipboard" && pass "VBoxClient clipboard running" || fail "VBoxClient clipboard not running"

  echo
  warn "Manual VirtualBox setting reminder:"
  echo "  Devices -> Shared Clipboard -> Bidirectional"
  echo "  Devices -> Drag and Drop    -> Bidirectional"

  echo
  if [ "$NEED_REBOOT" -eq 1 ]; then
    warn "Reboot is recommended"
    meaning "Guest Additions or system packages changed."
    echo "Run:"
    echo "  sudo reboot"
    echo
    echo "After reboot, run:"
    echo "  bash fix-parrot-vbox-clipboard.sh"
  fi

  echo
  echo "If Windows -> Parrot works but Parrot -> Windows does not:"
  echo "  1. Devices -> Shared Clipboard -> Guest to Host"
  echo "  2. Test Windows Notepad Ctrl + V"
  echo "  3. Then set back: Devices -> Shared Clipboard -> Bidirectional"

  echo
  echo "Terminal shortcuts:"
  echo "  Parrot Terminal Copy  : Ctrl + Shift + C"
  echo "  Parrot Terminal Paste : Ctrl + Shift + V"
  echo "  Normal apps           : Ctrl + C / Ctrl + V"

  echo
  echo "Repair commands:"
  echo "  Normal fix     : bash fix-parrot-vbox-clipboard.sh"
  echo "  Full repair    : bash fix-parrot-vbox-clipboard.sh --repair-all"
  echo "  ISO only       : bash fix-parrot-vbox-clipboard.sh --iso-only"
  echo "  Aggressive     : bash fix-parrot-vbox-clipboard.sh --aggressive"
  echo
  info "Log saved at: $LOG"
  echo "Send this log to trainer if issue still exists."

  echo
  if [ "$FAILED" -eq 0 ]; then
    pass "Guest-side setup looks correct. Test copy-paste now."
    exit 0
  else
    warn "Some checks failed. Follow the action messages above."
    echo
    echo "Recommended next command:"
    echo "  bash fix-parrot-vbox-clipboard.sh --repair-all"
    echo
    echo "If still not fixed:"
    echo "  bash fix-parrot-vbox-clipboard.sh --aggressive"
    echo "  sudo reboot"
    exit 2
  fi
}

main() {
  show_intro
  require_not_root
  check_sudo
  basic_checks
  check_disk_space
  check_internet

  if [ "$MODE" = "update-system" ]; then
    repair_package_manager
    update_system
    final_report
  fi

  repair_package_manager

  if [ "$MODE" = "repair-all" ]; then
    update_system
  fi

  if [ "$MODE" = "aggressive" ]; then
    remove_conflicting_guest_additions
  fi

  if [ "$MODE" = "iso-only" ]; then
    install_required_packages
    run_iso_guest_additions
  else
    guest_additions_strategy
  fi

  module_check_and_load
  restart_guest_service
  fix_device_nodes
  create_permanent_fixes
  start_clipboard_services
  clipboard_test
  final_report
}

main
