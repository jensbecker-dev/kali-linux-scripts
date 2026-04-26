#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[*] $1"
}

warn() {
    echo "[~] $1"
}

error() {
    echo "[!] $1" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

ensure_parent_dir() {
    local target="$1"
    mkdir -p "$(dirname "$target")"
}

download_file() {
    local url="$1"
    local dest="$2"

    ensure_parent_dir "$dest"

    if command_exists curl; then
        curl --fail --silent --show-error --location --retry 3 "$url" -o "$dest"
    elif command_exists wget; then
        wget -q --tries=3 -O "$dest" "$url"
    else
        error "Kein Download-Client gefunden. Installiere curl oder wget."
        return 1
    fi
}

extract_zip() {
    local archive="$1"
    local dest_dir="${2:-.}"

    if ! command_exists unzip; then
        error "unzip ist nicht installiert."
        return 1
    fi

    unzip -o "$archive" -d "$dest_dir"
}

gsettings_available() {
    if ! command_exists gsettings; then
        return 1
    fi
    if [ -z "${DBUS_SESSION_BUS_ADDRESS-}" ]; then
        return 1
    fi
    if ! gsettings writable org.gnome.desktop.interface gtk-theme >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

safe_apt_update() {
    if ! command_exists apt-get; then
        error "apt-get ist auf diesem System nicht vorhanden."
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

    if ! apt-cache show "$pkg" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

safe_install_packages() {
    if ! command_exists apt-get; then
        error "apt-get ist auf diesem System nicht vorhanden."
        return 1
    fi

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
        log "Paket(e) nicht verfügbar und werden übersprungen: ${unavailable[*]}"
    fi

    if [ "${#available[@]}" -eq 0 ]; then
        log "Keine verfügbaren Pakete zum Installieren."
        return 0
    fi

    log "Installiere verfügbare Pakete: ${available[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
}

backup_current_setup() {
    log "Backup der aktuellen Desktop-Einstellungen..."
    local backup_dir="$HOME/.desktop_backup"
    mkdir -p "$backup_dir"

    if command_exists scrot && [ -n "${DISPLAY-}" ]; then
        scrot "$backup_dir/current_desktop.png" >/dev/null 2>&1 || log "scrot fehlgeschlagen oder keine grafische Oberfläche verfügbar."
    else
        log "scrot nicht verfügbar oder DISPLAY nicht gesetzt. Überspringe Screenshot."
    fi

    if gsettings_available; then
        gsettings get org.gnome.desktop.interface gtk-theme > "$backup_dir/gtk_theme.txt" 2>/dev/null || true
        gsettings get org.gnome.desktop.interface icon-theme > "$backup_dir/icon_theme.txt" 2>/dev/null || true
        gsettings get org.gnome.desktop.wm.preferences theme > "$backup_dir/wm_theme.txt" 2>/dev/null || true
    else
        log "gsettings nicht verfügbar. Speichere keine Theme-Daten."
    fi

    log "Backup gespeichert in $backup_dir"
}

restore_backup() {
    log "Wiederherstellung der Desktop-Einstellungen..."
    local backup_dir="$HOME/.desktop_backup"

    if [ ! -d "$backup_dir" ]; then
        error "Kein Backup-Verzeichnis gefunden: $backup_dir"
        return 1
    fi

    if gsettings_available; then
        if [ -f "$backup_dir/gtk_theme.txt" ]; then
            gsettings set org.gnome.desktop.interface gtk-theme "$(<"$backup_dir/gtk_theme.txt")" || true
        fi
        if [ -f "$backup_dir/icon_theme.txt" ]; then
            gsettings set org.gnome.desktop.interface icon-theme "$(<"$backup_dir/icon_theme.txt")" || true
        fi
        if [ -f "$backup_dir/wm_theme.txt" ]; then
            gsettings set org.gnome.desktop.wm.preferences theme "$(<"$backup_dir/wm_theme.txt")" || true
        fi
        log "Wiederherstellung abgeschlossen. Bitte starte die Sitzung neu, falls erforderlich."
    else
        error "gsettings nicht verfügbar. Themes können nicht wiederhergestellt werden."
    fi
}

install_custom_dependencies() {
    log "Installiere Abhängigkeiten..."
    safe_apt_update
    safe_install_packages \
        curl wget unzip git picom feh rofi waybar alacritty thunar variety \
        lxappearance fonts-font-awesome fonts-firacode \
        fonts-jetbrains-mono \
        playerctl pulseaudio-utils pavucontrol \
        scrot flameshot arandr brightnessctl \
        network-manager-applet bluez blueman python3-pip

    log "Nitrogen und ttf-nerd-fonts-symbols werden auf Kali-rolling nicht immer angeboten und werden optional übersprungen."
    log "Variety wird als Kali-kompatibler Hintergrund-Manager installiert, falls verfügbar."
}

nerd_fonts_install() {
    log "Installiere Nerd Fonts..."
    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"

    local nerd_font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FiraCode.zip"
    local nerd_font_zip="$font_dir/FiraCode.zip"

    if download_file "$nerd_font_url" "$nerd_font_zip"; then
        if extract_zip "$nerd_font_zip" "$font_dir"; then
            rm -f "$nerd_font_zip"
            if command_exists fc-cache; then
                fc-cache -fv "$font_dir" >/dev/null 2>&1 || true
            fi
        fi
    else
        error "Nerd-Fonts konnten nicht heruntergeladen werden."
    fi
}

themes_and_icons_install() {
    local design="$1"
    log "Installiere Themes und Icons für '$design'..."

    local themes_dir="$HOME/.themes"
    local icons_dir="$HOME/.icons"

    mkdir -p "$themes_dir" "$icons_dir"

    case "$design" in
        minimalistic)
            safe_install_packages gnome-themes-extra
            ;;
        corporate)
            safe_install_packages arc-theme papirus-icon-theme
            ;;
        windows_xp|hacker)
            safe_install_packages papirus-icon-theme gtk2-engines gtk2-engines-pixbuf
            local xp_theme_url="https://github.com/B00merang-Project/Windows-XP/archive/refs/heads/master.zip"
            local xp_theme_zip="$themes_dir/windows-xp.zip"
            if download_file "$xp_theme_url" "$xp_theme_zip"; then
                extract_zip "$xp_theme_zip" "$themes_dir"
                rm -f "$xp_theme_zip"
                if [ -d "$themes_dir/Windows-XP-master/Windows XP Luna" ]; then
                    mv "$themes_dir/Windows-XP-master/Windows XP Luna" "$themes_dir/Windows XP Luna" 2>/dev/null || true
                fi
                rm -rf "$themes_dir/Windows-XP-master"
            fi
            ;;
        fsocietyhub)
            safe_install_packages papirus-icon-theme
            local fsociety_theme_url="https://github.com/dracula/gtk/archive/refs/heads/master.zip"
            local fsociety_theme_zip="$themes_dir/fsocietyhub.zip"
            if download_file "$fsociety_theme_url" "$fsociety_theme_zip"; then
                extract_zip "$fsociety_theme_zip" "$themes_dir"
                rm -f "$fsociety_theme_zip"
            fi
            ;;
        *)
            error "Unbekanntes Design: $design"
            return 1
            ;;
    esac
}

split_gsettings_key() {
    local full_key="$1"
    local schema="${full_key% *}"
    local key="${full_key##* }"

    if [ "$schema" = "$full_key" ] || [ -z "$key" ]; then
        error "Ungültiger GSettings-Schlüssel: $full_key"
        return 1
    fi

    printf '%s\n%s\n' "$schema" "$key"
}

set_gsettings_theme() {
    local full_key="$1"
    local value="$2"
    local schema
    local key

    mapfile -t _gsettings_parts < <(split_gsettings_key "$full_key") || return 1
    schema="${_gsettings_parts[0]}"
    key="${_gsettings_parts[1]}"

    if ! gsettings_available; then
        warn "gsettings nicht verfügbar oder keine DBUS-Sitzung. Überspringe Theme-Aktivierung für $full_key."
        return 1
    fi

    if ! gsettings writable "$schema" "$key" >/dev/null 2>&1; then
        warn "GSettings-Schlüssel $full_key ist nicht beschreibbar oder wird nicht unterstützt."
        return 1
    fi

    if ! gsettings set "$schema" "$key" "'$value'" >/dev/null 2>&1; then
        warn "Theme-Wert $value konnte für $full_key nicht gesetzt werden."
        return 1
    fi
}

