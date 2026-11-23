#!/usr/bin/env bash
# =========================================
# SKRYPT KONFIGURACJI WIZUALNEJ KDE PLASMA
# =========================================

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/sbin:/sbin:$PATH"

FAILED_PACKAGES=()

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
    set +e
    trap - ERR
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
        else
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${WARN}[!] Niektóre pakiety nie zostały zainstalowane. Log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${WARN}[!] Some packages failed to install. Log saved to: $LOG_FILE${NC}" >&3
            fi
        fi
    fi
    rm -f "$TMP_LOG"
    local do_reboot=0
    [ "$exit_code" -eq 0 ] && [ "${DO_REBOOT:-0}" = "1" ] && do_reboot=1
    if [ "${SUDO_READY:-0}" = "1" ]; then
        sudo sh -c 'rm -f "$1" "$2"; systemctl try-restart polkit 2>/dev/null || true; if [ "$3" = 1 ]; then systemctl reboot 2>/dev/null || reboot; fi' _ \
            "${RUN0_NOPASSWD_FILE:-/etc/polkit-1/rules.d/51-run0-nopasswd.rules}" \
            "/etc/sudoers.d/99-temp-installer" \
            "$do_reboot" || true
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
_log_write() {
    echo -e "$1"
    printf '\r\033[K%b\n' "$1" >&3
    cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
}
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
    for f in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock \
             /run/zypp.pid /var/run/zypp.pid /var/lib/pacman/db.lck \
             /var/cache/dnf/metadata_lock.pid /var/lib/rpm/.rpm.lock; do
        [[ -e "$f" ]] || continue
        sudo fuser "$f" >/dev/null 2>&1 && return 0
    done
    pgrep -x 'apt|apt-get|dpkg|zypper|pacman|dnf|dnf5|xbps-install|packagekitd' >/dev/null 2>&1 && return 0
    return 1
}

wait_for_pkg_lock() {
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
    MSG_PREP="[1/4] Przygotowywanie..."
    MSG_INSTALL="[2/4] Instalacja..."
    MSG_OPTIMIZE="[3/4] Optymalizacja..."
    MSG_FINALIZE="[4/4] Finalizowanie..."
else
    MSG_PREP="[1/4] Preparing..."
    MSG_INSTALL="[2/4] Installation..."
    MSG_OPTIMIZE="[3/4] Optimization..."
    MSG_FINALIZE="[4/4] Finalizing..."
fi

TOTAL_STEPS=10

CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$EUID" -eq 0 ]]; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERR}[X] Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    else
        echo -e "${ERR}[X] Do not run this script as root. Run as a normal user with sudo.${NC}" >&3
    fi
    exit 1
fi

RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if command -v run0 >/dev/null 2>&1; then
    if ! command -v visudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; then
        USE_RUN0=1
    fi
fi

# ==========================================================
# 1. WSTĘPNE SPRAWDZENIA I UPRAWNIENIA
# ==========================================================
printf '\033[?7h' >&3
SUDO_READY=0
if [[ "$USE_RUN0" -eq 1 ]]; then
    sudo mkdir -p "$(dirname "$RUN0_NOPASSWD_FILE")"
    sudo tee "$RUN0_NOPASSWD_FILE" > /dev/null <<POLKIT_RULE_EOF
polkit.addRule(function(action, subject) {
    if (subject.user == "$CURRENT_USER") {
        return polkit.Result.YES;
    }
});
POLKIT_RULE_EOF
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

    if command -v visudo >/dev/null 2>&1; then
        SUDOERS_TMP="$(mktemp)"
        echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
        if sudo visudo -cf "$SUDOERS_TMP" >/dev/null; then
            sudo mkdir -p /etc/sudoers.d
            sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
        else
            rm -f "$SUDOERS_TMP"
            log_err "Nieprawidłowa składnia reguły sudoers - przerywam." "Invalid sudoers rule syntax - aborting."
            exit 1
        fi
        rm -f "$SUDOERS_TMP"
    fi
    SUDO_READY=1
fi

printf '\033[?7l' >&3

show_progress 0 $TOTAL_STEPS "$MSG_PREP"

disable_packagekit

show_progress 1 $TOTAL_STEPS "$MSG_PREP"

# ==========================================================
# 2. WYKRYWANIE DYSTRYBUCJI I INSTALACJA PAKIETÓW
# ==========================================================
detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        log_err "Nie znaleziono /etc/os-release - nie można wykryć dystrybucji." \
                "Could not find /etc/os-release - unable to detect the distribution."
        exit 1
    fi
    source /etc/os-release
    local id_like="${ID:-} ${ID_LIKE:-}"

    case "${id_like,,}" in
        *arch*) DISTRO_FAMILY="arch" ;;
        *void*) DISTRO_FAMILY="void" ;;
        *fedora*) DISTRO_FAMILY="fedora" ;;
        *suse*) DISTRO_FAMILY="opensuse" ;;
        *debian*|*ubuntu*) DISTRO_FAMILY="debian" ;;
        *) log_err "Nierozpoznana dystrybucja." "Unrecognized distribution."; exit 1 ;;
    esac
}

