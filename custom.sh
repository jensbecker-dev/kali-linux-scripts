#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# custom.sh v2.0.0 (Release)
# Scope: Nur individuelle Desktop-Konfiguration über Schritte 1-12.

# ─────────────────────────────────────────────────────────────────────────────
# Farben
# ─────────────────────────────────────────────────────────────────────────────

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_GREEN='\033[0;32m'
C_BGREEN='\033[1;32m'
C_CYAN='\033[0;36m'
C_BCYAN='\033[1;36m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_WHITE='\033[1;37m'

cecho() { echo -e "$1$2${C_RESET}"; }
header_line() { cecho "$C_CYAN" "$(printf '─%.0s' {1..70})"; }
section_line() { cecho "$C_DIM" "$(printf '·%.0s' {1..70})"; }

# ─────────────────────────────────────────────────────────────────────────────
# Logging / Helpers
# ─────────────────────────────────────────────────────────────────────────────

log() { echo "[*] $1"; }
warn() { echo "[~] $1"; }
error() { echo "[!] $1" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }
is_interactive() { [ -t 0 ] && [ -t 1 ]; }

on_error() {
    local line="$1"
    error "Fehler in Zeile $line. Abbruch."
}
trap 'on_error $LINENO' ERR

prompt_choice() {
    echo "" >&2
    echo -e -n "  ${C_BCYAN}▶ Auswahl: ${C_RESET}" >&2
    local choice
    read -r choice
    choice="$(echo "$choice" | xargs)"
    printf '%s\n' "$choice"
}

confirm_action() {
    local msg="$1"
    echo -e "\n  ${C_YELLOW}${msg}${C_RESET}"
    echo -e -n "  ${C_BOLD}Fortfahren? [j/N]: ${C_RESET}" >&2
    local yn
    read -r yn
    [[ "${yn,,}" == "j" || "${yn,,}" == "ja" || "${yn,,}" == "y" || "${yn,,}" == "yes" ]]
}

press_enter() {
    if ! is_interactive; then
        return 0
    fi
    echo -e "\n  ${C_DIM}[ Enter drücken um fortzufahren... ]${C_RESET}"
    read -r
}

menu_header() {
    local title="$1"
    if is_interactive; then
        clear
    fi

    cecho "$C_BGREEN" "\n  fsocietyhub — Kali Linux Desktop Configurator (Release)"
    header_line
    cecho "$C_BCYAN" "  $title"
    cecho "$C_DIM" "  Fokus: Individuelle Desktop-Konfiguration (Schritt 1-12)"
    header_line
    echo ""
}

show_option() {
    local num="$1" label="$2" current="${3:-}"
    if [ -n "$current" ]; then
        echo -e "  ${C_YELLOW}${num})${C_RESET} ${C_WHITE}${label}${C_RESET}  ${C_DIM}[aktuell: ${current}]${C_RESET}"
    else
        echo -e "  ${C_YELLOW}${num})${C_RESET} ${C_WHITE}${label}${C_RESET}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Environment
# ─────────────────────────────────────────────────────────────────────────────

ENV_DE=""
ENV_WM=""
ENV_DISPLAY_SERVER=""
ENV_SESSION=""
ENV_DISTRO=""

SETTINGS_DIR="$HOME/.config/kali-desktop"
SETTINGS_FILE="$SETTINGS_DIR/settings.conf"
BACKUP_DIR="$HOME/.desktop_backup"

# Defaults
CFG_WM="auto"
CFG_COMPOSITOR="picom"
CFG_TERMINAL="alacritty"
CFG_BAR="auto"
CFG_LAUNCHER="rofi"
CFG_FILEMANAGER="thunar"
CFG_NOTIFICATIONS="dunst"
CFG_WALLPAPER_TOOL="feh"
CFG_GTK_THEME="auto"
CFG_ICON_THEME="auto"
CFG_FONT="FiraCode Nerd Font"
CFG_FONT_SIZE="11"

ensure_parent_dir() {
    local target="$1"
    mkdir -p "$(dirname "$target")"
}

detect_environment() {
    if [ -n "${WAYLAND_DISPLAY-}" ]; then
        ENV_DISPLAY_SERVER="Wayland"
    elif [ -n "${DISPLAY-}" ]; then
        ENV_DISPLAY_SERVER="X11"
    else
        ENV_DISPLAY_SERVER="Headless/TTY"
    fi

    ENV_SESSION="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unbekannt}}"
    case "${ENV_SESSION,,}" in
        *gnome*) ENV_DE="GNOME" ;;
        *kde*) ENV_DE="KDE Plasma" ;;
        *xfce*) ENV_DE="XFCE" ;;
        *i3*) ENV_DE="i3" ;;
        *sway*) ENV_DE="Sway" ;;
        *) ENV_DE="Unbekannt/Minimal" ;;
    esac

    if command_exists wmctrl; then
        ENV_WM="$(wmctrl -m 2>/dev/null | awk '/Name:/{print $2}' || true)"
    fi
    [ -z "$ENV_WM" ] && ENV_WM="unbekannt"

    if [ -f /etc/os-release ]; then
        ENV_DISTRO="$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")"
    else
        ENV_DISTRO="Unbekannt"
    fi
}

