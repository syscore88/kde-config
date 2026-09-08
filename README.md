# 🖥️ KDE Plasma Visual Configuration Script

An automated Bash shell script designed for complete visual and environment configuration of **KDE Plasma** desktop across popular Linux distributions. The script automatically detects the system package manager, installs the core KDE Plasma utility packages, temporarily grants passwordless sudo for a smooth unattended run, copies user configurations, sets wallpapers (desktop, login screen and lock screen), sets the user avatar, and finishes with a full system reboot.

The script auto-detects the system language (Polish/English) from the `LANG`/`LC_ALL` locale and prints all status messages accordingly.

---

## 🚀 Script Features

- **Automatic Linux Distribution Detection**: Full support for Debian, Ubuntu, Pop!_OS, Linux Mint, KDE neon, Zorin, Fedora, Arch Linux, Manjaro, EndeavourOS, and openSUSE/SLES.
- **Temporary Passwordless Sudo**: Requests the admin password once at the start, then configures a temporary `NOPASSWD` rule (via `/etc/sudoers.d/` or a `polkit`/`run0` rule on systems without `visudo`) so the rest of the script can run unattended. The rule is automatically removed at the end of the script.
- **KDE Plasma Package Installation**: Installs the core Plasma package set, resolving distribution-specific package names automatically (e.g. `aspell-pl` → `hunspell-pl` on Fedora/openSUSE, `plymouth-kcm` → `kde-config-plymouth` on Debian).
- **Configuration Files Sync**:
  - Copies `.config/` folder contents to `~/.config/`
  - Copies `.local/` folder contents to `~/.local/`
  - Copies `.icons/` folder contents to `~/.icons/`
  - Automatically rewrites any leftover hardcoded paths from the original author's home directory (`/home/bartek`) to the current user's home directory.
- **Wallpaper Management**:
  - Desktop wallpaper applied from `wallpaper.jpg` via an autostart entry that retries `plasma-apply-wallpaperimage` until it succeeds.
  - Login screen wallpaper applied from `login-wallpaper.png`, written to `/etc/plasmalogin.conf` via `kwriteconfig6` (with a `sed`-based fallback if it's unavailable).
  - Lock screen wallpaper applied from `lock_screen.jpg` via `kscreenlockerrc`.
- **User Avatar Setup**: Automatically sets the user profile picture in `AccountsService` and the Plasma avatars directory using `piwo.png`.
- **Progress Bar & Logging**: Displays a live progress bar across 3 phases / 12 steps. On failure, a detailed log is saved to `~/install_error_<timestamp>.log`.
- **Cache Cleanup & Reload**: Clears icon/Plasma caches and rebuilds the KDE system configuration cache (`kbuildsycoca6`) before rebooting.

---

## 🐧 Supported Distributions

The script identifies the OS using `/etc/os-release` (falling back to `ID_LIKE`) and selects the corresponding package manager:

| Distribution | Package Manager | Notes |
| :--- | :--- | :--- |
| **Debian / Ubuntu / Pop!_OS / Mint / neon / Zorin** | `apt` | `aspell-pl` → `hunspell-pl`, `kio-admin` → `kio_admin`, `plymouth-kcm` → `plymouth-kcm6` |
| **Fedora** | `dnf` | `aspell-pl` → `hunspell-pl`, `kio-admin` → `kio_admin`, `plymouth-kcm` → `plymouth-kcm6` |
| **Arch Linux / Manjaro / EndeavourOS** | `pacman` | `aspell-pl` → `hunspell-pl`, `kio-admin` → `kio_admin`, `plymouth-kcm` → `plymouth-kcm6` |
| **openSUSE / SLES** | `zypper` | `aspell-pl` → `hunspell-pl`, `kio-admin` → `kio_admin`, `plymouth-kcm` → `plymouth-kcm6` |

---


## 🔍 Module Details

### 1. Permissions & Distribution Detection
Verifies the script is **not** run as root, requests the sudo password once, and grants a temporary `NOPASSWD` rule (kept alive with a background refresher) for the duration of the run. The OS is detected via `/etc/os-release`.

### 2. Package Installation
Iterates over the package list, resolving distro-specific names, and installs each one, logging failures per package to `/tmp/install-<package>.log`.

### 3. User Avatar (AccountsService)
`piwo.png` is copied to `/usr/share/plasma/avatars/` and `/var/lib/AccountsService/icons/$USER`, and `/var/lib/AccountsService/users/$USER` is updated with the matching `Icon=` entry.

### 4. Login & Lock Screen Wallpapers
- `login-wallpaper.png` is copied to `/usr/share/wallpapers/` and referenced from `/etc/plasmalogin.conf`.
- The desktop `wallpaper.jpg` is applied via a self-removing autostart entry (`force-wallpaper.desktop`) that retries on next login until successful.
- `lock_screen.jpg` is referenced from `~/.config/kscreenlockerrc`.

### 5. Configuration Copy & Cleanup
Plasma Shell is stopped, the `.config`, `.local`, and `.icons` folders from the script directory are copied into the user's home directory, hardcoded old-username paths are rewritten, caches are cleared, and `kbuildsycoca6` rebuilds the system configuration database.

### 6. Finalization
The temporary sudo/polkit rule is removed and the system automatically **reboots** (`systemctl reboot`) to apply all changes.

---

🚀 How to Run

1. Clone the repository or download the files
```bash
git clone https://github.com/syscore88/kde-config.git
```

2. Enter the downloaded folder
```bash
cd kde-config
```

3. Make the script executable
```bash
chmod +x install.sh
```

4. Run the script
> ⚠️ **IMPORTANT:** Run the script as a **regular user** (NOT as root/sudo). The script will ask for the administrator password at the start to configure temporary elevated privileges.
```bash
./install.sh
```
---
<img width="1920" height="1080" alt="Zrzut ekranu_20260716_191008" src="https://github.com/user-attachments/assets/15eafeed-a1aa-4351-bbc1-46c0c231a1a6" />

### ☕ Support the Project

If you find this tool helpful and it saved you some time, consider buying me a coffee to support further development! 

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/bartekszczecinski)

---

If you find this project useful, leave a star! ⭐

---

## ⚠️ Important Notes

* **Auto-Reboot:** After all configurations complete successfully, the script will **automatically restart the computer** after 3 seconds so that all changes to the display manager and desktop environment are properly loaded. Save your work before running!
* **Temporary privileges:** The script creates a `/etc/sudoers.d/99-temp-installer` file to avoid password prompts during execution. This file is **completely removed** just before the script finishes.
