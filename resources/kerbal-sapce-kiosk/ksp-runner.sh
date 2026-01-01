#!/bin/bash

exec > /tmp/kerbal-kiosk.log 2>&1
set -x  # Enable debug output

# Safety: allow exiting via TTY
trap "exit 0" SIGTERM SIGINT

# Disable screen blanking
xset -dpms
xset s off
xset s noblank

# Start a minimal WM
openbox &
WM_PID=$!

# Set a black background
xsetroot -solid black &

# Wait for WM to initialize
sleep 1

# Define paths
GOG_PATH="$HOME/GOG Games/Kerbal Space Program/game/KSP.x86_64"

# Build menu dynamically based on what's installed
MENU_ITEMS=()

if [ -f "$GOG_PATH" ]; then
  MENU_ITEMS+=(TRUE "GOG Standalone" "Launch GOG version of KSP")
else
  MENU_ITEMS+=(FALSE "GOG Standalone" "Not installed")
fi

if command -v steam &> /dev/null; then
  if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
    MENU_ITEMS+=(TRUE "Steam" "Launch Steam version of KSP")
  else
    MENU_ITEMS+=(FALSE "Steam" "Launch Steam version of KSP")
  fi
else
  MENU_ITEMS+=(FALSE "Steam" "Not installed")
fi

MENU_ITEMS+=(FALSE "Exit" "Return to login screen")

# Check if any version is available
if [ ! -f "$GOG_PATH" ] && ! command -v steam &> /dev/null; then
  zenity --error \
    --title="Kerbal Space Kiosk" \
    --text="No KSP installation found!\n\nPlease install KSP via GOG or Steam." \
    --width=300
  kill $WM_PID 2>/dev/null
  exit 1
fi

# Show game version chooser
CHOICE=$(zenity --list \
  --title="Kerbal Space Kiosk" \
  --text="Select KSP version to launch:" \
  --radiolist \
  --column="" \
  --column="Version" \
  --column="Description" \
  "${MENU_ITEMS[@]}" \
  --height=300 \
  --width=500 \
  --hide-column=1)

# Launch based on choice
case "$CHOICE" in
  "GOG Standalone")
    if [ -f "$GOG_PATH" ]; then
      "$GOG_PATH" &
      KSP_PID=$!
    else
      zenity --error --text="GOG version not found at:\n$GOG_PATH"
      kill $WM_PID 2>/dev/null
      exit 1
    fi
    ;;
  "Steam")
    if command -v steam &> /dev/null; then
      steam -applaunch 220200 &
      KSP_PID=$!
    else
      zenity --error --text="Steam not found!"
      kill $WM_PID 2>/dev/null
      exit 1
    fi
    ;;
  "Exit"|"")
    # User selected exit or cancelled dialog
    kill $WM_PID 2>/dev/null
    exit 0
    ;;
  *)
    # Unknown choice
    kill $WM_PID 2>/dev/null
    exit 0
    ;;
esac

# Wait for KSP to exit
wait $KSP_PID

# Clean up: kill openbox when KSP exits
kill $WM_PID 2>/dev/null

# Exit the session
exit 0
