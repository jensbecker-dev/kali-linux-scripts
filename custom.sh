#!/bin/bash

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

log() {
    echo "[*] $1"
}

backup_current_setup() {
    log "Backing up current desktop setup..."
    local backup_dir="$HOME/.desktop_backup"
    mkdir -p "$backup_dir"

    # Screenshot
    scrot "$backup_dir/current_desktop.png"

    # Backup current themes and icons
    gsettings get org.gnome.desktop.interface gtk-theme > "$backup_dir/gtk_theme.txt"
    gsettings get org.gnome.desktop.interface icon-theme > "$backup_dir/icon_theme.txt"
    gsettings get org.gnome.desktop.wm.preferences theme > "$backup_dir/wm_theme.txt"

    log "Backup saved to $backup_dir"
}

restore_backup() {
    log "Restoring previous desktop setup..."
    local backup_dir="$HOME/.desktop_backup"

    if [ -d "$backup_dir" ]; then
        # Restore themes
        local gtk_theme=$(cat "$backup_dir/gtk_theme.txt")
        local icon_theme=$(cat "$backup_dir/icon_theme.txt")
        local wm_theme=$(cat "$backup_dir/wm_theme.txt")

        gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
        gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"
        gsettings set org.gnome.desktop.wm.preferences theme "$wm_theme"

        # Restore wallpaper or other settings if needed
        # For simplicity, assume feh or nitrogen can be reset manually or add more

        log "Restoration complete. Please restart your session."
    else
        log "No backup found."
    fi
}

install_custom_dependencies() {
    log "Installing custom dependencies..."

    sudo apt update && sudo apt full-upgrade -y
    sudo apt install -y \
        picom feh rofi waybar alacritty thunar nitrogen \
        lxappearance fonts-font-awesome fonts-firacode \
        fonts-jetbrains-mono ttf-nerd-fonts-symbols \
        playerctl pulseaudio-utils pavucontrol \
        scrot flameshot arandr brightnessctl \
        network-manager-applet bluez blueman
}

nerd_fonts_install() {
    log "Installing Nerd Fonts..."

    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"

    local nerd_font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FiraCode.zip"
    local nerd_font_zip="$font_dir/FiraCode.zip"

    wget -O "$nerd_font_zip" "$nerd_font_url"
    unzip -o "$nerd_font_zip" -d "$font_dir"
    rm "$nerd_font_zip"
}

themes_and_icons_install() {
    local design="$1"
    log "Installing themes and icons for $design..."

    local themes_dir="$HOME/.themes"
    local icons_dir="$HOME/.icons"

    mkdir -p "$themes_dir" "$icons_dir"

    case "$design" in
        minimalistic)
            # Minimal themes, e.g., Adwaita or simple GTK
            sudo apt install -y gnome-themes-extra
            ;;
        corporate)
            # Professional themes, e.g., Arc or Breeze
            sudo apt install -y arc-theme
            ;;
        hacker)
            # Dark themes, e.g., Dracula
            local dracula_theme_url="https://github.com/dracula/gtk/archive/refs/heads/master.zip"
            local dracula_theme_zip="$themes_dir/dracula.zip"
            wget -O "$dracula_theme_zip" "$dracula_theme_url"
            unzip -o "$dracula_theme_zip" -d "$themes_dir"
            rm "$dracula_theme_zip"
            ;;
        fsocietyhub)
            # Custom fsocietyhub theme (Dracula as base)
            local dracula_theme_url="https://github.com/dracula/gtk/archive/refs/heads/master.zip"
            local dracula_theme_zip="$themes_dir/dracula.zip"
            wget -O "$dracula_theme_zip" "$dracula_theme_url"
            unzip -o "$dracula_theme_zip" -d "$themes_dir"
            rm "$dracula_theme_zip"
            ;;
    esac
}

activate_themes_and_icons() {
    local design="$1"
    log "Activating themes and icons for $design..."

    case "$design" in
        minimalistic)
            gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
            gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
            gsettings set org.gnome.desktop.wm.preferences theme "Adwaita"
            ;;
        corporate)
            gsettings set org.gnome.desktop.interface gtk-theme "Arc"
            gsettings set org.gnome.desktop.interface icon-theme "Papirus"
            gsettings set org.gnome.desktop.wm.preferences theme "Arc"
            ;;
        hacker)
            gsettings set org.gnome.desktop.interface gtk-theme "gtk-master"
            gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
            gsettings set org.gnome.desktop.wm.preferences theme "gtk-master"
            ;;
        fsocietyhub)
            gsettings set org.gnome.desktop.interface gtk-theme "gtk-master"
            gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
            gsettings set org.gnome.desktop.wm.preferences theme "gtk-master"
            ;;
    esac

    lxappearance --set "$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")"
    lxappearance --set "$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")"
    lxappearance --set "$(gsettings get org.gnome.desktop.wm.preferences theme | tr -d "'")"
}

if_theme_not_available() {
    local theme="$1"
    if ! gsettings get org.gnome.desktop.interface gtk-theme | grep -q "$theme"; then
        sudo apt install -y qt5ct kvantum
        qt5ct  # Select the same GTK theme
        return 0
    fi
    return 1
}

config_i3_or_sway() {
    local design="$1"
    log "Configuring i3 or Sway for $design..."

    local config_dir="$HOME/.config"
    mkdir -p "$config_dir"

    if [ -d "$config_dir/i3" ]; then
        mkdir -p ~/.config/i3
        curl -o ~/.config/i3/config https://raw.githubusercontent.com/unixporn/i3/master/config
        ln -sf "$(pwd)/i3/config" "$config_dir/i3/config"
    fi

    if [ -d "$config_dir/sway" ]; then
        mkdir -p ~/.config/sway
        curl -o ~/.config/sway/config https://raw.githubusercontent.com/unixporn/sway/master/config
        mkdir -p ~/.config/waybar
        curl -o ~/.config/waybar/config https://raw.githubusercontent.com/Alexays/Waybar/master/resources/config
        curl -o ~/.config/waybar/style.css https://raw.githubusercontent.com/Alexays/Waybar/master/resources/style.css
        ln -sf "$(pwd)/sway/config" "$config_dir/sway/config"
    fi
} 