load_settings() {
    mkdir -p "$SETTINGS_DIR"
    if [ -f "$SETTINGS_FILE" ]; then
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            value="${value//\"/}"
            case "$key" in
                CFG_WM) CFG_WM="$value" ;;
                CFG_COMPOSITOR) CFG_COMPOSITOR="$value" ;;
                CFG_TERMINAL) CFG_TERMINAL="$value" ;;
                CFG_BAR) CFG_BAR="$value" ;;
                CFG_LAUNCHER) CFG_LAUNCHER="$value" ;;
                CFG_FILEMANAGER) CFG_FILEMANAGER="$value" ;;
                CFG_NOTIFICATIONS) CFG_NOTIFICATIONS="$value" ;;
                CFG_WALLPAPER_TOOL) CFG_WALLPAPER_TOOL="$value" ;;
                CFG_GTK_THEME) CFG_GTK_THEME="$value" ;;
                CFG_ICON_THEME) CFG_ICON_THEME="$value" ;;
                CFG_FONT) CFG_FONT="$value" ;;
                CFG_FONT_SIZE) CFG_FONT_SIZE="$value" ;;
            esac
        done < "$SETTINGS_FILE"
    fi
}

save_settings() {
    mkdir -p "$SETTINGS_DIR"
    cat > "$SETTINGS_FILE" <<EOF
# Kali Desktop Konfiguration – gespeichert am $(date)
CFG_WM="$CFG_WM"
CFG_COMPOSITOR="$CFG_COMPOSITOR"
CFG_TERMINAL="$CFG_TERMINAL"
CFG_BAR="$CFG_BAR"
CFG_LAUNCHER="$CFG_LAUNCHER"
CFG_FILEMANAGER="$CFG_FILEMANAGER"
CFG_NOTIFICATIONS="$CFG_NOTIFICATIONS"
CFG_WALLPAPER_TOOL="$CFG_WALLPAPER_TOOL"
CFG_GTK_THEME="$CFG_GTK_THEME"
CFG_ICON_THEME="$CFG_ICON_THEME"
CFG_FONT="$CFG_FONT"
CFG_FONT_SIZE="$CFG_FONT_SIZE"
EOF
    cecho "$C_BGREEN" "  ✔ Einstellungen gespeichert: $SETTINGS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# System-Aktionen
# ─────────────────────────────────────────────────────────────────────────────

safe_apt_update() {
    if ! command_exists apt-get; then
        error "apt-get ist nicht verfügbar."
        return 1
    fi
    log "Aktualisiere Paketlisten..."
    sudo apt-get update
}

package_available() {
    local pkg="$1"
    if ! command_exists apt-cache; then
        return 0
    fi
    apt-cache show "$pkg" >/dev/null 2>&1
}

safe_install_packages() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi

    local available=()
    local unavailable=()
    local seen=()

    for pkg in "$@"; do
        if [[ " ${seen[*]} " == *" $pkg "* ]]; then
            continue
        fi
        seen+=("$pkg")
        if package_available "$pkg"; then
            available+=("$pkg")
        else
            unavailable+=("$pkg")
        fi
    done

    if [ "${#unavailable[@]}" -gt 0 ]; then
        warn "Nicht verfügbar, übersprungen: ${unavailable[*]}"
    fi

    if [ "${#available[@]}" -eq 0 ]; then
        warn "Keine verfügbaren Pakete zu installieren."
        return 0
    fi

    log "Installiere: ${available[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
}

