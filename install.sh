#!/bin/bash
# ========================================
#  KOMPLEKSOWY SKRYPT KONFIGURACYJNY Arch
# ========================================

set -Eeuo pipefail
export PATH="/usr/sbin:/sbin:$PATH"

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl* ]]; then
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

TMP_LOG="$(mktemp /tmp/install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    declare -F restore_packagekit >/dev/null && restore_packagekit || true
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ] || [ "${#FAILED_PACKAGES[@]}" -gt 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [ "$exit_code" -ne 0 ]; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${ERR}[X] Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${ERR}[X] An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
            fi
        fi
    fi
    rm -f "$TMP_LOG"
    local do_reboot=0
    [ "$exit_code" -eq 0 ] && [ "${DO_REBOOT:-0}" = "1" ] && do_reboot=1
    if [ "${SUDO_READY:-0}" = "1" ]; then
        sudo sh -c 'rm -f "$1" "$2"; systemctl try-restart polkit 2>/dev/null; if [ "$3" = 1 ]; then systemctl reboot; fi' _ \
            "${RUN0_NOPASSWD_FILE:-/etc/polkit-1/rules.d/51-run0-nopasswd.rules}" \
            "/etc/sudoers.d/99-temp-installer" \
            "$do_reboot"
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
_log_write() { printf "\r\033[K" >&3; echo -e "$1" >&3; echo -e "$1"; cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${SUCCESS}[OK] $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${ERR}[X] ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${WARN}[!] WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

# ==========================================================
# PACKAGEKIT + BLOKADA MENEDŻERA PAKIETÓW
# ==========================================================
PACKAGEKIT_MASKED=0
PACKAGEKIT_UNITS=(packagekit.service packagekit-offline-update.service)

disable_packagekit() {
    [[ "${PACKAGEKIT_MASKED:-0}" -eq 1 ]] && return 0
    sudo systemctl stop "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    if command -v killall >/dev/null 2>&1; then
        sudo killall -q packagekitd 2>/dev/null || true
    else
        sudo pkill -x packagekitd 2>/dev/null || true
    fi
    sudo systemctl mask "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    PACKAGEKIT_MASKED=1
}

restore_packagekit() {
    [[ "${PACKAGEKIT_MASKED:-0}" -eq 1 ]] || return 0
    sudo systemctl unmask "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    PACKAGEKIT_MASKED=0
}

_pkg_lock_busy() {
    local f
    for f in /var/lib/pacman/db.lck; do
        [[ -e "$f" ]] || continue
        sudo fuser "$f" >/dev/null 2>&1 && return 0
    done
    pgrep -x 'pacman|packagekitd' >/dev/null 2>&1 && return 0
    return 1
}

wait_for_pacman_lock() {
    local timeout="${1:-300}" waited=0
    disable_packagekit
    while _pkg_lock_busy; do
        if (( waited >= timeout )); then
            log_warn "Blokada menedżera pakietów trwa ponad ${timeout}s - kontynuuję mimo to." \
                     "Package manager lock held for over ${timeout}s - continuing anyway."
            break
        fi
        sleep 3
        waited=$(( waited + 3 ))
    done
}

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(stty size </dev/tty 2>/dev/null || true)
    cols="${cols##* }"
    [[ "$cols" =~ ^[0-9]+$ ]] && (( cols > 0 )) || cols=80

    local bar_width=50
    local reserved=14
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 3))}..."
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
    MSG_PHASE_1="[1/4] Przygotowywanie..."
    MSG_PHASE_2="[2/4] Instalacja..."
    MSG_PHASE_3="[3/4] Optymalizacja..."
    MSG_PHASE_4="[4/4] Finalizowanie..."
else
    MSG_PHASE_1="[1/4] Preparing..."
    MSG_PHASE_2="[2/4] Installing..."
    MSG_PHASE_3="[3/4] Optimizing..."
    MSG_PHASE_4="[4/4] Finalizing..."
fi

TOTAL_STEPS=12
FAILED_PACKAGES=()

if [[ "$EUID" -eq 0 ]]; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERR}[X] Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    else
        echo -e "${ERR}[X] Do not run this script as root. Run as a normal user with sudo.${NC}" >&3
    fi
    exit 1
fi

CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf '\033[?7h\n' >&3

RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if ! command -v visudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

SUDO_READY=0
if [[ "$USE_RUN0" -eq 1 ]]; then
    sudo tee "$RUN0_NOPASSWD_FILE" > /dev/null << EOF
polkit.addRule(function(action, subject) {
    if (subject.user == "$CURRENT_USER") {
        return polkit.Result.YES;
    }
});
EOF
    sudo systemctl try-restart polkit 2>/dev/null || true
    SUDO_READY=1
else
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

    SUDOERS_TMP="$(mktemp)"
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
    if sudo visudo -cf "$SUDOERS_TMP" &>/dev/null; then
        sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
        echo "%wheel ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
        sudo visudo -cf "$SUDOERS_TMP" &>/dev/null && sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99_nopasswd || true
    else
        rm -f "$SUDOERS_TMP"
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}[X] Nieprawidłowa składnia pliku sudoers – przerywam.${NC}" >&3
        else
            echo -e "${ERR}[X] Invalid sudoers rule syntax - aborting.${NC}" >&3
        fi
        exit 1
    fi
    rm -f "$SUDOERS_TMP"
    SUDO_READY=1
