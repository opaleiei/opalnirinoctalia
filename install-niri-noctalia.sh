#!/usr/bin/env bash
# install-niri-noctalia.sh
#
# Installs and configures niri (scrollable-tiling Wayland compositor) with
# Noctalia v5, greetd + Noctalia Greeter, NVIDIA 580xx legacy drivers,
# Zsh terminal stack, Zen Browser with PSD, Docker, and KVM/virt-manager.
#
# Usage:
#   chmod +x install-niri-noctalia.sh
#   ./install-niri-noctalia.sh
#
# Run as your normal user (NOT root) with sudo available.

set -euo pipefail

log()  { echo -e "\033[1;32m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m!!\033[0m $*"; }
die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }

# Guard checks
[[ $EUID -eq 0 ]] && die "Run this as your normal user, not root. It will call sudo when needed."
command -v sudo >/dev/null 2>&1 || die "sudo is not installed. Add user to wheel group and install sudo first."
command -v pacman >/dev/null 2>&1 || die "This script is for Arch Linux (pacman not found)."

# Cleanup trap for temporary resources and background processes
TMP_REPO=""
SUDO_PID=""
cleanup() {
  [[ -n "$SUDO_PID" ]] && kill "$SUDO_PID" 2>/dev/null || true
  [[ -n "$TMP_REPO" && -d "$TMP_REPO" ]] && rm -rf "$TMP_REPO"
}
trap cleanup EXIT

# ── Authenticate sudo upfront and keep it alive ──────────────────────────
log "Authenticating sudo upfront for an unattended installation..."
sudo -v
(while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done) 2>/dev/null &
SUDO_PID=$!

# ── 0. Base System, Timezone, Locale & Tools ─────────────────────────────
log "Setting timezone to Asia/Bangkok (Thailand)..."
sudo ln -sf /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
sudo hwclock --systohc || true

log "Configuring locales (en_US.UTF-8, th_TH.UTF-8)..."
sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sudo sed -i 's/^#th_TH.UTF-8 UTF-8/th_TH.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
echo "LANG=en_US.UTF-8" | sudo tee /etc/locale.conf >/dev/null

log "Updating system databases and base tools..."
sudo pacman -Syu --needed --noconfirm base-devel git

# ── 1. Chaotic-AUR (prebuilt binary repository) ─────────────────────────
if ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf 2>/dev/null; then
  log "Enabling Chaotic-AUR..."
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
  sudo pacman -U --needed --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

  sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
  sudo pacman -Sy
else
  log "Chaotic-AUR already enabled."
fi

# ── 2. AUR Helper Setup (paru / yay) ────────────────────────────────────
if command -v paru >/dev/null 2>&1; then
  AUR_HELPER=paru
elif command -v yay >/dev/null 2>&1; then
  AUR_HELPER=yay
