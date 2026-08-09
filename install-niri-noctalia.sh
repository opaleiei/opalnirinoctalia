#!/usr/bin/env bash
# install-niri-noctalia.sh
#
# Installs and configures niri (scrollable-tiling Wayland compositor) with
# Noctalia v5 (standalone desktop shell — bar, launcher, notifications,
# control center, lock screen) on a minimal Arch Linux install, plus
# greetd + Noctalia Greeter as a matching login screen.
#
# Noctalia v5 is a native C++ binary, NOT the old Quickshell-based v4 line —
# no quickshell/noctalia-qs dependency, no conflicts with either.
#
# Also installs the NVIDIA 580xx legacy driver branch (nvidia-580xx-dkms),
# needed for Maxwell-era cards like the GTX 960 since Arch's official
# nvidia/nvidia-open packages dropped Maxwell/Pascal support at driver 590.
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

[[ $EUID -eq 0 ]] && die "Run this as your normal user, not root. It will call sudo when needed."
command -v sudo >/dev/null 2>&1 || die "sudo is not installed. Install it first: su -c 'pacman -S sudo' then add your user to the wheel group."
command -v pacman >/dev/null 2>&1 || die "This script is for Arch Linux (pacman not found)."

# ── 0. Base tooling ──────────────────────────────────────────────────────
log "Syncing package databases and updating system..."
sudo pacman -Syu --needed --noconfirm

log "Installing base-devel and git..."
sudo pacman -S --needed --noconfirm base-devel git

# ── 1. Chaotic-AUR (prebuilt binary repo — makes paru and noctalia
#      install instantly instead of compiling from source) ───────────────
if ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf 2>/dev/null; then
  log "Enabling Chaotic-AUR (prebuilt binaries)..."
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
  sudo pacman -U --needed --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

  sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF

  log "Syncing with Chaotic-AUR..."
  sudo pacman -Sy
else
  log "Chaotic-AUR already enabled, skipping."
fi

# ── 2. AUR helper (paru) — pulled as a prebuilt binary from Chaotic-AUR ──
if ! command -v paru >/dev/null 2>&1; then
  if command -v yay >/dev/null 2>&1; then
    log "yay already installed, using it as the AUR helper."
    AUR_HELPER=yay
  else
    log "Installing paru..."
    if ! sudo pacman -S --needed --noconfirm paru; then
      warn "paru not available as a binary, building it from the AUR instead..."
      tmpdir=$(mktemp -d)
      git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmpdir/paru-bin"
      (cd "$tmpdir/paru-bin" && makepkg -si --noconfirm)
      rm -rf "$tmpdir"
    fi
    AUR_HELPER=paru
  fi
else
  AUR_HELPER=paru
fi
log "Using AUR helper: $AUR_HELPER"

# ── 3. Core Wayland / niri stack (official repos) ────────────────────────
log "Installing niri and the Wayland session stack..."
sudo pacman -S --needed --noconfirm \
  niri \
  xwayland-satellite \
  xdg-desktop-portal \
  xdg-desktop-portal-gnome \
  polkit \
  pipewire \
  pipewire-pulse \
  pipewire-alsa \
  wireplumber \
  networkmanager \
  network-manager-applet \
  brightnessctl \
  playerctl \
  wl-clipboard \
  cliphist \
  grim \
  slurp \
  kitty \
  ttf-nerd-fonts-symbols \
  noto-fonts \
  jemalloc \
  dbus \
  accountsservice \
  greetd

# Icon theme (Noctalia looks much better with one installed)
sudo pacman -S --needed --noconfirm papirus-icon-theme || warn "papirus-icon-theme not found, skipping."

if [[ ! -f /usr/share/wayland-sessions/niri.desktop ]]; then
  warn "niri.desktop session file not found under /usr/share/wayland-sessions — the niri package should provide this; check your install."
fi

# accountsservice powers per-user avatars on the login screen.
sudo systemctl enable accounts-daemon.service

# ── 4. NVIDIA legacy 580xx driver (GTX 960 / Maxwell) ────────────────────
# Arch's official nvidia/nvidia-open packages dropped Maxwell + Pascal
# support starting with the 590 driver branch. A GTX 960 (Maxwell) needs
# the community-maintained legacy 580xx branch from the AUR instead.
log "Installing NVIDIA 580xx legacy driver for GTX 960..."

