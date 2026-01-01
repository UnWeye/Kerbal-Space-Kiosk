#!/bin/sh

# Dependency list for Debian/Ubuntu (APT)
DEB_PKGS="openbox zenity yad x11-xserver-utils"
# Equivalent names for Arch Linux (Pacman)
ARCH_PKGS="openbox zenity yad xorg-xsetroot"
# Equivalent names for Fedora/RHEL (DNF)
FEDORA_PKGS="openbox zenity yad xorg-x11-server-utils"

if command -v apt-get >/dev/null 2>&1; then
    echo "Detected Debian/Ubuntu-based system."
    sudo apt-get update
    sudo apt-get install -y $DEB_PKGS
elif command -v pacman >/dev/null 2>&1; then
    echo "Detected Arch-based system."
    sudo pacman -S --needed $ARCH_PKGS
elif command -v dnf >/dev/null 2>&1; then
    echo "Detected Fedora/RHEL-based system."
    sudo dnf install -y $FEDORA_PKGS
elif command -v zypper >/dev/null 2>&1; then
    echo "Detected OpenSUSE-based system."
    sudo zypper install -y openbox zenity yad xorg-x11-server-utils
else
    echo "Error: Unsupported package manager. Please install dependencies manually: $DEB_PKGS"
    exit 1
fi
