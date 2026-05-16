#!/bin/bash

# Only use basic error handling at start
set -e

# Config directory
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kerbal-kiosk"
CONFIG_FILE="$CONFIG_DIR/config.cfg"
STATE_FILE="$CONFIG_DIR/state"

# Create default config if it doesn't exist
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
# Kerbal Space Kiosk Configuration

# === KSP Installations ===
GOG_PATH="$HOME/GOG Games/Kerbal Space Program/game/KSP.x86_64"
STEAM_APPID="220200"

# === Window Manager ===
USE_WM="true"
WM_CHOICE="openbox"

# === Gamescope Settings ===
USE_GAMESCOPE="true"
GAMESCOPE_WIDTH="1920"
GAMESCOPE_HEIGHT="1080"
GAMESCOPE_REFRESH="60"
GAMESCOPE_UPSCALE="true"
GAMESCOPE_VRR="true"
record=no

# === Performance Overlays ===
SHOW_FPS="true"
FPS_TOOL="mangohud"

# === System Optimizations ===
OPTIMIZE_CPU="true"
OPTIMIZE_GPU="true"
STOP_SERVICES="true"
NICE_PRIORITY="-10"
IO_PRIORITY="0"

# === GPU Driver Optimizations ===
GPU_VENDOR=""
EOF
fi

# Load configuration
source "$CONFIG_FILE"

# Expand paths
GOG_PATH=$(eval echo "$GOG_PATH")

# ============================================================================
# SYSTEM OPTIMIZATION FUNCTIONS
# ============================================================================

save_state() {
    cat > "$STATE_FILE" << EOF
CPU_GOVERNOR=${ORIGINAL_CPU_GOV:-}
SERVICES_STOPPED=${STOPPED_SERVICES:-}
EOF
}

restore_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"

        if [ -n "${CPU_GOVERNOR:-}" ]; then
            echo "Restoring CPU governor to $CPU_GOVERNOR..."
            echo "$CPU_GOVERNOR" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
        fi

        if [ -n "${SERVICES_STOPPED:-}" ]; then
            echo "Restoring background services..."
            for service in $SERVICES_STOPPED; do
                systemctl --user start "$service" 2>/dev/null || true
            done
        fi

        rm -f "$STATE_FILE"
    fi
}

optimize_cpu_governor() {
    # Case-insensitive check
    local opt_cpu
    opt_cpu=$(echo "${OPTIMIZE_CPU:-false}" | tr '[:upper:]' '[:lower:]')
    if [ "$opt_cpu" = "true" ]; then
        echo "Optimizing CPU governor..."
        ORIGINAL_CPU_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")

        if [ -n "$ORIGINAL_CPU_GOV" ]; then
            echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
            echo "✓ CPU governor: performance mode"
        fi
    fi
}

stop_background_services() {
    # Case-insensitive check
    local stop_svc
    stop_svc=$(echo "${STOP_SERVICES:-false}" | tr '[:upper:]' '[:lower:]')
    if [ "$stop_svc" = "true" ]; then
        echo "Stopping unnecessary services..."
        STOPPED_SERVICES=""

        local services=(
            "tracker-miner-fs.service"
            "tracker-extract.service"
            "evolution-addressbook-factory.service"
            "evolution-calendar-factory.service"
            "gvfs-daemon.service"
            "at-spi-dbus-bus.service"
        )

        for service in "${services[@]}"; do
            if systemctl --user is-active --quiet "$service" 2>/dev/null; then
                systemctl --user stop "$service" 2>/dev/null && STOPPED_SERVICES="$STOPPED_SERVICES $service"
            fi
        done

        [ -n "$STOPPED_SERVICES" ] && echo "✓ Background services paused"
    fi
}

setup_gpu_optimizations() {
    # Case-insensitive check
    local opt_gpu
    opt_gpu=$(echo "${OPTIMIZE_GPU:-false}" | tr '[:upper:]' '[:lower:]')
    if [ "$opt_gpu" != "true" ]; then
        return
    fi

    echo "Applying GPU optimizations..."

    # Auto-detect GPU vendor if set to auto
    if [ "${GPU_VENDOR:-auto}" = "auto" ]; then
        if lspci 2>/dev/null | grep -qi "VGA.*AMD"; then
            GPU_VENDOR="amd"
        elif lspci 2>/dev/null | grep -qi "VGA.*NVIDIA"; then
            GPU_VENDOR="nvidia"
        elif lspci 2>/dev/null | grep -qi "VGA.*Intel"; then
            GPU_VENDOR="intel"
        fi
    fi

    case "${GPU_VENDOR:-}" in
        amd)
            export RADV_PERFTEST=aco,ngg
            export AMD_VULKAN_ICD=RADV
            export RADV_DEBUG=zerovram
            echo "✓ AMD GPU optimizations applied"
            ;;
        nvidia)
            export __GL_THREADED_OPTIMIZATIONS=1
            export __GL_SYNC_TO_VBLANK=0
            export __GL_SHADER_DISK_CACHE=1
            echo "✓ NVIDIA GPU optimizations applied"
            ;;
        intel)
            export MESA_LOADER_DRIVER_OVERRIDE=iris
            export vblank_mode=0
            echo "✓ Intel GPU optimizations applied"
            ;;
    esac
}

