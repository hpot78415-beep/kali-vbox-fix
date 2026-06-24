# EWB Kali VirtualBox Copy-Paste Fix

This script is for students using **Kali Linux inside VirtualBox** when copy-paste is not working between Windows and Kali.

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
