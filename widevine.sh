#!/bin/bash
# SPDX-License-Identifier: MIT
# Widevine installer for Firefox Flatpak on aarch64 systems

set -e

FLATPAK_APP_ID="org.mozilla.firefox"
FLATPAK_DATA_DIR="$HOME/.var/app/$FLATPAK_APP_ID"
INSTALL_BASE="$FLATPAK_DATA_DIR/widevine"
DISTFILES_BASE="https://commondatastorage.googleapis.com/chromeos-localmirror/distfiles"
LACROS_NAME="chromeos-lacros-arm64-squash-zstd"
LACROS_VERSION="128.0.6613.137"
WIDEVINE_VERSION="4.10.2710.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Check if running on aarch64
if [ "$(uname -m)" != "aarch64" ]; then
    print_error "This script is only supported on aarch64 (ARM64) systems."
    exit 1
fi

# Check if Firefox Flatpak is installed
if ! flatpak list | grep -q "$FLATPAK_APP_ID"; then
    print_error "Firefox Flatpak is not installed."
    echo "Please install it with: flatpak install flathub $FLATPAK_APP_ID"
    exit 1
fi

# Check glibc version
verchk() {
    (
        echo "2.36"
        ldd --version | head -1 | cut -d" " -f4
    ) | sort -CV
}

if ! verchk; then
    print_error "Your glibc version is too old. Widevine requires glibc 2.36 or newer."
    exit 1
fi

# Check for required tools
for tool in curl unsquashfs python3; do
    if ! command -v $tool &> /dev/null; then
        print_error "Required tool '$tool' is not installed."
        exit 1
    fi
done

# Check for widevine_fixup.py
if [ ! -f "$SCRIPT_DIR/widevine_fixup.py" ]; then
    print_error "widevine_fixup.py not found in $SCRIPT_DIR"
    exit 1
fi

cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                Widevine Installer for Firefox Flatpak (ARM64)                ║
╚══════════════════════════════════════════════════════════════════════════════╝

This script will download, adapt, and install a copy of the Widevine
Content Decryption Module for Firefox Flatpak on aarch64 systems.

IMPORTANT INFORMATION:

• Widevine is proprietary DRM technology developed by Google
• This uses ARM64 builds intended for ChromeOS
• Not supported or endorsed by Google
• The Asahi Linux/ARM community cannot provide support
• You assume all responsibility for using this script

SECURITY CONSIDERATIONS:

• The script only adapts the binary file format for compatibility
• The CDM software itself is not modified
• On systems with >4k page size (e.g., Apple Silicon), security is weakened

EOF

echo "Widevine version: $WIDEVINE_VERSION"
echo "LaCrOS version: $LACROS_VERSION"
echo "Install location: $INSTALL_BASE"
echo ""
read -p "Press Enter to proceed, or Ctrl-C to cancel: "

# Create temporary working directory
workdir="$(mktemp -d /tmp/widevine-flatpak-installer.XXXXXXXX)"
if [ -z "$workdir" ] || [ ! -d "$workdir" ]; then
    print_error "Failed to create temporary directory"
    exit 1
fi

# Cleanup function
cleanup() {
    if [ -d "$workdir" ]; then
        print_info "Cleaning up temporary files..."
        rm -rf "$workdir"
    fi
}
trap cleanup EXIT

cd "$workdir"

# Download LaCrOS image
print_info "Downloading LaCrOS (Chrome) image..."
URL="$DISTFILES_BASE/$LACROS_NAME-$LACROS_VERSION"
if ! curl -# -o lacros.squashfs "$URL"; then
    print_error "Failed to download LaCrOS image"
    exit 1
fi

# Extract Widevine
print_info "Extracting Widevine..."
if ! unsquashfs -q lacros.squashfs 'WidevineCdm/*'; then
    print_error "Failed to extract Widevine from LaCrOS image"
    exit 1
fi

# Display license
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "                         Widevine License Agreement"
echo "═══════════════════════════════════════════════════════════════════════════"
cat squashfs-root/WidevineCdm/LICENSE
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
read -p "Press Enter to accept the license and proceed, or Ctrl-C to cancel: "

