#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
	echo "[FSOCIETYHUB] $1"
}

warn() {
	echo "[FSOCIETYHUB][WARN] $1"
}

error() {
	echo "[FSOCIETYHUB][ERROR] $1" >&2
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
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

	touch "$file"
	grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

safe_apt_update() {
	if ! command_exists apt-get; then
		error "apt-get ist auf diesem System nicht verfügbar."
		return 1
	fi

	log "[...] Updating package lists..."
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

	for pkg in "$@"; do
		if package_available "$pkg"; then
			available+=("$pkg")
		else
			unavailable+=("$pkg")
		fi
	done

	if [ "${#unavailable[@]}" -gt 0 ]; then
		warn "Skipping unavailable packages: ${unavailable[*]}"
	fi

	if [ "${#available[@]}" -eq 0 ]; then
		warn "No installable packages left in this batch."
		return 0
	fi

	log "[...] Installing packages: ${available[*]}"
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
}

install_base_dependencies() {
	safe_apt_update

	log "[...] Upgrading packages..."
	sudo apt-get full-upgrade -y

	log "[...] Installing base and virtualization dependencies..."
	safe_install_packages \
		python3-full \
		python3-pip \
		git \
		curl \
		wget \
		npm \
		code-oss \
		jq \
		ca-certificates \
		docker.io \
		docker-compose \
		virtualbox \
		virtualbox-dkms \
		virtualbox-qt \
		qemu-system-x86 \
		qemu-utils \
		qemu-kvm \
		libvirt-daemon-system \
		libvirt-clients \
		bridge-utils \
		ovmf

	warn "virtualbox-ext-pack wird nicht automatisch installiert, da dafür meist eine interaktive Lizenzbestätigung nötig ist."

	log "[...] Installing uv package manager..."
	if ! command -v uv >/dev/null 2>&1; then
		python3 -m pip install --user uv --break-system-packages \
			|| python3 -m pip install --user uv \
			|| warn "uv konnte nicht installiert werden."
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
	if ! command_exists curl; then
		warn "curl ist nicht installiert. Überspringe Ollama-Installation."
		return 0
	fi

	if ! command -v ollama >/dev/null 2>&1; then
		curl -fsSL https://ollama.com/install.sh | sh
	fi
	log "[...] Configuring Ollama service and permissions..."
	sudo usermod -aG ollama "$USER" || true
	if command_exists systemctl && systemctl list-unit-files | grep -q '^ollama\.service'; then
		log "[...] Enabling and starting Ollama service..."
		sudo systemctl enable --now ollama || true
	fi
	log "[...] Ollama installation and configuration complete."
}

configure_shell() {
	log "[...] Setting up PATH and aliases..."
	touch "$HOME/.bashrc"
	append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
	append_if_missing 'alias ll="ls -alF"' "$HOME/.bashrc"
	append_if_missing 'alias la="ls -A"' "$HOME/.bashrc"
	append_if_missing 'alias l="ls -CF"' "$HOME/.bashrc"
	append_if_missing 'alias update="sudo apt update && sudo apt upgrade -y"' "$HOME/.bashrc"
}

install_kali_toolsuite() {
	log "[...] Installing Kali Linux tool suite..."
	safe_install_packages kali-linux-everything
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