else
  log "Installing paru..."
  if ! sudo pacman -S --needed --noconfirm paru; then
    warn "Building paru-bin from AUR fallback..."
    tmpdir=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmpdir/paru-bin"
    (cd "$tmpdir/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
  fi
  AUR_HELPER=paru
fi
log "Using AUR helper: $AUR_HELPER"

# Helper function to install packages via pacman or fallback to AUR helper
install_pkgs() {
  local pkgs=("$@")
  if ! sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>/dev/null; then
    "$AUR_HELPER" -S --needed --noconfirm "${pkgs[@]}"
  fi
}

# ── 3. Core Desktop, Audio, Media, Shell & Virtualization Stack ──────────
log "Installing official system stack, Docker, and Virtualization tools..."
OFFICIAL_PKGS=(
  # Niri & Wayland Desktop Stack
  niri xdg-desktop-portal xdg-desktop-portal-gnome polkit
  pipewire pipewire-pulse pipewire-alsa wireplumber
  networkmanager network-manager-applet brightnessctl playerctl
  wl-clipboard cliphist grim slurp ttf-nerd-fonts-symbols noto-fonts
  jemalloc dbus accountsservice greetd papirus-icon-theme
  
  # Shell & CLI Utilities
  zsh starship zsh-autosuggestions zsh-syntax-highlighting zsh-completions
  zsh-history-substring-search fzf zoxide eza bat atuin
  
  # Docker Stack
  docker docker-compose
  
  # Virt-Manager / KVM Virtualization Stack
  virt-manager qemu-desktop libvirt edk2-ovmf dnsmasq iptables-nft dmidecode bridge-utils
)

install_pkgs "${OFFICIAL_PKGS[@]}"

# ── 4. Foreign & AUR Packages ───────────────────────────────────────────
log "Installing AUR/Chaotic-AUR applications..."
AUR_PKGS=(
  noctalia
  noctalia-greeter
  xwayland-satellite
  ghostty-git
  fastfetch-git
  bibata-cursor-theme
  fzf-tab
  zen-browser-bin
  zed
  ffmpeg4.4
  profile-sync-daemon-zen
  limine-mkinitcpio-hook
  nautilus-admin-gtk4
)

"$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}"

# ── 5. NVIDIA Legacy 580xx Driver & Kernel Configuration ──────────────────
log "Installing NVIDIA 580xx legacy driver..."
NVIDIA_HEADERS_INSTALLED=0
for k in linux linux-lts linux-zen linux-hardened; do
  if pacman -Qq "$k" &>/dev/null; then
    sudo pacman -S --needed --noconfirm "${k}-headers"
    NVIDIA_HEADERS_INSTALLED=1
  fi
done
[[ $NVIDIA_HEADERS_INSTALLED -eq 0 ]] && warn "Could not detect active kernel package automatically for headers."

install_pkgs nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings

log "Configuring DRM kernel mode setting in mkinitcpio..."
sudo sed -i -E 's/^MODULES=\(([^)]*)\)/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sudo mkinitcpio -P

# Scan Limine config locations (including custom arch-limine paths)
LIMINE_CFG=""
for cfg in \
  /boot/EFI/arch-limine/limine.config /boot/EFI/arch-limine/limine.conf /boot/EFI/arch-limine/limine.cfg \
  /boot/limine.conf /boot/limine.cfg /boot/limine/limine.conf /boot/limine/limine.cfg \
  /boot/EFI/BOOT/limine.conf /boot/EFI/BOOT/limine.cfg /boot/EFI/BOOT/limine/limine.conf /boot/EFI/BOOT/limine/limine.cfg \
  /boot/efi/EFI/limine/limine.conf /boot/efi/EFI/limine/limine.cfg; do
  if [[ -f "$cfg" ]]; then
    LIMINE_CFG="$cfg"
    break
  fi
done

if [[ -n "$LIMINE_CFG" ]]; then
  log "Adding nvidia-drm.modeset=1 to Limine ($LIMINE_CFG)..."
  if ! grep -q "nvidia-drm.modeset=1" "$LIMINE_CFG"; then
    sudo sed -i -E 's/^([[:space:]]*(kernel_)?cmdline.*)/\1 nvidia-drm.modeset=1/i' "$LIMINE_CFG"
  fi
elif [[ -d /boot/loader/entries ]]; then
  log "Adding nvidia-drm.modeset=1 to systemd-boot entries..."
  for f in /boot/loader/entries/*.conf; do
    [[ -f "$f" ]] || continue
    if grep -q "^options" "$f" && ! grep -q "nvidia-drm.modeset=1" "$f"; then
      sudo sed -i 's/^options \(.*\)$/options \1 nvidia-drm.modeset=1/' "$f"
    fi
  done
elif [[ -f /etc/default/grub ]] && command -v grub-mkconfig >/dev/null 2>&1; then
  log "Adding nvidia-drm.modeset=1 to GRUB..."
  if ! grep -q "nvidia-drm.modeset=1" /etc/default/grub; then
    sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")([^"]*)(")/\1\2 nvidia-drm.modeset=1\3/' /etc/default/grub
  fi
  sudo grub-mkconfig -o /boot/grub/grub.cfg
else
  warn "Could not locate bootloader configuration automatically."
fi

# ── 6. Services & User Groups Setup ─────────────────────────────────────
log "Enabling system services..."
sudo systemctl enable NetworkManager.service
sudo systemctl enable accounts-daemon.service
sudo systemctl enable docker.service
sudo systemctl enable libvirtd.service

log "Adding user ($USER) to docker, libvirt, and kvm groups..."
sudo usermod -aG docker,libvirt,kvm "$USER"

# Configure libvirt default network
if command -v virsh >/dev/null 2>&1; then
  sudo virsh net-autostart default 2>/dev/null || true
fi

# Configure Greetd + Noctalia Greeter
GREETER_SESSION_BIN="$(command -v noctalia-greeter-session || true)"
if [[ -n "$GREETER_SESSION_BIN" ]]; then
  log "Configuring greetd with Noctalia Greeter..."
  sudo mkdir -p /etc/greetd
  sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "$GREETER_SESSION_BIN"
user = "greeter"
EOF
  sudo systemctl enable greetd.service
fi

log "Changing default shell to Zsh..."
sudo chsh -s "$(command -v zsh)" "$USER" || warn "Manual chsh execution may be required."

log "Configuring Profile Sync Daemon for Zen Browser..."
mkdir -p "$HOME/.config/psd"
cat > "$HOME/.config/psd/psd.conf" <<EOF
USE_OVERLAYFS="yes"
BROWSERS=("zen-browser")
EOF
systemctl --user enable psd.service

# ── 7. Fetch Dotfiles from Repository ──────────────────────────────────
log "Cloning dotfiles repository..."
TMP_REPO=$(mktemp -d)
git clone --depth 1 https://github.com/opaleiei/opalnirinoctalia.git "$TMP_REPO"

mkdir -p "$HOME/.config"
[[ -d "$TMP_REPO/niri" ]] && cp -r "$TMP_REPO/niri" "$HOME/.config/" && log "Copied niri config."
[[ -d "$TMP_REPO/fastfetch" ]] && cp -r "$TMP_REPO/fastfetch" "$HOME/.config/" && log "Copied fastfetch config."
[[ -d "$TMP_REPO/ghostty" ]] && cp -r "$TMP_REPO/ghostty" "$HOME/.config/" && log "Copied ghostty config."
[[ -f "$TMP_REPO/.zshrc" ]] && cp "$TMP_REPO/.zshrc" "$HOME/.zshrc" && log "Copied .zshrc."

# ── 8. Completion Summary ───────────────────────────────────────────────
log "Installation and optimization complete."
cat <<EOF

Summary of changes:
  • Installed Docker & Docker Compose; added user to 'docker' group.
  • Installed Virt-Manager & KVM stack; added user to 'libvirt' and 'kvm' groups.
  • Configured system timezone (Asia/Bangkok) and locales (en_US, th_TH).
  • Configured NVIDIA 580xx drivers and Limine kernel arguments.
  • Applied dotfiles for Niri, Fastfetch, and Zsh.

Next Steps:
  1. Reboot the system to initialize the kernel modules, group memberships, and services.
  2. Test Docker: 'docker run hello-world' (no sudo needed after reboot).
  3. Test Virt-Manager: Launch 'virt-manager' from your launcher or terminal.
EOF
