#!/usr/bin/env bash
# install-niri-noctalia.sh
#
# Installs and configures niri (scrollable-tiling Wayland compositor) with
# Noctalia v5, greetd + Noctalia Greeter, NVIDIA 580xx legacy drivers,
# Zsh terminal stack, Zen Browser with PSD, Docker, KVM/virt-manager,
# and Snapper + Limine snapshot sync for Btrfs (@root).
#
# Now includes CachyOS Repository, linux-cachyos kernel, and gaming optimizations.
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
sudo pacman -Syu --needed --noconfirm base-devel git curl wget wget2

# ── 1. Chaotic-AUR & CachyOS Repositories ────────────────────────────────
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

if ! grep -q "^\[cachyos\]" /etc/pacman.conf 2>/dev/null; then
  log "Enabling CachyOS repository..."
  tmp_cachy=$(mktemp -d)
  curl -sL https://mirror.cachyos.org/cachyos-repo.tar.xz | tar xJ -C "$tmp_cachy"
  (cd "$tmp_cachy/cachyos-repo" && sudo bash cachyos-repo.sh --dont-update)
  rm -rf "$tmp_cachy"
else
  log "CachyOS repository already enabled."
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

# ── 3. FIRST: Kernels, NVIDIA Legacy 580xx Driver & Bootloader Params ─────
log "Installing linux-cachyos kernel and cachyos-gaming-meta..."
sudo pacman -S --needed --noconfirm linux-cachyos linux-cachyos-headers cachyos-gaming-meta

log "Installing NVIDIA 580xx legacy driver early to prevent driver conflicts..."
NVIDIA_HEADERS_INSTALLED=0
for k in linux-cachyos linux linux-lts linux-zen linux-hardened; do
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

log "Ensuring nvidia-drm.modeset=1 is configured across Limine and Kernel cmdline..."

# 1. Update /etc/default/limine (read by limine-entry-tool / limine-mkinitcpio-hook)
sudo mkdir -p /etc/default
if [[ ! -f /etc/default/limine ]]; then
  sudo tee /etc/default/limine >/dev/null <<EOF
LIMIT_USAGE_PERCENT=85
MAX_SNAPSHOT_ENTRIES=auto
KERNEL_CMDLINE[default]+=" nvidia-drm.modeset=1"
KERNEL_PRIORITY=("linux-cachyos" "linux-zen" "linux-lts" "linux" "linux-hardened")
EOF
else
  if ! grep -q "nvidia-drm.modeset=1" /etc/default/limine; then
    echo 'KERNEL_CMDLINE[default]+=" nvidia-drm.modeset=1"' | sudo tee -a /etc/default/limine >/dev/null
  fi
  # Inject priority if missing to ensure cachyos boots by default
  if ! grep -q "KERNEL_PRIORITY" /etc/default/limine; then
    echo 'KERNEL_PRIORITY=("linux-cachyos" "linux-zen" "linux-lts" "linux" "linux-hardened")' | sudo tee -a /etc/default/limine >/dev/null
  fi
fi

# 2. Update /etc/kernel/cmdline (standard systemd/limine kernel command line file)
if [[ -f /etc/kernel/cmdline ]]; then
  if ! grep -q "nvidia-drm.modeset=1" /etc/kernel/cmdline; then
    sudo sed -i 's/$/ nvidia-drm.modeset=1/' /etc/kernel/cmdline
  fi
elif [[ -f /proc/cmdline ]]; then
  CMDLINE_VAL=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //g')
  if ! echo "$CMDLINE_VAL" | grep -q "nvidia-drm.modeset=1"; then
    CMDLINE_VAL="$CMDLINE_VAL nvidia-drm.modeset=1"
  fi
  echo "$CMDLINE_VAL" | sudo tee /etc/kernel/cmdline >/dev/null
fi

# 3. Update active Limine configuration file directly on the boot partition
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
  log "Adding nvidia-drm.modeset=1 to active Limine config ($LIMINE_CFG)..."
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

# ── 4. Core Desktop, Audio, Shell, Virtualization & Btrfs Stack ─────────
log "Installing official system stack, Docker, Virtualization, and Btrfs/Snapper..."
OFFICIAL_PKGS=(
  # Niri & Wayland Desktop Stack
  niri xdg-desktop-portal xdg-desktop-portal-gnome polkit
  pipewire pipewire-pulse pipewire-alsa wireplumber
  networkmanager network-manager-applet brightnessctl playerctl
  wl-clipboard cliphist grim slurp ttf-nerd-fonts-symbols noto-fonts
  jemalloc dbus accountsservice greetd papirus-icon-theme ddcutil
  
  # Shell & CLI Utilities
  zsh starship zsh-autosuggestions zsh-syntax-highlighting zsh-completions
  zsh-history-substring-search fzf zoxide eza bat atuin
  
  # Docker Stack
  docker docker-compose
  
  # Virt-Manager / KVM Virtualization Stack
  virt-manager qemu-desktop libvirt edk2-ovmf dnsmasq iptables-nft dmidecode bridge-utils

  # Btrfs & Snapper Stack
  btrfs-progs snapper snap-pac inotify-tools
)

