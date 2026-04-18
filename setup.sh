#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
	echo "[FSOCIETYHUB] $1"
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

append_if_missing() {
	local line="$1"
	local file="$2"

	grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

install_base_dependencies() {
	log "[...] Updating package lists..."
	sudo apt update

	log "[...] Upgrading packages..."
	sudo apt-get full-upgrade -y

	log "[...] Installing base and virtualization dependencies..."
	sudo apt install -y \
		python3-full \
		python3-pip \
		git \
		curl \
		wget \
		code-oss \
		jq \
		ca-certificates \
		docker.io \
		docker-compose \
		virtualbox \
		virtualbox-ext-pack \
		virtualbox-dkms \
		virtualbox-qt \
		qemu-system-x86 \
		qemu-utils \
		qemu-kvm \
		libvirt-daemon-system \
		libvirt-clients \
		bridge-utils \
		ovmf

	log "[...] Installing uv package manager..."
	if ! command -v uv >/dev/null 2>&1; then
		python3 -m pip install --user uv --break-system-packages
	fi
}

configure_system_services() {
	log "[...] Configuring virtualization services and groups..."
	sudo systemctl enable --now docker || true
	sudo systemctl enable --now libvirtd || true

	sudo usermod -aG docker "$USER" || true
	sudo usermod -aG kvm "$USER" || true
	sudo usermod -aG libvirt "$USER" || true
	sudo usermod -aG vboxusers "$USER" || true
}

create_directories() {
	log "[...] Creating workspace directory structure..."

	mkdir -p ~/Assistant/Tools
	mkdir -p ~/Assistant/Models
	log "[...] Created Assistant directories."

	mkdir -p ~/CTF/HackTheBox/{Rooms,Challenges,ProLabs,OpenVPN}
	mkdir -p ~/CTF/TryHackMe/{Rooms,Challenges,OpenVPN}
	log "[...] Created CTF directories."

	mkdir -p ~/Development/Projects
	mkdir -p ~/Github/Tools
	mkdir -p ~/Scripts ~/Tools
	log "[...] Created development and tools directories."

	mkdir -p ~/Virtual/virtualbox/{isos,images,snapshots}
	mkdir -p ~/Virtual/qemu/{isos,images,snapshots,scripts}
	mkdir -p ~/Virtual/docker/{images,containers,compose}
	mkdir -p ~/Virtual/labs/windows
	mkdir -p ~/Virtual/labs/linux
	log "[...] Created virtualization directories."
}

install_ollama() {
	log "[...] Installing Ollama for local AI model hosting..."
	if ! command -v ollama >/dev/null 2>&1; then
		curl -fsSL https://ollama.com/install.sh | sh
	fi
	log "[...] Configuring Ollama service and permissions..."
	sudo usermod -aG ollama "$USER" || true
	log "[...] Starting Ollama service..."
	sudo systemctl start ollama || true
	sudo systemctl disable --now ollama || true
	log "[...] Ollama installation and configuration complete."
}

configure_shell() {
	log "[...] Setting up PATH and aliases..."
	append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
	append_if_missing 'alias ll="ls -alF"' "$HOME/.bashrc"
	append_if_missing 'alias la="ls -A"' "$HOME/.bashrc"
	append_if_missing 'alias l="ls -CF"' "$HOME/.bashrc"
	append_if_missing 'alias update="sudo apt update && sudo apt upgrade -y"' "$HOME/.bashrc"
}

install_kali_toolsuite() {
	log "[...] Installing Kali Linux tool suite..."
	sudo apt-get install kali-linux-everything -y
}

main() {
	show_fsocietyhub_banner
	log "[...] Initializing setup..."

	install_base_dependencies
	configure_system_services
	create_directories
	configure_shell
	install_ollama

	install_kali_toolsuite

	log "[...] Setup complete."
}

main "$@"