#!/bin/bash
# ==========================================================
# SKRYPT KONFIGURACYJNY WIZUALNYCH ASPEKTÓW KDE PLASMA
# ==========================================================

set -Eeuo pipefail 
export PATH="/usr/sbin:/sbin:$PATH"

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
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ WARN: $m${NC}"; }

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
    MSG_PHASE_1="[1/3] Wykrywanie dystrybucji i konfiguracja uprawnień..."
    MSG_PHASE_2="[2/3] Instalacja i weryfikacja pakietów KDE Plasma..."
    MSG_PHASE_3="[3/3] Konfiguracja środowiska, tapety i ustawień wizualnych..."
else
    MSG_PHASE_1="[1/3] Detecting distribution and configuring permissions..."
    MSG_PHASE_2="[2/3] Installing and verifying KDE Plasma packages..."
    MSG_PHASE_3="[3/3] Configuring environment, wallpaper, and visual settings..."
fi

TOTAL_STEPS=12

CURRENT_USER=$(whoami)
OLD_USER_PLACEHOLDER="bartek"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$EUID" -eq 0 ]]; then
    echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    exit 1
fi

sudo -v

RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if ! command -v visudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!

# ==========================================================
# 1. WSTĘPNE SPRAWDZENIA I UPRAWNIENIA
# ==========================================================
show_progress 0 $TOTAL_STEPS "$MSG_PHASE_1"

printf '\033[?7h' >&3
if [[ "$USE_RUN0" -eq 1 ]]; then
    printf 'polkit._run0_nopasswd.push("%s");\n' "$CURRENT_USER" | sudo tee "$RUN0_NOPASSWD_FILE" > /dev/null
    sudo systemctl try-restart polkit 2>/dev/null || true
else
    SUDOERS_TMP="$(mktemp)"
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
    if sudo visudo -cf "$SUDOERS_TMP" >/dev/null; then
        sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
    else
        rm -f "$SUDOERS_TMP"
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Nieprawidłowa składnia reguły sudoers - przerywam.${NC}" >&3
        else
            echo -e "${ERR}✘ Invalid sudoers rule syntax - aborting.${NC}" >&3
        fi
        exit 1
    fi
    rm -f "$SUDOERS_TMP"
fi

printf '\033[?7l' >&3

show_progress 1 $TOTAL_STEPS "$MSG_PHASE_1"

# ==========================================================
# 2. WYKRYWANIE DYSTRYBUCJI I INSTALACJA PAKIETÓW
# ==========================================================
PACKAGES=(
    plasma-firewall plasma-nm plasma-pa kscreen bluedevil
    kde-gtk-config kinfocenter kio-admin kdeplasma-addons
    aspell-pl kaccounts-providers dolphin konsole
    dolphin-plugins spectacle gwenview okular ark kate
    plymouth-kcm
)

declare -A PACKAGE_NAME_OVERRIDES=(
    [fedora:aspell-pl]="hunspell-pl"
    [opensuse:aspell-pl]="hunspell-pl"
    [opensuse:kio-admin]="kio_admin"
    [debian:plymouth-kcm]="kde-config-plymouth"
    [opensuse:plymouth-kcm]="plymouth-kcm6"
)

resolve_package_name() {
    local canonical="$1"
    local key="${DISTRO_FAMILY}:${canonical}"
    if [[ -n "${PACKAGE_NAME_OVERRIDES[$key]:-}" ]]; then
        echo "${PACKAGE_NAME_OVERRIDES[$key]}"
    else
        echo "$canonical"
    fi
}

detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        exit 1
    fi
    source /etc/os-release
    local id="${ID:-}"
    local id_like="${ID_LIKE:-}"

    case "$id" in
        arch|archlinux|endeavouros|manjaro) DISTRO_FAMILY="arch" ;;
        fedora) DISTRO_FAMILY="fedora" ;;
        opensuse*|sles) DISTRO_FAMILY="opensuse" ;;
        debian|ubuntu|kubuntu|linuxmint|pop|neon|zorin) DISTRO_FAMILY="debian" ;;
        *)
            case "$id_like" in
                *arch*) DISTRO_FAMILY="arch" ;;
                *fedora*) DISTRO_FAMILY="fedora" ;;
                *suse*) DISTRO_FAMILY="opensuse" ;;
                *debian*|*ubuntu*) DISTRO_FAMILY="debian" ;;
                *) log_err "Nierozpoznana dystrybucja." "Unrecognized distribution."; exit 1 ;;
            esac
            ;;
    esac
}

install_one_package() {
    local pkg="$1"
    case "$DISTRO_FAMILY" in
        arch)     sudo pacman -S --noconfirm --needed "$pkg" ;;
        fedora)   sudo dnf install -y "$pkg" ;;
        debian)   sudo apt-get install -y "$pkg" ;;
        opensuse) sudo zypper --non-interactive install --no-recommends "$pkg" ;;
    esac
}

