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

    log "Installing themes and icons..."

    local themes_dir="$HOME/.themes"
    local icons_dir="$HOME/.icons"

    mkdir -p "$themes_dir" "$icons_dir"

    # Install Dracula theme
    local dracula_theme_url="https://github.com/dracula/gtk/archive/refs/heads/master.zip"
    local dracula_theme_zip="$themes_dir/dracula.zip"

    wget -O "$dracula_theme_zip" "$dracula_theme_url"
    unzip -o "$dracula_theme_zip" -d "$themes_dir"
    rm "$dracula_theme_zip"

}

activate_themes_and_icons() {
    log "Activating themes and icons..."

    gsettings set org.gnome.desktop.interface gtk-theme "gtk-master"
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
    gsettings set org.gnome.desktop.wm.preferences theme "gtk-master"

    lxappearance --set gtk-master
    lxappearance --set Papirus-Dark
    lxappearance --set gtk-master
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
    log "Configuring i3 or Sway..."

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
    log "Customizing desktop environment..."
    bindsym $mod+Return exec alacritty
    exec --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg
    exec --no-startup-id picom -b --config ~/.config/picom.conf
    mkdir -p ~/.config/rofi
    curl -o ~/.config/rofi/config.rasi https://raw.githubusercontent.com/adi1090x/rofi/master/themes/gruvbox-dark.rasi
    if if_theme_not_available "gtk-master"; then
        themes_and_icons_install
        activate_themes_and_icons
    fi

    config_i3_or_sway
}

install_and_config_alacritty() {
    log "Installing and configuring Alacritty terminal emulator..."
    sudo apt install -y alacritty
    mkdir -p ~/.config/alacritty
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

main() {
    show_fsocietyhub_banner
    install_custom_dependencies
    nerd_fonts_install
    customize_desktop_environment
    install_and_config_alacritty
    install_system_monitoring_tools
    audio_and_media_tools
    brightness_control
    network_manager
    finetuning_and_optimizations
    manage_dot_files
    install_uv

    log "Custom setup complete! Please restart your session to apply all changes."
}

main