backup_current_setup() {
    mkdir -p "$BACKUP_DIR"
    log "Erstelle Backup aktueller Theme-Einstellungen..."

    if command_exists gsettings && [ -n "${DBUS_SESSION_BUS_ADDRESS-}" ]; then
        gsettings get org.gnome.desktop.interface gtk-theme > "$BACKUP_DIR/gtk_theme.txt" 2>/dev/null || true
        gsettings get org.gnome.desktop.interface icon-theme > "$BACKUP_DIR/icon_theme.txt" 2>/dev/null || true
    fi

    cecho "$C_BGREEN" "  ✔ Backup erstellt: $BACKUP_DIR"
}

install_base_dependencies() {
    safe_apt_update
    safe_install_packages \
        curl wget unzip git \
        picom feh rofi alacritty thunar \
        waybar polybar tint2 dmenu wofi \
        pavucontrol playerctl vlc \
        brightnessctl network-manager-applet \
        fonts-firacode fonts-jetbrains-mono \
        papirus-icon-theme arc-theme gnome-themes-extra
}

apply_gsettings_if_available() {
    if ! command_exists gsettings || [ -z "${DBUS_SESSION_BUS_ADDRESS-}" ]; then
        warn "gsettings/DBUS nicht verfügbar, überspringe Theme-Aktivierung."
        return 0
    fi

    if [ "$CFG_GTK_THEME" != "auto" ] && [ -n "$CFG_GTK_THEME" ]; then
        gsettings set org.gnome.desktop.interface gtk-theme "$CFG_GTK_THEME" 2>/dev/null || true
    fi

    if [ "$CFG_ICON_THEME" != "auto" ] && [ -n "$CFG_ICON_THEME" ]; then
        gsettings set org.gnome.desktop.interface icon-theme "$CFG_ICON_THEME" 2>/dev/null || true
    fi
}

configure_alacritty() {
    if [ "$CFG_TERMINAL" != "alacritty" ]; then
        return 0
    fi

    mkdir -p "$HOME/.config/alacritty"
    cat > "$HOME/.config/alacritty/alacritty.yml" <<EOF
font:
  normal:
    family: "$CFG_FONT"
    style: Regular
  size: ${CFG_FONT_SIZE}.0
window:
  padding:
    x: 10
    y: 10
  opacity: 0.95
EOF
}

configure_i3_sway() {
    local terminal_cmd="$CFG_TERMINAL"

    if [ "$CFG_WM" = "i3" ]; then
        mkdir -p "$HOME/.config/i3"
        cat > "$HOME/.config/i3/config" <<EOF
set $mod Mod4
font pango:${CFG_FONT} ${CFG_FONT_SIZE}
bindsym $mod+Return exec ${terminal_cmd}
exec --no-startup-id picom -b
EOF
    fi

    if [ "$CFG_WM" = "sway" ]; then
        mkdir -p "$HOME/.config/sway"
        cat > "$HOME/.config/sway/config" <<EOF
set $mod Mod4
font pango:${CFG_FONT} ${CFG_FONT_SIZE}
bindsym $mod+Return exec ${terminal_cmd}
EOF
    fi
}