fi

printf '\033[?7l' >&3

# =============================================================
#  ETAP 1/4: PRZYGOTOWYWANIE
# =============================================================
show_progress 0 $TOTAL_STEPS "$MSG_PHASE_1"

disable_packagekit

pkg_installed() {
    pacman -Qq "$1" &>/dev/null
}

install_pacman_pkgs() {
    wait_for_pacman_lock
    local valid_pkgs=()
    for pkg in "$@"; do
        pkg_installed "$pkg" && continue
        if pacman -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        else
            FAILED_PACKAGES+=("$pkg")
        fi
    done
    for pkg in "${valid_pkgs[@]}"; do
        sudo pacman -S --noconfirm --needed "$pkg" || FAILED_PACKAGES+=("$pkg")
    done
}

install_yay_pkgs() {
    wait_for_pacman_lock
    local valid_pkgs=()
    for pkg in "$@"; do
        pkg_installed "$pkg" && continue
        if yay -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        else
            FAILED_PACKAGES+=("$pkg")
        fi
    done
    for pkg in "${valid_pkgs[@]}"; do
        yay -S --noconfirm --needed "$pkg" || FAILED_PACKAGES+=("$pkg")
    done
}

retry_cmd() {
    local attempts="$1"; shift
    local delay=3
    local n=1
    until "$@"; do
        if (( n >= attempts )); then
            return 1
        fi
        sleep "$delay"
        delay=$(( delay * 2 ))
        n=$(( n + 1 ))
    done
}

install_pacman_pkgs dconf pciutils curl