# DKMS rebuilds the kernel module for whichever kernel(s) you have headers
# for — detect the installed kernel package(s) and grab matching headers.
NVIDIA_HEADERS_INSTALLED=0
for k in linux linux-lts linux-zen linux-hardened; do
  if pacman -Qq "$k" &>/dev/null; then
    sudo pacman -S --needed --noconfirm "${k}-headers"
    NVIDIA_HEADERS_INSTALLED=1
  fi
done
[[ $NVIDIA_HEADERS_INSTALLED -eq 0 ]] && warn "Could not detect your kernel package automatically — install the matching *-headers package yourself so DKMS can build."

install_nvidia_pkg() {
  local pkg="$1"
  if sudo pacman -S --needed --noconfirm "$pkg" 2>/dev/null; then
    log "Installed $pkg as a prebuilt package from Chaotic-AUR."
  else
    log "Not available as a prebuilt package, building $pkg via $AUR_HELPER..."
    "$AUR_HELPER" -S --needed --noconfirm "$pkg"
  fi
}
install_nvidia_pkg nvidia-580xx-dkms
install_nvidia_pkg nvidia-580xx-utils
install_nvidia_pkg nvidia-580xx-settings

# DRM kernel mode setting is required for a clean Wayland session.
sudo sed -i -E \
  's/^MODULES=\(([^)]*)\)/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
  /etc/mkinitcpio.conf
sudo mkinitcpio -P

# Add the nvidia-drm.modeset=1 kernel parameter, whichever bootloader is in use.
if [[ -d /boot/loader/entries ]]; then
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
  warn "Could not detect systemd-boot or GRUB automatically — add 'nvidia-drm.modeset=1' to your kernel command line manually."
fi

# ── 5. Enable NetworkManager (minimal installs often lack a network daemon) ─
sudo systemctl enable NetworkManager.service

# ── 6. Noctalia v5 (AUR) ──────────────────────────────────────────────────
# Standalone binary, no Quickshell involved. Dependencies (sdbus-cpp,
# libpipewire, libqalculate, libjxl, libwebp, libsndfile, librsvg, etc.)
# are pulled automatically. Fast if Chaotic-AUR has a prebuilt package,
# otherwise the AUR helper builds it (a C++/meson build, a few minutes).
log "Installing Noctalia v5..."

if sudo pacman -S --needed --noconfirm noctalia 2>/dev/null; then
  log "Installed noctalia as a prebuilt package from Chaotic-AUR."
else
  log "Not available as a prebuilt package, building via $AUR_HELPER..."
  "$AUR_HELPER" -S --needed --noconfirm noctalia
fi

# ── 7. Noctalia Greeter (AUR) — login screen matching Noctalia's look ────
log "Installing Noctalia Greeter..."

if sudo pacman -S --needed --noconfirm noctalia-greeter 2>/dev/null; then
  log "Installed noctalia-greeter as a prebuilt package from Chaotic-AUR."
else
  log "Not available as a prebuilt package, building via $AUR_HELPER..."
  "$AUR_HELPER" -S --needed --noconfirm noctalia-greeter
fi

# Packaged installs ship a tmpfiles.d drop-in that creates /var/lib/noctalia-greeter
# (owned by the "greeter" user) — apply it now instead of waiting for a reboot.
if [[ -f /usr/lib/tmpfiles.d/noctalia-greeter.conf ]]; then
  sudo systemd-tmpfiles --create /usr/lib/tmpfiles.d/noctalia-greeter.conf
else
  warn "No noctalia-greeter tmpfiles.d drop-in found; creating /var/lib/noctalia-greeter manually."
  sudo mkdir -p /var/lib/noctalia-greeter
  sudo chown greeter:greeter /var/lib/noctalia-greeter 2>/dev/null || true
fi

GREETER_SESSION_BIN="$(command -v noctalia-greeter-session || true)"
[[ -z "$GREETER_SESSION_BIN" ]] && die "noctalia-greeter-session not found after install — check the noctalia-greeter package."