pkg_installed() {
    case "$DISTRO_FAMILY" in
        arch)            pacman -Qq "$1" &>/dev/null ;;
        void)            xbps-query "$1" &>/dev/null ;;
        fedora|opensuse) rpm -q --quiet "$1" &>/dev/null ;;
        debian)          [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" == ii* ]] ;;
        *)               return 1 ;;
    esac
}

install_one_package() {
    local pkg="$1"
    pkg_installed "$pkg" && return 0
    case "$DISTRO_FAMILY" in
        arch)     sudo pacman -S --noconfirm --needed "$pkg" ;;
        void)     sudo xbps-install -y "$pkg" ;;
        fedora)   sudo dnf install -yq "$pkg" ;;
        debian)   sudo apt-get install -yq "$pkg" ;;
        opensuse) sudo zypper -nq install --no-recommends -y "$pkg" ;;
        *) return 1 ;;
    esac
}

detect_distro
show_progress 2 $TOTAL_STEPS "$MSG_PREP"

case "$DISTRO_FAMILY" in
    arch)
        PACKAGES=(
            plasma-firewall plasma-nm plasma-pa kscreen bluedevil
            kde-gtk-config kinfocenter kio-admin kdeplasma-addons
            aspell-pl kaccounts-providers dolphin konsole
            dolphin-plugins spectacle gwenview okular ark kate
            plasma-systemmonitor kcalc kup bup qrca krdc krfb
        )
        ;;
    void)
        PACKAGES=(
            dbus elogind NetworkManager sddm xorg-minimal mesa-dri
            plasma-workspace plasma-desktop kwin xorg-server-xwayland
            plasma-firewall plasma-nm plasma-pa kscreen bluedevil
            kde-gtk-config kinfocenter kio-admin kdeplasma-addons
            aspell-pl kaccounts-providers dolphin konsole
            dolphin-plugins spectacle gwenview okular ark kate
            plasma-systemmonitor kcalc kup bup krdc krfb pulseaudio-utils rtkit
        )
        ;;
    fedora)
        PACKAGES=(kio-admin dolphin-plugins kup bup qrca kcalc krdc krfb okular)
        ;;
    opensuse)
        PACKAGES=(kio-admin dolphin-plugins kup bup qrca kcalc krdc krfb okular)
        ;;
    debian)
        PACKAGES=(kio-admin dolphin-plugins kup-backup bup qrca kcalc krdc krfb okular)
        ;;
esac

show_progress 3 $TOTAL_STEPS "$MSG_INSTALL"

install_packages() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        wait_for_pkg_lock
        sudo apt-get update -yq || true
    elif [[ "$DISTRO_FAMILY" == "opensuse" ]]; then
        wait_for_pkg_lock
    elif [[ "$DISTRO_FAMILY" == "void" ]]; then
        wait_for_pkg_lock
        sudo xbps-install -Suy xbps || true
        sudo xbps-install -uy || true
    fi

    show_progress 4 $TOTAL_STEPS "$MSG_INSTALL"

    wait_for_pkg_lock

    for pkg in "${PACKAGES[@]}"; do
        if ! install_one_package "$pkg"; then
            FAILED_PACKAGES+=("$pkg")
        fi
    done
}

install_packages
show_progress 5 $TOTAL_STEPS "$MSG_OPTIMIZE"

# ==========================================================
# 3. KONFIGURACJA SYSTEMOWA (SUDO)
# ==========================================================
restore_packagekit