install_selected_components() {
    # WM
    case "$CFG_WM" in
        i3|openbox|bspwm|fluxbox|dwm|sway|hyprland|river)
            safe_install_packages "$CFG_WM"
            ;;
    esac

    # Compositor
    case "$CFG_COMPOSITOR" in
        picom|compton|xcompmgr)
            safe_install_packages "$CFG_COMPOSITOR"
            ;;
    esac

    # Terminal
    case "$CFG_TERMINAL" in
        alacritty|kitty|xterm|terminator)
            safe_install_packages "$CFG_TERMINAL"
            ;;
        xfce4-terminal|gnome-terminal|konsole|st)
            safe_install_packages "$CFG_TERMINAL"
            ;;
    esac

    # Bar
    case "$CFG_BAR" in
        polybar|waybar|tint2|xfce4-panel|lxpanel|i3bar)
            safe_install_packages "$CFG_BAR"
            ;;
    esac

    # Launcher
    case "$CFG_LAUNCHER" in
        rofi)
            safe_install_packages rofi ;;
        dmenu)
            safe_install_packages suckless-tools ;;
        wofi|ulauncher|albert)
            safe_install_packages "$CFG_LAUNCHER" ;;
    esac

    # Filemanager
    case "$CFG_FILEMANAGER" in
        thunar|nautilus|dolphin|nemo|ranger|pcmanfm|lf)
            safe_install_packages "$CFG_FILEMANAGER" ;;
    esac

    # Notifications
    case "$CFG_NOTIFICATIONS" in
        dunst)
            safe_install_packages dunst ;;
        mako)
            safe_install_packages mako-notifier ;;
        notify-osd|xfce4-notifyd)
            safe_install_packages "$CFG_NOTIFICATIONS" ;;
    esac

    # Wallpaper tool
    case "$CFG_WALLPAPER_TOOL" in
        feh|nitrogen|variety|swaybg|xwallpaper)
            safe_install_packages "$CFG_WALLPAPER_TOOL" ;;
    esac
}

apply_custom_config() {
    menu_header "SCHRITT 12 – KONFIGURATION ANWENDEN"

    cecho "$C_YELLOW" "  Folgende Konfiguration wird angewendet:"
    echo -e "  ${C_DIM}1  WM:${C_RESET}             $CFG_WM"
    echo -e "  ${C_DIM}2  Compositor:${C_RESET}     $CFG_COMPOSITOR"
    echo -e "  ${C_DIM}3  Terminal:${C_RESET}       $CFG_TERMINAL"
    echo -e "  ${C_DIM}4  Bar:${C_RESET}            $CFG_BAR"
    echo -e "  ${C_DIM}5  Launcher:${C_RESET}       $CFG_LAUNCHER"
    echo -e "  ${C_DIM}6  Dateimanager:${C_RESET}   $CFG_FILEMANAGER"
    echo -e "  ${C_DIM}7  Notifications:${C_RESET}  $CFG_NOTIFICATIONS"
    echo -e "  ${C_DIM}8  Wallpaper-Tool:${C_RESET} $CFG_WALLPAPER_TOOL"
    echo -e "  ${C_DIM}9  GTK Theme:${C_RESET}      $CFG_GTK_THEME"
    echo -e "  ${C_DIM}10 Icon Theme:${C_RESET}     $CFG_ICON_THEME"
    echo -e "  ${C_DIM}11 Font:${C_RESET}           $CFG_FONT $CFG_FONT_SIZE"
    echo ""

    if ! confirm_action "Konfiguration jetzt ausrollen?"; then
        return
    fi

    backup_current_setup
    install_base_dependencies
    install_selected_components
    apply_gsettings_if_available
    configure_alacritty
    configure_i3_sway
    save_settings

    cecho "$C_BGREEN" "\n  ✔ Fertig. Individuelle Desktop-Konfiguration wurde angewendet."
    cecho "$C_YELLOW" "  Hinweis: Ein Logout/Login kann erforderlich sein."
    press_enter
}

# ─────────────────────────────────────────────────────────────────────────────
# Schritt 1–11 Menüs
# ─────────────────────────────────────────────────────────────────────────────