activate_themes_and_icons() {
    local design="$1"
    log "Aktiviere Themes und Icons für '$design'..."

    case "$design" in
        minimalistic)
            set_gsettings_theme "org.gnome.desktop.interface gtk-theme" "Adwaita"
            set_gsettings_theme "org.gnome.desktop.interface icon-theme" "Adwaita"
            set_gsettings_theme "org.gnome.desktop.wm.preferences theme" "Adwaita"
            ;;
        corporate)
            set_gsettings_theme "org.gnome.desktop.interface gtk-theme" "Arc"
            set_gsettings_theme "org.gnome.desktop.interface icon-theme" "Papirus"
            set_gsettings_theme "org.gnome.desktop.wm.preferences theme" "Arc"
            ;;
        windows_xp|hacker)
            set_gsettings_theme "org.gnome.desktop.interface gtk-theme" "Windows XP Luna"
            set_gsettings_theme "org.gnome.desktop.interface icon-theme" "Papirus"
            set_gsettings_theme "org.gnome.desktop.wm.preferences theme" "Windows XP Luna"
            ;;
        fsocietyhub)
            set_gsettings_theme "org.gnome.desktop.interface gtk-theme" "gtk-master"
            set_gsettings_theme "org.gnome.desktop.interface icon-theme" "Papirus-Dark"
            set_gsettings_theme "org.gnome.desktop.wm.preferences theme" "gtk-master"
            ;;
        *)
            error "Unbekanntes Design: $design"
            return 1
            ;;
    esac
}

apply_wallpaper() {
    local wallpaper_path="$1"
    local wallpaper_tool="${2:-${CFG_WALLPAPER_TOOL:-feh}}"

    if [ ! -f "$wallpaper_path" ]; then
        warn "Wallpaper-Datei fehlt: $wallpaper_path"
        return 1
    fi

    case "$wallpaper_tool" in
        variety)
            if command_exists variety; then
                variety --set "$wallpaper_path" >/dev/null 2>&1 || warn "Variety konnte das Wallpaper nicht setzen."
                return 0
            fi
            ;;
        nitrogen)
            if command_exists nitrogen && [ -n "${DISPLAY-}" ]; then
                nitrogen --set-zoom-fill "$wallpaper_path" >/dev/null 2>&1 || warn "Nitrogen konnte das Wallpaper nicht setzen."
                return 0
            fi
            ;;
        swaybg)
            if command_exists swaybg && [ -n "${WAYLAND_DISPLAY-}" ]; then
                pkill -x swaybg >/dev/null 2>&1 || true
                swaybg -i "$wallpaper_path" -m fill >/dev/null 2>&1 &
                disown || true
                return 0
            fi
            ;;
        xwallpaper)
            if command_exists xwallpaper && [ -n "${DISPLAY-}" ]; then
                xwallpaper --zoom "$wallpaper_path" >/dev/null 2>&1 || warn "xwallpaper konnte das Wallpaper nicht setzen."
                return 0
            fi
            ;;
    esac

    if command_exists feh && [ -n "${DISPLAY-}" ]; then
        feh --bg-scale "$wallpaper_path" >/dev/null 2>&1 || warn "feh konnte das Wallpaper nicht setzen."
        return 0
    fi

    warn "Kein kompatibles Wallpaper-Tool verfügbar oder keine grafische Sitzung erkannt."
    return 1
}

config_i3_or_sway() {
    local design="$1"
    local terminal_cmd="${CFG_TERMINAL:-alacritty}"
    local font_name="${CFG_FONT:-FiraCode Nerd Font}"
    local font_size="${CFG_FONT_SIZE:-10}"

    log "Konfiguriere i3/Sway für '$design'..."

    if command_exists i3; then
        mkdir -p "$HOME/.config/i3"
        cat > "$HOME/.config/i3/config" <<EOF
set $mod Mod4
font pango:${font_name} ${font_size}
bindsym $mod+Return exec ${terminal_cmd}
exec --no-startup-id picom -b
EOF
    fi

    if command_exists sway; then
        mkdir -p "$HOME/.config/sway"
        cat > "$HOME/.config/sway/config" <<EOF
set $mod Mod4
font pango:${font_name} ${font_size}
bindsym $mod+Return exec ${terminal_cmd}
EOF
        mkdir -p "$HOME/.config/waybar"
        cat > "$HOME/.config/waybar/config" <<'EOF'
{
  "layer": "top",
  "position": "top",
  "modules-left": ["sway/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["battery"]
}
EOF
    fi
}

customize_desktop_environment() {
    local design="$1"
    log "Passe Desktop-Umgebung für '$design' an..."

    local wallpaper_path
    local wallpaper_url

    mkdir -p "$HOME/Pictures"

    case "$design" in
        minimalistic)
            wallpaper_path="$HOME/Pictures/minimalistic_wallpaper.jpg"
            wallpaper_url="https://w.wallhaven.cc/full/5w/wallhaven-5wzvq1.jpg"
            ;;
        corporate)
            wallpaper_path="$HOME/Pictures/corporate_wallpaper.jpg"
            wallpaper_url="https://w.wallhaven.cc/full/o3/wallhaven-o3y1v7.jpg"
            ;;
        windows_xp)
            wallpaper_path="$HOME/Pictures/windows_xp_wallpaper.jpg"
            wallpaper_url="https://upload.wikimedia.org/wikipedia/commons/0/0c/Bliss_%28Windows_XP%29.jpg"
            ;;
        fsocietyhub)
            wallpaper_path="$HOME/Pictures/fsociety_wallpaper.jpg"
            wallpaper_url="https://w.wallhaven.cc/full/48/wallhaven-48q6yj.jpg"
            ;;
        *)
            wallpaper_path="$HOME/Pictures/wallpaper.jpg"
            wallpaper_url=""
            ;;
    esac

    if [ -n "$wallpaper_url" ] && ! [ -f "$wallpaper_path" ]; then
        download_file "$wallpaper_url" "$wallpaper_path" || warn "Wallpaper konnte nicht heruntergeladen werden: $wallpaper_url"
    fi

    if [ -f "$wallpaper_path" ]; then
        apply_wallpaper "$wallpaper_path" || true
    else
        warn "Kein Wallpaper gesetzt: Datei fehlt oder Download war nicht erfolgreich."
    fi

    if command_exists picom; then
        if [ -f "$HOME/.config/picom.conf" ]; then
            picom -b --config "$HOME/.config/picom.conf" >/dev/null 2>&1 || log "Picom konnte nicht gestartet werden."
        else
            picom -b >/dev/null 2>&1 || log "Picom konnte nicht gestartet werden."
        fi
    fi

    local rofi_config_dir="$HOME/.config/rofi"
    local rofi_config_path="$rofi_config_dir/config.rasi"
    mkdir -p "$rofi_config_dir"

    local rofi_config_url="https://raw.githubusercontent.com/adi1090x/rofi/master/files/colors/gruvbox.rasi"
    if ! download_file "$rofi_config_url" "$rofi_config_path"; then
        log "Rofi-Konfiguration konnte nicht heruntergeladen werden. Verwende Standardkonfiguration."
        cat > "$rofi_config_path" <<'EOF'
configuration {
    theme: "gruvbox"
}
EOF
    fi

    config_i3_or_sway "$design"
}

install_and_config_alacritty() {
    local design="$1"
    log "Installiere und konfiguriere Alacritty für '$design'..."
    safe_install_packages alacritty

    mkdir -p "$HOME/.config/alacritty"
    case "$design" in
        minimalistic)
            cat > "$HOME/.config/alacritty/alacritty.yml" <<'EOF'
font:
  normal:
    family: "Monospace"
    style: Regular
  size: 12.0
window:
  padding:
    x: 5
    y: 5
  opacity: 1.0
EOF
            ;;
        corporate)
            cat > "$HOME/.config/alacritty/alacritty.yml" <<'EOF'
font:
  normal:
    family: "DejaVu Sans Mono"
    style: Regular
  size: 10.0
window:
  padding:
    x: 10
    y: 10
  opacity: 0.9
EOF
            ;;
        windows_xp|hacker)
            cat > "$HOME/.config/alacritty/alacritty.yml" <<'EOF'
font:
  normal:
    family: "Tahoma"
    style: Regular
  size: 11.0
colors:
  primary:
    background: '0xC0C0C0'
    foreground: '0x000000'
  cursor:
    text: '0x000000'
    cursor: '0xFFFFFF'
window:
  padding:
    x: 10
    y: 10
  opacity: 0.95
EOF
            ;;
        fsocietyhub)
            cat > "$HOME/.config/alacritty/alacritty.yml" <<'EOF'
font:
  normal:
    family: "FiraCode Nerd Font"
    style: Regular
  size: 11.0
colors:
  primary:
    background: '0x000000'
    foreground: '0x00FF00'
  cursor:
    text: '0x000000'
    cursor: '0xFF0000'
window:
  padding:
    x: 10
    y: 10
  opacity: 0.95
EOF
            ;;
        *)
            error "Unbekanntes Design: $design"
            return 1
            ;;
    esac
}

install_system_monitoring_tools() {
    log "Installiere Systemüberwachungstools..."
    safe_install_packages btop htop glances neofetch
}