# ============================================================================
# LAUNCH FUNCTIONS
# ============================================================================

launch_with_optimizations() {
    local command="$1"

    local launch_cmd=""

    # Add FPS overlay if using MangoHud - case-insensitive
    local show_fps
    show_fps=$(echo "${SHOW_FPS:-false}" | tr '[:upper:]' '[:lower:]')
    if [ "$show_fps" = "true" ] && [ "${FPS_TOOL:-none}" = "mangohud" ]; then
        if command -v mangohud &> /dev/null; then
            launch_cmd="mangohud "
        fi
    fi

    # Add nice priority
    launch_cmd+="nice -n ${NICE_PRIORITY:--10} "

    # Add the actual command
    launch_cmd+="$command"

    echo "Launching: $launch_cmd"
    eval $launch_cmd &
    local pid=$!

    # Set IO priority
    sleep 0.5
    ionice -c 2 -n "${IO_PRIORITY:-0}" -p "$pid" 2>/dev/null || true

    wait $pid
}

launch_with_gamescope() {
    # 1. Capturamos TODOS los argumentos, no solo el primero ($1)
    local game_cmd=("$@")
    local log_file="/tmp/gamescope_$(date +%s).log"

    if [[ ${#game_cmd[@]} -eq 0 ]]; then
        echo "Error: No se proporcionó ningún comando de juego."
        return 1
    fi

    if ! command -v gamescope &> /dev/null; then
        zenity --error --text="Gamescope no instalado."
        return 1
    fi

    local gs_args=(nice -n "${NICE_PRIORITY:--10}" gamescope)

    # ... (Toda tu lógica de resolución y flags está perfecta aquí) ...
    gs_args+=(
        "-W" "${GAMESCOPE_WIDTH:-1920}" "-H" "${GAMESCOPE_HEIGHT:-1080}"
        "-w" "${GAMESCOPE_WIDTH:-1920}" "-h" "${GAMESCOPE_HEIGHT:-1080}"
        "-r" "${GAMESCOPE_REFRESH:-60}" "--fps-limit" "${GAMESCOPE_REFRESH:-60}"
        "-f" "--immediate-flips" "--force-grab-cursor"
    )

    [[ "${GAMESCOPE_VRR,,}" == "true" ]] && gs_args+=("--adaptive-sync")
    [[ "${GAMESCOPE_UPSCALE,,}" == "true" ]] && gs_args+=("--fsr-upscaling")
    [[ "${SHOW_FPS,,}" == "true" ]] && gs_args+=("--mangoapp")

    echo "Lanzando: ${gs_args[*]} -- ${game_cmd[*]}"

    # 2. Ejecución expandiendo el array del juego correctamente
    "${gs_args[@]}" -- "${game_cmd[@]}" > "$log_file" 2>&1 &
    local pid=$!

    sleep 0.5
    ionice -c 2 -n "${IO_PRIORITY:-0}" -p "$pid" 2>/dev/null || true

    wait $pid

    exit 0
}

# ============================================================================
# SETTINGS DIALOG
# ============================================================================

show_settings() {
    local result
    result=$(yad --form \
        --title="Kerbal Kiosk Settings" \
        --width=600 \
        --text="<b>Performance & Display Settings</b>" \
        --separator="|" \
        --field="<b>Gamescope Settings</b>:LBL" "" \
        --field="Use Gamescope:CHK" "${USE_GAMESCOPE:-true}" \
        --field="Resolution Width:NUM" "${GAMESCOPE_WIDTH:-1920}!1024..7680!1" \
        --field="Resolution Height:NUM" "${GAMESCOPE_HEIGHT:-1080}!768..4320!1" \
        --field="Refresh Rate:NUM" "${GAMESCOPE_REFRESH:-60}!30..360!1" \
        --field="FSR Upscaling:CHK" "${GAMESCOPE_UPSCALE:-true}" \
        --field="Adaptive Sync (VRR):CHK" "${GAMESCOPE_VRR:-true}" \
        --field="<b>Performance Overlays</b>:LBL" "" \
        --field="Show FPS Counter:CHK" "${SHOW_FPS:-true}" \
        --field="FPS Tool:CB" "${FPS_TOOL:-mangohud}!mangohud!gamescope!none" \
        --field="<b>System Optimizations</b>:LBL" "" \
        --field="Optimize CPU Governor:CHK" "${OPTIMIZE_CPU:-true}" \
        --field="Apply GPU Tweaks:CHK" "${OPTIMIZE_GPU:-true}" \
        --field="Stop Background Services:CHK" "${STOP_SERVICES:-true}" \
        --field="Process Priority (lower = faster):NUM" "${NICE_PRIORITY:--10}!-20..19!1" \
        --field="IO Priority (lower = faster):NUM" "${IO_PRIORITY:-0}!0..7!1" \
        --field="<b>Window Manager</b>:LBL" "" \
        --field="Use Window Manager:CHK" "${USE_WM:-true}" \
        --field="GPU Vendor:CB" "${GPU_VENDOR:-auto}!auto!amd!nvidia!intel" \
        --button="Save:0" \
        --button="Cancel:1")

    if [ $? -eq 0 ]; then
        # Parse results
        IFS='|' read -r _ use_gs width height refresh upscale vrr _ show_fps fps_tool _ opt_cpu opt_gpu stop_svc nice_val io_val _ use_wm gpu_vendor <<< "$result"

        # Update config file
        sed -i "s/^USE_GAMESCOPE=.*/USE_GAMESCOPE=\"$use_gs\"/" "$CONFIG_FILE"
        sed -i "s/^GAMESCOPE_WIDTH=.*/GAMESCOPE_WIDTH=\"$width\"/" "$CONFIG_FILE"
        sed -i "s/^GAMESCOPE_HEIGHT=.*/GAMESCOPE_HEIGHT=\"$height\"/" "$CONFIG_FILE"
        sed -i "s/^GAMESCOPE_REFRESH=.*/GAMESCOPE_REFRESH=\"$refresh\"/" "$CONFIG_FILE"
        sed -i "s/^GAMESCOPE_UPSCALE=.*/GAMESCOPE_UPSCALE=\"$upscale\"/" "$CONFIG_FILE"
        sed -i "s/^GAMESCOPE_VRR=.*/GAMESCOPE_VRR=\"$vrr\"/" "$CONFIG_FILE"
        sed -i "s/^SHOW_FPS=.*/SHOW_FPS=\"$show_fps\"/" "$CONFIG_FILE"
        sed -i "s/^FPS_TOOL=.*/FPS_TOOL=\"$fps_tool\"/" "$CONFIG_FILE"
        sed -i "s/^OPTIMIZE_CPU=.*/OPTIMIZE_CPU=\"$opt_cpu\"/" "$CONFIG_FILE"
        sed -i "s/^OPTIMIZE_GPU=.*/OPTIMIZE_GPU=\"$opt_gpu\"/" "$CONFIG_FILE"
        sed -i "s/^STOP_SERVICES=.*/STOP_SERVICES=\"$stop_svc\"/" "$CONFIG_FILE"
        sed -i "s/^NICE_PRIORITY=.*/NICE_PRIORITY=\"$nice_val\"/" "$CONFIG_FILE"
        sed -i "s/^IO_PRIORITY=.*/IO_PRIORITY=\"$io_val\"/" "$CONFIG_FILE"
        sed -i "s/^USE_WM=.*/USE_WM=\"$use_wm\"/" "$CONFIG_FILE"
        sed -i "s/^GPU_VENDOR=.*/GPU_VENDOR=\"$gpu_vendor\"/" "$CONFIG_FILE"

        zenity --info --text="Settings saved!\n\nChanges will apply on next launch."
        return 0
    fi

    return 1
}

# ============================================================================
# CLEANUP HANDLER
# ============================================================================

WM_PID=""

cleanup() {
    echo "Cleaning up..."
    if record=yes then
        pkill -f ffmpeg

    restore_state
    if [ -n "${WM_PID:-}" ]; then
        kill "$WM_PID" 2>/dev/null || true
    fi
    exit 0
}

trap cleanup EXIT SIGTERM SIGINT

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Disable screen blanking
xset -dpms s off s noblank 2>/dev/null || true

# Start window manager if enabled
use_wm=$(echo "${USE_WM:-true}" | tr '[:upper:]' '[:lower:]')
if [ "$use_wm" = "true" ]; then
    case "${WM_CHOICE:-openbox}" in
        openbox)
            openbox --config-file /dev/null &
            WM_PID=$!
            ;;
        dwm)
            command -v dwm &>/dev/null && dwm &
            WM_PID=$!
            ;;
        matchbox)
            command -v matchbox-window-manager &>/dev/null && matchbox-window-manager &
            WM_PID=$!
            ;;
        *)
            openbox --config-file /dev/null &
            WM_PID=$!
            ;;
    esac
    sleep 1
