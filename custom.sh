#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[*] $1"
}

error() {
    echo "[!] $1" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

download_file() {
    local url="$1"
    local dest="$2"

    if command_exists curl; then
        curl -fsSL "$url" -o "$dest"
    elif command_exists wget; then
        wget -qO "$dest" "$url"
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
    sudo apt-get update -y
}

safe_install_packages() {
    if ! command_exists apt-get; then
        error "apt-get ist auf diesem System nicht vorhanden."
        return 1
    fi

    if [ "$#" -eq 0 ]; then
        return 0
    fi

    log "Installiere Pakete: $*"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
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
        curl wget unzip git picom feh rofi waybar alacritty thunar nitrogen \
        lxappearance fonts-font-awesome fonts-firacode \
        fonts-jetbrains-mono ttf-nerd-fonts-symbols \
        playerctl pulseaudio-utils pavucontrol \
        scrot flameshot arandr brightnessctl \
        network-manager-applet bluez blueman python3-pip
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
        hacker)
            safe_install_packages papirus-icon-theme
            local dracula_theme_url="https://github.com/dracula/gtk/archive/refs/heads/master.zip"
            local dracula_theme_zip="$themes_dir/dracula.zip"
            if download_file "$dracula_theme_url" "$dracula_theme_zip"; then
                extract_zip "$dracula_theme_zip" "$themes_dir"
                rm -f "$dracula_theme_zip"
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

set_gsettings_theme() {
    local key="$1"
    local value="$2"

    if gsettings_available; then
        if ! gsettings set "$key" "$value" >/dev/null 2>&1; then
            log "Warnung: Theme-Wert $value konnte für $key nicht gesetzt werden."
        fi
    else
        log "gsettings nicht verfügbar. Überspringe Theme-Aktivierung."
    fi
}

activate_themes_and_icons() {
    local design="$1"
    log "Aktiviere Themes und Icons für '$design'..."

    case "$design" in
        minimalistic)
            set_gsettings_theme org.gnome.desktop.interface gtk-theme "Adwaita"
            set_gsettings_theme org.gnome.desktop.interface icon-theme "Adwaita"
            set_gsettings_theme org.gnome.desktop.wm.preferences theme "Adwaita"
            ;;
        corporate)
            set_gsettings_theme org.gnome.desktop.interface gtk-theme "Arc"
            set_gsettings_theme org.gnome.desktop.interface icon-theme "Papirus"
            set_gsettings_theme org.gnome.desktop.wm.preferences theme "Arc"
            ;;
        hacker|fsocietyhub)
            set_gsettings_theme org.gnome.desktop.interface gtk-theme "gtk-master"
            set_gsettings_theme org.gnome.desktop.interface icon-theme "Papirus-Dark"
            set_gsettings_theme org.gnome.desktop.wm.preferences theme "gtk-master"
            ;;
        *)
            error "Unbekanntes Design: $design"
            return 1
            ;;
    esac
}