set_kde_ini_key() {
    local file="$1" header="$2" key="$3" value="$4" use_sudo="${5:-0}"
    local tmp_ini
    tmp_ini="$(mktemp)"
    if [[ "$use_sudo" -eq 1 ]]; then
        sudo mkdir -p "$(dirname "$file")"
        sudo touch "$file"
        sudo awk -v hdr="$header" -v k="$key" -v v="$value" '
            BEGIN { in_sec = 0; found_sec = 0; updated = 0 }
            /^[[:space:]]*\[.*\][[:space:]]*$/ {
                if (in_sec && !updated) {
                    print k "=" v
                    updated = 1
                }
                if ($0 == hdr) {
                    in_sec = 1
                    found_sec = 1
                } else {
                    in_sec = 0
                }
                print
                next
            }
            {
                if (in_sec && $0 ~ "^[[:space:]]*" k "[[:space:]]*=") {
                    if (!updated) {
                        print k "=" v
                        updated = 1
                    }
                    next
                }
                print
            }
            END {
                if (!found_sec) {
                    if (NR > 0) print ""
                    print hdr
                    print k "=" v
                } else if (in_sec && !updated) {
                    print k "=" v
                }
            }
        ' "$file" > "$tmp_ini"
        sudo install -m 644 -o root -g root "$tmp_ini" "$file"
    else
        mkdir -p "$(dirname "$file")"
        touch "$file"
        awk -v hdr="$header" -v k="$key" -v v="$value" '
            BEGIN { in_sec = 0; found_sec = 0; updated = 0 }
            /^[[:space:]]*\[.*\][[:space:]]*$/ {
                if (in_sec && !updated) {
                    print k "=" v
                    updated = 1
                }
                if ($0 == hdr) {
                    in_sec = 1
                    found_sec = 1
                } else {
                    in_sec = 0
                }
                print
                next
            }
            {
                if (in_sec && $0 ~ "^[[:space:]]*" k "[[:space:]]*=") {
                    if (!updated) {
                        print k "=" v
                        updated = 1
                    }
                    next
                }
                print
            }
            END {
                if (!found_sec) {
                    if (NR > 0) print ""
                    print hdr
                    print k "=" v
                } else if (in_sec && !updated) {
                    print k "=" v
                }
            }
        ' "$file" > "$tmp_ini"
        mv -f "$tmp_ini" "$file"
        chmod 644 "$file" || true
    fi
    rm -f "$tmp_ini"
}

if [[ -f "$SCRIPT_DIR/piwo.png" ]]; then
    install -m 644 "$SCRIPT_DIR/piwo.png" "$HOME/.face" 2>/dev/null || true
    install -m 644 "$SCRIPT_DIR/piwo.png" "$HOME/.face.icon" 2>/dev/null || true

    sudo mkdir -p /usr/share/plasma/avatars || true
    sudo install -m 644 -o root -g root "$SCRIPT_DIR/piwo.png" /usr/share/plasma/avatars/piwo.png || true

    AVATAR_DEST="/var/lib/AccountsService/icons/$CURRENT_USER"
    ACCOUNTS_FILE="/var/lib/AccountsService/users/$CURRENT_USER"

    sudo mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users || true
    sudo install -m 644 -o root -g root "$SCRIPT_DIR/piwo.png" "$AVATAR_DEST" || true

    if ! sudo test -f "$ACCOUNTS_FILE"; then
        printf '[User]\nIcon=%s\n' "$AVATAR_DEST" | sudo tee "$ACCOUNTS_FILE" > /dev/null || true
    elif sudo grep -q "^Icon=" "$ACCOUNTS_FILE"; then
        sudo sed -i "s|^Icon=.*|Icon=$AVATAR_DEST|" "$ACCOUNTS_FILE" || true
    elif sudo grep -q "^\[User\]" "$ACCOUNTS_FILE"; then
        sudo sed -i "/^\[User\]/a Icon=$AVATAR_DEST" "$ACCOUNTS_FILE" || true
    else
        printf '\n[User]\nIcon=%s\n' "$AVATAR_DEST" | sudo tee -a "$ACCOUNTS_FILE" > /dev/null || true
    fi

    sudo systemctl restart accounts-daemon 2>/dev/null || true
    if command -v busctl >/dev/null 2>&1; then
        busctl call org.freedesktop.Accounts \
            "/org/freedesktop/Accounts/User$(id -u "$CURRENT_USER" 2>/dev/null || id -u)" \
            org.freedesktop.Accounts.User SetIconFile s "$AVATAR_DEST" 2>/dev/null || true
    fi
fi

if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    sudo mkdir -p /usr/share/wallpapers || true
    sudo install -m 644 -o root -g root "$SCRIPT_DIR/login-wallpaper.png" /usr/share/wallpapers/login-wallpaper.png || true
fi

PLASMALOGIN_CONF="/etc/plasmalogin.conf"
GREETER_WALLPAPER_URI="file:///usr/share/wallpapers/login-wallpaper.png"

if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    sudo touch "$PLASMALOGIN_CONF"
    if command -v kwriteconfig6 &>/dev/null; then
        sudo kwriteconfig6 --file "$PLASMALOGIN_CONF" \
            --group Greeter --group Wallpaper --group org.kde.image --group General \
            --key Image "$GREETER_WALLPAPER_URI" || true
        sudo chmod 644 "$PLASMALOGIN_CONF" || true
    else
        set_kde_ini_key "$PLASMALOGIN_CONF" "[Greeter][Wallpaper][org.kde.image][General]" "Image" "$GREETER_WALLPAPER_URI" 1
    fi
fi

TARGET_DIR="$HOME/.local/share/wallpapers"
mkdir -p "$TARGET_DIR"

show_progress 6 $TOTAL_STEPS "$MSG_OPTIMIZE"