fi

# Set background
xsetroot -solid black 2>/dev/null || true

# Build menu function
build_menu() {
    MENU_ITEMS=()

    # Check if Gamescope is available - try multiple detection methods
    local has_gamescope
    has_gamescope=false
    if command -v gamescope >/dev/null 2>&1; then
        has_gamescope=true
    elif which gamescope >/dev/null 2>&1; then
        has_gamescope=true
    elif [ -x /usr/bin/gamescope ]; then
        has_gamescope=true
    fi

    # Normalize USE_GAMESCOPE to lowercase for comparison
    local use_gs_normalized
    use_gs_normalized=$(echo "${USE_GAMESCOPE:-true}" | tr '[:upper:]' '[:lower:]')

    if [ -f "$GOG_PATH" ]; then
        MENU_ITEMS+=(FALSE "GOG Standard" "Launch GOG KSP normally")
        if [ "$has_gamescope" = "true" ] && [ "$use_gs_normalized" = "true" ]; then
            MENU_ITEMS+=(TRUE "GOG + Gamescope" "Launch with Gamescope (recommended)")
        fi
    fi

    if command -v steam &> /dev/null; then
        MENU_ITEMS+=(FALSE "Steam Standard" "Launch Steam KSP normally")
        if [ "$has_gamescope" = "true" ] && [ "$use_gs_normalized" = "true" ]; then
            MENU_ITEMS+=(FALSE "Steam + Gamescope" "Launch with Gamescope")
        fi
    fi

    MENU_ITEMS+=(FALSE "Settings" "Configure performance options")
    MENU_ITEMS+=(FALSE "Exit" "Return to login")
}