customize_desktop_environment() {
    local design="$1"
    log "Customizing desktop environment for $design..."
    bindsym $mod+Return exec alacritty
    exec --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg
    exec --no-startup-id picom -b --config ~/.config/picom.conf
    mkdir -p ~/.config/rofi
    curl -o ~/.config/rofi/config.rasi https://raw.githubusercontent.com/adi1090x/rofi/master/themes/gruvbox-dark.rasi
    if if_theme_not_available "$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")"; then
        themes_and_icons_install "$design"
        activate_themes_and_icons "$design"
    fi

    config_i3_or_sway "$design"
}

install_and_config_alacritty() {
    local design="$1"
    log "Installing and configuring Alacritty for $design..."
    sudo apt install -y alacritty
    mkdir -p ~/.config/alacritty
    case "$design" in
        minimalistic)
            cat > ~/.config/alacritty/alacritty.yml <<'EOF'
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
            cat > ~/.config/alacritty/alacritty.yml <<'EOF'
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
        hacker)
            cat > ~/.config/alacritty/alacritty.yml <<'EOF'
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
        fsocietyhub)
            cat > ~/.config/alacritty/alacritty.yml <<'EOF'
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
    esac
}

install_system_monitoring_tools() {
    log "Installing system monitoring tools..."
    sudo apt install -y btop
    sudo apt install -y htop glances neofetch
    neofetch --config ~/.config/neofetch/config.conf
}

audio_and_media_tools() {
    log "Installing audio and media tools..."
    sudo apt install -y pavucontrol playerctl vlc
    playerctl --player=spotify play-pause  # Example for Spotify control
    pavucontrol  # Opens the PulseAudio volume control
}

brightness_control() {
    log "Setting up brightness control..."
    sudo apt install -y brightnessctl
    brightnessctl set 50%  # Sets the screen brightness to 50% as an example
}  

network_manager() {
    log "Setting up Network Manager..."
    sudo apt install -y network-manager-applet
    nmcli device wifi list  # Lists available Wi-Fi networks
    nmcli device wifi connect "SSID_NAME" password "PASSWORD"  # Connects to a Wi-Fi network
    nm-applet --indicator &  # Starts the Network Manager applet in the background
}

finetuning_and_optimizations() {
    log "Performing finetuning and optimizations..."
    sudo apt autoremove -y
    sudo apt clean
    log "System cleanup complete."
    exec --no-startup-id nitrogen --restore
    exec --no-startup-id picom -b
    exec --no-startup-id nm-applet --indicator
    exec --no-startup-id blueman-applet
    exec --no-startup-id /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
}

manage_dot_files() {
    log "Managing dotfiles..."
    mkdir -p "$HOME/.config"
    ln -sf "$(pwd)/alacritty/alacritty.yml" "$HOME/.config/alacritty/alacritty.yml"
    ln -sf "$(pwd)/rofi/config.rasi" "$HOME/.config/rofi/config.rasi"
    git init --bare \$HOME/.dotfiles
    alias dotfiles='/usr/bin/git --git-dir=\$HOME/.dotfiles/ --work-tree=\$HOME'
    dotfiles config --local status.showUntrackedFiles no
    dotfiles add ~/.config/i3 ~/.config/alacritty ~/.themes ~/.icons
    dotfiles commit -m "Initial commit of dotfiles"
    dotfiles remote add origin
    if [ -d "$HOME/.config/i3" ]; then
        ln -sf "$(pwd)/i3/config" "$HOME/.config/i3/config"
    fi
    if [ -d "$HOME/.config/sway" ]; then
        ln -sf "$(pwd)/sway/config" "$HOME/.config/sway/config"
    fi
}

install_uv() {
    log "Installing UV for Python environment management..."
    if ! command -v uv >/dev/null 2>&1; then
        python3 -m pip install --user uv --break-system-packages
    fi
}

apply_design() {
    local design="$1"
    backup_current_setup
    install_custom_dependencies
    nerd_fonts_install
    themes_and_icons_install "$design"
    activate_themes_and_icons "$design"
    customize_desktop_environment "$design"
    install_and_config_alacritty "$design"
    install_system_monitoring_tools
    audio_and_media_tools
    brightness_control
    network_manager
    finetuning_and_optimizations
    manage_dot_files
    install_uv
    log "Design '$design' applied! Please restart your session to apply all changes."
}

main() {
    show_fsocietyhub_banner

    echo "Choose an option:"
    echo "1) Apply a design"
    echo "2) Restore backup"
    echo "3) Exit"
    read -p "Enter choice: " choice

    case $choice in
        1)
            echo "Available designs:"
            echo "1) Minimalistic"
            echo "2) Corporate"
            echo "3) Hacker"
            echo "4) Fsocietyhub"
            read -p "Select design: " design_choice

            case $design_choice in
                1) apply_design "minimalistic" ;;
                2) apply_design "corporate" ;;
                3) apply_design "hacker" ;;
                4) apply_design "fsocietyhub" ;;
                *) log "Invalid choice." ;;
            esac
            ;;
        2)
            restore_backup
            ;;
        3)
            log "Exiting."
            ;;
        *)
            log "Invalid choice."
            ;;
    esac
}

main