audio_and_media_tools() {
    log "Installiere Audio- und Medientools..."
    safe_install_packages pavucontrol playerctl vlc
    log "Starte pavucontrol oder playerctl manuell in deiner Sitzung, falls gewünscht."
}

brightness_control() {
    log "Installiere Helligkeitssteuerung..."
    safe_install_packages brightnessctl
    log "brightnessctl installiert. Helligkeit kann mit 'brightnessctl set <percent>' angepasst werden."
}

network_manager() {
    log "Installiere Network Manager..."
    safe_install_packages network-manager-applet
    log "Network Manager installiert. Verwende 'nmcli' oder das Applet deiner DE zum Verbinden."
}

finetuning_and_optimizations() {
    log "Führe Systembereinigung durch..."
    sudo apt-get autoremove -y || true
    sudo apt-get clean || true
}

manage_dot_files() {
    log "Verwalte Dotfiles..."

    local git_dir="$HOME/.dotfiles"
    local work_tree="$HOME"
    local git_cmd=(git --git-dir="$git_dir" --work-tree="$work_tree")

    if ! command_exists git; then
        error "Git ist nicht installiert. Überspringe Dotfiles-Verwaltung."
        return 1
    fi

    if [ ! -d "$git_dir" ]; then
        git init --bare "$git_dir"
    fi

    "${git_cmd[@]}" config --local status.showUntrackedFiles no >/dev/null 2>&1 || true

    local paths=()
    [ -f "$HOME/.config/alacritty/alacritty.yml" ] && paths+=(".config/alacritty/alacritty.yml")
    [ -f "$HOME/.config/rofi/config.rasi" ] && paths+=(".config/rofi/config.rasi")
    [ -d "$HOME/.themes" ] && paths+=(".themes")
    [ -d "$HOME/.icons" ] && paths+=(".icons")

    if [ "${#paths[@]}" -gt 0 ]; then
        "${git_cmd[@]}" add "${paths[@]}" >/dev/null 2>&1 || true
        if ! "${git_cmd[@]}" diff --cached --quiet --exit-code >/dev/null 2>&1; then
            "${git_cmd[@]}" commit -m "Update dotfiles" >/dev/null 2>&1 || true
        else
            log "Keine Änderungen für Dotfiles zum Committen."
        fi
    else
        log "Keine Dotfiles zum Hinzufügen gefunden."
    fi

    log "Dotfiles-Repository: $git_dir"
    log "Verwende 'git --git-dir=$git_dir --work-tree=$work_tree' für weitere Dotfiles-Operationen."
}

install_uv() {
    log "Installiere uv für Python-Umgebungsmanagement..."

    if ! command_exists python3; then
        error "python3 ist nicht installiert."
        return 1
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        safe_install_packages python3-pip
    fi

    python3 -m pip install --user uv --break-system-packages >/dev/null 2>&1 \
        || python3 -m pip install --user uv >/dev/null 2>&1 \
        || warn "uv konnte nicht installiert werden."
}

apply_design() {
    local design="$1"

    if [ "$design" = "hacker" ]; then
        log "Altes Hacker-Design wird als Kali Windows XP Mode interpretiert."
        design="windows_xp"
    fi

    clean_previous_installation "$design"
    backup_current_setup
    install_custom_dependencies
    nerd_fonts_install
    themes_and_icons_install "$design"
    activate_themes_and_icons "$design" || true
    customize_desktop_environment "$design"
    install_and_config_alacritty "$design"
    install_system_monitoring_tools
    audio_and_media_tools
    brightness_control
    network_manager
    finetuning_and_optimizations
    manage_dot_files
    install_uv
    
    # Track installation
    track_installation "$design"

    cecho "$C_BGREEN" "\n  ✔ Design '$design' erfolgreich angewendet."
    cecho "$C_YELLOW" "  Bitte starte deine Sitzung neu, um alle Änderungen zu übernehmen."
}

# ─────────────────────────────────────────────────────────────────────────────
# FARBEN & FORMATIERUNG
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
C_BRED='\033[1;31m'
C_MAGENTA='\033[0;35m'
C_BMAGENTA='\033[1;35m'
C_BLUE='\033[0;34m'
C_WHITE='\033[1;37m'

cecho() { echo -e "$1$2${C_RESET}"; }
header_line() { cecho "$C_CYAN" "$(printf '─%.0s' {1..60})"; }
section_line() { cecho "$C_DIM" "$(printf '·%.0s' {1..60})"; }

# ─────────────────────────────────────────────────────────────────────────────
# UMGEBUNGSERKENNUNG
# ─────────────────────────────────────────────────────────────────────────────

ENV_DE=""
ENV_WM=""
ENV_DISPLAY_SERVER=""
ENV_SESSION=""
ENV_DISTRO=""
ENV_COMPOSITOR=""

detect_environment() {
    # Display-Server
    if [ -n "${WAYLAND_DISPLAY-}" ]; then
        ENV_DISPLAY_SERVER="Wayland"
    elif [ -n "${DISPLAY-}" ]; then
        ENV_DISPLAY_SERVER="X11"
    else
        ENV_DISPLAY_SERVER="Headless/TTY"
    fi

    # Session / Desktop Environment
    ENV_SESSION="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unbekannt}}"
    case "${ENV_SESSION,,}" in
        *gnome*)  ENV_DE="GNOME" ;;
        *kde*)    ENV_DE="KDE Plasma" ;;
        *xfce*)   ENV_DE="XFCE" ;;
        *lxde*)   ENV_DE="LXDE" ;;
        *lxqt*)   ENV_DE="LXQt" ;;
        *mate*)   ENV_DE="MATE" ;;
        *cinnamon*) ENV_DE="Cinnamon" ;;
        *i3*)     ENV_DE="i3" ;;
        *sway*)   ENV_DE="Sway" ;;
        *openbox*) ENV_DE="Openbox" ;;
        *)        ENV_DE="Unbekannt/Minimal" ;;
    esac

    # Window Manager
    if command_exists wmctrl; then
        ENV_WM="$(wmctrl -m 2>/dev/null | awk '/Name:/{print $2}' || echo "")"
    fi
    if [ -z "$ENV_WM" ]; then
        for wm in i3 sway openbox kwin_x11 kwin_wayland mutter xfwm4 fluxbox bspwm dwm; do
            if pgrep -x "$wm" >/dev/null 2>&1; then
                ENV_WM="$wm"; break
            fi
        done
    fi
    [ -z "$ENV_WM" ] && ENV_WM="unbekannt"

    # Compositor
    for comp in picom compton xcompmgr; do
        if pgrep -x "$comp" >/dev/null 2>&1; then
            ENV_COMPOSITOR="$comp"; break
        fi
    done
    [ -z "$ENV_COMPOSITOR" ] && ENV_COMPOSITOR="keiner/eingebaut"

    # Distro
    if [ -f /etc/os-release ]; then
        ENV_DISTRO="$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")"
    else
        ENV_DISTRO="Unbekannt"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# EINSTELLUNGS-PERSISTENZ
# ─────────────────────────────────────────────────────────────────────────────

SETTINGS_DIR="$HOME/.config/kali-desktop"
SETTINGS_FILE="$SETTINGS_DIR/settings.conf"
INSTALL_TRACKER_FILE="$SETTINGS_DIR/installed.conf"
MODES_DIR="$SETTINGS_DIR/modes"

# Aktuelle Konfigurationswerte (Defaults)
CFG_DESIGN="fsocietyhub"
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

load_settings() {
    mkdir -p "$SETTINGS_DIR"
    if [ -f "$SETTINGS_FILE" ]; then
        # Nur bekannte Schlüssel einlesen (Sicherheit: kein blindes source)
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            value="${value//\"/}"
            case "$key" in
                CFG_DESIGN)       CFG_DESIGN="$value" ;;
                CFG_WM)           CFG_WM="$value" ;;
                CFG_COMPOSITOR)   CFG_COMPOSITOR="$value" ;;
                CFG_TERMINAL)     CFG_TERMINAL="$value" ;;
                CFG_BAR)          CFG_BAR="$value" ;;
                CFG_LAUNCHER)     CFG_LAUNCHER="$value" ;;
                CFG_FILEMANAGER)  CFG_FILEMANAGER="$value" ;;
                CFG_NOTIFICATIONS) CFG_NOTIFICATIONS="$value" ;;
                CFG_WALLPAPER_TOOL) CFG_WALLPAPER_TOOL="$value" ;;
                CFG_GTK_THEME)    CFG_GTK_THEME="$value" ;;
                CFG_ICON_THEME)   CFG_ICON_THEME="$value" ;;
                CFG_FONT)         CFG_FONT="$value" ;;
                CFG_FONT_SIZE)    CFG_FONT_SIZE="$value" ;;
            esac
        done < "$SETTINGS_FILE"
    fi
}