GPU_TYPE="unknown"
HYBRID_GPU=false
GPU_VENDORS=()
GPU_UNKNOWN_PKGS=(
    mesa lib32-mesa vulkan-mesa-layers lib32-vulkan-mesa-layers
    vulkan-icd-loader lib32-vulkan-icd-loader opencl-mesa lib32-opencl-mesa
    vulkan-dzn vulkan-gfxstream vulkan-swrast lib32-vulkan-swrast
)
if command -v lspci &>/dev/null; then
    GPU_INFO=$(lspci | grep -i -E "vga|3d|display" || true)

    echo "$GPU_INFO" | grep -qi "nvidia"      && GPU_VENDORS+=("nvidia")
    echo "$GPU_INFO" | grep -qi -E "\b(amd|ati)\b|advanced micro devices|radeon" && GPU_VENDORS+=("amd")
    echo "$GPU_INFO" | grep -qi "intel"       && GPU_VENDORS+=("intel")

    TOTAL_KNOWN=${#GPU_VENDORS[@]}

    if [ -z "$GPU_INFO" ] || [ "$TOTAL_KNOWN" -eq 0 ]; then
        HYBRID_GPU=false
        install_pacman_pkgs "${GPU_UNKNOWN_PKGS[@]}"
    elif [ "$TOTAL_KNOWN" -ge 2 ]; then
        HYBRID_GPU=true
        GPU_TYPE="$(IFS=+; echo "${GPU_VENDORS[*]}")"
        log_info "Wykryto hybrydowy układ graficzny (HYBRID_GPU=$HYBRID_GPU): $GPU_TYPE" "Detected a hybrid GPU setup (HYBRID_GPU=$HYBRID_GPU): $GPU_TYPE"
    else
        HYBRID_GPU=false
        GPU_TYPE="${GPU_VENDORS[0]}"
    fi
else
    install_pacman_pkgs "${GPU_UNKNOWN_PKGS[@]}"
fi

if [ -f "$SCRIPT_DIR/.update.sh" ]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

if [ -d "$SCRIPT_DIR/.local" ]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
fi

if [ -d "$SCRIPT_DIR/.config" ]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
fi

show_progress 1 $TOTAL_STEPS "$MSG_PHASE_1"

TO_REMOVE=(
htop konqueror plasma-browser-integration plasma-vault
kontact kmail kontrast plasma-welcome imagemagick
kaddressbook kdepim-runtime akonadi akregator korganizer 
gnome-software epiphany decibels rhythmbox showtime cosmic-store
cosmic-player parole gnome-calendar gnome-clocks gnome-music
gnome-user-docs gnome-contacts gnome-maps gnome-weather evolution
evolution-ews evolution-bogofilter evolution-spamassassin evolution-data-server 
kwalletmanager elisa dragon transmission-gtk exaile mpv juk yelp
totem pragha transmission-qt discover "evolution*"
)
wait_for_pacman_lock
INSTALLED_PACKAGES=$(pacman -Qq "${TO_REMOVE[@]}" 2>/dev/null || true)
for pkg in $INSTALLED_PACKAGES; do
    sudo pacman -Rs --noconfirm "$pkg" 2>/dev/null || true
done

if pacman -Qq plasma-desktop &>/dev/null || pacman -Qq plasma-workspace &>/dev/null; then
    mkdir -p ~/.config
    cat > ~/.config/kwalletrc << 'EOF'
[Wallet]
Close When Idle=false
Close on Screensaver=false
Default Wallet=kdewallet
Enabled=false
First Use=false
Idle Timeout=10
Launch Manager=false
Leave Manager Open=false
Leave Open=true
Prompt on Open=false
Use One Wallet=true

[org.freedesktop.secrets]
apiEnabled=false
EOF
fi
rm -rf ~/.config/akonadi* ~/.config/kmail* ~/.config/kontact* ~/.config/korganizer* ~/.config/kaddressbook* ~/.config/akregator* ~/.config/emailidentities ~/.config/mailtransports
rm -rf ~/.cache/akonadi* ~/.cache/kmail* ~/.cache/kontact* ~/.cache/korganizer* ~/.cache/kaddressbook* ~/.cache/akregator* ~/.cache/konqueror*
rm -rf ~/.local/share/{gnome-software,epiphany,decibels,rhythmbox,showtime,parole,evolution,gnome-calendar,gnome-clocks,gnome-music,gnome-contacts,gnome-maps,gnome-weather,yelp,dragonplayer,elisa,cosmic-store,cosmic-player,pragha,transmission,totem,exaile,mpv,juk}
rm -rf ~/.config/{gnome-software,epiphany,decibels,rhythmbox,showtime,parole,gnome-calendar,evolution,gnome-clocks,gnome-music,gnome-contacts,gnome-maps,gnome-weather,yelp,dragonplayer,elisa,cosmic-store,cosmic-player,pragha,transmission,totem,exaile,mpv,juk}
rm -rf ~/.cache/{gnome-software,epiphany,decibels,rhythmbox,showtime,parole,gnome-calendar,evolution,gnome-clocks,gnome-music,gnome-contacts,gnome-maps,gnome-weather,yelp,dragonplayer,elisa,cosmic-store,cosmic-player,pragha,transmission,totem,exaile,mpv,juk}

show_progress 2 $TOTAL_STEPS "$MSG_PHASE_1"

sudo sed -i 's/^#[[:space:]]*Color/Color/' /etc/pacman.conf
if ! grep -qw "ILoveCandy" /etc/pacman.conf; then
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
fi
sudo sed -i 's/^[[:space:]]*CheckSpace/#CheckSpace/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

if ! grep -q "NoExtract = usr/share/locale" /etc/pacman.conf; then
    sudo sed -i '/^\[options\]/a NoExtract = usr/share/locale/* !usr/share/locale/pl* !usr/share/locale/en*\nNoExtract = usr/share/cups/doc/*' /etc/pacman.conf
fi
if ! grep -q "NoExtract = usr/share/man" /etc/pacman.conf; then
    sudo sed -i '/NoExtract = usr\/share\/cups\/doc/a NoExtract = usr/share/man/*\nNoExtract = usr/share/doc/*\nNoExtract = usr/share/info/*\nNoExtract = usr/share/gtk-doc/*\nNoExtract = usr/share/help/*' /etc/pacman.conf
fi
install_pacman_pkgs cups

sudo mkdir -p /etc/NetworkManager/conf.d
echo -e "[main]\ndns=default\nrc-manager=symlink" | sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null
echo -e "[global-dns]\n\n[global-dns-domain-*]\nservers=1.1.1.2,1.0.0.2,2606:4700:4700::1112,2606:4700:4700::1002" | sudo tee /etc/NetworkManager/conf.d/global-dns.conf > /dev/null

ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" ipv4.dns "1.1.1.2,1.0.0.2" ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002"
    sudo nmcli connection up "$ACTIVE_CONN" || true
fi

show_progress 3 $TOTAL_STEPS "$MSG_PHASE_1"

# =============================================================
#  ETAP 2/4: INSTALACJA
# =============================================================
show_progress 4 $TOTAL_STEPS "$MSG_PHASE_2"

wait_for_pacman_lock
sudo pacman -Syu --noconfirm || true

show_progress 5 $TOTAL_STEPS "$MSG_PHASE_2"

SYSTEM_PKGS=(
    base-devel git zsh pacman-contrib fastfetch reflector
    gcc clang llvm make cmake meson ninja just firefox firefox-i18n-pl    
    python-pip python-tqdm python-defusedxml python-packaging
    partitionmanager bleachbit unrar mc btrfs-progs exfat-utils ntfs-3g os-prober
    fsarchiver inxi pv rsync 7zip zenity innoextract android-tools dnsmasq vde2
    plymouth profile-sync-daemon ananicy-cpp dconf-editor geoclue fwupd fwupd-efi
    bluez-obex appmenu-gtk-module libayatana-appindicator flatpak timeshift
    zsh-syntax-highlighting zsh-autosuggestions ghostwriter
    vlc vlc-plugins-all libappimage handbrake xorg-xhost
    gimp gmic gimp-plugin-gmic cdemu-client cdemu-daemon vhba-module
    audacity qmmp mixxx kdenlive soundconverter
    discord telegram-desktop qbittorrent
    libreoffice-fresh libreoffice-fresh-pl hunspell-pl krita
    wine-staging winetricks gamemode gamescope mangohud vkd3d
    virt-manager qemu-desktop libvirt edk2-ovmf
    qt6-base qt6-declarative
)

PKGS_32BIT=(
    lib32-libxrandr lib32-libxrender lib32-gamemode lib32-vkd3d
    lib32-alsa-plugins lib32-libpulse lib32-mangohud lib32-pipewire
)

PKGS_CODECS=(
    gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav ffmpeg x264
)

for vendor in "${GPU_VENDORS[@]}"; do
    case "$vendor" in
        "nvidia") SYSTEM_PKGS+=(libva-nvidia-driver lib32-nvidia-utils opencl-nvidia mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader vulkan-dzn vulkan-gfxstream vulkan-swrast lib32-vulkan-swrast) ;;
        "amd")    SYSTEM_PKGS+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon lib32-vulkan-mesa-layers lib32-mesa-utils vulkan-icd-loader lib32-vulkan-icd-loader opencl-mesa vulkan-dzn vulkan-gfxstream vulkan-swrast lib32-vulkan-swrast) ;;
        "intel")  SYSTEM_PKGS+=(intel-media-driver mesa lib32-mesa vulkan-intel lib32-vulkan-intel lib32-vulkan-mesa-layers lib32-mesa-utils vulkan-icd-loader lib32-vulkan-icd-loader intel-compute-runtime vulkan-dzn vulkan-gfxstream vulkan-swrast lib32-vulkan-swrast) ;;
    esac