menu_select_wm() {
    menu_header "SCHRITT 1 – WINDOW MANAGER"
    show_option "1" "i3"
    show_option "2" "openbox"
    show_option "3" "bspwm"
    show_option "4" "fluxbox"
    show_option "5" "dwm"
    show_option "6" "sway"
    show_option "7" "hyprland"
    show_option "8" "river"
    show_option "9" "auto"
    show_option "99" "Manuell eingeben"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_WM"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_WM="i3" ;;
        2) CFG_WM="openbox" ;;
        3) CFG_WM="bspwm" ;;
        4) CFG_WM="fluxbox" ;;
        5) CFG_WM="dwm" ;;
        6) CFG_WM="sway" ;;
        7) CFG_WM="hyprland" ;;
        8) CFG_WM="river" ;;
        9) CFG_WM="auto" ;;
        99)
            echo -e -n "  ${C_BCYAN}WM Name: ${C_RESET}"
            read -r CFG_WM
            ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_compositor() {
    menu_header "SCHRITT 2 – COMPOSITOR"
    show_option "1" "picom"
    show_option "2" "compton"
    show_option "3" "xcompmgr"
    show_option "4" "eingebaut"
    show_option "5" "keiner"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_COMPOSITOR"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_COMPOSITOR="picom" ;;
        2) CFG_COMPOSITOR="compton" ;;
        3) CFG_COMPOSITOR="xcompmgr" ;;
        4) CFG_COMPOSITOR="eingebaut" ;;
        5) CFG_COMPOSITOR="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_terminal() {
    menu_header "SCHRITT 3 – TERMINAL"
    show_option "1" "alacritty"
    show_option "2" "kitty"
    show_option "3" "xterm"
    show_option "4" "xfce4-terminal"
    show_option "5" "gnome-terminal"
    show_option "6" "konsole"
    show_option "7" "terminator"
    show_option "8" "st"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_TERMINAL"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_TERMINAL="alacritty" ;;
        2) CFG_TERMINAL="kitty" ;;
        3) CFG_TERMINAL="xterm" ;;
        4) CFG_TERMINAL="xfce4-terminal" ;;
        5) CFG_TERMINAL="gnome-terminal" ;;
        6) CFG_TERMINAL="konsole" ;;
        7) CFG_TERMINAL="terminator" ;;
        8) CFG_TERMINAL="st" ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_bar() {
    menu_header "SCHRITT 4 – BAR / PANEL"
    show_option "1" "polybar"
    show_option "2" "waybar"
    show_option "3" "tint2"
    show_option "4" "xfce4-panel"
    show_option "5" "lxpanel"
    show_option "6" "i3bar"
    show_option "7" "auto"
    show_option "8" "keiner"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_BAR"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_BAR="polybar" ;;
        2) CFG_BAR="waybar" ;;
        3) CFG_BAR="tint2" ;;
        4) CFG_BAR="xfce4-panel" ;;
        5) CFG_BAR="lxpanel" ;;
        6) CFG_BAR="i3bar" ;;
        7) CFG_BAR="auto" ;;
        8) CFG_BAR="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_launcher() {
    menu_header "SCHRITT 5 – LAUNCHER"
    show_option "1" "rofi"
    show_option "2" "dmenu"
    show_option "3" "wofi"
    show_option "4" "ulauncher"
    show_option "5" "albert"
    show_option "6" "keiner"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_LAUNCHER"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_LAUNCHER="rofi" ;;
        2) CFG_LAUNCHER="dmenu" ;;
        3) CFG_LAUNCHER="wofi" ;;
        4) CFG_LAUNCHER="ulauncher" ;;
        5) CFG_LAUNCHER="albert" ;;
        6) CFG_LAUNCHER="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_filemanager() {
    menu_header "SCHRITT 6 – DATEIMANAGER"
    show_option "1" "thunar"
    show_option "2" "nautilus"
    show_option "3" "dolphin"
    show_option "4" "nemo"
    show_option "5" "ranger"
    show_option "6" "lf"
    show_option "7" "pcmanfm"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_FILEMANAGER"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_FILEMANAGER="thunar" ;;
        2) CFG_FILEMANAGER="nautilus" ;;
        3) CFG_FILEMANAGER="dolphin" ;;
        4) CFG_FILEMANAGER="nemo" ;;
        5) CFG_FILEMANAGER="ranger" ;;
        6) CFG_FILEMANAGER="lf" ;;
        7) CFG_FILEMANAGER="pcmanfm" ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_notifications() {
    menu_header "SCHRITT 7 – NOTIFICATIONS"
    show_option "1" "dunst"
    show_option "2" "mako"
    show_option "3" "notify-osd"
    show_option "4" "xfce4-notifyd"
    show_option "5" "keiner"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_NOTIFICATIONS"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_NOTIFICATIONS="dunst" ;;
        2) CFG_NOTIFICATIONS="mako" ;;
        3) CFG_NOTIFICATIONS="notify-osd" ;;
        4) CFG_NOTIFICATIONS="xfce4-notifyd" ;;
        5) CFG_NOTIFICATIONS="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_wallpaper_tool() {
    menu_header "SCHRITT 8 – WALLPAPER-TOOL"
    show_option "1" "feh"
    show_option "2" "nitrogen"
    show_option "3" "variety"
    show_option "4" "swaybg"
    show_option "5" "xwallpaper"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_WALLPAPER_TOOL"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_WALLPAPER_TOOL="feh" ;;
        2) CFG_WALLPAPER_TOOL="nitrogen" ;;
        3) CFG_WALLPAPER_TOOL="variety" ;;
        4) CFG_WALLPAPER_TOOL="swaybg" ;;
        5) CFG_WALLPAPER_TOOL="xwallpaper" ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_gtk_theme() {
    menu_header "SCHRITT 9 – GTK THEME"
    show_option "1" "auto"
    show_option "2" "Adwaita"
    show_option "3" "Arc"
    show_option "4" "Arc-Dark"
    show_option "5" "Dracula"
    show_option "6" "Windows XP Luna"
    show_option "99" "Manuell eingeben"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_GTK_THEME"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_GTK_THEME="auto" ;;
        2) CFG_GTK_THEME="Adwaita" ;;
        3) CFG_GTK_THEME="Arc" ;;
        4) CFG_GTK_THEME="Arc-Dark" ;;
        5) CFG_GTK_THEME="Dracula" ;;
        6) CFG_GTK_THEME="Windows XP Luna" ;;
        99)
            echo -e -n "  ${C_BCYAN}Theme-Name: ${C_RESET}"
            read -r CFG_GTK_THEME
            ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_icon_theme() {
    menu_header "SCHRITT 10 – ICON THEME"
    show_option "1" "auto"
    show_option "2" "Adwaita"
    show_option "3" "Papirus"
    show_option "4" "Papirus-Dark"
    show_option "5" "hicolor"
    show_option "99" "Manuell eingeben"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_ICON_THEME"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_ICON_THEME="auto" ;;
        2) CFG_ICON_THEME="Adwaita" ;;
        3) CFG_ICON_THEME="Papirus" ;;
        4) CFG_ICON_THEME="Papirus-Dark" ;;
        5) CFG_ICON_THEME="hicolor" ;;
        99)
            echo -e -n "  ${C_BCYAN}Icon-Theme: ${C_RESET}"
            read -r CFG_ICON_THEME
            ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    save_settings
}