# Build initial menu
build_menu

# Check if any KSP found
if [ ! -f "$GOG_PATH" ] && ! command -v steam &> /dev/null; then
    zenity --error --text="No KSP installation found!\n\nExpected GOG at:\n$GOG_PATH"
    exit 1
fi

# Main menu loop
while true; do
    # Show menu
    CHOICE=$(zenity --list \
        --title="Kerbal Space Kiosk - MEGA OPTIMIZED" \
        --text="Select launch option:\n\n<small>Optimizations: CPU ${OPTIMIZE_CPU:-true}, GPU ${OPTIMIZE_GPU:-true}, Services ${STOP_SERVICES:-true}</small>" \
        --radiolist \
        --column="" --column="Option" --column="Description" \
        "${MENU_ITEMS[@]}" \
        --height=500 --width=700 \
        --hide-column=1) || CHOICE="Exit"

    # Handle choice
    case "$CHOICE" in
        "GOG Standard")
            optimize_cpu_governor
            stop_background_services
            setup_gpu_optimizations
            save_state
            launch_with_optimizations "\"$GOG_PATH\""
            if record=yes then
                ffmpeg -loglevel quiet -f x11grab -video_size 1280 -720 -framerate 30 -i :0.0 -c:v h264_vaapi -vf "format=nv12,hwupload" -qp 25 output.mp4 &
            cd $HOME/GOG Games/Kerbal Space Program/game/
            break
            ;;
        "GOG + Gamescope")
            optimize_cpu_governor
            stop_background_services
            setup_gpu_optimizations
            save_state
            gamescope -w 1280 -h 720 -f -r 30 -- $GOG_PATH
            cd $HOME/GOG Games/Kerbal Space Program/game/
            break
            ;;
        "Steam Standard")
            optimize_cpu_governor
            stop_background_services
            setup_gpu_optimizations
            save_state
            launch_with_optimizations "steam -applaunch ${STEAM_APPID:-220200}"
            break
            ;;
        "Steam + Gamescope")
            optimize_cpu_governor
            stop_background_services
            setup_gpu_optimizations
            save_state
            gamescope -w 1280 -h 720 -f -r 30 -- "steam -applaunch ${STEAM_APPID:-220200}"
            break
            ;;
        "Settings")
            show_settings
            # Reload config after settings change
            source "$CONFIG_FILE"
            GOG_PATH=$(eval echo "$GOG_PATH")
            # Rebuild menu with new settings
            build_menu
            # Loop back to show menu again
            ;;
        "Exit"|*)
            # Exit selected or dialog closed - just exit cleanly
            break
            ;;
    esac
done



cleanup