install_pkgs "${OFFICIAL_PKGS[@]}"

# ── 5. Foreign & AUR Packages ───────────────────────────────────────────
log "Installing AUR/Chaotic-AUR applications and Limine hooks..."
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
  limine-snapper-sync
  nautilus-admin-gtk4
)

"$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}"

# Trigger limine-update if limine-entry-tool / limine-mkinitcpio-hook was just installed
if command -v limine-update >/dev/null 2>&1; then
  log "Rebuilding Limine entries with limine-update (which will set CachyOS as default)..."
  sudo limine-update || warn "limine-update encountered an issue, check config manually."
fi

# ── 6. Snapper & Limine Snapshot Integration (Btrfs @root) ───────────────
log "Configuring Snapper for root (/) and Limine snapshot sync..."

if [[ ! -f /etc/snapper/configs/root ]]; then
  if [[ -d "/.snapshots" ]]; then
    sudo umount /.snapshots 2>/dev/null || true
    sudo rm -rf /.snapshots 2>/dev/null || true
  fi
  sudo snapper -c root create-config /
fi

# Set permissions for wheel group
sudo chmod 750 /.snapshots 2>/dev/null || true
sudo chown root:wheel /.snapshots 2>/dev/null || true
sudo sed -i 's/^ALLOW_GROUPS=""/ALLOW_GROUPS="wheel"/' /etc/snapper/configs/root
sudo sed -i 's/^SYNC_USER="no"/SYNC_USER="yes"/' /etc/snapper/configs/root

# Enable Snapper automatic timeline and cleanup services
sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer

# Ensure Limine config has the snapshot marker //Snapshots for limine-snapper-sync
if [[ -n "$LIMINE_CFG" && -f "$LIMINE_CFG" ]]; then
  if ! grep -q "//Snapshots" "$LIMINE_CFG" && ! grep -q "/Snapshots" "$LIMINE_CFG"; then
    log "Adding //Snapshots marker to $LIMINE_CFG for Limine snapshot sync..."
    echo -e "\n//Snapshots" | sudo tee -a "$LIMINE_CFG" >/dev/null
  fi
fi

# Enable Limine Snapper Sync watcher service
if systemctl list-unit-files | grep -q "limine-snapper-sync.service"; then
  log "Enabling limine-snapper-sync service..."
  sudo systemctl enable limine-snapper-sync.service
fi

# ── 7. Services & User Groups Setup ─────────────────────────────────────
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

# ── 8. Fetch Dotfiles from Repository ──────────────────────────────────
log "Cloning dotfiles repository..."
TMP_REPO=$(mktemp -d)
git clone --depth 1 https://github.com/opaleiei/opalnirinoctalia.git "$TMP_REPO"

mkdir -p "$HOME/.config"
[[ -d "$TMP_REPO/niri" ]] && cp -r "$TMP_REPO/niri" "$HOME/.config/" && log "Copied niri config."
[[ -d "$TMP_REPO/fastfetch" ]] && cp -r "$TMP_REPO/fastfetch" "$HOME/.config/" && log "Copied fastfetch config."
[[ -d "$TMP_REPO/ghostty" ]] && cp -r "$TMP_REPO/ghostty" "$HOME/.config/" && log "Copied ghostty config."
[[ -d "$TMP_REPO/atuin" ]] && cp -r "$TMP_REPO/atuin" "$HOME/.config/" && log "Copied atuin config."
[[ -f "$TMP_REPO/.zshrc" ]] && cp "$TMP_REPO/.zshrc" "$HOME/.zshrc" && log "Copied .zshrc."

# ── 9. Completion Summary ───────────────────────────────────────────────
log "Installation and optimization complete."
cat <<EOF

Summary of changes:
  • Installed and enabled CachyOS repository.
  • Installed linux-cachyos, cachyos-gaming-meta, and configured Limine to boot linux-cachyos by default.
  • Installed NVIDIA 580xx drivers FIRST to eliminate provider/package conflicts.
  • Configured 'nvidia-drm.modeset=1' across /etc/default/limine, /etc/kernel/cmdline, and active Limine config files.
  • Configured Snapper for root (/) and enabled snap-pac automatic pacman snapshots.
  • Configured limine-snapper-sync and added //Snapshots marker to Limine boot config.
  • Installed Docker & Docker Compose; added user to 'docker' group.
  • Installed Virt-Manager & KVM stack; added user to 'libvirt' and 'kvm' groups.
  • Configured system timezone (Asia/Bangkok) and locales (en_US, th_TH).
  • Applied dotfiles for Niri, Fastfetch, Ghostty, and Zsh.

Next Steps:
  1. Reboot the system to initialize the CachyOS kernel, NVIDIA modules, group memberships, and services.
  2. Verify kernel parameter after reboot: 'cat /proc/cmdline' (should show nvidia-drm.modeset=1 and your new kernel name).
EOF