done

if [ "${#GPU_VENDORS[@]}" -gt 0 ]; then
    readarray -t SYSTEM_PKGS < <(printf '%s\n' "${SYSTEM_PKGS[@]}" | awk '!seen[$0]++')
fi

install_pacman_pkgs "${SYSTEM_PKGS[@]}"
install_pacman_pkgs "${PKGS_32BIT[@]}"
install_pacman_pkgs "${PKGS_CODECS[@]}"

sudo depmod -a &>/dev/null || true

sudo systemctl disable --now cdemu-daemon 2>/dev/null || true
sudo systemctl mask cdemu-daemon 2>/dev/null || true
mkdir -p "$HOME/.config/autostart"
for f in /etc/xdg/autostart/gcdemu.desktop /etc/xdg/autostart/cdemu.desktop /usr/share/applications/gcdemu.desktop; do
    if [[ -f "$f" ]]; then
        cp -f "$f" "$HOME/.config/autostart/$(basename "$f")"
        if grep -q '^Hidden=' "$HOME/.config/autostart/$(basename "$f")"; then
            sed -i 's/^Hidden=.*/Hidden=true/' "$HOME/.config/autostart/$(basename "$f")"
        else
            echo "Hidden=true" >> "$HOME/.config/autostart/$(basename "$f")"
        fi
    fi
done
pkill -f gcdemu 2>/dev/null || true

show_progress 6 $TOTAL_STEPS "$MSG_PHASE_2"

if command -v flatpak &>/dev/null; then
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    sudo flatpak update --appstream || true
    flatpak info com.github.tchx84.Flatseal &>/dev/null || sudo flatpak install -y flathub com.github.tchx84.Flatseal || true
    flatpak info it.mijorus.gearlever &>/dev/null || sudo flatpak install -y flathub it.mijorus.gearlever || true
fi

show_progress 7 $TOTAL_STEPS "$MSG_PHASE_2"

if ! command -v yay &>/dev/null; then
    sudo timedatectl set-ntp true &>/dev/null || true

    rm -rf /tmp/yay
    if ! retry_cmd 5 git clone https://aur.archlinux.org/yay.git /tmp/yay; then
        rm -rf /tmp/yay
        mkdir -p /tmp/yay
        if ! retry_cmd 5 curl -4 -fsSL \
            "https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz" \
            -o /tmp/yay.tar.gz; then
            exit 1
        fi
        tar -xzf /tmp/yay.tar.gz -C /tmp/yay --strip-components=1
        rm -f /tmp/yay.tar.gz
    fi
    (cd /tmp/yay && makepkg -si --noconfirm) || true
    rm -rf /tmp/yay
fi

yay --save --cleanafter --cleanmenu=false --diffmenu=false --editmenu=false || true

AUR_PKGS=(ventoy-bin google-chrome brave-origin-bin faugus-launcher-bin opencode-desktop-bin shelly-flatpak-backend-bin dmemcg-booster needrestart makeself lsfg-vk-bin)
install_yay_pkgs "${AUR_PKGS[@]}"

show_progress 8 $TOTAL_STEPS "$MSG_PHASE_2"

# =============================================================
#  ETAP 3/4: OPTYMALIZACJA
# =============================================================
show_progress 9 $TOTAL_STEPS "$MSG_PHASE_3"

restore_packagekit

CMDLINE="quiet splash loglevel=3 systemd.show_status=false rd.udev.log_level=3 vt.global_cursor_default=0 plymouth.ignore-serial-consoles mitigations=off split_lock_detect=off"
[[ $GPU_TYPE == *"nvidia"* ]] && CMDLINE="$CMDLINE nvidia_drm.modeset=1"

BOOT_METHODS_FOUND=()

declare -a LOADER_ROOTS=()
if command -v bootctl &>/dev/null; then
    for p in "$(bootctl --print-esp-path 2>/dev/null || true)" \
             "$(bootctl --print-boot-path 2>/dev/null || true)"; do
        [ -n "$p" ] && [ -d "$p" ] && LOADER_ROOTS+=("$p")
    done
fi
for p in /boot /efi /boot/efi; do
    [ -d "$p" ] && LOADER_ROOTS+=("$p")
done