config_i3_or_sway() {
    local design="$1"
    log "Konfiguriere i3/Sway für '$design'..."

    if command_exists i3; then
        mkdir -p "$HOME/.config/i3"
        cat > "$HOME/.config/i3/config" <<'EOF'
set $mod Mod4
font pango:FiraCode Nerd Font 10
bindsym $mod+Return exec alacritty
exec --no-startup-id picom -b
EOF
    fi

    if command_exists sway; then
        mkdir -p "$HOME/.config/sway"
        cat > "$HOME/.config/sway/config" <<'EOF'
set $mod Mod4
font pango:FiraCode Nerd Font 10
bindsym $mod+Return exec alacritty
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

    local wallpaper_path="$HOME/Pictures/wallpaper.jpg"
    if [ -n "${DISPLAY-}" ] && command_exists feh && [ -f "$wallpaper_path" ]; then
        feh --bg-scale "$wallpaper_path" >/dev/null 2>&1 || log "Fehler beim Setzen der Hintergrundgrafik."
    else
        log "Kein Wallpaper gesetzt: feh nicht verfügbar, DISPLAY nicht gesetzt oder Bild fehlt."
    fi

    if command_exists picom; then
        if [ -f "$HOME/.config/picom.conf" ]; then
            picom -b --config "$HOME/.config/picom.conf" >/dev/null 2>&1 || log "Picom konnte nicht gestartet werden."
        else
            picom -b >/dev/null 2>&1 || log "Picom konnte nicht gestartet werden."
        fi
    fi

    mkdir -p "$HOME/.config/rofi"
    local rofi_config_url="https://raw.githubusercontent.com/adi1090x/rofi/master/themes/gruvbox-dark.rasi"
    local rofi_config_path="$HOME/.config/rofi/config.rasi"
    if ! download_file "$rofi_config_url" "$rofi_config_path"; then
        log "Rofi-Konfiguration konnte nicht heruntergeladen werden. Verwende Standardkonfiguration."
        cat > "$rofi_config_path" <<'EOF'
configuration {
    theme: "gruvbox-dark"
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
        hacker|fsocietyhub)
            cat > "$HOME/.config/alacritty/alacritty.yml" <<'EOF'
font:
  normal:
    family: "FiraCode Nerd Font"
    style: Regular
  size: 11.0
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
    [ -f "$HOME/.config/alacritty/alacritty.yml" ] && paths+=("$HOME/.config/alacritty/alacritty.yml")
    [ -f "$HOME/.config/rofi/config.rasi" ] && paths+=("$HOME/.config/rofi/config.rasi")
    [ -d "$HOME/.themes" ] && paths+=("$HOME/.themes")
    [ -d "$HOME/.icons" ] && paths+=("$HOME/.icons")

    if [ "${#paths[@]}" -gt 0 ]; then
        "${git_cmd[@]}" add "${paths[@]}" >/dev/null 2>&1 || true
        if ! "${git_cmd[@]}" diff --cached --quiet --exit-code >/dev/null 2>&1; then
            "${git_cmd[@]}" commit -m "Initial commit of dotfiles" >/dev/null 2>&1 || true
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

    python3 -m pip install --user uv >/dev/null 2>&1 || log "uv konnte nicht installiert werden."
}

apply_design() {
    local design="$1"

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

    log "Design '$design' angewendet. Bitte starte deine Sitzung neu, um alle Änderungen zu übernehmen."
}

show_fsocietyhub_banner() {
    cat <<'EOF'
███████╗███████╗ ██████╗  ██████╗██╗███████╗████████╗██╗   ██╗██╗  ██╗██╗   ██╗██████╗
██╔════╝██╔════╝██╔═══██╗██╔════╝██║██╔════╝╚══██╔══╝╚██╗ ██╔╝██║  ██║██║   ██║██╔══██╗
█████╗  ███████╗██║   ██║██║     ██║█████╗     ██║    ╚████╔╝ ███████║██║   ██║██████╔╝
██╔══╝  ╚════██║██║   ██║██║     ██║██╔══╝     ██║     ╚██╔╝  ██╔══██║██║   ██║██╔══██╗
██║     ███████║╚██████╔╝╚██████╗██║███████╗   ██║      ██║   ██║  ██║╚██████╔╝██████╔╝
╚═╝     ╚══════╝ ╚═════╝  ╚═════╝╚═╝╚══════╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝
EOF
}

print_help() {
    cat <<'EOF'
Verwendung: ./custom.sh [OPTION]

Optionen:
  --design <name>    Wende ein Design an (minimalistic, corporate, hacker, fsocietyhub)
  --restore          Stelle den zuletzt gespeicherten Desktop-Zustand wieder her
  --help             Zeige diese Hilfe an
EOF
}

show_menu() {
    show_fsocietyhub_banner

    echo "Wähle eine Option:"
    echo "1) Design anwenden"
    echo "2) Backup wiederherstellen"
    echo "3) Beenden"
    read -rp "Eingabe: " choice

    case "$choice" in
        1)
            echo "Verfügbare Designs:"
            echo "1) Minimalistic"
            echo "2) Corporate"
            echo "3) Hacker"
            echo "4) Fsocietyhub"
            read -rp "Design wählen: " design_choice
            case "$design_choice" in
                1) apply_design "minimalistic" ;;
                2) apply_design "corporate" ;;
                3) apply_design "hacker" ;;
                4) apply_design "fsocietyhub" ;;
                *) error "Ungültige Auswahl." ;;
            esac
            ;;
        2)
            restore_backup
            ;;
        3)
            log "Beende." ;;
        *)
            error "Ungültige Auswahl." ;;
    esac
}

main() {
    if [ "$#" -gt 0 ]; then
        case "$1" in
            --design)
                if [ "$#" -lt 2 ]; then
                    error "Fehlendes Design-Argument."
                    exit 1
                fi
                apply_design "$2"
                ;;
            --restore)
                restore_backup
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
        show_menu
    fi
}

main "$@"
