#!/usr/bin/env bash

# ============================================================

# EWB Parrot Security OS VirtualBox Copy-Paste Auto Fix

# File: fix-parrot-vbox-clipboard.sh

# Run : bash fix-parrot-vbox-clipboard.sh

#

# Student-friendly modes:

# bash fix-parrot-vbox-clipboard.sh

# bash fix-parrot-vbox-clipboard.sh --update-system

# bash fix-parrot-vbox-clipboard.sh --repair-all

# bash fix-parrot-vbox-clipboard.sh --aggressive

# bash fix-parrot-vbox-clipboard.sh --diagnose-only

#

# Important:

# This script fixes Parrot/Linux guest-side issues.

# VirtualBox host-side menu must be manually set:

# Devices -> Shared Clipboard -> Bidirectional

# Devices -> Drag and Drop    -> Bidirectional

# ============================================================

set +e

VERSION="2.0"
MODE="safe"
FAILED=0
NEED_REBOOT=0
INTERNET_OK=0
APT_UPDATED=0
LOG="$HOME/ewb_parrot_vbox_clipboard_fix_$(date +%Y%m%d_%H%M%S).log"

for arg in "$@"; do
case "$arg" in
--update-system) MODE="update-system" ;;
--repair-all) MODE="repair-all" ;;
--aggressive) MODE="aggressive" ;;
--diagnose-only) MODE="diagnose" ;;
--help|-h)
echo "Usage:"
echo "  bash fix-parrot-vbox-clipboard.sh"
echo "  bash fix-parrot-vbox-clipboard.sh --update-system"
echo "  bash fix-parrot-vbox-clipboard.sh --repair-all"
echo "  bash fix-parrot-vbox-clipboard.sh --aggressive"
echo "  bash fix-parrot-vbox-clipboard.sh --diagnose-only"
exit 0
;;
*)
echo "Unknown option: $arg"
echo "Use --help to see supported modes."
exit 1
;;
esac
done

exec > >(tee -a "$LOG") 2>&1

if [ -t 1 ]; then
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"
else
GREEN=""
RED=""
YELLOW=""
BLUE=""
CYAN=""
BOLD=""
RESET=""
fi

