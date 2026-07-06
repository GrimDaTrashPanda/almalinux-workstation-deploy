#!/usr/bin/env bash
#
# AlmaLinux 10 Workstation Baseline Deployment Script
#
# Run this AFTER first boot into a fresh AlmaLinux 10 Workstation install
# (GNOME desktop). Takes a clean install to a fully provisioned baseline:
# EPEL, native toolkit, Flathub, a full browser stack, and a single
# unified update utility with a GNOME launcher.
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Safe to re-run. Uses dnf's native idempotency, plus explicit checks
# before adding any repo that's already configured.

set -euo pipefail

# ── Colour output helpers ────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

info()  { echo -e "${BOLD}${GREEN}==>${RESET} $1"; }
warn()  { echo -e "${BOLD}${YELLOW}==>${RESET} $1"; }
error() { echo -e "${BOLD}${RED}==>${RESET} $1" >&2; }

# ── Sanity checks ─────────────────────────────────────────────────────────
if [ "$(id -u)" -eq 0 ]; then
  error "Don't run this as root. Run as your normal user — it calls sudo where needed."
  exit 1
fi

if ! command -v dnf &> /dev/null; then
  error "dnf not found. This script is intended for enterprise RHEL-based systems (AlmaLinux)."
  exit 1
fi

echo ""
echo -e "${BOLD}AlmaLinux 10 Workstation Baseline Deployment${RESET}"
echo "──────────────────────────────────────────────────────"
echo ""

# ── Phase 1: CPU microcode ────────────────────────────────────────────────
info "Detecting CPU vendor..."

CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')

case "$CPU_VENDOR" in
  GenuineIntel)
    info "Detected: Intel CPU → installing microcode_ctl"
    sudo dnf install -y microcode_ctl
    ;;
  AuthenticAMD)
    info "Detected: AMD CPU → microcode is bundled into linux-firmware, already present by default"
    ;;
  *)
    warn "Could not determine CPU vendor (got: '${CPU_VENDOR:-unknown}'). Skipping microcode step."
    ;;
esac

echo ""

# ── Phase 2: Enable EPEL Repository ───────────────────────────────────────
info "Configuring Extra Packages for Enterprise Linux (EPEL 10)..."
sudo dnf install -y epel-release
sudo dnf config-manager --set-enabled crb || true

echo ""

# ── Phase 2.5: Enable RPM Fusion (Free) ───────────────────────────────────
# VLC isn't in EPEL — RHEL-based distros exclude it there over codec
# licensing. RPM Fusion (Free) is the standard source for it, and it
# depends on EPEL already being enabled above.
info "Configuring RPM Fusion (Free) repository (required for VLC)..."
sudo dnf install -y --nogpgcheck \
  "https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" || true

echo ""

# ── Phase 3: Native App Layer (DNF Repositories) ──────────────────────────
info "Installing core system utilities and development tools..."

# Install development groups and standard packages available in AppStream/EPEL/RPM Fusion
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y \
  git \
  firefox \
  glances \
  fastfetch \
  duf \
  tldr \
  flatpak \
  vlc \
  p7zip \
  p7zip-plugins

echo ""

# ── Phase 4: Firefox Wayland rendering ────────────────────────────────────
info "Enabling native Firefox Wayland rendering..."

if ! grep -q "MOZ_ENABLE_WAYLAND" /etc/environment 2>/dev/null; then
  echo "MOZ_ENABLE_WAYLAND=1" | sudo tee -a /etc/environment > /dev/null
  info "Added MOZ_ENABLE_WAYLAND=1 to /etc/environment (applies at next login)."
else
  info "MOZ_ENABLE_WAYLAND already set in /etc/environment — skipping."
fi

echo ""

# ── Phase 5: Flathub Remote ───────────────────────────────────────────────
info "Setting up Flathub remote..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Optional: Add LibreWolf via Flatpak right away
# flatpak install -y flathub io.gitlab.librewolf-community

echo ""

# ── Phase 6: Third-Party Native Browsers (RPM Repos) ──────────────────────
info "Configuring official browser repositories..."

# Google Chrome Repository
if [ ! -f /etc/yum.repos.d/google-chrome.repo ]; then
  info "Adding Google Chrome repository..."
  sudo dnf config-manager --add-repo https://dl.google.com/linux/chrome/rpm/stable/x86_64
fi

# Brave Browser Repository
if [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
  info "Adding Brave Browser repository..."
  sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
fi

# Microsoft Edge Repository
if [ ! -f /etc/yum.repos.d/microsoft-edge.repo ]; then
  info "Adding Microsoft Edge repository..."
  sudo dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/edge
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
fi

info "Installing Chrome, Brave, and Edge via DNF..."
sudo dnf install -y google-chrome-stable brave-browser microsoft-edge-stable

echo ""

# ── Phase 7: Workstation Maintenance Unified Script ───────────────────────
info "Setting up clean workstation update utility..."

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

# AlmaLinux has no equivalent of a separate "foreign package" tier the way
# some rolling-release distros do — everything here is either an official
# dnf-tracked package or a Flatpak, so one unified updater covers both.
cat << 'SCRIPT_EOF' > "$HOME/.local/bin/update-workstation.sh"
#!/usr/bin/env bash
clear
echo "========================================="
echo "   UPDATING ALMALINUX WORKSTATION"
echo "========================================="
echo ""
echo "==> Updating System Packages (DNF)..."
sudo dnf upgrade -y
echo ""
echo "==> Updating Flatpak Applications..."
if command -v flatpak &> /dev/null; then
    flatpak update -y
fi
echo ""
echo "System maintenance execution complete."
echo "Press Enter to close..."
read -r
SCRIPT_EOF

chmod +x "$HOME/.local/bin/update-workstation.sh"

# Identify launcher execution target
if command -v gnome-terminal &> /dev/null; then
    TERM_EXEC="gnome-terminal --"
elif command -v kgx &> /dev/null; then
    TERM_EXEC="kgx -e"
else
    TERM_EXEC="bash -c"
fi

# Create single static menu launcher
cat << EOF > "$HOME/.local/share/applications/update-workstation.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Update Workstation
Comment=Updates native DNF packages and Flatpaks seamlessly
Exec=$TERM_EXEC "$HOME/.local/bin/update-workstation.sh"
Terminal=false
Icon=system-software-update
Categories=System;Settings;
Keywords=update;upgrade;dnf;flatpak;workstation;
EOF

update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true

echo ""
info "Deployment complete."
warn "Log out and back in to apply the Wayland env var for Firefox."
warn "Chromium browsers (Chrome/Brave/Edge) still need their Wayland flag set manually per browser:"
warn "      chrome://flags/#ozone-platform-hint -> Set to 'Wayland' -> Relaunch."
echo ""
