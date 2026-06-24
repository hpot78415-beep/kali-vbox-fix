# Parrot Security OS - Copy & Paste Fix (Student Guide)

This is a simple, beginner-friendly guide. Follow the steps in order.

## 1. What problem does this fix?

You are running **Parrot Security OS inside VirtualBox** on a Windows computer.
You try to copy text in Windows and paste it in Parrot (or the other way), but
nothing happens.

This is a very common VirtualBox problem. It happens because the small helper
software inside Parrot (called **Guest Additions**) is either not fully
installed, or its background service did not start. This script fixes that for
you, so you do not have to type many commands by hand.

## 2. Before running - VirtualBox settings (very important)

The script can fix the Linux side, but it **cannot** change VirtualBox menu
settings. You must do this part yourself.

1. Start your Parrot VM and wait for the desktop to load.
2. Look at the **top menu bar of the VirtualBox window**.
3. Set both of these to Bidirectional:

   ```text
   Devices -> Shared Clipboard -> Bidirectional
   Devices -> Drag and Drop    -> Bidirectional
   ```

"Bidirectional" means copy-paste works in **both** directions.

## 3. Open a terminal

Log in to the Parrot **desktop** first (not just a black text screen).
Then open the **Terminal** app.

## 4. Download the script

You can use either method. Both do the same thing.

### Method A - git clone

```bash
git clone https://github.com/hpot78415-beep/kali-vbox-fix.git
cd kali-vbox-fix
```

### Method B - curl raw link (one line)

```bash
curl -fsSL "https://raw.githubusercontent.com/hpot78415-beep/kali-vbox-fix/refs/heads/main/fix-parrot-vbox-clipboard.sh" -o fix-parrot-vbox-clipboard.sh
```

## 5. Run the script

```bash
bash fix-parrot-vbox-clipboard.sh
```

Do **not** type `sudo` in front of it. The script will ask for your password
only on the steps that really need it.

While running, it shows a clear report:

- `[PASS]` = this part is good
- `[WARN]` = small problem, usually okay
- `[FAIL]` = this part failed, read the message

## 6. Test the copy-paste

At the end, the script prints a test text, for example:

```text
EWB_PARROT_TO_WINDOWS_TEST_123456
```

Now:

1. Go to **Windows**.
2. Open **Notepad**.
3. Press **Ctrl + V**.

If that text appears in Notepad, your copy-paste is fixed.

## 7. Common errors and solutions

**Error: "Do not run this script using sudo."**
You ran it with sudo. Run it again without sudo:

```bash
bash fix-parrot-vbox-clipboard.sh
```

**Error: "DISPLAY is not set."**
You are not in the desktop. Log in to the Parrot graphical desktop, open a
terminal there, and run the script again.

**Message: "vboxguest module is not active" or asks you to reboot.**
Reboot once, then run the script again:

```bash
sudo reboot
# after reboot
bash fix-parrot-vbox-clipboard.sh
```

**Windows to Parrot works, but Parrot to Windows does not.**
In the VirtualBox top menu:

```text
Devices -> Shared Clipboard -> Guest to Host
```

Test once in Windows Notepad with Ctrl + V, then change it back to:

```text
Devices -> Shared Clipboard -> Bidirectional
```

**Copy-paste does not work inside the terminal.**
Inside the terminal you must use special shortcuts:

```text
Parrot Terminal Copy  : Ctrl + Shift + C
Parrot Terminal Paste : Ctrl + Shift + V
Normal Parrot apps    : Ctrl + C / Ctrl + V
```

## 8. When to use aggressive mode

Use this only if the normal command did not fix the problem. It removes and
reinstalls the VirtualBox guest software cleanly:

```bash
bash fix-parrot-vbox-clipboard.sh --aggressive
```

After it finishes, reboot and run the normal command again.

## 9. When to reboot

Reboot when:

- The script says "Reboot is recommended".
- You just ran aggressive mode.
- Copy-paste still does not work after a normal run.

```bash
sudo reboot
```

## 10. Just want to check, not change anything?

Diagnose-only mode prints all checks but changes nothing:

```bash
bash fix-parrot-vbox-clipboard.sh --diagnose-only
```