menu_select_font() {
    menu_header "SCHRITT 11 – SCHRIFT"
    show_option "1" "FiraCode Nerd Font"
    show_option "2" "JetBrains Mono"
    show_option "3" "Hack Nerd Font"
    show_option "4" "DejaVu Sans Mono"
    show_option "5" "Monospace"
    show_option "6" "Tahoma"
    show_option "99" "Manuell eingeben"
    show_option "0" "Zurück"
    cecho "$C_DIM" "  Aktuell: $CFG_FONT $CFG_FONT_SIZE"

    local c
    c=$(prompt_choice)
    case "$c" in
        1) CFG_FONT="FiraCode Nerd Font" ;;
        2) CFG_FONT="JetBrains Mono" ;;
        3) CFG_FONT="Hack Nerd Font" ;;
        4) CFG_FONT="DejaVu Sans Mono" ;;
        5) CFG_FONT="Monospace" ;;
        6) CFG_FONT="Tahoma" ;;
        99)
            echo -e -n "  ${C_BCYAN}Schriftname: ${C_RESET}"
            read -r CFG_FONT
            ;;
        0) return ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac

    echo -e -n "  ${C_BCYAN}Schriftgröße [aktuell: $CFG_FONT_SIZE]: ${C_RESET}"
    local size
    read -r size
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        CFG_FONT_SIZE="$size"
    fi

    save_settings
}

