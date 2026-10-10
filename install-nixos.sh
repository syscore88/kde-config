#!/usr/bin/env bash
# ==========================================================
# SKRYPT KONFIGURACYJNY KDE PLASMA NIXOS
# ==========================================================

set -Eeuo pipefail
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/kde-install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
    if [ "$exit_code" -eq 0 ] && [ "${DO_REBOOT:-0}" = "1" ]; then
        sudo systemctl reboot
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
_log_write() {
    echo -e "$1"
    echo -e "$1" >&3
}
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    local bar_width=50
    local reserved=12
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 1))}…"
    fi

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ $filled -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ $empty -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
}

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    MSG_PREP="Przygotowywanie..."
    MSG_COPY="Kopiowanie plików..."
    MSG_CONFIG="Konfiguracja NixOS..."
    MSG_REBUILD="Przebudowa systemu (to może potrwać)..."
    MSG_OPTIMIZE="Optymalizacja..."
    MSG_FINALIZE="Finalizowanie..."
else
    MSG_PREP="Preparing..."
    MSG_COPY="Copying files..."
    MSG_CONFIG="Configuring NixOS..."
    MSG_REBUILD="Rebuilding system (this may take a while)..."
    MSG_OPTIMIZE="Optimization..."
    MSG_FINALIZE="Finalizing..."
fi

TOTAL_STEPS=8

CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="/etc/nixos"
CONF="$NIXOS_DIR/configuration.nix"
GRAPHICS_DIR="$NIXOS_DIR/images"
GRAPHICS_FILES=(login-wallpaper.png piwo.png)

if [[ "$EUID" -eq 0 ]]; then
    echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    exit 1
fi

# ==========================================================
# 1. WSTĘPNE SPRAWDZENIA I UPRAWNIENIA
# ==========================================================
printf '\033[?7h' >&3

if ! grep -qx 'ID=nixos' /etc/os-release 2>/dev/null; then
    log_err "Ten skrypt działa tylko na NixOS." "This script works on NixOS only."
    exit 1
fi

if [[ ! -f "$CONF" ]]; then
    log_err "Nie znaleziono $CONF." "Could not find $CONF."
    exit 1
fi

sudo -v

(
    set +e
    trap - ERR
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
    done
) &
SUDO_KEEPALIVE_PID=$!

printf '\033[?7l' >&3

show_progress 0 $TOTAL_STEPS "$MSG_PREP"
show_progress 1 $TOTAL_STEPS "$MSG_PREP"

# ==========================================================
# 2. KOPIOWANIE PLIKÓW GRAFICZNYCH DO /etc/nixos/images
# ==========================================================
show_progress 2 $TOTAL_STEPS "$MSG_COPY"

sudo install -d -m 755 "$GRAPHICS_DIR"
for f in "${GRAPHICS_FILES[@]}"; do
    if [[ -f "$SCRIPT_DIR/$f" ]]; then
        sudo install -m 644 "$SCRIPT_DIR/$f" "$GRAPHICS_DIR/$f"
    else
        log_warn "Brak pliku $f obok skryptu - pomijam." \
                 "File $f not found next to the script - skipping."
    fi
done

# ==========================================================
# 3. USTAWIENIA DO configuration.nix
# ==========================================================
show_progress 3 $TOTAL_STEPS "$MSG_CONFIG"

BACKUP="$CONF.bak-$(date +%Y%m%d_%H%M%S)"
sudo cp -a "$CONF" "$BACKUP"