add_opensuse_kde_frameworks_repo() {
    local repo_alias="KDE_Frameworks_plymouth"
    local suse_target

    if [[ "${NAME:-}" == *Tumbleweed* || "${PRETTY_NAME:-}" == *Tumbleweed* ]]; then
        suse_target="openSUSE_Tumbleweed"
    else
        suse_target="openSUSE_Leap_${VERSION_ID:-16.0}"
    fi

    local repo_url="https://download.opensuse.org/repositories/KDE:/Frameworks/${suse_target}/"

    if sudo zypper lr -u 2>/dev/null | grep -qF "$repo_url"; then
        return 0
    fi

    if sudo zypper --non-interactive addrepo --refresh --priority 90 "$repo_url" "$repo_alias"; then
        sudo zypper --non-interactive --gpg-auto-import-keys refresh "$repo_alias" || true
    fi
}

detect_distro
show_progress 2 $TOTAL_STEPS "$MSG_PHASE_1"

show_progress 3 $TOTAL_STEPS "$MSG_PHASE_2"

install_packages() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        sudo apt-get update || true
    elif [[ "$DISTRO_FAMILY" == "opensuse" ]]; then
        add_opensuse_kde_frameworks_repo
    fi

    show_progress 4 $TOTAL_STEPS "$MSG_PHASE_2"

    local installed=()
    local failed=()
    local canonical real_name

    for canonical in "${PACKAGES[@]}"; do
        real_name="$(resolve_package_name "$canonical")"
        if install_one_package "$real_name" > /tmp/install-"$canonical".log 2>&1; then
            installed+=("$canonical")
        else
            failed+=("$canonical (pakiet: $real_name)")
        fi
    done

    show_progress 5 $TOTAL_STEPS "$MSG_PHASE_2"
}

install_packages
show_progress 6 $TOTAL_STEPS "$MSG_PHASE_2"

# ==========================================================
# 3. KONFIGURACJA SYSTEMOWA (SUDO)
# ==========================================================
show_progress 7 $TOTAL_STEPS "$MSG_PHASE_3"

if [[ -f "$SCRIPT_DIR/piwo.png" ]]; then
    sudo mkdir -p /usr/share/plasma/avatars/ || true
    sudo cp -f "$SCRIPT_DIR/piwo.png" /usr/share/plasma/avatars/piwo.png || true
    sudo chmod 644 /usr/share/plasma/avatars/piwo.png || true

    sudo mkdir -p /var/lib/AccountsService/icons/ || true
    sudo cp -f "$SCRIPT_DIR/piwo.png" /var/lib/AccountsService/icons/"$CURRENT_USER" || true
    sudo chmod 644 /var/lib/AccountsService/icons/"$CURRENT_USER" || true

    ACCOUNTS_FILE="/var/lib/AccountsService/users/$CURRENT_USER"
    sudo mkdir -p /var/lib/AccountsService/users/ || true

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "[User]\nIcon=/var/lib/AccountsService/icons/$CURRENT_USER" | sudo tee "$ACCOUNTS_FILE" > /dev/null
    else
        if sudo grep -q "^Icon=" "$ACCOUNTS_FILE"; then
            sudo sed -i "s|^Icon=.*|Icon=/var/lib/AccountsService/icons/$CURRENT_USER|" "$ACCOUNTS_FILE" || true
        else
            echo "Icon=/var/lib/AccountsService/icons/$CURRENT_USER" | sudo tee -a "$ACCOUNTS_FILE" > /dev/null
        fi
    fi
fi

if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    sudo mkdir -p /usr/share/wallpapers || true
    sudo cp -f "$SCRIPT_DIR/login-wallpaper.png" /usr/share/wallpapers/login-wallpaper.png || true
    sudo chmod 644 /usr/share/wallpapers/login-wallpaper.png || true
fi

PLASMALOGIN_CONF="/etc/plasmalogin.conf"
GREETER_WALLPAPER_URI="file:///usr/share/wallpapers/login-wallpaper.png"

if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    sudo touch "$PLASMALOGIN_CONF"
    if command -v kwriteconfig6 &>/dev/null; then
        sudo kwriteconfig6 --file "$PLASMALOGIN_CONF" \
            --group Greeter --group Wallpaper --group org.kde.image --group General \
            --key Image "$GREETER_WALLPAPER_URI" || true
    else
        SECTION_HEADER="[Greeter][Wallpaper][org.kde.image][General]"
        if sudo grep -qF "$SECTION_HEADER" "$PLASMALOGIN_CONF" 2>/dev/null; then
            if sudo awk -v hdr="$SECTION_HEADER" 'BEGIN{f=0} $0==hdr{f=1} f && /^Image=/{found=1} END{exit !found}' "$PLASMALOGIN_CONF"; then
                sudo sed -i "\|^\[Greeter\]\[Wallpaper\]\[org\.kde\.image\]\[General\]\$|,/^\[/{s|^Image=.*|Image=$GREETER_WALLPAPER_URI|}" "$PLASMALOGIN_CONF" || true
            else
                sudo sed -i "\|^\[Greeter\]\[Wallpaper\]\[org\.kde\.image\]\[General\]\$|a Image=$GREETER_WALLPAPER_URI" "$PLASMALOGIN_CONF" || true
            fi
        else
            printf '\n%s\nImage=%s\n' "$SECTION_HEADER" "$GREETER_WALLPAPER_URI" | sudo tee -a "$PLASMALOGIN_CONF" > /dev/null
        fi
    fi
    sudo chmod 644 "$PLASMALOGIN_CONF" || true