# ==========================================================
# 4. KONFIGURACJA WIZUALNA (KONTO UŻYTKOWNIKA)
# ==========================================================
systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
kquitapp6 plasmashell 2>/dev/null || killall -9 plasmashell 2>/dev/null || pkill -9 -u "$CURRENT_USER" -x plasmashell 2>/dev/null || true
sleep 2

show_progress 7 $TOTAL_STEPS "$MSG_OPTIMIZE"

safe_copy_dir() {
    local src="$1" dst="$2"
    if [[ -d "$src" ]] && [[ "$(realpath "$src" 2>/dev/null)" != "$(realpath "$dst" 2>/dev/null)" ]]; then
        mkdir -p "$dst" 2>/dev/null || return 0
        cp -af "$src/." "$dst/" 2>/dev/null || true
    fi
    return 0
}

safe_copy_dir "$SCRIPT_DIR/.config" "$HOME/.config"
safe_copy_dir "$SCRIPT_DIR/.local" "$HOME/.local"
safe_copy_dir "$SCRIPT_DIR/.icons" "$HOME/.icons"

LOCKSCREEN_CONF="$HOME/.config/kscreenlockerrc"
LOCKSCREEN_WALLPAPER_PATH="$HOME/.local/share/wallpapers/lock_screen.jpg"
LOCKSCREEN_WALLPAPER_URI="file://$LOCKSCREEN_WALLPAPER_PATH"

if [[ -f "$LOCKSCREEN_WALLPAPER_PATH" ]]; then
    mkdir -p "$(dirname "$LOCKSCREEN_CONF")"
    touch "$LOCKSCREEN_CONF"
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file "$LOCKSCREEN_CONF" \
            --group Greeter --group Wallpaper --group org.kde.image --group General \
            --key Image "$LOCKSCREEN_WALLPAPER_URI" || true
        chmod 644 "$LOCKSCREEN_CONF" || true
    else
        set_kde_ini_key "$LOCKSCREEN_CONF" "[Greeter][Wallpaper][org.kde.image][General]" "Image" "$LOCKSCREEN_WALLPAPER_URI" 0
    fi
fi

show_progress 8 $TOTAL_STEPS "$MSG_OPTIMIZE"

rm -rf "$HOME/.cache/icon-cache.kcache" "$HOME/.cache/icon-cache"* "$HOME/.cache/plasma"*

WALLPAPER_PATH="$HOME/.local/share/wallpapers/wallpaper.jpg"
AUTOSTART_DIR="$HOME/.config/autostart"
HELPER_BIN_DIR="$HOME/.local/bin"
HELPER_SCRIPT="$HELPER_BIN_DIR/force-wallpaper.sh"

if [[ -f "$WALLPAPER_PATH" ]]; then
    mkdir -p "$AUTOSTART_DIR" "$HELPER_BIN_DIR"
    cat > "$HELPER_SCRIPT" <<EOF
#!/usr/bin/env bash
for i in {1..30}; do
    if command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && plasma-apply-wallpaperimage "$WALLPAPER_PATH"; then
        rm -f "$AUTOSTART_DIR/force-wallpaper.desktop" "$HELPER_SCRIPT"
        exit 0
    fi
    sleep 2
done
EOF
    chmod 755 "$HELPER_SCRIPT"

    cat > "$AUTOSTART_DIR/force-wallpaper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Wymuszenie Tapety
Exec="$HELPER_SCRIPT"
Hidden=false
NoDisplay=true
X-KDE-autostart-condition=
EOF
    chmod 644 "$AUTOSTART_DIR/force-wallpaper.desktop"
fi

# ==========================================================
# 5. ZAKOŃCZENIE I SPRZĄTANIE
# ==========================================================

show_progress 9 $TOTAL_STEPS "$MSG_FINALIZE"

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental &>/dev/null || true
fi

if [[ "$DISTRO_FAMILY" == "void" ]]; then
    for svc in dhcpcd wpa_supplicant; do
        [[ -L "/var/service/$svc" ]] && sudo rm -f "/var/service/$svc" || true
    done
    for svc in dbus NetworkManager bluetoothd sddm; do
        if [[ -d "/etc/sv/$svc" && ! -e "/var/service/$svc" ]]; then
            sudo ln -s "/etc/sv/$svc" "/var/service/$svc" || true
        fi
    done
fi

show_progress 10 $TOTAL_STEPS "$MSG_FINALIZE"
printf '\n\n' >&3

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    log_warn "Nie udało się zainstalować: ${FAILED_PACKAGES[*]}. Sprawdź log: $LOG_FILE" \
             "Failed to install: ${FAILED_PACKAGES[*]}. Check the log: $LOG_FILE"
fi

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}[OK] KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}[OK] CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

DO_REBOOT=1
exit 0