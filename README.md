# EWB Kali VirtualBox Copy-Paste Fix

This script is for students using **Kali Linux inside VirtualBox** when copy-paste is not working between Windows and Kali.

> Parrot Security OS users: jump to the [Parrot Security OS](#parrot-security-os-copy-paste-fix) section below.

## Before running

In the running Kali VM window, set:

```text
Devices -> Shared Clipboard -> Bidirectional
Devices -> Drag and Drop    -> Bidirectional
```

This part is host-side VirtualBox setting, so the Linux script cannot change it automatically.

## Student command after uploading this file to GitHub

Use your raw GitHub URL:

```bash
curl -fsSL "RAW_GITHUB_URL_HERE" -o fix-vbox-clipboard.sh
bash fix-vbox-clipboard.sh
```

Example format:

```bash
curl -fsSL "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/fix-vbox-clipboard.sh" -o fix-vbox-clipboard.sh
bash fix-vbox-clipboard.sh
```

## Do not run with sudo

Correct:

```bash
bash fix-vbox-clipboard.sh
```

Wrong:

```bash
sudo bash fix-vbox-clipboard.sh
```

The script will ask for sudo only when required.

## If normal mode fails

Run:

```bash
bash fix-vbox-clipboard.sh --aggressive
```

Then reboot:

```bash
sudo reboot
```

After reboot, run again:

```bash
bash fix-vbox-clipboard.sh
```

## Testing

After script completes, it will show a text like:

```text
EWB_KALI_TO_WINDOWS_TEST_123456
```

Open Windows Notepad and press:

```text
Ctrl + V
```

If the test text is pasted, copy-paste is fixed.

## Shortcuts

```text
Kali Terminal Copy  : Ctrl + Shift + C
Kali Terminal Paste : Ctrl + Shift + V
Normal Kali apps    : Ctrl + C / Ctrl + V
```

## If Windows to Kali works but Kali to Windows fails

In VirtualBox VM top menu:

```text
Devices -> Shared Clipboard -> Guest to Host
```

Test once in Windows Notepad using Ctrl + V.

Then change it back:

```text
Devices -> Shared Clipboard -> Bidirectional
```

---

# Parrot Security OS Copy-Paste Fix

This script is for students using **Parrot Security OS inside VirtualBox** (on a Windows host) when copy-paste is not working between Windows and Parrot.

Script file: `fix-parrot-vbox-clipboard.sh`

It also has a beginner guide: `PARROT_STUDENT_GUIDE.md`
and a trainer guide: `PARROT_TRAINER_SCRIPT.txt`.

## Before running checklist

1. The VM must be **Parrot Security OS** running **inside VirtualBox**.
2. Log in to the Parrot **desktop (GUI)**, then open a terminal.
3. In the running Parrot VM window, set the host-side menu:

   ```text
   Devices -> Shared Clipboard -> Bidirectional
   Devices -> Drag and Drop    -> Bidirectional
   ```

   This is a host-side VirtualBox setting. The Linux script cannot change it automatically.
4. Do **not** run the script with `sudo`.

## Quick command for Parrot students (git clone method)

```bash
git clone https://github.com/hpot78415-beep/kali-vbox-fix.git
cd kali-vbox-fix
bash fix-parrot-vbox-clipboard.sh
```

## Quick command for Parrot students (curl raw link method)

```bash
curl -fsSL "https://raw.githubusercontent.com/hpot78415-beep/kali-vbox-fix/refs/heads/main/fix-parrot-vbox-clipboard.sh" -o fix-parrot-vbox-clipboard.sh && bash fix-parrot-vbox-clipboard.sh
```

## Normal (safe) mode

```bash
bash fix-parrot-vbox-clipboard.sh
```

## Aggressive repair mode

Use this only when normal mode fails. It removes conflicting ISO Guest Additions,
purges and reinstalls the VirtualBox guest packages, and installs required headers/tools.

```bash
bash fix-parrot-vbox-clipboard.sh --aggressive
```

After it finishes, reboot, then run normal mode again:

```bash
sudo reboot
# after reboot
bash fix-parrot-vbox-clipboard.sh
```

## Diagnose-only mode

This prints all checks but makes **no** changes to the system.

```bash
bash fix-parrot-vbox-clipboard.sh --diagnose-only
```

## Do not run with sudo (Parrot)

Correct:

```bash
bash fix-parrot-vbox-clipboard.sh
```

Wrong:

```bash
sudo bash fix-parrot-vbox-clipboard.sh
```

The script asks for sudo only on the steps that need it.

## Testing (Parrot)

When the script finishes, it shows a text like:

```text
EWB_PARROT_TO_WINDOWS_TEST_123456
```

Open Windows Notepad and press:

```text
Ctrl + V
```

If the test text is pasted, copy-paste is fixed.

## Troubleshooting notes (Parrot)

If Windows to Parrot works but Parrot to Windows does not:

```text
Devices -> Shared Clipboard -> Guest to Host
```

Test once in Windows Notepad using Ctrl + V, then change it back:

```text
Devices -> Shared Clipboard -> Bidirectional
```

Terminal shortcuts:

```text
Parrot Terminal Copy  : Ctrl + Shift + C
Parrot Terminal Paste : Ctrl + Shift + V
Normal Parrot apps    : Ctrl + C / Ctrl + V
```

## Difference between the Kali script and the Parrot script

Both scripts solve the same VirtualBox clipboard problem and share the same
safe / aggressive / diagnose-only modes, the same PASS / WARN / FAIL output,
the device-node fix, the systemd reboot fix, the login autostart fix, and the
xclip clipboard test. The differences are:

- **Kernel headers:** the Parrot script first tries the exact headers for the
  running kernel (`linux-headers-$(uname -r)`) because Parrot sometimes runs a
  custom kernel, and only falls back to the generic `linux-headers-amd64`. The
  Kali script installs `linux-headers-amd64` directly.
- **OS detection:** the Parrot script checks `/etc/os-release` for "parrot" and
  prints a clear PASS/WARN; the Kali script does a generic check.
- **DKMS:** the Parrot script adds an explicit DKMS check section and prints any
  vbox DKMS module status.
- **Test text and messages:** the Parrot script uses
  `EWB_PARROT_TO_WINDOWS_TEST_...` and Parrot-worded instructions.

Use `fix-vbox-clipboard.sh` on Kali and `fix-parrot-vbox-clipboard.sh` on Parrot.