BLOCK_TMP="$(mktemp)"
cat > "$BLOCK_TMP" <<'NIXMODULE_EOF'
  # --- install.sh: BEGIN (blok jest nadpisywany przy ponownym uruchomieniu skryptu) ---
  # Sterowniki graficzne
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Włącza 32-bitowe sterowniki graficzne
  };

  programs.dconf.enable = true;

  # Włączenie usługi geolokalizacji Geoclue2
  services.geoclue2.enable = true;

  # Włączenie modułu vhba, demona cdemu oraz klienta graficznego/CLI
  programs.cdemu.enable = true;

  # Obsługa Bluetooth i dodatkowych systemów plików
  hardware.bluetooth.enable = true;
  boot.supportedFilesystems = [ "ntfs" "exfat" "btrfs" ];

  # DNS Cloudflare (z blokowaniem złośliwych domen)
  networking.nameservers = [
    "1.1.1.2"
    "1.0.0.2"
    "2606:4700:4700::1112"
    "2606:4700:4700::1002"
  ];
  # NetworkManager (Plasma) inaczej nadpisałby DNS-y z DHCP
  networking.networkmanager.insertNameservers = [
    "1.1.1.2"
    "1.0.0.2"
    "2606:4700:4700::1112"
    "2606:4700:4700::1002"
  ];

  # Menedżer logowania Plasma Login Manager
  services.displayManager.plasma-login-manager.enable = true;

  # Tapeta ekranu logowania (plik kopiowany niżej do stałej ścieżki)
  services.displayManager.plasma-login-manager.settings = {
    "Greeter][Wallpaper][org.kde.image][General" = {
      Image = "file:///usr/share/wallpapers/login-wallpaper.png";
    };
  };

  # Automatyczne kopiowanie tapety ekranu logowania i awatara z /etc/nixos/images (wgrywa je install.sh)
  # tylko przy przebudowie systemu (nixos-rebuild switch lub test), nie przy każdym starcie systemu.
  # Nazwa użytkownika i katalog domowy są brane z konfiguracji systemu. Brakujące pliki są pomijane.
  system.activationScripts.copyGraphicsFiles = {
    deps = [ "users" ];
    text = ''
      if [ "''${NIXOS_ACTION:-}" = switch ] || [ "''${NIXOS_ACTION:-}" = test ]; then
      SOURCE_DIR="/etc/nixos/images"
      copy_file() { if [ -f "$SOURCE_DIR/$1" ]; then install -Dm644 "$SOURCE_DIR/$1" "$2"; fi; }

      # Tapeta ekranu logowania i awatar (systemowe)
      copy_file login-wallpaper.png /usr/share/wallpapers/login-wallpaper.png
      copy_file piwo.png /usr/share/plasma/avatars/piwo.png
    '' + builtins.concatStringsSep "\n" (map (u: ''
      # Użytkownik: ${u.name}
      copy_file piwo.png /var/lib/AccountsService/icons/${u.name}
      if [ -f "$SOURCE_DIR/piwo.png" ]; then
        ACCOUNTS_FILE="/var/lib/AccountsService/users/${u.name}"
        install -d /var/lib/AccountsService/users
        if [ ! -f "$ACCOUNTS_FILE" ]; then
          printf '[User]\nIcon=/var/lib/AccountsService/icons/${u.name}\n' > "$ACCOUNTS_FILE"
          chmod 600 "$ACCOUNTS_FILE"
        elif grep -q '^Icon=' "$ACCOUNTS_FILE"; then
          sed -i 's|^Icon=.*|Icon=/var/lib/AccountsService/icons/${u.name}|' "$ACCOUNTS_FILE"
        else
          echo 'Icon=/var/lib/AccountsService/icons/${u.name}' >> "$ACCOUNTS_FILE"
        fi
      fi
    '') (builtins.filter (u: u.isNormalUser) (builtins.attrValues config.users.users))) + ''
      fi
    '';
  };

  # Ustawienie tapety pulpitu i ekranu blokady przy logowaniu z ~/.local/share/wallpapers
  # (pliki wallpaper.jpg i lock_screen.jpg kopiuje tam install.sh razem z katalogiem .local; ponowne ustawienie po ich zmianie)
  environment.etc."xdg/autostart/force-wallpaper.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Force Wallpaper
    Exec=${pkgs.writeShellScript "force-wallpaper" ''
      DIR="$HOME/.local/share/wallpapers"
      [ -f "$DIR/wallpaper.jpg" ] || exit 0
      MARKER="$HOME/.local/state/wallpaper-applied"
      STAMP="$(cksum "$DIR/wallpaper.jpg" "$DIR/lock_screen.jpg" 2>/dev/null)"
      [ "$(cat "$MARKER" 2>/dev/null)" = "$STAMP" ] && exit 0
      for i in $(seq 1 30); do
        if plasma-apply-wallpaperimage "$DIR/wallpaper.jpg"; then
          [ -f "$DIR/lock_screen.jpg" ] && kwriteconfig6 --file kscreenlockerrc \
            --group Greeter --group Wallpaper --group org.kde.image --group General \
            --key Image "file://$DIR/lock_screen.jpg"
          mkdir -p "$(dirname "$MARKER")" && echo "$STAMP" > "$MARKER"
          break
        fi
        sleep 2
      done
    ''}
    NoDisplay=true
  '';

  # Plymouth - ekran startowy
  boot.plymouth = {
    enable = true;
    theme = "bgrt"; # Używa logo producenta płyty głównej (UEFI)
  };

  # Ciche uruchamianie, żeby Plymouth nie był zasłaniany komunikatami
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "udev.log_level=3"
    "systemd.show_status=auto"
  ];

  # Ukrycie menu systemd-boot (menu pokaże się po przytrzymaniu Spacji/Shift przy starcie)
  boot.loader.timeout = pkgs.lib.mkDefault 0;
  boot.loader.systemd-boot.enable = pkgs.lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = pkgs.lib.mkDefault true;

  # Zostaw tylko 2 najnowsze generacje systemu w menu startowym
  boot.loader.systemd-boot.configurationLimit = pkgs.lib.mkDefault 2;

  # Automatyczne usuwanie starych generacji (zostają 2 najnowsze)
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-generations +2";
  };

  environment.systemPackages = with pkgs; [
    # --- Narzędzia i Aplikacje ---
    flatseal
    dconf-editor
    steam-run
    brave-origin
    google-chrome
    firefox
    faugus-launcher
    kdePackages.ghostwriter
    libreoffice-qt
    hunspellDicts.pl_PL
    gimp
    krita
    krita-plugin-gmic
    discord
    telegram-desktop
    qbittorrent
    audacity
    handbrake
    kdePackages.kdenlive
    soundconverter
    mixxx
    qmmp
    vlc
    opencode
    ventoy
    wine-staging
    winetricks
    mangohud
    gamemode
    gamescope
    vkd3d
    lsfg-vk-ui

    # --- System, Dyski & Wygoda ---
    kdePackages.partitionmanager
    timeshift
    bleachbit
    fastfetch
    inxi
    rsync
    pv
    zenity
    btrfs-progs
    fwupd
    p7zip
    unrar
    unzip
    wget
    curl
    mc
    vim
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting

    # --- Deweloperka & Kompilacja ---
    git
    patch
    stdenv.cc
    gcc
    clang
    llvm
    gnumake
    cmake
    meson
    ninja
    pkg-config
    binutils
    coreutils
  ];

  # Zezwolenie na pakiety unfree (Chrome, Discord itd.)
  nixpkgs.config.allowUnfree = true;

  # Optymalizacja pod gry
  programs.gamemode.enable = true;

  # Wirtualizacja (Virt-Manager)
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  security.polkit.enable = true;

  # Przypisanie użytkownika do grupy libvirtd
  users.users.__INSTALL_USER__.extraGroups = [ "libvirtd" ];

  # Obsługa Flatpak
  services.flatpak.enable = true;

  # Wykluczenia domyślnych pakietów z KDE Plasma
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
    elisa
    kwalletmanager
    plasma-vault
    plasma-browser-integration
    krdp
    krfb
  ];
  # --- install.sh: END ---