save_settings() {
    mkdir -p "$SETTINGS_DIR"
    cat > "$SETTINGS_FILE" <<EOF
# Kali Desktop Konfiguration – gespeichert am $(date)
CFG_DESIGN="$CFG_DESIGN"
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
# INSTALLATION TRACKING & KALI MODES MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

track_installation() {
    local mode="$1"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    mkdir -p "$SETTINGS_DIR"
    
    # Append to installation tracker
    echo "${mode}|${timestamp}|installed" >> "$INSTALL_TRACKER_FILE"
    log "Installation von '$mode' getracked: $INSTALL_TRACKER_FILE"
}

get_installed_modes() {
    if [ ! -f "$INSTALL_TRACKER_FILE" ]; then
        return
    fi
    
    awk -F'|' '$3 == "installed" {print $1}' "$INSTALL_TRACKER_FILE" | sort -u
}

is_mode_installed() {
    local mode="$1"
    if [ ! -f "$INSTALL_TRACKER_FILE" ]; then
        return 1
    fi
    
    grep -q "^${mode}|" "$INSTALL_TRACKER_FILE" && return 0
    return 1
}

clean_previous_installation() {
    local new_mode="$1"
    
    log "Bereite vorherige Installation auf für neuen Mode: $new_mode"
    
    # Remove old theme configs if switching modes
    if [ -d "$HOME/.config/i3" ]; then
        rm -rf "$HOME/.config/i3" || true
    fi
    
    if [ -d "$HOME/.config/sway" ]; then
        rm -rf "$HOME/.config/sway" || true
    fi
    
    if [ -d "$HOME/.config/alacritty" ]; then
        rm -rf "$HOME/.config/alacritty" || true
    fi
    
    log "Aufräumen abgeschlossen."
}

# Define Kali Modes with presets
define_kali_modes() {
    mkdir -p "$MODES_DIR"
    
    # PENTESTER MODE - Max security tools, minimal eye candy
    cat > "$MODES_DIR/pentester.conf" <<'EOF'
MODE_NAME="Pentester"
MODE_DESC="Optimiert für Penetrationstests – Sicherheitstools, minimalistische GUI"
CFG_DESIGN="minimalistic"
CFG_WM="i3"
CFG_COMPOSITOR="picom"
CFG_TERMINAL="alacritty"
CFG_LAUNCHER="rofi"
CFG_BAR="polybar"
CFG_NOTIFICATIONS="dunst"
CFG_GTK_THEME="Adwaita"
CFG_ICON_THEME="Papirus"
EOF
    
    # CORPORATE MODE - Professional look
    cat > "$MODES_DIR/corporate.conf" <<'EOF'
MODE_NAME="Corporate"
MODE_DESC="Professionelle Umgebung – Arc-Theme, standardisiert"
CFG_DESIGN="corporate"
CFG_WM="auto"
CFG_COMPOSITOR="picom"
CFG_TERMINAL="gnome-terminal"
CFG_LAUNCHER="rofi"
CFG_BAR="waybar"
CFG_NOTIFICATIONS="mako"
CFG_GTK_THEME="Arc"
CFG_ICON_THEME="Papirus"
EOF
    
    # FSOCIETY MODE - Dark, Hacker-style
    cat > "$MODES_DIR/fsociety.conf" <<'EOF'
MODE_NAME="Fsociety"
MODE_DESC="Hacker-Ästhetik – Dracula-Theme, grün-auf-schwarz"
CFG_DESIGN="fsocietyhub"
CFG_WM="i3"
CFG_COMPOSITOR="picom"
CFG_TERMINAL="alacritty"
CFG_LAUNCHER="rofi"
CFG_BAR="polybar"
CFG_NOTIFICATIONS="dunst"
CFG_GTK_THEME="Dracula"
CFG_ICON_THEME="Papirus-Dark"
EOF
    
    # XFCE MODE - Lightweight, classic
    cat > "$MODES_DIR/xfce.conf" <<'EOF'
MODE_NAME="XFCE Classic"
MODE_DESC="Leichtgewichtig – XFCE mit Standardkomponenten"
CFG_DESIGN="minimalistic"
CFG_WM="xfwm4"
CFG_COMPOSITOR="keiner"
CFG_TERMINAL="xfce4-terminal"
CFG_LAUNCHER="rofi"
CFG_BAR="xfce4-panel"
CFG_NOTIFICATIONS="xfce4-notifyd"
CFG_GTK_THEME="Adwaita"
CFG_ICON_THEME="Papirus"
EOF
    
    log "Kali Modes definiert in: $MODES_DIR"
}

load_kali_mode() {
    local mode="$1"
    local mode_file="$MODES_DIR/${mode}.conf"
    
    if [ ! -f "$mode_file" ]; then
        error "Modus-Datei nicht gefunden: $mode_file"
        return 1
    fi
    
    log "Lade Kali Mode: $mode"
    source "$mode_file"
}

list_kali_modes() {
    local modes=()
    if [ -d "$MODES_DIR" ]; then
        for f in "$MODES_DIR"/*.conf; do
            [ -f "$f" ] && modes+=("$(basename "$f" .conf)")
        done
    fi
    printf '%s\n' "${modes[@]}"
}

get_mode_info() {
    local mode="$1"
    local mode_file="$MODES_DIR/${mode}.conf"
    
    if [ ! -f "$mode_file" ]; then
        return 1
    fi
    
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        value="${value//\"/}"
        echo "${key}=${value}"
    done < "$mode_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER & MENÜ-HELFER
# ─────────────────────────────────────────────────────────────────────────────

show_fsocietyhub_banner() {
    echo -e "${C_BGREEN}"
    cat <<'EOF'
███████╗███████╗ ██████╗  ██████╗██╗███████╗████████╗██╗   ██╗██╗  ██╗██╗   ██╗██████╗
██╔════╝██╔════╝██╔═══██╗██╔════╝██║██╔════╝╚══██╔══╝╚██╗ ██╔╝██║  ██║██║   ██║██╔══██╗
█████╗  ███████╗██║   ██║██║     ██║█████╗     ██║    ╚████╔╝ ███████║██║   ██║██████╔╝
██╔══╝  ╚════██║██║   ██║██║     ██║██╔══╝     ██║     ╚██╔╝  ██╔══██║██║   ██║██╔══██╗
██║     ███████║╚██████╔╝╚██████╗██║███████╗   ██║      ██║   ██║  ██║╚██████╔╝██████╔╝
╚═╝     ╚══════╝ ╚═════╝  ╚═════╝╚═╝╚══════╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝
EOF
    echo -e "${C_RESET}"
}

menu_header() {
    local title="$1"
    if is_interactive; then
        clear
    fi
    show_fsocietyhub_banner
    header_line
    cecho "$C_BCYAN" "  $title"
    cecho "$C_DIM" "  System: $ENV_DISTRO  |  DE: $ENV_DE  |  WM: $ENV_WM  |  $ENV_DISPLAY_SERVER"
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

show_back() {
    echo -e "  ${C_DIM}0) Zurück${C_RESET}"
}

prompt_choice() {
    # Send prompts to stderr so they don't interfere with stdout capture
    echo "" >&2
    echo -e -n "  ${C_BCYAN}▶ Auswahl: ${C_RESET}" >&2
    local choice
    read -r choice
    # Trim leading and trailing whitespace
    choice="${choice#[[:space:]]*}"
    choice="${choice%[[:space:]]*}"
    # Output ONLY the value to stdout (for command substitution)
    printf '%s\n' "$choice"
}

confirm_action() {
    local msg="$1"
    echo -e "\n  ${C_YELLOW}${msg}${C_RESET}"
    echo -e -n "  ${C_BOLD}Fortfahren? [j/N]: ${C_RESET}"
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

# ─────────────────────────────────────────────────────────────────────────────
# STATUS-ANZEIGE
# ─────────────────────────────────────────────────────────────────────────────

show_status() {
    menu_header "SYSTEM STATUS & KONFIGURATION"

    cecho "$C_BCYAN" "  ── Erkannte Umgebung ──────────────────────────────────"
    echo -e "  ${C_DIM}Distro:${C_RESET}          $ENV_DISTRO"
    echo -e "  ${C_DIM}Desktop:${C_RESET}         $ENV_DE"
    echo -e "  ${C_DIM}Window Manager:${C_RESET}  $ENV_WM"
    echo -e "  ${C_DIM}Compositor:${C_RESET}      $ENV_COMPOSITOR"
    echo -e "  ${C_DIM}Display Server:${C_RESET}  $ENV_DISPLAY_SERVER"
    echo -e "  ${C_DIM}Session:${C_RESET}         $ENV_SESSION"

    echo ""
    cecho "$C_BCYAN" "  ── Gespeicherte Konfiguration ─────────────────────────"
    echo -e "  ${C_DIM}Design-Preset:${C_RESET}   $CFG_DESIGN"
    echo -e "  ${C_DIM}Window Manager:${C_RESET}  $CFG_WM"
    echo -e "  ${C_DIM}Compositor:${C_RESET}      $CFG_COMPOSITOR"
    echo -e "  ${C_DIM}Terminal:${C_RESET}        $CFG_TERMINAL"
    echo -e "  ${C_DIM}Bar/Panel:${C_RESET}       $CFG_BAR"
    echo -e "  ${C_DIM}Launcher:${C_RESET}        $CFG_LAUNCHER"
    echo -e "  ${C_DIM}Dateimanager:${C_RESET}    $CFG_FILEMANAGER"
    echo -e "  ${C_DIM}Notifications:${C_RESET}   $CFG_NOTIFICATIONS"
    echo -e "  ${C_DIM}Wallpaper-Tool:${C_RESET}  $CFG_WALLPAPER_TOOL"
    echo -e "  ${C_DIM}GTK Theme:${C_RESET}       $CFG_GTK_THEME"
    echo -e "  ${C_DIM}Icon Theme:${C_RESET}      $CFG_ICON_THEME"
    echo -e "  ${C_DIM}Schrift:${C_RESET}         $CFG_FONT $CFG_FONT_SIZE"

    echo ""
    cecho "$C_BCYAN" "  ── Installierte Kali Modes ────────────────────────────"
    local installed_modes=$(get_installed_modes)
    if [ -z "$installed_modes" ]; then
        echo -e "  ${C_DIM}Keine Modi installiert. Wende einen Mode an, um zu beginnen.${C_RESET}"
    else
        echo "$installed_modes" | while read -r mode; do
            echo -e "  ${C_BGREEN}✔${C_RESET} $mode"
        done
    fi

    echo ""
    cecho "$C_BCYAN" "  ── Verfügbare Kali Modes ──────────────────────────────"
    while IFS= read -r mode; do
        local mode_name=$(grep "^MODE_NAME=" "$MODES_DIR/${mode}.conf" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        echo -e "  • $mode_name ($mode)"
    done < <(list_kali_modes)

    echo ""
    cecho "$C_BCYAN" "  ── Installierte Tools ─────────────────────────────────"
    local tools=(i3 sway openbox picom alacritty kitty rofi dmenu waybar polybar thunar nautilus dunst mako feh nitrogen variety neofetch btop)
    for t in "${tools[@]}"; do
        if command_exists "$t"; then
            echo -e "  ${C_BGREEN}✔${C_RESET} $t"
        else
            echo -e "  ${C_DIM}✘ $t${C_RESET}"
        fi
    done

    press_enter
}

# ─────────────────────────────────────────────────────────────────────────────
# KOMPONENTEN-KONFIGURATIONSMENÜS
# ─────────────────────────────────────────────────────────────────────────────

menu_select_wm() {
    menu_header "WINDOW MANAGER AUSWÄHLEN"
    cecho "$C_DIM" "  Erkannt: $ENV_WM  |  Display: $ENV_DISPLAY_SERVER"
    echo ""

    local wms_x11=(i3 openbox bspwm fluxbox dwm xmonad)
    local wms_wayland=(sway hyprland river)
    declare -A wm_options=()

    if [ "$ENV_DISPLAY_SERVER" = "Wayland" ]; then
        cecho "$C_YELLOW" "  Wayland-kompatible Window Manager:"
        for i in "${!wms_wayland[@]}"; do
            wm_options["$((i+1))"]="${wms_wayland[$i]}"
            show_option "$((i+1))" "${wms_wayland[$i]}"
        done
        echo ""
        cecho "$C_YELLOW" "  X11 Window Manager (über XWayland):"
        for i in "${!wms_x11[@]}"; do
            wm_options["$((i+10))"]="${wms_x11[$i]}"
            show_option "$((i+10))" "${wms_x11[$i]}"
        done
    else
        cecho "$C_YELLOW" "  X11 Window Manager:"
        for i in "${!wms_x11[@]}"; do
            wm_options["$((i+1))"]="${wms_x11[$i]}"
            show_option "$((i+1))" "${wms_x11[$i]}"
        done
        echo ""
        cecho "$C_YELLOW" "  Wayland Window Manager:"
        for i in "${!wms_wayland[@]}"; do
            wm_options["$((i+10))"]="${wms_wayland[$i]}"
            show_option "$((i+10))" "${wms_wayland[$i]}"
        done
    fi
    echo ""
    show_option "99" "Manuell eingeben"
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_WM"

    local c; c=$(prompt_choice)
    case "$c" in
        99)
            echo -e -n "  ${C_BCYAN}Window Manager Name: ${C_RESET}"
            read -r CFG_WM
            ;;
        0) return ;;
        *)
            if [ -n "${wm_options[$c]:-}" ]; then
                CFG_WM="${wm_options[$c]}"
            else
                error "Ungültige Auswahl."
                press_enter
                return
            fi
            ;;
    esac
    cecho "$C_BGREEN" "  ✔ Window Manager gesetzt: $CFG_WM"
    save_settings
    press_enter
}

menu_select_compositor() {
    menu_header "COMPOSITOR AUSWÄHLEN"
    echo ""
    show_option "1" "picom          " "empfohlen für X11"
    show_option "2" "compton        " "älterer picom-Fork"
    show_option "3" "xcompmgr       " "minimal"
    show_option "4" "eingebaut      " "z.B. KWin, Mutter"
    show_option "5" "keiner         " "kein Compositor"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_COMPOSITOR"

    local c; c=$(prompt_choice)
    case "$c" in
        1) CFG_COMPOSITOR="picom" ;;
        2) CFG_COMPOSITOR="compton" ;;
        3) CFG_COMPOSITOR="xcompmgr" ;;
        4) CFG_COMPOSITOR="eingebaut" ;;
        5) CFG_COMPOSITOR="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl." ; press_enter ; return ;;
    esac
    cecho "$C_BGREEN" "  ✔ Compositor gesetzt: $CFG_COMPOSITOR"
    save_settings
    press_enter
}

menu_select_terminal() {
    menu_header "TERMINAL-EMULATOR AUSWÄHLEN"
    echo ""
    show_option "1" "alacritty      " "GPU-beschleunigt, konfigurierbar"
    show_option "2" "kitty          " "GPU-beschleunigt, Feature-reich"
    show_option "3" "xterm          " "klassisch, minimal"
    show_option "4" "xfce4-terminal " "XFCE Standard"
    show_option "5" "gnome-terminal " "GNOME Standard"
    show_option "6" "konsole        " "KDE Standard"
    show_option "7" "terminator     " "Split-Pane Terminal"
    show_option "8" "st             " "suckless terminal"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_TERMINAL"

    local c; c=$(prompt_choice)
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
        *) error "Ungültige Auswahl." ; press_enter ; return ;;
    esac
    cecho "$C_BGREEN" "  ✔ Terminal gesetzt: $CFG_TERMINAL"
    save_settings
    press_enter
}

menu_select_bar() {
    menu_header "BAR / PANEL AUSWÄHLEN"
    echo ""
    show_option "1" "polybar        " "sehr konfigurierbar, X11"
    show_option "2" "waybar         " "Wayland/Sway Standard"
    show_option "3" "tint2          " "leichtgewichtig, X11"
    show_option "4" "xfce4-panel    " "XFCE Panel"
    show_option "5" "lxpanel        " "LXDE Panel"
    show_option "6" "i3bar          " "i3 integriert"
    show_option "7" "keiner         " "keine Bar"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_BAR"
    cecho "$C_DIM" "  Erkannter Display-Server: $ENV_DISPLAY_SERVER"

    local c; c=$(prompt_choice)
    case "$c" in
        1) CFG_BAR="polybar" ;;
        2) CFG_BAR="waybar" ;;
        3) CFG_BAR="tint2" ;;
        4) CFG_BAR="xfce4-panel" ;;
        5) CFG_BAR="lxpanel" ;;
        6) CFG_BAR="i3bar" ;;
        7) CFG_BAR="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl." ; press_enter ; return ;;
    esac
    cecho "$C_BGREEN" "  ✔ Bar gesetzt: $CFG_BAR"
    save_settings
    press_enter
}

menu_select_launcher() {
    menu_header "APP-LAUNCHER AUSWÄHLEN"
    echo ""
    show_option "1" "rofi           " "mächtig, sehr anpassbar"
    show_option "2" "dmenu          " "minimal, suckless"
    show_option "3" "wofi           " "Wayland-native"
    show_option "4" "ulauncher      " "modernes GUI"
    show_option "5" "albert         " "spotlight-ähnlich"
    show_option "6" "keiner         " "kein Launcher"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_LAUNCHER"

    local c; c=$(prompt_choice)
    case "$c" in
        1) CFG_LAUNCHER="rofi" ;;
        2) CFG_LAUNCHER="dmenu" ;;
        3) CFG_LAUNCHER="wofi" ;;
        4) CFG_LAUNCHER="ulauncher" ;;
        5) CFG_LAUNCHER="albert" ;;
        6) CFG_LAUNCHER="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl." ; press_enter ; return ;;
    esac
    cecho "$C_BGREEN" "  ✔ Launcher gesetzt: $CFG_LAUNCHER"
    save_settings
    press_enter
}

menu_select_filemanager() {
    menu_header "DATEIMANAGER AUSWÄHLEN"
    echo ""
    show_option "1" "thunar         " "XFCE, schnell"
    show_option "2" "nautilus       " "GNOME Files"
    show_option "3" "dolphin        " "KDE Dolphin"
    show_option "4" "nemo           " "Cinnamon Fork"
    show_option "5" "ranger         " "TUI, vim-like"
    show_option "6" "lf             " "TUI, modernes ranger"
    show_option "7" "pcmanfm        " "LXDE, leichtgewichtig"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_FILEMANAGER"

    local c; c=$(prompt_choice)
    case "$c" in
        1) CFG_FILEMANAGER="thunar" ;;
        2) CFG_FILEMANAGER="nautilus" ;;
        3) CFG_FILEMANAGER="dolphin" ;;
        4) CFG_FILEMANAGER="nemo" ;;
        5) CFG_FILEMANAGER="ranger" ;;
        6) CFG_FILEMANAGER="lf" ;;
        7) CFG_FILEMANAGER="pcmanfm" ;;
        0) return ;;
        *) error "Ungültige Auswahl." ; press_enter ; return ;;
    esac
    cecho "$C_BGREEN" "  ✔ Dateimanager gesetzt: $CFG_FILEMANAGER"
    save_settings
    press_enter
}

menu_select_notifications() {
    menu_header "BENACHRICHTIGUNGS-DAEMON AUSWÄHLEN"
    echo ""
    show_option "1" "dunst          " "leichtgewichtig, X11/Wayland"
    show_option "2" "mako           " "Wayland-native"
    show_option "3" "notify-osd     " "Ubuntu-Stil"
    show_option "4" "xfce4-notifyd  " "XFCE Standard"
    show_option "5" "keiner         " "keine Benachrichtigungen"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_NOTIFICATIONS"

    local c; c=$(prompt_choice)
    case "$c" in
        1) CFG_NOTIFICATIONS="dunst" ;;
        2) CFG_NOTIFICATIONS="mako" ;;
        3) CFG_NOTIFICATIONS="notify-osd" ;;
        4) CFG_NOTIFICATIONS="xfce4-notifyd" ;;
        5) CFG_NOTIFICATIONS="keiner" ;;
        0) return ;;
        *) error "Ungültige Auswahl." ; press_enter ; return ;;
    esac
    cecho "$C_BGREEN" "  ✔ Notifications gesetzt: $CFG_NOTIFICATIONS"
    save_settings
    press_enter
}

menu_select_wallpaper_tool() {
    menu_header "WALLPAPER-TOOL AUSWÄHLEN"
    echo ""
    show_option "1" "feh            " "minimal, CLI, X11"
    show_option "2" "nitrogen       " "GUI-Auswahl, X11"
    show_option "3" "variety        " "automatischer Wechsel"
    show_option "4" "swaybg         " "Wayland/Sway"
    show_option "5" "xwallpaper     " "X11, einfach"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_WALLPAPER_TOOL"

    local c; c=$(prompt_choice)
    case "$c" in
        1) CFG_WALLPAPER_TOOL="feh" ;;
        2) CFG_WALLPAPER_TOOL="nitrogen" ;;
        3) CFG_WALLPAPER_TOOL="variety" ;;
        4) CFG_WALLPAPER_TOOL="swaybg" ;;
        5) CFG_WALLPAPER_TOOL="xwallpaper" ;;
        0) return ;;
        *) error "Ungültige Auswahl." ; press_enter ; return ;;
    esac
    cecho "$C_BGREEN" "  ✔ Wallpaper-Tool gesetzt: $CFG_WALLPAPER_TOOL"
    save_settings
    press_enter
}

menu_select_gtk_theme() {
    menu_header "GTK-THEME AUSWÄHLEN"
    echo ""

    # Installierte Themes auflisten
    local themes=()
    local theme_dirs=("$HOME/.themes" "/usr/share/themes")
    for d in "${theme_dirs[@]}"; do
        if [ -d "$d" ]; then
            while IFS= read -r -d '' t; do
                themes+=("$(basename "$t")")
            done < <(find "$d" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
        fi
    done

    if [ "${#themes[@]}" -gt 0 ]; then
        cecho "$C_YELLOW" "  Installierte Themes:"
        for i in "${!themes[@]}"; do
            show_option "$((i+1))" "${themes[$i]}"
        done
    else
        cecho "$C_DIM" "  Keine installierten Themes gefunden."
    fi
    echo ""
    cecho "$C_YELLOW" "  Bekannte Themes (direkte Auswahl):"
    show_option "50" "Adwaita        " "GNOME Standard"
    show_option "51" "Arc            " "modern, flach"
    show_option "52" "Arc-Dark       " "dark variant"
    show_option "53" "Dracula        " "dunkel, lila"
    show_option "54" "Windows XP Luna" "retro"
    show_option "99" "Manuell eingeben"
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_GTK_THEME"

    local c; c=$(prompt_choice)
    case "$c" in
        0) return ;;
        50) CFG_GTK_THEME="Adwaita" ;;
        51) CFG_GTK_THEME="Arc" ;;
        52) CFG_GTK_THEME="Arc-Dark" ;;
        53) CFG_GTK_THEME="Dracula" ;;
        54) CFG_GTK_THEME="Windows XP Luna" ;;
        99)
            echo -e -n "  ${C_BCYAN}Theme-Name: ${C_RESET}"
            read -r CFG_GTK_THEME
            ;;
        *)
            if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#themes[@]}" ]; then
                CFG_GTK_THEME="${themes[$((c-1))]}"
            else
                error "Ungültige Auswahl."; press_enter; return
            fi
            ;;
    esac
    cecho "$C_BGREEN" "  ✔ GTK-Theme gesetzt: $CFG_GTK_THEME"
    if gsettings_available; then
        gsettings set org.gnome.desktop.interface gtk-theme "$CFG_GTK_THEME" 2>/dev/null || true
    fi
    save_settings
    press_enter
}

menu_select_icon_theme() {
    menu_header "ICON-THEME AUSWÄHLEN"
    echo ""

    local icons=()
    local icon_dirs=("$HOME/.icons" "/usr/share/icons")
    for d in "${icon_dirs[@]}"; do
        if [ -d "$d" ]; then
            while IFS= read -r -d '' t; do
                icons+=("$(basename "$t")")
            done < <(find "$d" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
        fi
    done

    if [ "${#icons[@]}" -gt 0 ]; then
        cecho "$C_YELLOW" "  Installierte Icon-Themes:"
        for i in "${!icons[@]}"; do
            show_option "$((i+1))" "${icons[$i]}"
        done
    else
        cecho "$C_DIM" "  Keine installierten Icon-Themes gefunden."
    fi
    echo ""
    show_option "50" "Adwaita"
    show_option "51" "Papirus"
    show_option "52" "Papirus-Dark"
    show_option "53" "hicolor"
    show_option "99" "Manuell eingeben"
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell gespeichert: $CFG_ICON_THEME"

    local c; c=$(prompt_choice)
    case "$c" in
        0) return ;;
        50) CFG_ICON_THEME="Adwaita" ;;
        51) CFG_ICON_THEME="Papirus" ;;
        52) CFG_ICON_THEME="Papirus-Dark" ;;
        53) CFG_ICON_THEME="hicolor" ;;
        99)
            echo -e -n "  ${C_BCYAN}Icon-Theme-Name: ${C_RESET}"
            read -r CFG_ICON_THEME
            ;;
        *)
            if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#icons[@]}" ]; then
                CFG_ICON_THEME="${icons[$((c-1))]}"
            else
                error "Ungültige Auswahl."; press_enter; return
            fi
            ;;
    esac
    cecho "$C_BGREEN" "  ✔ Icon-Theme gesetzt: $CFG_ICON_THEME"
    if gsettings_available; then
        gsettings set org.gnome.desktop.interface icon-theme "$CFG_ICON_THEME" 2>/dev/null || true
    fi
    save_settings
    press_enter
}

menu_select_font() {
    menu_header "SCHRIFTART KONFIGURIEREN"
    echo ""
    cecho "$C_YELLOW" "  Empfohlene Schriftarten:"
    show_option "1" "FiraCode Nerd Font    " "empfohlen, mit Icons"
    show_option "2" "JetBrains Mono        " "Programmier-Schrift"
    show_option "3" "Hack Nerd Font        " "klar, lesbar"
    show_option "4" "DejaVu Sans Mono      " "Standard"
    show_option "5" "Monospace             " "System-Standard"
    show_option "6" "Tahoma                " "Windows-ähnlich"
    show_option "99" "Manuell eingeben"
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktuell: $CFG_FONT  Größe: $CFG_FONT_SIZE"

    local c; c=$(prompt_choice)
    case "$c" in
        0) return ;;
        1) CFG_FONT="FiraCode Nerd Font" ;;
        2) CFG_FONT="JetBrains Mono" ;;
        3) CFG_FONT="Hack Nerd Font" ;;
        4) CFG_FONT="DejaVu Sans Mono" ;;
        5) CFG_FONT="Monospace" ;;
        6) CFG_FONT="Tahoma" ;;
        99)
            echo -e -n "  ${C_BCYAN}Schriftart: ${C_RESET}"
            read -r CFG_FONT
            ;;
        *) error "Ungültige Auswahl."; press_enter; return ;;
    esac
    echo -e -n "  ${C_BCYAN}Schriftgröße [aktuell: $CFG_FONT_SIZE]: ${C_RESET}"
    read -r new_size
    if [[ "$new_size" =~ ^[0-9]+$ ]]; then
        CFG_FONT_SIZE="$new_size"
    fi
    cecho "$C_BGREEN" "  ✔ Schrift gesetzt: $CFG_FONT $CFG_FONT_SIZE"
    save_settings
    press_enter
}

# ─────────────────────────────────────────────────────────────────────────────
# BENUTZERDEFINIERTES SETUP-MENÜ
# ─────────────────────────────────────────────────────────────────────────────

apply_custom_config() {
    menu_header "BENUTZERDEFINIERTE KONFIGURATION ANWENDEN"
    echo ""
    cecho "$C_YELLOW" "  Folgende Komponenten werden konfiguriert:"
    echo -e "  ${C_DIM}Window Manager:${C_RESET}  $CFG_WM"
    echo -e "  ${C_DIM}Compositor:${C_RESET}      $CFG_COMPOSITOR"
    echo -e "  ${C_DIM}Terminal:${C_RESET}        $CFG_TERMINAL"
    echo -e "  ${C_DIM}Bar:${C_RESET}             $CFG_BAR"
    echo -e "  ${C_DIM}Launcher:${C_RESET}        $CFG_LAUNCHER"
    echo -e "  ${C_DIM}GTK Theme:${C_RESET}       $CFG_GTK_THEME"
    echo -e "  ${C_DIM}Icon Theme:${C_RESET}      $CFG_ICON_THEME"
    echo -e "  ${C_DIM}Schrift:${C_RESET}         $CFG_FONT $CFG_FONT_SIZE"
    echo ""

    if ! confirm_action "Benutzerdefinierte Konfiguration anwenden?"; then
        return
    fi

    backup_current_setup
    install_custom_dependencies

    # Compositor installieren
    if [[ "$CFG_COMPOSITOR" =~ ^(picom|compton|xcompmgr)$ ]]; then
        safe_install_packages "$CFG_COMPOSITOR"
    fi

    # Terminal installieren
    case "$CFG_TERMINAL" in
        alacritty|kitty|xterm|terminator)
            safe_install_packages "$CFG_TERMINAL"
            ;;
        xfce4-terminal) safe_install_packages "xfce4-terminal" ;;
        gnome-terminal) safe_install_packages "gnome-terminal" ;;
        konsole)        safe_install_packages "konsole" ;;
    esac

    # Launcher installieren
    case "$CFG_LAUNCHER" in
        rofi)       safe_install_packages rofi ;;
        dmenu)      safe_install_packages suckless-tools ;;
        wofi)       safe_install_packages wofi ;;
        ulauncher)  safe_install_packages ulauncher ;;
    esac

    # Bar installieren
    case "$CFG_BAR" in
        polybar)    safe_install_packages polybar ;;
        waybar)     safe_install_packages waybar ;;
        tint2)      safe_install_packages tint2 ;;
    esac

    # Dateimanager installieren
    case "$CFG_FILEMANAGER" in
        thunar)   safe_install_packages thunar ;;
        nautilus) safe_install_packages nautilus ;;
        dolphin)  safe_install_packages dolphin ;;
        nemo)     safe_install_packages nemo ;;
        ranger)   safe_install_packages ranger ;;
        pcmanfm)  safe_install_packages pcmanfm ;;
    esac

    # Benachrichtigungen installieren
    case "$CFG_NOTIFICATIONS" in
        dunst)         safe_install_packages dunst ;;
        mako)          safe_install_packages mako-notifier ;;
        notify-osd)    safe_install_packages notify-osd ;;
        xfce4-notifyd) safe_install_packages xfce4-notifyd ;;
    esac

    # Wallpaper Tool installieren
    case "$CFG_WALLPAPER_TOOL" in
        feh)       safe_install_packages feh ;;
        nitrogen)  safe_install_packages nitrogen ;;
        variety)   safe_install_packages variety ;;
        swaybg)    safe_install_packages swaybg ;;
    esac

    # Nerd Fonts installieren
    nerd_fonts_install

    # Preset-Assets installieren, damit 'auto' und Override-Fälle konsistent bleiben.
    themes_and_icons_install "$CFG_DESIGN" || true

    # GTK Theme & Icons
    if [ "$CFG_GTK_THEME" = "auto" ] || [ "$CFG_ICON_THEME" = "auto" ]; then
        activate_themes_and_icons "$CFG_DESIGN" || true
    fi
    if [ "$CFG_GTK_THEME" != "auto" ]; then
        if gsettings_available && [ -n "$CFG_GTK_THEME" ]; then
            gsettings set org.gnome.desktop.interface gtk-theme "$CFG_GTK_THEME" 2>/dev/null || true
        fi
    fi
    if gsettings_available && [ "$CFG_ICON_THEME" != "auto" ] && [ -n "$CFG_ICON_THEME" ]; then
        gsettings set org.gnome.desktop.interface icon-theme "$CFG_ICON_THEME" 2>/dev/null || true
    fi

    # Alacritty konfigurieren (mit gewählter Schrift)
    if [ "$CFG_TERMINAL" = "alacritty" ]; then
        mkdir -p "$HOME/.config/alacritty"
        cat > "$HOME/.config/alacritty/alacritty.yml" <<EOF
font:
  normal:
    family: "$CFG_FONT"
    style: Regular
  size: $CFG_FONT_SIZE.0
window:
  padding:
    x: 10
    y: 10
  opacity: 0.95
EOF
    fi

    # i3/Sway konfigurieren
    config_i3_or_sway "$CFG_DESIGN"

    # Compositor starten
    if [[ "$CFG_COMPOSITOR" =~ ^(picom|compton)$ ]] && command_exists "$CFG_COMPOSITOR"; then
        "$CFG_COMPOSITOR" -b >/dev/null 2>&1 || true
    fi

    finetuning_and_optimizations
    manage_dot_files
    install_uv

    cecho "$C_BGREEN" "\n  ✔ Benutzerdefinierte Konfiguration angewendet."
    cecho "$C_YELLOW" "  Bitte starte deine Sitzung neu, um alle Änderungen zu übernehmen."
    press_enter
}

menu_custom_setup() {
    while true; do
        menu_header "BENUTZERDEFINIERTES SETUP"
        echo ""
        show_option "1"  "Window Manager      " "$CFG_WM"
        show_option "2"  "Compositor          " "$CFG_COMPOSITOR"
        show_option "3"  "Terminal            " "$CFG_TERMINAL"
        show_option "4"  "Bar / Panel         " "$CFG_BAR"
        show_option "5"  "App-Launcher        " "$CFG_LAUNCHER"
        show_option "6"  "Dateimanager        " "$CFG_FILEMANAGER"
        show_option "7"  "Benachrichtigungen  " "$CFG_NOTIFICATIONS"
        show_option "8"  "Wallpaper-Tool      " "$CFG_WALLPAPER_TOOL"
        show_option "9"  "GTK Theme           " "$CFG_GTK_THEME"
        show_option "10" "Icon Theme          " "$CFG_ICON_THEME"
        show_option "11" "Schriftart          " "$CFG_FONT $CFG_FONT_SIZE"
        echo ""
        section_line
        show_option "12" "Alles anwenden"
        show_option "13" "Einstellungen speichern (ohne Anwenden)"
        show_back
        echo ""

        local c; c=$(prompt_choice)
        case "$c" in
            1)  menu_select_wm ;;
            2)  menu_select_compositor ;;
            3)  menu_select_terminal ;;
            4)  menu_select_bar ;;
            5)  menu_select_launcher ;;
            6)  menu_select_filemanager ;;
            7)  menu_select_notifications ;;
            8)  menu_select_wallpaper_tool ;;
            9)  menu_select_gtk_theme ;;
            10) menu_select_icon_theme ;;
            11) menu_select_font ;;
            12) apply_custom_config ;;
            13) save_settings ; press_enter ;;
            0)  break ;;
            *)  error "Ungültige Auswahl." ; press_enter ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# TOOLS-MENÜ
# ─────────────────────────────────────────────────────────────────────────────

menu_tools() {
    while true; do
        menu_header "TOOLS VERWALTEN"
        echo ""
        cecho "$C_YELLOW" "  ── Systemüberwachung ───────────────────────────────"
        show_option "1" "btop / htop / glances / neofetch  installieren"
        echo ""
        cecho "$C_YELLOW" "  ── Audio & Medien ──────────────────────────────────"
        show_option "2" "pavucontrol / playerctl / vlc     installieren"
        echo ""
        cecho "$C_YELLOW" "  ── Hardware ────────────────────────────────────────"
        show_option "3" "brightnessctl                     installieren"
        show_option "4" "network-manager-applet            installieren"
        show_option "5" "arandr (Bildschirm-Layout)        installieren"
        echo ""
        cecho "$C_YELLOW" "  ── Entwicklung ─────────────────────────────────────"
        show_option "6" "Nerd Fonts                        installieren"
        show_option "7" "uv (Python-Manager)               installieren"
        echo ""
        cecho "$C_YELLOW" "  ── Wartung ─────────────────────────────────────────"
        show_option "8" "Systembereinigung (autoremove/clean)"
        show_option "9" "Dotfiles verwalten (git bare repo)"
        echo ""
        show_back
        echo ""

        local c; c=$(prompt_choice)
        case "$c" in
            1) install_system_monitoring_tools ; press_enter ;;
            2) audio_and_media_tools ; press_enter ;;
            3) brightness_control ; press_enter ;;
            4) network_manager ; press_enter ;;
            5) safe_install_packages arandr ; press_enter ;;
            6) nerd_fonts_install ; press_enter ;;
            7) install_uv ; press_enter ;;
            8) finetuning_and_optimizations ; press_enter ;;
            9) manage_dot_files ; press_enter ;;
            0) break ;;
            *) error "Ungültige Auswahl." ; press_enter ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP-MENÜ
# ─────────────────────────────────────────────────────────────────────────────

menu_backup() {
    while true; do
        menu_header "BACKUP & WIEDERHERSTELLUNG"
        echo ""
        show_option "1" "Aktuellen Desktop sichern"
        show_option "2" "Letztes Backup wiederherstellen"
        echo ""
        cecho "$C_DIM" "  Backup-Verzeichnis: $HOME/.desktop_backup"

        if [ -d "$HOME/.desktop_backup" ]; then
            echo ""
            cecho "$C_DIM" "  Vorhandene Backup-Dateien:"
            ls -lh "$HOME/.desktop_backup" 2>/dev/null | awk 'NR>1{print "    "$0}' || true
        fi
        echo ""
        show_back
        echo ""

        local c; c=$(prompt_choice)
        case "$c" in
            1) backup_current_setup ; press_enter ;;
            2) restore_backup ; press_enter ;;
            0) break ;;
            *) error "Ungültige Auswahl." ; press_enter ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHNELL-SETUP MENÜ
# ─────────────────────────────────────────────────────────────────────────────

menu_quick_setup() {
    menu_header "SCHNELL-SETUP – KALI MODES"
    echo ""
    cecho "$C_DIM" "  Wende einen vorgefertigten Kali Mode an."
    cecho "$C_DIM" "  Alle Komponenten werden automatisch installiert und konfiguriert."
    echo ""
    
    local modes=()
    local mode_names=()
    local mode_index=1
    
    # Load and display all available modes
    while IFS= read -r mode; do
        modes+=("$mode")
        # Get mode name from conf file
        local mode_name=$(grep "^MODE_NAME=" "$MODES_DIR/${mode}.conf" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        local mode_desc=$(grep "^MODE_DESC=" "$MODES_DIR/${mode}.conf" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        mode_names+=("$mode_name")
        
        local installed_marker=""
        if is_mode_installed "$mode"; then
            installed_marker=" ✔"
        fi
        
        show_option "$mode_index" "$mode_name$installed_marker" "$mode_desc"
        ((mode_index++))
    done < <(list_kali_modes)
    
    echo ""
    show_back
    echo ""
    cecho "$C_DIM" "  Aktueller Mode: $CFG_DESIGN"

    local c; c=$(prompt_choice)
    
    if [ "$c" = "0" ]; then
        return
    fi
    
    # Check if choice is valid
    if ! [[ "$c" =~ ^[0-9]+$ ]]; then
        error "Ungültige Auswahl."
        press_enter
        return
    fi
    
    if [ "$c" -lt 1 ] || [ "$c" -gt "${#modes[@]}" ]; then
        error "Ungültige Auswahl."
        press_enter
        return
    fi
    
    local selected_mode="${modes[$((c-1))]}"
    
    if confirm_action "Mode '$selected_mode' anwenden? (Backups werden erstellt)"; then
        load_kali_mode "$selected_mode"
        apply_design "$CFG_DESIGN"
        press_enter
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HAUPTMENÜ
# ─────────────────────────────────────────────────────────────────────────────

print_help() {
    cat <<EOF
Verwendung: ./custom.sh [OPTION]

Optionen:
  --mode <name>      Lade einen vordefinierten Kali Mode (pentester, corporate, fsociety, xfce)
  --design <name>    Wende ein Design an (minimalistic, corporate, windows_xp, fsocietyhub)
  --list-modes       Zeige alle verfügbaren Kali Modes an
  --restore          Stelle den zuletzt gespeicherten Desktop-Zustand wieder her
  --status           Zeige Systemstatus und Konfiguration an
  --help             Zeige diese Hilfe an

Beispiele:
  ./custom.sh --mode pentester          # Pentester-Mode anwenden
  ./custom.sh --design fsocietyhub      # Fsociety-Design direkt anwenden
  ./custom.sh --list-modes              # Alle verfügbaren Modi auflisten
EOF
}

show_main_menu() {
    while true; do
        menu_header "KALI LINUX DESKTOP CONFIGURATOR"
        echo ""
        show_option "1" "Schnell-Setup       " "Design-Preset in einem Schritt anwenden"
        show_option "2" "Benutzerdefiniert   " "Jede Komponente einzeln konfigurieren"
        show_option "3" "Status anzeigen     " "Umgebung & aktuelle Konfiguration"
        show_option "4" "Backup / Restore    " "Einstellungen sichern oder wiederherstellen"
        show_option "5" "Tools installieren  " "Systemtools, Fonts, Dev-Tools"
        echo ""
        section_line
        show_option "0" "Beenden"
        echo ""

        local c; c=$(prompt_choice)
        case "$c" in
            1) menu_quick_setup ;;
            2) menu_custom_setup ;;
            3) show_status ;;
            4) menu_backup ;;
            5) menu_tools ;;
            0) cecho "$C_DIM" "\n  Auf Wiedersehen." ; echo "" ; exit 0 ;;
            *) error "Ungültige Auswahl." ; press_enter ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# EINSTIEGSPUNKT
# ─────────────────────────────────────────────────────────────────────────────

main() {
    detect_environment
    define_kali_modes
    load_settings

    if [ "$#" -gt 0 ]; then
        case "$1" in
            --design)
                if [ "$#" -lt 2 ]; then
                    error "Fehlendes Design-Argument."
                    exit 1
                fi
                apply_design "$2"
                ;;
            --mode)
                if [ "$#" -lt 2 ]; then
                    error "Fehlendes Mode-Argument."
                    exit 1
                fi
                load_kali_mode "$2"
                apply_design "$CFG_DESIGN"
                ;;
            --restore)
                restore_backup
                ;;
            --status)
                show_status
                ;;
            --list-modes)
                echo "Verfügbare Kali Modes:"
                while IFS= read -r mode; do
                    local mode_name=$(grep "^MODE_NAME=" "$MODES_DIR/${mode}.conf" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
                    local mode_desc=$(grep "^MODE_DESC=" "$MODES_DIR/${mode}.conf" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
                    printf "  %-15s %s\n" "$mode" "$mode_desc"
                done < <(list_kali_modes)
                ;;
            --help|-h)
                print_help
                ;;
            *)
                error "Unbekannte Option: $1"
                print_help
                exit 1
                ;;
        esac
    else
        if ! is_interactive; then
            error "Kein interaktives Terminal erkannt. Verwende --help für CLI-Optionen."
            print_help
            exit 1
        fi
        show_main_menu
    fi
}

main "$@"
