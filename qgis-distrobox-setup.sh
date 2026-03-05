#!/bin/bash
# QGIS Distrobox Setup Script
# Usage: ./qgis-distrobox-setup.sh [latest|ltr|nightly] [ubuntu-version]
# Example: ./qgis-distrobox-setup.sh nightly 25.10
# Example: ./qgis-distrobox-setup.sh ltr 24.04

set -e

VARIANT=${1:-latest}
UBUNTU_VERSION=${2:-}

# Map Ubuntu version to suite codename
get_suite() {
    case "$1" in
        24.04) echo "noble" ;;
        25.04) echo "plucky" ;;
        25.10) echo "questing" ;;
        *)
            echo "Unknown Ubuntu version: $1" >&2
            echo "Supported versions: 24.04, 25.04, 25.10" >&2
            exit 1
            ;;
    esac
}

case "$VARIANT" in
    latest)
        CONTAINER_NAME="qgis-latest"
        REPO_URI="https://qgis.org/ubuntu"
        EXPORT_LABEL=""
        BASE_IMAGE="ubuntu:${UBUNTU_VERSION:-24.04}"
        SUITE=$(get_suite "${UBUNTU_VERSION:-24.04}")
        ;;
    ltr)
        CONTAINER_NAME="qgis-ltr"
        REPO_URI="https://qgis.org/ubuntu-ltr"
        EXPORT_LABEL="QGIS LTR"
        BASE_IMAGE="ubuntu:${UBUNTU_VERSION:-24.04}"
        SUITE=$(get_suite "${UBUNTU_VERSION:-24.04}")
        ;;
    nightly)
        CONTAINER_NAME="qgis-nightly"
        REPO_URI="https://qgis.org/ubuntu-nightly"
        EXPORT_LABEL="QGIS Nightly"
        BASE_IMAGE="ubuntu:${UBUNTU_VERSION:-25.10}"
        SUITE=$(get_suite "${UBUNTU_VERSION:-25.10}")
        ;;
    *)
        echo "Unknown variant: $VARIANT"
        echo "Usage: $0 [latest|ltr|nightly] [ubuntu-version]"
        exit 1
        ;;
esac

echo "==> Setting up QGIS ($VARIANT) in container: $CONTAINER_NAME"

# Create container if it doesn't already exist
if distrobox list | grep -q "$CONTAINER_NAME"; then
    echo "==> Container $CONTAINER_NAME already exists, skipping creation"
else
    distrobox create --name "$CONTAINER_NAME" --image "$BASE_IMAGE"
fi

# Run setup inside container
distrobox enter "$CONTAINER_NAME" -- bash -s << CONTAINER_SCRIPT
set -e

echo "==> Updating package lists"
sudo apt update

echo "==> Installing prerequisites"
sudo apt install -y software-properties-common gnupg wget unzip

echo "==> Adding QGIS signing key"
sudo mkdir -m755 -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/qgis-archive-keyring.gpg https://download.qgis.org/downloads/qgis-archive-keyring.gpg

echo "==> Adding QGIS repository"
sudo tee /etc/apt/sources.list.d/qgis.sources > /dev/null <<EOF
Types: deb deb-src
URIs: $REPO_URI
Suites: $SUITE
Architectures: amd64
Components: main
Signed-By: /etc/apt/keyrings/qgis-archive-keyring.gpg
EOF

echo "==> Installing QGIS"
sudo apt update
sudo apt install -y qgis qgis-plugin-grass qgis-common

echo "==> Copying QGIS icon to host"
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
cp /usr/share/icons/hicolor/scalable/apps/qgis.svg ~/.local/share/icons/hicolor/scalable/apps/qgis.svg

echo "==> Exporting QGIS to host launcher"
if find ~/.local/share/applications/ -name "${CONTAINER_NAME}-org.qgis.qgis.desktop" 2>/dev/null | grep -q .; then
    echo "==> Desktop file already exists, skipping export"
else
    if [ -n "$EXPORT_LABEL" ]; then
        distrobox-export --app qgis --export-label "$EXPORT_LABEL"
    else
        distrobox-export --app qgis
    fi
fi

echo "==> Container setup complete"
CONTAINER_SCRIPT

# Fix icon cache on host
echo "==> Updating icon cache"
cp /usr/share/icons/hicolor/index.theme ~/.local/share/icons/hicolor/ 2>/dev/null || true
gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null || true

# Fix desktop file for Wayland and correct icon
DESKTOP_FILE=$(find ~/.local/share/applications/ -name "${CONTAINER_NAME}-org.qgis.qgis.desktop" 2>/dev/null | head -1)

if [ -n "$DESKTOP_FILE" ]; then
    echo "==> Fixing desktop file: $DESKTOP_FILE"
    # Fix Wayland (skip for nightly to test Qt6 native Wayland support)
    if [ "$VARIANT" != "nightly" ]; then
        if grep -q "QT_QPA_PLATFORM=xcb" "$DESKTOP_FILE"; then
            echo "==> Wayland fix already applied, skipping"
        else
            sed -i 's|-- \+qgis|-- env QT_QPA_PLATFORM=xcb qgis|g' "$DESKTOP_FILE"
        fi
    fi
    # Fix icon
    sed -i 's|^Icon=.*|Icon=qgis|' "$DESKTOP_FILE"
    echo "==> Desktop file updated"
else
    echo "==> Warning: Could not find desktop file to patch"
fi

# Create processing output folder if it doesn't exist
mkdir -p ~/processing
mkdir -p ~/grassdata

echo ""
echo "==> Done! QGIS ($VARIANT) is ready."
echo "    You may need to log out and back in for the launcher icon to update."
echo ""
echo "    WhiteboxTools path (if installed):"
echo "    /home/$USER/.local/bin/whiteboxtools/WhiteboxTools_linux_amd64/WBT/whitebox_tools"
