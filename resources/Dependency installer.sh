#!/bin/bash

# SPDX-License-Identifier: Apache-2.0 
# Copyright 2026 Jose Manuel


cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "/tmp/ksk_temp_files"
}

# Execute cleanup if the script exits or is interrupted (SIGINT/SIGTERM)
trap cleanup EXIT


bar() {
total=100
for ((i=0; i<=total; i++)); do
  percent=$((i * 100 / total))
  printf "\rProgress: [%-50s] %d%%" "$(printf '#%.0s' $(seq 1 $((i / 2))))" "$percent"
  sleep 0.05
done
echo ""
}


echo "Loading Stuff"
bar

echo "Fetching OS"
sleep 2.5


# Dependency list
DEB_PKGS="openbox zenity yad x11-xserver-utils"
ARCH_PKGS="openbox zenity yad xorg-xsetroot"
FEDORA_PKGS="openbox zenity yad xorg-x11-server-utils"

if command -v apt-get >/dev/null 2>&1; then
    echo "Detected Debian/Ubuntu-based system."
    sudo apt-get update
    sudo apt-get install -y $DEB_PKGS
    var=1
elif command -v pacman >/dev/null 2>&1; then
    echo "Detected Arch-based system."
    sudo pacman -S --needed $ARCH_PKGS
    var=1
elif command -v dnf >/dev/null 2>&1; then
    echo "Detected Fedora/RHEL-based system."
    sudo dnf install -y $FEDORA_PKGS
    var=1
elif command -v zypper >/dev/null 2>&1; then
    echo "Detected OpenSUSE-based system."
    sudo zypper install -y openbox zenity yad xorg-x11-server-utils
    var=1
else
    echo "Error: Unsupported package manager. Please install dependencies manually."
    exit 1
fi  # <--- Added missing 'fi'

echo "Finishing the install process. Please wait"
sleep 1.9999

echo "Moving Files..."
bar

# Define targets
BIN_TARGET="/usr/local/bin/kerbal-space-kiosk"
CONF_TARGET="/usr/share/xsessions"

# Create directories
sudo mkdir -p "$BIN_TARGET" "$CONF_TARGET"

# Move files (Make sure these filenames match your source folder exactly)
sudo cp ksp-runner.sh "$BIN_TARGET/"
sudo cp kerbal-space-kiosk.desktop "$CONF_TARGET/"

# Set permissions (Updated to match your actual file name)
sudo chmod +x "$BIN_TARGET/ksp-runner.sh"

echo "Installation finished successfully."