# ─────────────────────────────────────────────────────────────────────────────
# Hauptmenü (NUR Schritte 1-12)
# ─────────────────────────────────────────────────────────────────────────────

show_main_menu() {
    while true; do
        menu_header "INDIVIDUELLE DESKTOP-KONFIGURATION (SCHRITT 1-12)"

        echo -e "  ${C_DIM}System:${C_RESET} $ENV_DISTRO  |  ${C_DIM}DE:${C_RESET} $ENV_DE  |  ${C_DIM}WM:${C_RESET} $ENV_WM  |  ${C_DIM}Display:${C_RESET} $ENV_DISPLAY_SERVER"
        echo ""

        show_option "1" "Window Manager" "$CFG_WM"
        show_option "2" "Compositor" "$CFG_COMPOSITOR"
        show_option "3" "Terminal" "$CFG_TERMINAL"
        show_option "4" "Bar / Panel" "$CFG_BAR"
        show_option "5" "Launcher" "$CFG_LAUNCHER"
        show_option "6" "Dateimanager" "$CFG_FILEMANAGER"
        show_option "7" "Benachrichtigungen" "$CFG_NOTIFICATIONS"
        show_option "8" "Wallpaper-Tool" "$CFG_WALLPAPER_TOOL"
        show_option "9" "GTK Theme" "$CFG_GTK_THEME"
        show_option "10" "Icon Theme" "$CFG_ICON_THEME"
        show_option "11" "Schriftart" "$CFG_FONT $CFG_FONT_SIZE"

        echo ""
        section_line
        show_option "12" "Konfiguration anwenden"
        show_option "0" "Beenden"

        local c
        c=$(prompt_choice)
        case "$c" in
            1) menu_select_wm ;;
            2) menu_select_compositor ;;
            3) menu_select_terminal ;;
            4) menu_select_bar ;;
            5) menu_select_launcher ;;
            6) menu_select_filemanager ;;
            7) menu_select_notifications ;;
            8) menu_select_wallpaper_tool ;;
            9) menu_select_gtk_theme ;;
            10) menu_select_icon_theme ;;
            11) menu_select_font ;;
            12) apply_custom_config ;;
            0)
                cecho "$C_DIM" "\n  Auf Wiedersehen."
                echo ""
                exit 0
                ;;
            *)
                error "Ungültige Auswahl."
                press_enter
                ;;
        esac
    done
}

print_help() {
    cat <<EOF
Verwendung: ./custom.sh

Release-Fokus:
  - Ausschließlich individueller Konfigurationsfluss über Schritt 1-12
  - Keine Schnell-Setups, keine Modes, keine Zusatz-Tools-Menüs

Schritte:
  1  Window Manager
  2  Compositor
  3  Terminal
  4  Bar/Panel
  5  Launcher
  6  Dateimanager
  7  Benachrichtigungen
  8  Wallpaper-Tool
  9  GTK Theme
  10 Icon Theme
  11 Schrift
  12 Anwenden
EOF
}

main() {
    detect_environment
    load_settings

    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        print_help
        return 0
    fi

    if ! is_interactive; then
        error "Kein interaktives Terminal erkannt. Nutze --help."
        return 1
    fi

    show_main_menu
}

main "$@"