fi

TARGET_DIR="$HOME/.local/share/wallpapers"
mkdir -p "$TARGET_DIR"

show_progress 8 $TOTAL_STEPS "$MSG_PHASE_3"

# ==========================================================
# 4. KONFIGURACJA WIZUALNA (KONTO UŻYTKOWNIKA)
# ==========================================================
systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
kquitapp6 plasmashell 2>/dev/null || killall -9 plasmashell 2>/dev/null || true
sleep 2

show_progress 9 $TOTAL_STEPS "$MSG_PHASE_3"

if [[ -d "$SCRIPT_DIR/.config" ]]; then cp -af "$SCRIPT_DIR/.config/." ~/.config/; fi
if [[ -d "$SCRIPT_DIR/.local" ]]; then cp -af "$SCRIPT_DIR/.local/." ~/.local/; fi
if [[ -d "$SCRIPT_DIR/.icons" ]]; then cp -af "$SCRIPT_DIR/.icons/." ~/.icons/; fi

LOCKSCREEN_CONF="$HOME/.config/kscreenlockerrc"
LOCKSCREEN_WALLPAPER_PATH="$HOME/.local/share/wallpapers/lock_screen.jpg"
LOCKSCREEN_WALLPAPER_URI="file://$LOCKSCREEN_WALLPAPER_PATH"

if [[ -f "$LOCKSCREEN_WALLPAPER_PATH" ]]; then
    touch "$LOCKSCREEN_CONF"
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file "$LOCKSCREEN_CONF" \
            --group Greeter --group Wallpaper --group org.kde.image --group General \
            --key Image "$LOCKSCREEN_WALLPAPER_URI" || true
    else
        SECTION_HEADER="[Greeter][Wallpaper][org.kde.image][General]"
        if grep -qF "$SECTION_HEADER" "$LOCKSCREEN_CONF" 2>/dev/null; then
            if awk -v hdr="$SECTION_HEADER" 'BEGIN{f=0} $0==hdr{f=1} f && /^Image=/{found=1} END{exit !found}' "$LOCKSCREEN_CONF"; then
                sed -i "\|^\[Greeter\]\[Wallpaper\]\[org\.kde\.image\]\[General\]\$|,/^\[/{s|^Image=.*|Image=$LOCKSCREEN_WALLPAPER_URI|}" "$LOCKSCREEN_CONF" || true
            else
                sed -i "\|^\[Greeter\]\[Wallpaper\]\[org\.kde\.image\]\[General\]\$|a Image=$LOCKSCREEN_WALLPAPER_URI" "$LOCKSCREEN_CONF" || true
            fi
        else
            printf '\n%s\nImage=%s\n' "$SECTION_HEADER" "$LOCKSCREEN_WALLPAPER_URI" >> "$LOCKSCREEN_CONF"
        fi
    fi
    chmod 644 "$LOCKSCREEN_CONF" || true
fi

if [[ "$OLD_USER_PLACEHOLDER" != "$CURRENT_USER" ]]; then
    for dir in ~/.config ~/.local ~/.icons; do
        [[ -d "$dir" ]] || continue
        grep -rl --include="*.conf" --include="*.json" --include="*.ini" \
            "/home/$OLD_USER_PLACEHOLDER" "$dir" 2>/dev/null \
            | xargs -r sed -i "s|/home/$OLD_USER_PLACEHOLDER|/home/$CURRENT_USER|g" || true
    done
fi

show_progress 10 $TOTAL_STEPS "$MSG_PHASE_3"

rm -rf ~/.cache/icon-cache.kcache ~/.cache/plasma* ~/.cache/ico*

WALLPAPER_PATH="$HOME/.local/share/wallpapers/wallpaper.jpg"
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_DIR/force-wallpaper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Wymuszenie Tapety
Exec=bash -c 'for i in {1..30}; do plasma-apply-wallpaperimage "$WALLPAPER_PATH" && rm -f "$AUTOSTART_DIR/force-wallpaper.desktop" && break; sleep 2; done'
Hidden=false
NoDisplay=true
X-KDE-autostart-condition=
EOF
chmod +x "$AUTOSTART_DIR/force-wallpaper.desktop"

show_progress 11 $TOTAL_STEPS "$MSG_PHASE_3"

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental &>/dev/null || true
fi

# ==========================================================
# 5. ZAKOŃCZENIE I SPRZĄTANIE
# ==========================================================
if [[ "$USE_RUN0" -eq 1 ]]; then
    sudo rm -f "$RUN0_NOPASSWD_FILE"
    sudo systemctl try-restart polkit 2>/dev/null || true
else
    sudo rm -f /etc/sudoers.d/99-temp-installer
fi

show_progress 12 $TOTAL_STEPS "$MSG_PHASE_3"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

systemctl reboot
