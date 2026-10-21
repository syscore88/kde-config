#!/usr/bin/env bash
# =================================================
# SKRYPT KONFIGURACJI WIZUALNEJ KDE PLASMA (NixOS)
# =================================================

set -Eeuo pipefail

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
    local do_reboot=0
    [ "$exit_code" -eq 0 ] && [ "${DO_REBOOT:-0}" = "1" ] && do_reboot=1
    if [ "${SUDO_READY:-0}" = "1" ]; then
        sudo sh -c 'rm -f "$1" "$2"; systemctl try-restart polkit 2>/dev/null; [ "$3" = 1 ] && systemctl reboot' _ \
            "${RUN0_NOPASSWD_FILE:-/etc/polkit-1/rules.d/51-run0-nopasswd.rules}" \
            "/etc/sudoers.d/99-temp-installer" \
            "$do_reboot"
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
    MSG_OPTIMIZE="Optymalizacja..."
    MSG_FINALIZE="Finalizowanie..."
else
    MSG_PREP="Preparing..."
    MSG_OPTIMIZE="Optimization..."
    MSG_FINALIZE="Finalizing..."
fi

TOTAL_STEPS=7

CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$EUID" -eq 0 ]]; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    else
        echo -e "${ERR}✘ Do not run this script as root. Run as a normal user with sudo.${NC}" >&3
    fi
    exit 1
fi

RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if ! command -v visudo >/dev/null 2>&1; then
    USE_RUN0=1
elif command -v run0 >/dev/null 2>&1 && sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

# ==========================================================
# 1. WSTĘPNE SPRAWDZENIA I UPRAWNIENIA
# ==========================================================
printf '\033[?7h' >&3
SUDO_READY=0
if [[ "$USE_RUN0" -eq 1 ]]; then
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
    SUDO_READY=1
fi

printf '\033[?7l' >&3

show_progress 0 $TOTAL_STEPS "$MSG_PREP"

show_progress 1 $TOTAL_STEPS "$MSG_PREP"

# ==========================================================
# 2. KONFIGURACJA SYSTEMOWA (SUDO)
# ==========================================================
show_progress 2 $TOTAL_STEPS "$MSG_OPTIMIZE"

NIXOS_DIR="/etc/nixos"
NIXOS_CONF="$NIXOS_DIR/configuration.nix"
KDE_MODULE="$NIXOS_DIR/kde-visual.nix"

if [[ ! -f "$NIXOS_CONF" ]]; then
    log_err "Nie znaleziono $NIXOS_CONF." "$NIXOS_CONF not found."
    exit 1
fi

if [[ -f "$SCRIPT_DIR/piwo.png" ]]; then
    cp -af "$SCRIPT_DIR/piwo.png" "$HOME/.face" 2>/dev/null || true
    chmod 644 "$HOME/.face" 2>/dev/null || true

    AVATAR_DEST="/var/lib/AccountsService/icons/$CURRENT_USER"
    ACCOUNTS_FILE="/var/lib/AccountsService/users/$CURRENT_USER"

    sudo mkdir -p /var/lib/AccountsService/icons/ /var/lib/AccountsService/users/ || true
    sudo cp -f "$SCRIPT_DIR/piwo.png" "$AVATAR_DEST" || true
    sudo chmod 644 "$AVATAR_DEST" || true

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "[User]\nIcon=$AVATAR_DEST" | sudo tee "$ACCOUNTS_FILE" > /dev/null
    elif sudo grep -q "^Icon=" "$ACCOUNTS_FILE"; then
        sudo sed -i "s|^Icon=.*|Icon=$AVATAR_DEST|" "$ACCOUNTS_FILE" || true
    else
        echo "Icon=$AVATAR_DEST" | sudo tee -a "$ACCOUNTS_FILE" > /dev/null
    fi

    sudo systemctl restart accounts-daemon 2>/dev/null || true
fi

KDE_MODULE_TMP="$(mktemp)"
cat > "$KDE_MODULE_TMP" <<'NIX_EOF'
{ config, pkgs, lib, ... }:

{
NIX_EOF

if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    sudo mkdir -p "$NIXOS_DIR/wallpapers"
    sudo install -m 644 -o root -g root "$SCRIPT_DIR/login-wallpaper.png" "$NIXOS_DIR/wallpapers/login-wallpaper.png"
    cat >> "$KDE_MODULE_TMP" <<'NIX_EOF'
  environment.etc."plasmalogin.conf".text = ''
    [Greeter][Wallpaper][org.kde.image][General]
    Image=file:///etc/nixos/wallpapers/login-wallpaper.png
  '';
NIX_EOF
fi

echo "}" >> "$KDE_MODULE_TMP"
sudo install -m 644 -o root -g root "$KDE_MODULE_TMP" "$KDE_MODULE"
rm -f "$KDE_MODULE_TMP"

sudo cp -f "$NIXOS_CONF" "$NIXOS_CONF.bak"
if ! sudo grep -q "kde-visual.nix" "$NIXOS_CONF"; then
    if sudo grep -q "\./hardware-configuration\.nix" "$NIXOS_CONF"; then
        sudo sed -i 's|\./hardware-configuration\.nix|& ./kde-visual.nix|' "$NIXOS_CONF"
    else
        log_err "Nie można dodać ./kde-visual.nix do imports w $NIXOS_CONF - dodaj ręcznie." \
                "Cannot add ./kde-visual.nix to imports in $NIXOS_CONF - add it manually."
        exit 1
    fi
fi

[[ -e /etc/plasmalogin.conf && ! -L /etc/plasmalogin.conf ]] && sudo rm -f /etc/plasmalogin.conf

if ! sudo nixos-rebuild switch; then
    sudo cp -f "$NIXOS_CONF.bak" "$NIXOS_CONF"
    log_err "nixos-rebuild nie powiódł się - przywrócono configuration.nix." "nixos-rebuild failed - configuration.nix restored."
    exit 1
fi

safe_copy_dir() {
    local src="$1" dst="$2"
    if [[ -d "$src" ]] && [[ "$(realpath "$src" 2>/dev/null)" != "$(realpath "$dst" 2>/dev/null)" ]]; then
        mkdir -p "$dst" 2>/dev/null || return 0
        cp -af "$src/." "$dst/" 2>/dev/null || true
    fi
    return 0
}

TARGET_DIR="$HOME/.local/share/wallpapers"
mkdir -p "$TARGET_DIR"

show_progress 3 $TOTAL_STEPS "$MSG_OPTIMIZE"

# ==========================================================
# 3. KONFIGURACJA WIZUALNA (KONTO UŻYTKOWNIKA)
# ==========================================================
systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
kquitapp6 plasmashell 2>/dev/null || killall -9 plasmashell 2>/dev/null || true
sleep 2

show_progress 4 $TOTAL_STEPS "$MSG_OPTIMIZE"

safe_copy_dir "$SCRIPT_DIR/.config" ~/.config
safe_copy_dir "$SCRIPT_DIR/.local" ~/.local
safe_copy_dir "$SCRIPT_DIR/.icons" ~/.icons

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

show_progress 5 $TOTAL_STEPS "$MSG_OPTIMIZE"

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

show_progress 6 $TOTAL_STEPS "$MSG_OPTIMIZE"

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental &>/dev/null || true
fi

# ==========================================================
# 4. ZAKOŃCZENIE I SPRZĄTANIE
# ==========================================================

show_progress 7 $TOTAL_STEPS "$MSG_FINALIZE"
printf '\n\n' >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

DO_REBOOT=1
exit 0