# Patch Widevine binary
print_info "Patching Widevine binary for compatibility..."
if ! python3 "$SCRIPT_DIR/widevine_fixup.py" \
    squashfs-root/WidevineCdm/_platform_specific/cros_arm64/libwidevinecdm.so \
    libwidevinecdm.so; then
    print_error "Failed to patch Widevine binary"
    exit 1
fi

# Create installation directory
print_info "Installing Widevine to $INSTALL_BASE..."
mkdir -p "$INSTALL_BASE"

# Install files
install -m 0755 libwidevinecdm.so "$INSTALL_BASE/"
install -m 0644 squashfs-root/WidevineCdm/manifest.json "$INSTALL_BASE/"
install -m 0644 squashfs-root/WidevineCdm/LICENSE "$INSTALL_BASE/"

# Create GMP directory structure for Firefox
print_info "Setting up Firefox plugin structure..."
mkdir -p "$INSTALL_BASE/gmp-widevinecdm/system-installed"
ln -sf ../../manifest.json "$INSTALL_BASE/gmp-widevinecdm/system-installed/"
ln -sf ../../libwidevinecdm.so "$INSTALL_BASE/gmp-widevinecdm/system-installed/"

# Configure Flatpak environment
print_info "Configuring Firefox Flatpak environment..."
flatpak override --user "$FLATPAK_APP_ID" \
    --env=MOZ_GMP_PATH="$INSTALL_BASE/gmp-widevinecdm/system-installed" \
    --filesystem="$INSTALL_BASE:ro"

# Create preferences file
print_info "Creating Firefox preferences..."
PREFS_DIR="$FLATPAK_DATA_DIR/prefs"
mkdir -p "$PREFS_DIR"

cat > "$PREFS_DIR/widevine.js" << EOF
// Widevine preferences for Firefox Flatpak
pref("media.gmp-widevinecdm.version", "$WIDEVINE_VERSION");
pref("media.gmp-widevinecdm.visible", true);
pref("media.gmp-widevinecdm.enabled", true);
pref("media.gmp-widevinecdm.autoupdate", false);
pref("media.eme.enabled", true);
pref("media.eme.encrypted-media-encryption-scheme.enabled", true);
EOF

# Create info file
cat > "$INSTALL_BASE/README" << EOF
Widevine CDM for Firefox Flatpak
=================================

Version: $WIDEVINE_VERSION
Installed: $(date)

This directory contains the Widevine Content Decryption Module
for use with Firefox Flatpak on ARM64 systems.

Files:
  - libwidevinecdm.so: The Widevine CDM library (patched)
  - manifest.json: Plugin manifest
  - LICENSE: Widevine license agreement
  - gmp-widevinecdm/: Firefox plugin structure

To uninstall:
  1. Remove this directory: rm -rf "$INSTALL_BASE"
  2. Reset Flatpak overrides: flatpak override --user --reset $FLATPAK_APP_ID
  3. Remove preferences: rm "$PREFS_DIR/widevine.js"
EOF

cat << EOF

${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗
║                         Installation Complete!                               ║
╚══════════════════════════════════════════════════════════════════════════════╝${NC}

Widevine has been installed for Firefox Flatpak.

Next steps:
  1. Restart Firefox if it's currently running
  2. Visit about:plugins in Firefox to verify Widevine is loaded
  3. Test with a DRM-protected video (e.g., Netflix, Spotify Web Player)

Installation details:
  • Widevine library: $INSTALL_BASE/libwidevinecdm.so
  • Version: $WIDEVINE_VERSION
  • Flatpak overrides applied: MOZ_GMP_PATH environment variable

To uninstall:
  Run: rm -rf "$INSTALL_BASE" && flatpak override --user --reset $FLATPAK_APP_ID

Troubleshooting:
  • If Widevine doesn't load, check: about:support in Firefox
  • Look for "Widevine" under "Media" section
  • Ensure EME is enabled in Firefox settings

EOF

# Verify installation
if [ -f "$INSTALL_BASE/libwidevinecdm.so" ] && [ -f "$INSTALL_BASE/manifest.json" ]; then
    print_info "Verification: Installation files present ✓"
else
    print_warn "Verification: Some files may be missing"
fi

# Check Flatpak override
if flatpak override --user --show "$FLATPAK_APP_ID" | grep -q "MOZ_GMP_PATH"; then
    print_info "Verification: Flatpak environment configured ✓"
else
    print_warn "Verification: Flatpak override may not be set correctly"
fi

exit 0
