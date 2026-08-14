#!/usr/bin/env bash
# install-niri-noctalia.sh
#
# Installs and configures niri (scrollable-tiling Wayland compositor) with
# Noctalia v5, greetd + Noctalia Greeter, NVIDIA 580xx legacy drivers,
# Zsh terminal stack, Zen Browser with PSD, Docker, KVM/virt-manager,
# Snapper + Limine snapshot sync for Btrfs (@root), and CachyOS repos + kernel.
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
if [[ $EUID -eq 0 ]]; then
  die "Run this as your normal user, not root. It will call sudo when needed."
fi
command -v sudo >/dev/null 2>&1 || die "sudo is not installed. Add user to wheel group and install sudo first."
command -v pacman >/dev/null 2>&1 || die "This script is for Arch Linux (pacman not found)."

# Cleanup trap for temporary resources and background processes
TMP_REPO=""
SUDO_PID=""
cleanup() {
  [[ -n "$SUDO_PID" ]] && kill "$SUDO_PID" 2>/dev/null || true
  [[ -n "$TMP_REPO" && -d "$TMP_REPO" ]] && rm -rf "$TMP_REPO" || true
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

log "Ensuring [multilib] repository is enabled for 32-bit gaming support..."
if ! grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null; then
  if grep -q "^#\[multilib\]" /etc/pacman.conf 2>/dev/null; then
    sudo sed -i '/^#\[multilib\]/{n;s/^#//}' /etc/pacman.conf
    sudo sed -i 's/^#\[multilib\]/\[multilib\]/' /etc/pacman.conf
  else
    sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
  fi
fi

log "Updating system databases and base tools..."
sudo pacman -Syu --needed --noconfirm base-devel git curl wget

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
  (cd "$tmp_cachy/cachyos-repo" && sudo bash cachyos-repo.sh)
  rm -rf "$tmp_cachy"
  sudo pacman -Sy
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

# ── 3. FIRST: Kernels & NVIDIA Legacy 580xx Driver ───────────────────────
log "Installing linux-cachyos kernel and headers..."
sudo pacman -S --needed --noconfirm linux-cachyos linux-cachyos-headers

log "Installing NVIDIA 580xx legacy drivers (64-bit + 32-bit) FIRST..."
NVIDIA_HEADERS_INSTALLED=0
for k in linux-cachyos linux linux-lts linux-zen linux-hardened; do
  if pacman -Qq "$k" &>/dev/null; then
    sudo pacman -S --needed --noconfirm "${k}-headers"
    NVIDIA_HEADERS_INSTALLED=1
  fi
done
if [[ $NVIDIA_HEADERS_INSTALLED -eq 0 ]]; then
  warn "Could not detect active kernel package automatically for headers."
fi

install_pkgs nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings

log "Installing cachyos-gaming-meta..."
install_pkgs cachyos-gaming-meta

log "Configuring Btrfs and DRM kernel modules in mkinitcpio..."
CURRENT_MODS=$(grep -E '^MODULES=\(' /etc/mkinitcpio.conf | sed -E 's/MODULES=\((.*)\)/\1/')
NEW_MODS="$CURRENT_MODS"
for mod in btrfs nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
  if ! echo "$NEW_MODS" | grep -qw "$mod"; then
    NEW_MODS="$NEW_MODS $mod"
  fi
done
NEW_MODS=$(echo "$NEW_MODS" | xargs)
sudo sed -i -E "s/^MODULES=\(.*\)/MODULES=($NEW_MODS)/" /etc/mkinitcpio.conf

log "Rebuilding initramfs for all kernels..."
sudo mkinitcpio -P

# ── 3b. Resolve Limine Config Conflicts & Set Kernel Parameters ──────────
log "Resolving Limine configuration conflicts and fixing root parameters..."

# 1. Capture exact working kernel cmdline (including root UUID & Btrfs subvolume)
CMDLINE_STRING=""
if [[ -f /proc/cmdline ]]; then
  CMDLINE_STRING=$(cat /proc/cmdline | sed -E 's/BOOT_IMAGE=[^ ]* //g')
  if ! echo "$CMDLINE_STRING" | grep -q "nvidia-drm.modeset=1"; then
    CMDLINE_STRING="$CMDLINE_STRING nvidia-drm.modeset=1"
  fi
fi

if [[ -z "$CMDLINE_STRING" || ! "$CMDLINE_STRING" =~ root= ]]; then
  ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV" 2>/dev/null || true)
  ROOT_SUBVOL=$(findmnt -n -o OPTIONS / 2>/dev/null | tr ',' '\n' | grep '^subvol=' | head -n 1 || true)
  
  CMDLINE_STRING="root=UUID=$ROOT_UUID"
  [[ -n "$ROOT_SUBVOL" ]] && CMDLINE_STRING="$CMDLINE_STRING rootflags=$ROOT_SUBVOL"
  CMDLINE_STRING="$CMDLINE_STRING rw nvidia-drm.modeset=1"
fi

log "Writing complete kernel parameters to /etc/kernel/cmdline:"
log "  -> $CMDLINE_STRING"
sudo mkdir -p /etc/kernel
echo "$CMDLINE_STRING" | sudo tee /etc/kernel/cmdline >/dev/null

# 2. Update /etc/default/limine (do NOT override KERNEL_CMDLINE so it reads /etc/kernel/cmdline)
sudo mkdir -p /etc/default
sudo tee /etc/default/limine >/dev/null <<EOF
LIMIT_USAGE_PERCENT=85
MAX_SNAPSHOT_ENTRIES=auto
KERNEL_PRIORITY=("linux-cachyos" "linux-zen" "linux-lts" "linux" "linux-hardened")
EOF

# 3. Clean up conflicting Limine config files across /boot
log "Scanning for conflicting Limine config files in /boot..."
mapfile -t ALL_LIMINE_CFGS < <(sudo find /boot -type f \( -name "limine.conf" -o -name "limine.cfg" -o -name "limine.config" \) 2>/dev/null || true)

if [[ ! -f /boot/limine.conf ]]; then
  if [[ ${#ALL_LIMINE_CFGS[@]} -gt 0 ]]; then
    log "Migrating ${ALL_LIMINE_CFGS[0]} to /boot/limine.conf..."
    sudo cp "${ALL_LIMINE_CFGS[0]}" /boot/limine.conf
  else
    log "Creating new /boot/limine.conf..."
    sudo touch /boot/limine.conf
  fi
fi

for cfg_file in "${ALL_LIMINE_CFGS[@]}"; do
  if [[ "$cfg_file" != "/boot/limine.conf" ]]; then
    log "Removing conflicting duplicate config file: $cfg_file"
    sudo rm -f "$cfg_file"
  fi
done

if ! grep -q "//Snapshots" /boot/limine.conf 2>/dev/null && ! grep -q "/Snapshots" /boot/limine.conf 2>/dev/null; then
  log "Adding //Snapshots marker to /boot/limine.conf..."
  echo -e "\n//Snapshots" | sudo tee -a /boot/limine.conf >/dev/null
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

# Re-deploy Limine bootloader EFI binary to ensure boot NVRAM targets /boot/limine.conf
if command -v limine-install >/dev/null 2>&1; then
  log "Deploying Limine EFI bootloader..."
  sudo limine-install || warn "limine-install completed with warnings."
  sudo limine-install --fallback 2>/dev/null || true
fi

if command -v limine-update >/dev/null 2>&1; then
  log "Updating Limine entries for /boot/limine.conf..."
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

sudo chmod 750 /.snapshots 2>/dev/null || true
sudo chown root:wheel /.snapshots 2>/dev/null || true
sudo sed -i 's/^ALLOW_GROUPS=""/ALLOW_GROUPS="wheel"/' /etc/snapper/configs/root
sudo sed -i 's/^SYNC_USER="no"/SYNC_USER="yes"/' /etc/snapper/configs/root

sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer

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

if command -v virsh >/dev/null 2>&1; then
  sudo virsh net-autostart default 2>/dev/null || true
fi

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
systemctl --user enable psd.service 2>/dev/null || warn "User systemd bus not running; enable psd.service manually after rebooting."

# ── 8. Fetch Dotfiles from Repository ──────────────────────────────────
log "Cloning dotfiles repository..."
TMP_REPO=$(mktemp -d)
git clone --depth 1 https://github.com/opaleiei/opalnirinoctalia.git "$TMP_REPO"

mkdir -p "$HOME/.config"
if [[ -d "$TMP_REPO/niri" ]]; then
  cp -r "$TMP_REPO/niri" "$HOME/.config/"
  log "Copied niri config."
fi

if [[ -d "$TMP_REPO/fastfetch" ]]; then
  cp -r "$TMP_REPO/fastfetch" "$HOME/.config/"
  log "Copied fastfetch config."
fi

if [[ -d "$TMP_REPO/ghostty" ]]; then
  cp -r "$TMP_REPO/ghostty" "$HOME/.config/"
  log "Copied ghostty config."
fi

if [[ -d "$TMP_REPO/atuin" ]]; then
  cp -r "$TMP_REPO/atuin" "$HOME/.config/"
  log "Copied atuin config."
fi

if [[ -f "$TMP_REPO/.zshrc" ]]; then
  cp "$TMP_REPO/.zshrc" "$HOME/.zshrc"
  log "Copied .zshrc."
fi

# ── 9. Completion Summary ───────────────────────────────────────────────
log "Installation complete."
cat <<EOF

Summary of fixes & changes applied:
  • Extracted exact root UUID & Btrfs flags into /etc/kernel/cmdline.
  • Eliminated duplicate Limine configs across /boot, standardizing on /boot/limine.conf.
  • Added 'btrfs' to mkinitcpio MODULES and rebuilt initramfs images.
  • Re-deployed Limine EFI bootloader via 'limine-install'.
  • Installed CachyOS repository, linux-cachyos kernel, and 64-bit/32-bit NVIDIA drivers.
  • Applied dotfiles for Niri, Fastfetch, Ghostty, Atuin, and Zsh.

Next Steps:
  1. Reboot your system.
  2. Select 'linux-cachyos' in Limine—it will now mount your Btrfs root cleanly without dropping into emergency shell.
EOF