NIXMODULE_EOF
sed -i "s/__INSTALL_USER__/$CURRENT_USER/g" "$BLOCK_TMP"

# Usunięcie poprzedniego bloku (jeśli skrypt był już uruchamiany)
sudo sed -i '/install\.sh: BEGIN/,/install\.sh: END/d' "$CONF"

# Wstawienie bloku przed ostatnim nawiasem zamykającym }
LAST_BRACE_LINE="$(grep -n '^}' "$CONF" | tail -n 1 | cut -d: -f1)"
if [[ -z "$LAST_BRACE_LINE" ]]; then
    rm -f "$BLOCK_TMP"
    log_err "Nie znaleziono końca konfiguracji (}) w $CONF." \
            "Could not find the closing brace (}) in $CONF."
    exit 1
fi
sudo sed -i "$((LAST_BRACE_LINE - 1))r $BLOCK_TMP" "$CONF"
rm -f "$BLOCK_TMP"

# ==========================================================
# 4. PRZEBUDOWA SYSTEMU
# ==========================================================
show_progress 4 $TOTAL_STEPS "$MSG_REBUILD"

if ! sudo nixos-rebuild switch; then
    sudo cp -af "$BACKUP" "$CONF"
    log_err "Przebudowa systemu nie powiodła się. Przywrócono configuration.nix z kopii: $BACKUP" \
            "System rebuild failed. configuration.nix restored from backup: $BACKUP"
    exit 1
fi

show_progress 5 $TOTAL_STEPS "$MSG_REBUILD"

# ==========================================================
# 5. KONFIGURACJA WIZUALNA (KONTO UŻYTKOWNIKA)
# ==========================================================
show_progress 6 $TOTAL_STEPS "$MSG_OPTIMIZE"

systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
kquitapp6 plasmashell 2>/dev/null || pkill -9 -x plasmashell 2>/dev/null || true
sleep 2

mkdir -p ~/.config ~/.local ~/.icons
if [[ -d "$SCRIPT_DIR/.config" ]]; then cp -af "$SCRIPT_DIR/.config/." ~/.config/; fi
if [[ -d "$SCRIPT_DIR/.local" ]]; then cp -af "$SCRIPT_DIR/.local/." ~/.local/; fi
if [[ -d "$SCRIPT_DIR/.icons" ]]; then cp -af "$SCRIPT_DIR/.icons/." ~/.icons/; fi

show_progress 7 $TOTAL_STEPS "$MSG_OPTIMIZE"

rm -rf ~/.cache/icon-cache.kcache ~/.cache/plasma* ~/.cache/ico*

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental &>/dev/null || true
fi

# ==========================================================
# 6. ZAKOŃCZENIE
# ==========================================================
show_progress 8 $TOTAL_STEPS "$MSG_FINALIZE"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

DO_REBOOT=1
exit 0