if [ ${#LOADER_ROOTS[@]} -gt 0 ]; then
    readarray -t LOADER_ROOTS < <(printf '%s\n' "${LOADER_ROOTS[@]}" | awk '!seen[$0]++')
fi

broot_f() { sudo test -f "$1" 2>/dev/null; }
broot_d() { sudo test -d "$1" 2>/dev/null; }
sgrep() { sudo grep "$@" 2>/dev/null; }
broot_glob_first() { sudo find "$1" -maxdepth 1 -iname "$2" -print -quit 2>/dev/null; }

UKI_EFI_FOUND=false
for r in "${LOADER_ROOTS[@]}"; do
    if [ -n "$(broot_glob_first "$r/EFI/Linux" '*.efi')" ]; then
        UKI_EFI_FOUND=true
        break
    fi
done
if [ -f /etc/kernel/cmdline ] && \
   { sgrep -rlq '_uki=' /etc/mkinitcpio.d/*.preset 2>/dev/null || \
     [ "$UKI_EFI_FOUND" = true ]; }; then
    BOOT_METHODS_FOUND+=("uki")
    if ! sgrep -qw "splash" /etc/kernel/cmdline; then
        sudo sed -i "s/\$/ $CMDLINE/" /etc/kernel/cmdline
        sudo sed -i 's/  */ /g'       /etc/kernel/cmdline
    fi
fi

SYSTEMD_BOOT_DETECTED=false
for r in "${LOADER_ROOTS[@]}"; do
    broot_f "$r/loader/loader.conf" && SYSTEMD_BOOT_DETECTED=true
done
if command -v bootctl &>/dev/null && [ "$SYSTEMD_BOOT_DETECTED" = true ]; then
    BOOT_METHODS_FOUND+=("systemd-boot")
    for loader_root in "${LOADER_ROOTS[@]}"; do
        if broot_d "$loader_root/loader/entries"; then
            if broot_f "$loader_root/loader/loader.conf"; then
                if sgrep -q '^timeout ' "$loader_root/loader/loader.conf"; then
                    sudo sed -i 's/^timeout .*/timeout 0/' "$loader_root/loader/loader.conf"
                else
                    echo "timeout 0" | sudo tee -a "$loader_root/loader/loader.conf" >/dev/null
                fi
            fi

            for entry in $(sudo find "$loader_root/loader/entries" -maxdepth 1 -iname '*.conf' 2>/dev/null); do
                if ! sgrep -qw "splash" "$entry"; then
                    sudo sed -i "/^options/ s/\$/ $CMDLINE/" "$entry"
                    sudo sed -i 's/  */ /g' "$entry"
                fi
            done
        fi
    done
    sudo bootctl set-timeout 0 &>/dev/null || true
fi

if [ -f /etc/default/grub ] && command -v grub-mkconfig &>/dev/null; then
    BOOT_METHODS_FOUND+=("grub")
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"|" \
        /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
fi

# --- Limine ---
declare -a LIMINE_CONFS=()
for candidate in /boot/limine.conf /efi/limine.conf \
                  /boot/EFI/Limine/limine.conf /efi/EFI/Limine/limine.conf \
                  /boot/EFI/BOOT/limine.conf /efi/EFI/BOOT/limine.conf \
                  /boot/limine.cfg /efi/limine.cfg; do
    broot_f "$candidate" && LIMINE_CONFS+=("$candidate")
done

patch_one_limine_conf() {
    local f="$1"
    broot_f "$f" || return 0
    if [[ "$f" == *.conf ]]; then
        if sgrep -qiE '^timeout:' "$f"; then
            sudo sed -i -E 's/^timeout:.*/timeout: 0/I' "$f"
        else
            sudo sed -i '1i timeout: 0' "$f"
        fi
        sudo sed -i -E "/^[[:space:]]*cmdline:/{/splash/!s/\$/ $CMDLINE/}" "$f"
    else
        if sgrep -qiE '^timeout=' "$f"; then
            sudo sed -i -E 's/^timeout=.*/TIMEOUT=0/I' "$f"
        else
            sudo sed -i '1i TIMEOUT=0' "$f"
        fi
        sudo sed -i -E "/^[[:space:]]*CMDLINE=/{/splash/!s/\$/ $CMDLINE/}" "$f"
    fi
    sudo sed -i 's/[[:space:]]\{2,\}/ /g' "$f"
}

patch_limine_conf() {
    local f
    for f in "${LIMINE_CONFS[@]}"; do
        patch_one_limine_conf "$f"
    done
    if [ ${#LIMINE_CONFS[@]} -gt 1 ]; then
        local src="${LIMINE_CONFS[0]}"
        for f in "${LIMINE_CONFS[@]:1}"; do
            [[ "$src" == *.conf && "$f" == *.conf ]] && sudo cp -f "$src" "$f" 2>/dev/null || true
        done
    fi
}

if [ ${#LIMINE_CONFS[@]} -gt 0 ]; then
    BOOT_METHODS_FOUND+=("limine")
    patch_limine_conf
fi

# --- rEFInd ---
REFIND_CONF=""
for candidate in /boot/EFI/refind/refind.conf /efi/EFI/refind/refind.conf \
                 /boot/refind_linux.conf /efi/refind_linux.conf; do
    broot_f "$candidate" && { REFIND_CONF="$candidate"; break; }
done
if [ -n "$REFIND_CONF" ]; then
    BOOT_METHODS_FOUND+=("refind")

    REFIND_MAIN_CONF=""
    for candidate in /boot/EFI/refind/refind.conf /efi/EFI/refind/refind.conf; do
        broot_f "$candidate" && { REFIND_MAIN_CONF="$candidate"; break; }
    done
    if [ -n "$REFIND_MAIN_CONF" ]; then
        if sgrep -qE '^timeout[[:space:]]' "$REFIND_MAIN_CONF"; then
            sudo sed -i -E 's/^timeout[[:space:]].*/timeout -1/' "$REFIND_MAIN_CONF"
        else
            echo "timeout -1" | sudo tee -a "$REFIND_MAIN_CONF" >/dev/null
        fi
    fi

    for rl_conf in /boot/refind_linux.conf /efi/refind_linux.conf \
                   /boot/EFI/Linux/refind_linux.conf /efi/EFI/Linux/refind_linux.conf; do
        broot_f "$rl_conf" || continue
        sudo sed -i -E "/splash/! s/^([[:space:]]*\"[^\"]*\"[[:space:]]+\")([^\"]*)\"[[:space:]]*\$/\\1\\2 ${CMDLINE}\"/" "$rl_conf"
    done
fi

# --- EFISTUB ---
EFISTUB_FOUND=false
if command -v efibootmgr &>/dev/null; then
    re_boot_line='^Boot([0-9A-Fa-f]{4})\*?[[:space:]]*(.*)$'
    re_file_node='/File\(([^)]*)\)(.*)$'
    re_partuuid='GPT,([0-9A-Fa-f-]{36})'
    while IFS= read -r line; do
        [[ "$line" =~ $re_boot_line ]] || continue
        boot_num="${BASH_REMATCH[1]}"
        rest="${BASH_REMATCH[2]}"
        [[ "$rest" =~ $re_file_node ]] || continue
        loader_path="${BASH_REMATCH[1]}"
        cmdline_data="${BASH_REMATCH[2]}"
        [[ "$loader_path" == *.efi || "$loader_path" == *.EFI ]] && continue
        [[ "$loader_path" =~ [Vv][Mm][Ll][Ii][Nn][Uu][Zz] ]] || continue

        EFISTUB_FOUND=true

        if ! sgrep -qw "splash" <<<"$cmdline_data"; then
            partuuid=""
            [[ "$rest" =~ $re_partuuid ]] && partuuid="${BASH_REMATCH[1]}"
            label="${rest%%$'\t'*}"
            if [ -n "$partuuid" ] && command -v blkid &>/dev/null; then
                part_dev="$(blkid --match-token "PARTUUID=$partuuid" -o device 2>/dev/null || true)"
                if [ -n "$part_dev" ]; then
                    re_nvme_part='^(.*[0-9])p([0-9]+)$'
                    re_sata_part='^(.*[a-zA-Z])([0-9]+)$'
                    if [[ "$part_dev" =~ $re_nvme_part ]]; then
                        disk_dev="${BASH_REMATCH[1]}"; part_num="${BASH_REMATCH[2]}"
                    elif [[ "$part_dev" =~ $re_sata_part ]]; then
                        disk_dev="${BASH_REMATCH[1]}"; part_num="${BASH_REMATCH[2]}"
                    else
                        disk_dev=""; part_num=""
                    fi
                    if [ -n "$disk_dev" ] && [ -n "$part_num" ]; then
                        loader_path_bs="$(sed 's#/#\\#g' <<<"$loader_path")"
                        new_cmdline="$(sed 's/[[:space:]]*$//' <<<"$cmdline_data") $CMDLINE"
                        new_cmdline="$(sed 's/  */ /g' <<<"$new_cmdline")"
                        sudo efibootmgr -b "$boot_num" -B &>/dev/null || true
                        sudo efibootmgr -c -d "$disk_dev" -p "$part_num" \
                            -L "$label" -l "$loader_path_bs" -u "$new_cmdline" &>/dev/null || true
                    fi
                fi
            fi
        fi
    done < <(efibootmgr -v 2>/dev/null)
fi
[ "$EFISTUB_FOUND" = true ] && BOOT_METHODS_FOUND+=("efistub")

if [[ " ${BOOT_METHODS_FOUND[*]} " != *" systemd-boot "* ]] && \
   [[ " ${BOOT_METHODS_FOUND[*]} " != *" grub "* ]] && \
   [[ " ${BOOT_METHODS_FOUND[*]} " != *" limine "* ]] && \
   [[ " ${BOOT_METHODS_FOUND[*]} " != *" refind "* ]] && \
   command -v efibootmgr &>/dev/null; then
    sudo efibootmgr -t 0 &>/dev/null || true
fi
unset -f sgrep

show_progress 10 $TOTAL_STEPS "$MSG_PHASE_3"

sudo plymouth-set-default-theme -R bgrt 2>/dev/null || true

if [[ $GPU_TYPE == *"nvidia"* ]]; then
    grep -q "nvidia_drm" /etc/mkinitcpio.conf || \
        sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
fi
if [[ $GPU_TYPE == *"amd"* ]]; then
    grep -q "amdgpu" /etc/mkinitcpio.conf || \
        sudo sed -i 's/^MODULES=(/MODULES=(amdgpu /' /etc/mkinitcpio.conf
fi
if [[ $GPU_TYPE == *"intel"* ]]; then
    grep -q "^MODULES=([^)]*i915" /etc/mkinitcpio.conf || \
        sudo sed -i 's/^MODULES=(/MODULES=(i915 /' /etc/mkinitcpio.conf
fi

PLYMOUTHD_CONF="/etc/plymouth/plymouthd.conf"
[ -f "$PLYMOUTHD_CONF" ] || printf '[Daemon]\n' | sudo tee "$PLYMOUTHD_CONF" >/dev/null
grep -q '^\[Daemon\]' "$PLYMOUTHD_CONF" || sudo sed -i '1i [Daemon]' "$PLYMOUTHD_CONF"

if grep -q '^Theme=' "$PLYMOUTHD_CONF"; then
    sudo sed -i 's/^Theme=.*/Theme=bgrt/' "$PLYMOUTHD_CONF"
elif grep -q '^#Theme=' "$PLYMOUTHD_CONF"; then
    sudo sed -i 's/^#Theme=.*/Theme=bgrt/' "$PLYMOUTHD_CONF"
else
    sudo sed -i '/^\[Daemon\]/a Theme=bgrt' "$PLYMOUTHD_CONF"
fi

if grep -q '^ShowDelay=' "$PLYMOUTHD_CONF"; then
    sudo sed -i 's/^ShowDelay=.*/ShowDelay=0/' "$PLYMOUTHD_CONF"
elif grep -q '^#ShowDelay=' "$PLYMOUTHD_CONF"; then
    sudo sed -i 's/^#ShowDelay=.*/ShowDelay=0/' "$PLYMOUTHD_CONF"
else
    sudo sed -i '/^\[Daemon\]/a ShowDelay=0' "$PLYMOUTHD_CONF"
fi

for preset in /etc/mkinitcpio.d/*.preset; do
    [ -f "$preset" ] && sudo sed -i 's/--splash [^ "]*//g' "$preset"
done

if ! grep -qE '^HOOKS=.*(^|[[:space:]])(sd-plymouth|plymouth)([[:space:]]|\))' /etc/mkinitcpio.conf; then
    if grep -qE '^HOOKS=.*(^|[[:space:]])kms([[:space:]]|\))' /etc/mkinitcpio.conf; then
        if grep -qE '^HOOKS=.*(^|[[:space:]])systemd([[:space:]]|\))' /etc/mkinitcpio.conf; then
            sudo sed -i '/^HOOKS=/ s/\bkms\b/kms sd-plymouth/' /etc/mkinitcpio.conf
        else
            sudo sed -i '/^HOOKS=/ s/\bkms\b/kms plymouth/' /etc/mkinitcpio.conf
        fi
    elif grep -qE '^HOOKS=.*(^|[[:space:]])systemd([[:space:]]|\))' /etc/mkinitcpio.conf; then
        sudo sed -i '/^HOOKS=/ s/\bsystemd\b/systemd kms sd-plymouth/' /etc/mkinitcpio.conf
    else
        sudo sed -i '/^HOOKS=/ s/\budev\b/udev kms plymouth/' /etc/mkinitcpio.conf
    fi
fi

fix_uki_collisions() {
    local -A seen_uki=()
    local preset kname uki_key line uki_path new_path suffix
    for preset in /etc/mkinitcpio.d/*.preset; do
        [ -f "$preset" ] || continue
        kname="$(basename "$preset" .preset)"
        for uki_key in default_uki fallback_uki; do
            line="$(grep -E "^${uki_key}=" "$preset" 2>/dev/null || true)"
            [ -z "$line" ] && continue
            uki_path="$(sed -E "s/^${uki_key}=\"?([^\"]*)\"?.*/\1/" <<<"$line")"
            [ -z "$uki_path" ] && continue
            if [ -n "${seen_uki[$uki_path]:-}" ] && [ "${seen_uki[$uki_path]}" != "$kname" ]; then
                suffix=""
                [[ "$uki_key" == "fallback_uki" ]] && suffix="-fallback"
                new_path="$(dirname "$uki_path")/arch-${kname}${suffix}.efi"
                sudo sed -i "s#^${uki_key}=.*#${uki_key}=\"${new_path}\"#" "$preset"
                seen_uki["$new_path"]="$kname"
            else
                seen_uki["$uki_path"]="$kname"
            fi
        done
    done
}
fix_uki_collisions

sudo mkinitcpio -P || true

if [ ${#LIMINE_CONFS[@]} -gt 0 ] && pacman -Qq limine-mkinitcpio-hook &>/dev/null; then
    for candidate in /boot/limine.conf /efi/limine.conf \
                      /boot/EFI/Limine/limine.conf /efi/EFI/Limine/limine.conf \
                      /boot/EFI/BOOT/limine.conf /efi/EFI/BOOT/limine.conf \
                      /boot/limine.cfg /efi/limine.cfg; do
        if broot_f "$candidate" && [[ ! " ${LIMINE_CONFS[*]} " == *" ${candidate} "* ]]; then
            LIMINE_CONFS+=("$candidate")
        fi
    done
    patch_limine_conf
fi

show_progress 11 $TOTAL_STEPS "$MSG_PHASE_3"

sudo systemctl enable --now geoclue.service || true
sudo systemctl enable --now ananicy-cpp || true
sudo systemctl enable --now fstrim.timer || true
sudo systemctl enable --now bluetooth || true
echo "options btusb enable_autosuspend=0" | sudo tee /etc/modprobe.d/btusb.conf > /dev/null
sudo systemctl enable --now libvirtd || true

LIBVIRT_NET="192.168.122.0/24"
if ip -4 -o addr show 2>/dev/null | awk '$2 != "virbr0" && $4 ~ /^192\.168\.122\./ {found=1} END {exit !found}'; then
    LIBVIRT_NET="192.168.150.0/24"
fi

if ! sudo virsh net-info default &>/dev/null; then
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi

if [[ "$LIBVIRT_NET" == "192.168.150.0/24" ]]; then
    LIBVIRT_NET_XML="$(mktemp)"
    if sudo virsh net-dumpxml default --inactive 2>/dev/null > "$LIBVIRT_NET_XML" && grep -q '192\.168\.122\.' "$LIBVIRT_NET_XML"; then
        sed -i 's/192\.168\.122\./192.168.150./g' "$LIBVIRT_NET_XML"
        sudo virsh net-destroy default 2>/dev/null || true
        sudo virsh net-undefine default 2>/dev/null || true
        sudo virsh net-define "$LIBVIRT_NET_XML" || true
    fi
    rm -f "$LIBVIRT_NET_XML"
fi

sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default 2>/dev/null || true

if command -v ufw &>/dev/null; then
    [[ -f /etc/default/ufw ]] && sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw || true
    sudo ufw --force reset || true
    sudo ufw default deny incoming || true
    sudo ufw default allow outgoing || true
    sudo ufw allow in  on virbr0 || true
    sudo ufw allow out on virbr0 || true
    sudo ufw allow from "$LIBVIRT_NET" || true
    if pkg_installed openssh || [[ -x /usr/bin/sshd ]] || [[ -x /usr/sbin/sshd ]] \
        || systemctl is-active --quiet sshd 2>/dev/null; then
        sudo ufw allow ssh || true
    fi
    sudo ufw --force enable || true
    sudo systemctl enable --now ufw || true
fi

if command -v dconf &>/dev/null; then
    dconf load /org/virt-manager/virt-manager/ <<'EOF'
[/]
manager-window-height=297
manager-window-width=478
xmleditor-enabled=true

[confirm]
delete-storage=false
forcepoweroff=false

[connections]
autoconnect=['qemu:///system']
uris=['qemu:///system']

[conns/qemu:system]
window-size=(800, 600)

[details]
show-toolbar=true

[new-vm]
cpu-default='host-passthrough'
firmware='uefi'
graphics-type='spice'
storage-format='raw'

[stats]
enable-disk-poll=true
enable-memory-poll=true
enable-net-poll=true

[vmlist-fields]
disk-usage=false
network-traffic=false
EOF
fi

sudo sed -i 's/^#\?[[:space:]]*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=3s/' /etc/systemd/system.conf
sudo sed -i 's/^#\?[[:space:]]*DefaultTimeoutStartSec=.*/DefaultTimeoutStartSec=3s/' /etc/systemd/system.conf
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
sudo journalctl --vacuum-time=2d || true

for grp in libvirt kvm; do
    getent group "$grp" &>/dev/null && sudo usermod -aG "$grp" "$CURRENT_USER" || true
done

if command -v zsh &>/dev/null; then
    sudo chsh -s /usr/bin/zsh "$CURRENT_USER" || true

    [ ! -d "$HOME/.oh-my-zsh" ] && \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended || true

    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    [ ! -d "$P10K_DIR" ] && \
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || true

    if [ -f ~/.zshrc ]; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
        sed -i 's/^plugins=(.*/plugins=(git sudo systemd archlinux)/' ~/.zshrc

        SHELL_LOCALE="${LANG:-${LC_ALL:-${LC_MESSAGES:-en_US.UTF-8}}}"
        if command -v locale &>/dev/null; then
            AVAILABLE_LOCALES="$(locale -a 2>/dev/null)"
            if ! echo "$AVAILABLE_LOCALES" | grep -qiF "$SHELL_LOCALE" && ! echo "$AVAILABLE_LOCALES" | grep -qiF "$(echo "$SHELL_LOCALE" | sed 's/UTF-8/utf8/')"; then
                SHELL_LOCALE="en_US.UTF-8"
            fi
        fi
        if ! grep -q "^export LC_ALL=" ~/.zshrc; then
            {
                echo ""
                echo "export LC_ALL=${SHELL_LOCALE}"
                echo "export LC_MESSAGES=${SHELL_LOCALE}"
                echo "fastfetch"
            } >> ~/.zshrc
        fi

        if ! grep -q "zsh-syntax-highlighting.zsh" ~/.zshrc; then
            {
                echo ""
                echo "source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
                echo "source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
            } >> ~/.zshrc
        fi
    fi
fi


# =============================================================
#  ETAP 4/4: CZYSZCZENIE
# =============================================================
show_progress 12 $TOTAL_STEPS "$MSG_PHASE_4"
printf '\n\n' >&3

if [ "${#FAILED_PACKAGES[@]}" -gt 0 ]; then
    log_warn "Nie udało się zainstalować: ${FAILED_PACKAGES[*]}" "Failed to install: ${FAILED_PACKAGES[*]}"
fi

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}[OK] KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}[OK] CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

# =============================================================
#  RESTART SYSTEMU
# =============================================================
if [[ "$SCRIPT_LANG" == "pl" ]]; then
    RESTART_PROMPT="Czy chcesz teraz zrestartować system? [T/N]: "
else
    RESTART_PROMPT="Do you want to restart the system now? [Y/N]: "
fi
echo -en "${INFO}==> ${RESTART_PROMPT}${NC}" >&3
read -r RESTART_CHOICE < /dev/tty
case "$RESTART_CHOICE" in
    [YyTt]*)
        DO_REBOOT=1
        ;;
esac
exit 0