pass() { echo -e "${GREEN}[PASS]${RESET} $1"; }
fail() { echo -e "${RED}[FAIL]${RESET} $1"; FAILED=1; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
step() { echo -e "${CYAN}[STEP]${RESET} $1"; }
action() { echo -e "${YELLOW}Action:${RESET} $1"; }
meaning() { echo -e "${BLUE}Simple meaning:${RESET} $1"; }
section() {
echo
echo "===================================================="
echo "$1"
echo "===================================================="
}

can_change() {
[ "$MODE" != "diagnose" ]
}

run_cmd() {
if ! can_change; then
info "DIAGNOSE ONLY: skipped command: $*"
return 0
fi
"$@"
}

require_not_root() {
if [ "$EUID" -eq 0 ]; then
fail "Do not run this script using sudo."
meaning "If you run the whole script as root, some user-level clipboard settings may be created in the wrong place."
action "Run this instead:"
echo
echo "  bash fix-parrot-vbox-clipboard.sh"
echo
exit 1
fi
}

show_intro() {
clear
echo "===================================================="
echo " EWB Parrot VirtualBox Copy-Paste Auto Fix v$VERSION"
echo " Mode: $MODE"
echo "===================================================="
echo
echo "This script will:"
echo "  1. Check your Parrot system"
echo "  2. Repair package manager issues"
echo "  3. Install required VirtualBox guest packages"
echo "  4. Fix copy-paste background services"
echo "  5. Create permanent reboot fix"
echo "  6. Show final test instructions"
echo
echo "Before continuing, manually set this in VirtualBox:"
echo
echo "  Devices -> Shared Clipboard -> Bidirectional"
echo "  Devices -> Drag and Drop    -> Bidirectional"
echo
warn "This script can fix Parrot-side issues only."
warn "It cannot click the VirtualBox menu for you."
echo
info "Log file: $LOG"
echo
}

wait_for_apt() {
step "Checking if APT/dpkg is busy..."

if ! command -v fuser >/dev/null 2>&1; then
warn "fuser command not found. Skipping lock check."
return 0
fi

while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || 
sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || 
sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
warn "APT/dpkg is busy."
meaning "Another update or installation is running in the background."
action "Please wait. I will check again in 10 seconds."
sleep 10
done

pass "APT/dpkg is free"
}

check_internet() {
section "INTERNET CHECK"

step "Checking internet connection..."

if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
pass "Internet connection is working"
INTERNET_OK=1
else
warn "Ping test failed"
meaning "Parrot could not reach the internet using a direct IP check."
action "Check Wi-Fi/LAN. If your browser has internet, continue; otherwise connect internet and run again."
fi

step "Checking DNS name resolution..."

if getent hosts deb.parrot.sh >/dev/null 2>&1 || getent hosts google.com >/dev/null 2>&1; then
pass "DNS is working"
INTERNET_OK=1
else
warn "DNS is not resolving domain names"
meaning "Internet may be connected, but Parrot cannot convert website names into IP addresses."
action "Reconnect network or change DNS, then run the script again."
fi

if [ "$INTERNET_OK" -eq 0 ]; then
fail "Internet/DNS check failed"
action "Connect internet and run this command again:"
echo "  bash fix-parrot-vbox-clipboard.sh"
fi
}

check_disk_space() {
section "DISK SPACE CHECK"

local avail_mb
avail_mb=$(df -Pm / | awk 'NR==2 {print $4}')

echo "Available root disk space: ${avail_mb} MB"

if [ -z "$avail_mb" ]; then
warn "Could not read disk space"
return 0
fi

if [ "$avail_mb" -lt 1000 ]; then
fail "Low disk space"
meaning "Package installation or update may fail because the disk is almost full."
action "Free some disk space, then run the script again."
elif [ "$avail_mb" -lt 2500 ]; then
warn "Disk space is low but script may continue"
meaning "Normal fix may work, but full system update may fail."
else
pass "Disk space looks fine"
fi
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

```
if echo "${PRETTY_NAME:-} ${ID:-} ${NAME:-}" | grep -qi "parrot"; then
  pass "Parrot OS detected"
else
  warn "This does not clearly look like Parrot OS"
  meaning "The script can still work on Debian-based systems, but it is designed for Parrot students."
fi
```

fi

if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
pass "Desktop session is X11"
else
warn "Desktop session is not X11"
meaning "Clipboard tools work best in X11. Wayland may block clipboard integration."
action "If copy-paste fails, log out and select X11/Xorg session."
fi

if [ -n "${DISPLAY:-}" ]; then
pass "GUI display is available"
else
fail "DISPLAY variable is missing"
meaning "You may be running from a non-GUI terminal."
action "Login to the Parrot desktop and run the script from Terminal/Konsole."
fi

if command -v systemd-detect-virt >/dev/null 2>&1; then
local virt
virt=$(systemd-detect-virt 2>/dev/null)
echo "Virtualization: ${virt:-none}"

```
if echo "$virt" | grep -qi "oracle\|virtualbox"; then
  pass "VirtualBox VM detected"
else
  warn "VirtualBox was not clearly detected"
  meaning "If this is VMware/Hyper-V, this script will not solve clipboard problems."
  action "Use this script only for Parrot running inside VirtualBox."
fi
```

fi

if command -v apt >/dev/null 2>&1; then
pass "APT package manager found"
else
fail "APT not found"
meaning "This script supports Parrot/Debian-based systems only."
exit 1
fi
}

repair_package_manager() {
section "PACKAGE MANAGER HEALTH REPAIR"

if [ "$INTERNET_OK" -eq 0 ]; then
warn "Internet check failed earlier. Package installation may fail."
fi

wait_for_apt

step "Repairing unfinished dpkg work..."
meaning "If a previous installation was interrupted, this completes it."

if can_change; then
sudo dpkg --configure -a
if [ $? -eq 0 ]; then
pass "dpkg repair completed"
else
warn "dpkg repair returned an error"
fi
else
info "DIAGNOSE ONLY: skipped dpkg repair"
fi

wait_for_apt

step "Fixing broken packages..."
meaning "If any package dependency is broken, APT will try to repair it."

if can_change; then
sudo apt --fix-broken install -y
if [ $? -eq 0 ]; then
pass "Broken package repair completed"
else
warn "APT broken package repair returned an error"
fi
else
info "DIAGNOSE ONLY: skipped apt --fix-broken install"
fi

apt_update_once
}

apt_update_once() {
if [ "$APT_UPDATED" -eq 1 ]; then
return 0
fi

wait_for_apt
step "Updating package list..."
meaning "This downloads the latest package information. It does not upgrade the full system."

if can_change; then
sudo apt update
if [ $? -eq 0 ]; then
pass "Package list updated"
APT_UPDATED=1
else
fail "apt update failed"
meaning "Parrot could not refresh package information."
action "Check internet/repositories, then run again."
fi
else
info "DIAGNOSE ONLY: skipped apt update"
fi
}

update_system_optional() {
section "OPTIONAL SYSTEM UPDATE"

warn "This step may take time depending on internet speed."
warn "If many packages are upgraded, reboot is recommended."

apt_update_once
wait_for_apt

if can_change; then
sudo apt upgrade -y
if [ $? -eq 0 ]; then
pass "System packages upgraded"
NEED_REBOOT=1
else
warn "System upgrade returned an error"
fi

```
sudo apt autoremove -y
```

else
info "DIAGNOSE ONLY: skipped apt upgrade/autoremove"
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
warn "$pkg is missing"
return 1
fi

apt_update_once
wait_for_apt

step "Installing missing package: $pkg"

sudo apt install -y "$pkg"
if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
pass "$pkg installed successfully"
return 0
else
fail "$pkg installation failed"
meaning "Required package could not be installed."
action "Check internet and package repositories."
return 1
fi
}

install_pkg_if_available() {
local pkg="$1"

apt-cache show "$pkg" >/dev/null 2>&1
if [ $? -ne 0 ]; then
warn "$pkg is not available in current repositories. Skipping."
return 0
fi

install_pkg_if_missing "$pkg"
}

install_kernel_headers() {
section "KERNEL HEADER CHECK"

local exact="linux-headers-$(uname -r)"

if dpkg-query -W -f='${Status}' "$exact" 2>/dev/null | grep -q "install ok installed"; then
pass "$exact installed"
return 0
fi

if ! can_change; then
warn "$exact not installed"
return 1
fi

apt_update_once

if apt-cache show "$exact" >/dev/null 2>&1; then
install_pkg_if_missing "$exact"
else
warn "$exact not found in repositories"
meaning "Exact headers for your running kernel are not available."
action "I will try generic headers. If module build fails, reboot after system update may be needed."
install_pkg_if_available linux-headers-amd64
fi
}

check_iso_guest_additions_conflict() {
section "GUEST ADDITIONS CONFLICT CHECK"

if ls /opt/VBoxGuestAdditions-* >/dev/null 2>&1; then
warn "VirtualBox Guest Additions installed from ISO were found"
meaning "Sometimes ISO Guest Additions and APT Guest Additions conflict."
if [ "$MODE" = "aggressive" ] || [ "$MODE" = "repair-all" ]; then
action "In this repair mode, I will try to remove ISO Guest Additions."
if can_change; then
sudo /opt/VBoxGuestAdditions-*/uninstall.sh 2>/dev/null || true
fi
else
action "Normal mode will not remove it. If normal mode fails, run:"
echo "  bash fix-parrot-vbox-clipboard.sh --aggressive"
fi
else
pass "No ISO Guest Additions conflict found under /opt"
fi
}

package_checks() {
section "REQUIRED PACKAGE CHECKS"

install_pkg_if_missing build-essential
install_pkg_if_missing dkms
install_kernel_headers
install_pkg_if_missing virtualbox-guest-utils
install_pkg_if_missing virtualbox-guest-x11
install_pkg_if_missing xclip
install_pkg_if_available virtualbox-guest-dkms
}

aggressive_reinstall() {
section "AGGRESSIVE REPAIR MODE"

warn "Aggressive mode removes conflicting Guest Additions and reinstalls VirtualBox guest packages."
warn "Use this only if normal mode failed."

check_iso_guest_additions_conflict

apt_update_once
wait_for_apt

if can_change; then
step "Purging VirtualBox guest packages..."
sudo apt purge -y virtualbox-guest-x11 virtualbox-guest-utils virtualbox-guest-dkms

```
step "Cleaning unused packages..."
sudo apt autoremove -y
```

else
info "DIAGNOSE ONLY: skipped purge/reinstall"
fi

package_checks
NEED_REBOOT=1
}

dkms_check() {
section "DKMS CHECK"

if command -v dkms >/dev/null 2>&1; then
pass "dkms command available"
echo "DKMS status:"
dkms status 2>/dev/null | grep -i vbox || echo "  No VirtualBox DKMS modules listed"
else
warn "dkms command is not available"
meaning "Some systems still work without DKMS, but module building may need it."
fi
}

module_check() {
section "VIRTUALBOX MODULE CHECK"

if lsmod | grep -q "^vboxguest"; then
pass "vboxguest module already loaded"
else
warn "vboxguest module is not loaded"
meaning "The VirtualBox communication driver is not active."
action "I will try to load it now."

```
run_cmd sudo modprobe vboxguest 2>/dev/null || true
```

fi

if lsmod | grep -q "^vboxguest"; then
pass "vboxguest module active"
else
fail "vboxguest module is not active"
meaning "Parrot cannot fully communicate with VirtualBox yet."
action "A reboot or aggressive repair may be needed."
NEED_REBOOT=1
fi

echo
echo "Current VirtualBox related modules:"
lsmod | grep -E "vbox|vmwgfx" || true
}

service_check() {
section "VIRTUALBOX SERVICE CHECK"

if systemctl list-unit-files | grep -q "virtualbox-guest-utils.service"; then
step "Restarting virtualbox-guest-utils.service..."
run_cmd sudo systemctl restart virtualbox-guest-utils.service 2>/dev/null || true

```
systemctl status virtualbox-guest-utils.service --no-pager -l 2>/dev/null | sed -n '1,12p'
```

else
warn "virtualbox-guest-utils.service not found"
meaning "Some systems do not provide this service name. Clipboard may still work through VBoxClient."
fi
}

create_vbox_device() {
local dev="$1"
local minor

minor=$(awk -v d="$dev" '$2==d {print $1}' /proc/misc)

if [ -z "$minor" ]; then
fail "/proc/misc does not contain $dev"
meaning "The VirtualBox kernel module has not registered this device."
action "Reboot or run aggressive repair if this continues."
return 1
fi

if [ -e "/dev/$dev" ]; then
pass "/dev/$dev already exists"
else
warn "/dev/$dev missing"
meaning "Parrot can load VirtualBox support, but the communication device file is missing."
action "I will create it automatically."

```
run_cmd sudo rm -f "/dev/$dev"
run_cmd sudo mknod -m 666 "/dev/$dev" c 10 "$minor"
```

fi

run_cmd sudo chmod 666 "/dev/$dev" 2>/dev/null || true

if [ -e "/dev/$dev" ]; then
pass "/dev/$dev ready"
ls -l "/dev/$dev"
else
fail "/dev/$dev still missing"
meaning "The device file could not be created."
fi
}

device_node_fix() {
section "VIRTUALBOX DEVICE NODE FIX"

create_vbox_device vboxguest
create_vbox_device vboxuser
}

create_permanent_fix() {
section "PERMANENT REBOOT FIX"

step "Creating udev rule for VirtualBox guest device permissions..."

if can_change; then
echo 'KERNEL=="vboxguest", MODE="0666"
KERNEL=="vboxuser", MODE="0666"' | sudo tee /etc/udev/rules.d/60-ewb-vboxguest.rules >/dev/null

```
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
```

else
info "DIAGNOSE ONLY: skipped udev rule creation"
fi

step "Creating system boot fix script..."

if can_change; then
sudo tee /usr/local/bin/ewb-fix-vbox-devices.sh >/dev/null <<'EOF'
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

```
sudo chmod +x /usr/local/bin/ewb-fix-vbox-devices.sh
```

else
info "DIAGNOSE ONLY: skipped boot script creation"
fi

step "Creating systemd service for reboot fix..."

if can_change; then
sudo tee /etc/systemd/system/ewb-fix-vbox-devices.service >/dev/null <<'EOF'
[Unit]
Description=EWB Fix VirtualBox guest device nodes for Parrot
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ewb-fix-vbox-devices.sh

[Install]
WantedBy=multi-user.target
EOF

```
sudo systemctl daemon-reload
sudo systemctl enable ewb-fix-vbox-devices.service >/dev/null
sudo systemctl start ewb-fix-vbox-devices.service
```

else
info "DIAGNOSE ONLY: skipped systemd service creation"
fi

if systemctl is-enabled ewb-fix-vbox-devices.service >/dev/null 2>&1; then
pass "Boot device auto-fix service enabled"
else
warn "Boot device auto-fix service not enabled"
fi
}

create_user_autostart() {
section "USER LOGIN AUTOSTART FIX"

step "Creating VBoxClient autostart script..."

if can_change; then
sudo tee /usr/local/bin/ewb-start-vboxclient.sh >/dev/null <<'EOF'
#!/bin/bash
/usr/local/bin/ewb-fix-vbox-devices.sh 2>/dev/null || true

if [ -n "$DISPLAY" ]; then
pgrep -u "$USER" -f "VBoxClient --clipboard" >/dev/null || VBoxClient --clipboard >/dev/null 2>&1 &
pgrep -u "$USER" -f "VBoxClient --draganddrop" >/dev/null || VBoxClient --draganddrop >/dev/null 2>&1 &
pgrep -u "$USER" -f "VBoxClient --display" >/dev/null || VBoxClient --display >/dev/null 2>&1 &
pgrep -u "$USER" -f "VBoxClient --seamless" >/dev/null || VBoxClient --seamless >/dev/null 2>&1 &
fi
EOF

```
sudo chmod +x /usr/local/bin/ewb-start-vboxclient.sh

mkdir -p "$HOME/.config/autostart"

cat > "$HOME/.config/autostart/ewb-vboxclient.desktop" <<'EOF'
```

[Desktop Entry]
Type=Application
Name=EWB VirtualBox Clipboard Service
Comment=Start VirtualBox clipboard and drag-drop service
Exec=/usr/local/bin/ewb-start-vboxclient.sh
OnlyShowIn=XFCE;GNOME;KDE;LXDE;MATE;
X-GNOME-Autostart-enabled=true
EOF
else
info "DIAGNOSE ONLY: skipped user autostart creation"
fi

if [ -f "$HOME/.config/autostart/ewb-vboxclient.desktop" ]; then
pass "User login autostart created"
else
warn "User login autostart not created"
fi
}

start_vbox_clients() {
section "START COPY-PASTE SERVICES"

if [ -z "${DISPLAY:-}" ]; then
fail "DISPLAY is not set"
meaning "The graphical desktop is not available."
action "Open Terminal inside Parrot desktop and run again."
return 1
fi

if ! command -v VBoxClient >/dev/null 2>&1; then
fail "VBoxClient command not found"
meaning "VirtualBox guest user tools are not installed correctly."
action "Run repair-all or aggressive mode."
return 1
fi

step "Stopping old VBoxClient processes..."
run_cmd killall VBoxClient 2>/dev/null || true
sleep 1

step "Starting clipboard service..."
run_cmd VBoxClient --clipboard &
sleep 1

step "Starting drag-and-drop service..."
run_cmd VBoxClient --draganddrop &
sleep 1

step "Starting display/seamless helper services..."
run_cmd VBoxClient --display &
run_cmd VBoxClient --seamless &
sleep 3

echo "Running VBoxClient processes:"
pgrep -a VBoxClient || true

if pgrep -a VBoxClient | grep -q "clipboard"; then
pass "VBoxClient clipboard service running"
else
fail "VBoxClient clipboard service not running"
meaning "The background copy-paste service is not active."
action "Try reboot, then run this script again."
fi

if pgrep -a VBoxClient | grep -q "draganddrop"; then
pass "VBoxClient drag-and-drop service running"
else
warn "VBoxClient drag-and-drop service not running"
meaning "File drag-and-drop may not work, but text copy-paste may still work."
fi
}

clipboard_test() {
section "PARROT TO WINDOWS CLIPBOARD TEST"

local test_text
local clip_out

test_text="EWB_PARROT_TO_WINDOWS_TEST_$(date +%H%M%S)"

if ! command -v xclip >/dev/null 2>&1; then
fail "xclip not found"
meaning "The script cannot test the internal Parrot clipboard."
action "Run repair-all mode."
return 1
fi

if [ -z "${DISPLAY:-}" ]; then
fail "DISPLAY missing"
meaning "Clipboard test needs graphical desktop."
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
fail "Parrot internal clipboard is not holding the test text"
meaning "Parrot clipboard itself is not behaving correctly."
action "Restart desktop or reboot and run the script again."
fi
}

final_report() {
section "FINAL STUDENT RESULT"

echo "Checklist:"
if [ -e /dev/vboxguest ]; then pass "/dev/vboxguest exists"; else fail "/dev/vboxguest missing"; fi
if [ -e /dev/vboxuser ]; then pass "/dev/vboxuser exists"; else fail "/dev/vboxuser missing"; fi
if pgrep -a VBoxClient | grep -q "clipboard"; then pass "VBoxClient clipboard running"; else fail "VBoxClient clipboard not running"; fi

echo
if [ "$INTERNET_OK" -eq 0 ]; then
warn "Internet issue was detected"
echo "What to do:"
echo "  1. Connect Wi-Fi/LAN"
echo "  2. Open browser and test internet"
echo "  3. Run again:"
echo "     bash fix-parrot-vbox-clipboard.sh"
fi

echo
if [ "$NEED_REBOOT" -eq 1 ]; then
warn "Reboot is recommended"
meaning "Packages/modules changed. Reboot helps VirtualBox services start cleanly."
echo "Run:"
echo "  sudo reboot"
echo
echo "After reboot, run:"
echo "  bash fix-parrot-vbox-clipboard.sh"
fi

echo
echo "If Windows -> Parrot works but Parrot -> Windows does not:"
echo "  1. VirtualBox VM top menu:"
echo "     Devices -> Shared Clipboard -> Guest to Host"
echo "  2. Test Windows Notepad Ctrl + V"
echo "  3. Then change back:"
echo "     Devices -> Shared Clipboard -> Bidirectional"
echo
echo "If nothing works, check VirtualBox menu manually:"
echo "  Devices -> Shared Clipboard -> Bidirectional"
echo "  Devices -> Drag and Drop    -> Bidirectional"
echo
echo "Terminal shortcuts:"
echo "  Parrot Terminal Copy  : Ctrl + Shift + C"
echo "  Parrot Terminal Paste : Ctrl + Shift + V"
echo "  Normal Parrot apps    : Ctrl + C / Ctrl + V"
echo
echo "Troubleshooting commands:"
echo "  Normal fix      : bash fix-parrot-vbox-clipboard.sh"
echo "  Update system   : bash fix-parrot-vbox-clipboard.sh --update-system"
echo "  Full repair     : bash fix-parrot-vbox-clipboard.sh --repair-all"
echo "  Aggressive fix  : bash fix-parrot-vbox-clipboard.sh --aggressive"
echo "  Diagnose only   : bash fix-parrot-vbox-clipboard.sh --diagnose-only"
echo
info "Full log saved at: $LOG"
echo "Please send this log to trainer if issue still exists."

echo
if [ "$FAILED" -eq 0 ]; then
pass "Guest-side setup looks correct."
echo "Now test copy-paste with Windows Notepad."
exit 0
else
warn "Some checks failed."
echo "Follow the actions shown above."
echo
echo "If normal mode failed, try:"
echo "  bash fix-parrot-vbox-clipboard.sh --repair-all"
echo
echo "If repair-all failed, try:"
echo "  bash fix-parrot-vbox-clipboard.sh --aggressive"
echo "  sudo reboot"
exit 2
fi
}

main() {
show_intro
require_not_root

basic_checks
check_disk_space
check_internet

if [ "$MODE" = "update-system" ]; then
repair_package_manager
update_system_optional
final_report
fi

if [ "$MODE" = "repair-all" ]; then
repair_package_manager
update_system_optional
check_iso_guest_additions_conflict
package_checks
elif [ "$MODE" = "aggressive" ]; then
repair_package_manager
aggressive_reinstall
else
repair_package_manager
check_iso_guest_additions_conflict
package_checks
fi

dkms_check
module_check
service_check
device_node_fix
create_permanent_fix
create_user_autostart
start_vbox_clients
clipboard_test
final_report
}

main