log "Configuring greetd to use Noctalia Greeter ($GREETER_SESSION_BIN)..."
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "$GREETER_SESSION_BIN"
user = "greeter"
EOF

sudo systemctl enable greetd.service

# ── 8. niri config: wire in Noctalia + recommended settings ─────────────
NIRI_CFG_DIR="$HOME/.config/niri"
NIRI_CFG="$NIRI_CFG_DIR/config.kdl"
mkdir -p "$NIRI_CFG_DIR"

if [[ ! -f "$NIRI_CFG" ]]; then
  log "No existing niri config found, seeding one from the default template..."
  DEFAULT_CFG="/usr/share/doc/niri/default-config.kdl"
  if [[ -f "$DEFAULT_CFG" ]]; then
    cp "$DEFAULT_CFG" "$NIRI_CFG"
  else
    touch "$NIRI_CFG"
  fi
fi

if ! grep -q 'spawn-at-startup "noctalia"' "$NIRI_CFG" 2>/dev/null; then
  log "Wiring Noctalia and recommended settings into $NIRI_CFG..."
  cat >> "$NIRI_CFG" <<'EOF'

// ── Added by install-niri-noctalia.sh (Noctalia v5) ─────────────────────
spawn-at-startup "noctalia"
spawn-at-startup "xwayland-satellite"
spawn-at-startup "nm-applet" "--indicator"

// NVIDIA (GTX 960 / 580xx legacy driver) — required for a stable Wayland
// session. WLR_NO_HARDWARE_CURSORS works around cursor corruption that's
// common on Maxwell-era cards; remove it if your cursor looks fine without it.
environment {
    LIBVA_DRIVER_NAME "nvidia"
    GBM_BACKEND "nvidia-drm"
    __GLX_VENDOR_LIBRARY_NAME "nvidia"
    NVD_BACKEND "direct"
    WLR_NO_HARDWARE_CURSORS "1"
}

// Rounded corners + floating Noctalia settings window
window-rule {
    geometry-corner-radius 20
    clip-to-geometry true
}
window-rule {
    match app-id="dev.noctalia.Noctalia.Settings"
    open-floating true
    default-column-width { fixed 1080; }
    default-window-height { fixed 920; }
}

// Lets Noctalia's notification actions and window activation work correctly
debug {
    honor-xdg-activation-with-invalid-serial
}

// Blurred overview wallpaper (Noctalia's backdrop layer in niri's overview)
layer-rule {
    match namespace="^noctalia-backdrop"
    place-within-backdrop true
}

// Noctalia keybinds
binds {
    Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+S { spawn-sh "noctalia msg panel-toggle control-center"; }
    Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }
    XF86AudioRaiseVolume { spawn-sh "noctalia msg volume-up"; }
    XF86AudioLowerVolume { spawn-sh "noctalia msg volume-down"; }
    XF86AudioMute { spawn-sh "noctalia msg volume-mute"; }
    XF86MonBrightnessUp { spawn-sh "noctalia msg brightness-up"; }
    XF86MonBrightnessDown { spawn-sh "noctalia msg brightness-down"; }
}
EOF
fi

# ── 9. Done ────────────────────────────────────────────────────────────
log "Install complete."
cat <<EOF

Next steps:
  1. Reboot — required for the NVIDIA kernel modules and the
     nvidia-drm.modeset=1 parameter to take effect.
  2. Noctalia Greeter appears at login. Press F3 to pick the "niri" session
     if it isn't already selected, then log in.
  3. Noctalia starts automatically after login. Open its settings with
     Mod+Comma to pick a theme, wallpaper, and bar modules.
  4. Keybinds added: Mod+Space (launcher), Mod+S (control center),
     Mod+Comma (settings).
  5. To make the login screen match your desktop (wallpaper, palette,
     font), go to Settings → Security → Noctalia Greeter → Sync Now
     inside Noctalia (needs a polkit agent / pkexec).
  6. Your niri config lives at: $NIRI_CFG

Verify NVIDIA after reboot with:
  nvidia-smi
  cat /sys/module/nvidia_drm/parameters/modeset   # should print Y

If something fails to start, check logs with:
  journalctl --user -b | grep -i noctalia
  journalctl -u greetd -b | grep -i noctalia-greeter
  journalctl -b | grep -i niri
EOF
