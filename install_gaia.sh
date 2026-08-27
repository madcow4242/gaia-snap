#!/bin/bash
set -e

# =====================================================================
# GLOBAL CONFIGURATION CONFIG/VERSION VARIABLES
# =====================================================================
GAIA_VERSION="0.23.0"  # Centralized single source of truth for installations

# Capture the absolute path of the directory where the script is located
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =====================================================================
# VALIDATION: System compatibility and required tools
# =====================================================================
check_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            echo "WARNING: This script is tested on Ubuntu 24.04. Detected: $ID $VERSION_ID"
            echo "    Some functionality may not work as expected."
        fi
    fi
}

check_distro

# =====================================================================
# HELPER: Pre-flight cleanup of orphaned GAIA snaps and processes
# =====================================================================
cleanup_gaia_environment() {
    echo "INFO: Checking for existing GAIA installations and orphaned processes..."
    
    # Kill any running GAIA processes
    if pgrep -f "gaia-desktop|\.gaia-desktop-bin|gaia chat --ui" >/dev/null 2>&1; then
        echo "INFO: Terminating running GAIA processes..."
        pkill -9 gaia-desktop 2>/dev/null || true
        pkill -9 -f "\.gaia-desktop-bin" 2>/dev/null || true
        pkill -9 -f "gaia chat --ui" 2>/dev/null || true
        sleep 1
    fi
    
    # Remove existing gaia-desktop snap with --purge to clean data
    if snap list gaia-desktop >/dev/null 2>&1; then
        echo "INFO: Removing existing gaia-desktop snap (--purge)..."
        sudo snap remove --purge gaia-desktop 2>/dev/null || true
        sleep 2
    fi
    
    # Clean up home directory state
    if [ -d ~/.gaia ]; then
        echo "INFO: Cleaning up ~/.gaia configuration directory..."
        rm -rf ~/.gaia || true
    fi
    
    echo "✅ Environment cleanup complete"
}

# =====================================================================
# HELPER: Pre-flight cleanup for LXD topology
# =====================================================================
cleanup_lxd_environment() {
    echo "INFO: Checking for existing LXD GAIA container..."

    if lxc info gaia-runtime-sandbox >/dev/null 2>&1; then
        echo "INFO: Stopping gaia-runtime-sandbox container..."
        lxc stop gaia-runtime-sandbox 2>/dev/null || true
        sleep 1
        echo "INFO: Deleting gaia-runtime-sandbox container..."
        lxc delete gaia-runtime-sandbox --force 2>/dev/null || true
    fi

    echo "✅ LXD cleanup complete"
}

# =====================================================================
# HELPER: Pre-flight cleanup for Docker/Podman topologies
# =====================================================================
cleanup_container_environment() {
    local RUNTIME="$1"  # docker | podman
    local CONTAINER_NAME=""

    if [[ "$RUNTIME" == "docker" ]]; then
        CONTAINER_NAME="gaia-docker-sandbox"
    elif [[ "$RUNTIME" == "podman" ]]; then
        CONTAINER_NAME="gaia-podman-sandbox"
    else
        echo "WARNING: Unknown container runtime '$RUNTIME'; skipping cleanup"
        return 0
    fi

    echo "INFO: Checking for existing $RUNTIME GAIA container..."

    if $RUNTIME inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        echo "INFO: Stopping $RUNTIME container $CONTAINER_NAME..."
        $RUNTIME stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        sleep 1
        echo "INFO: Removing $RUNTIME container $CONTAINER_NAME..."
        $RUNTIME rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi

    echo "✅ $RUNTIME cleanup complete"
}

# =====================================================================
# HELPER: Create desktop application launcher
# =====================================================================
create_desktop_launcher() {
    local LAUNCHER_NAME="$1"        # e.g., "gaia-lxd"
    local LAUNCHER_EXEC="$2"        # command to execute
    local LAUNCHER_DESC="$3"        # description (shown as Comment)
    local ICON_PATH="${4:-/snap/gaia-desktop/current/meta/gui/amd-gaia.png}"  # full icon path
    local APP_NAME="$5"             # display name in app menu

    # Create wrapper script in /usr/local/bin
    sudo tee "/usr/local/bin/${LAUNCHER_NAME}" > /dev/null <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_EOF
    echo "$LAUNCHER_EXEC" | sudo tee -a "/usr/local/bin/${LAUNCHER_NAME}" > /dev/null
    sudo chmod +x "/usr/local/bin/${LAUNCHER_NAME}"

    # Create .desktop file in /usr/share/applications
    sudo tee "/usr/share/applications/${LAUNCHER_NAME}.desktop" > /dev/null <<DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${APP_NAME}
Comment=${LAUNCHER_DESC}
Exec=/usr/local/bin/${LAUNCHER_NAME}
Icon=${ICON_PATH}
Categories=Utility;Development;AI;
StartupNotify=true
Terminal=false
DESKTOP_EOF

    echo "✅ Desktop launcher created: ${LAUNCHER_NAME} (${APP_NAME})"
}

# =====================================================================
# PHASE 1: FRONTLOADED USER INTERACTIVE DATA COLLECTION
# =====================================================================

clear
echo "====================================================================="
echo "        GAIA Deployment Installer"
echo "====================================================================="
echo " Select a deployment topology:"
echo "    1) Native host Snap"
echo "    2) LXD system container"
echo "    3) Docker container"
echo "    4) Podman container"
echo "    5) Kubernetes manifest output"
echo "---------------------------------------------------------------------"

read -p " Enter Choice (1-5): " TOPOLOGY_CHOICE

# =====================================================================
# PRE-FLIGHT VALIDATION: Check required tools for chosen topology
# =====================================================================
validate_topology_tools() {
    case "$1" in
        1)
            if ! command -v snap &>/dev/null; then
                echo "ERROR: Snap is not installed on this system."
                echo "   Install with: sudo apt install snapd"
                exit 1
            fi
            ;;
        2)
            if ! command -v lxc &>/dev/null; then
                echo "ERROR: LXD CLI is not installed on this system."
                echo "   Install with: sudo apt install lxd"
                exit 1
            fi
            ;;
        3)
            if ! command -v docker &>/dev/null; then
                echo "ERROR: Docker is not installed on this system."
                echo "   Install with: sudo apt install docker.io"
                exit 1
            fi
            ;;
        4)
            if ! command -v podman &>/dev/null; then
                echo "ERROR: Podman is not installed on this system."
                echo "   Install with: sudo apt install podman"
                exit 1
            fi
            ;;
        5)
            if ! command -v kubectl &>/dev/null; then
                echo "ERROR: kubectl is not installed on this system."
                echo "   Install from: https://kubernetes.io/docs/tasks/tools/"
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Invalid topology choice. Please select 1-5."
            exit 1
            ;;
    esac
}

validate_topology_tools "$TOPOLOGY_CHOICE"

# Prompt common configuration settings
read -p " Enter your Lemonade/AI Backend URL [http://127.0.0.1:13305]: " BACKEND_URL
BACKEND_URL=${BACKEND_URL:-"http://127.0.0.1:13305"}

read -p " Enter Maximum Agent Plan Steps (Default 20): " AGENT_STEPS
AGENT_STEPS=${AGENT_STEPS:-"20"}

read -p " Enter OpenAI API Key (Optional / Leave Blank): " OPENAI_KEY
read -p " Enter Anthropic API Key (Optional / Leave Blank): " ANTHROPIC_KEY
read -p " Enter Groq API Key (Optional / Leave Blank): " GROQ_KEY
read -p " Enter Tavily Search API Key (Optional / Leave Blank): " TAVILY_KEY
read -p " Enter Serper Search API Key (Optional / Leave Blank): " SERPER_KEY

# Diagnostics toggle for runtime network reliability hooks
GAIA_NETWORK_RELIABILITY_LOG="1"
if [[ "$TOPOLOGY_CHOICE" =~ ^(2|3|4)$ ]]; then
    read -p " Enable network reliability diagnostics logging? (Y/n): " RELIABILITY_LOG_CHOICE
    if [[ "$RELIABILITY_LOG_CHOICE" =~ ^[Nn]$ ]]; then
        GAIA_NETWORK_RELIABILITY_LOG="0"
    fi
fi

EXPOSE_HOST_DIR="n"
HOST_PATH_TO_EXPOSE=""
if [[ "$TOPOLOGY_CHOICE" =~ ^(2|3|4)$ ]]; then
    echo "---------------------------------------------------------------------"
    echo " The container sandbox is isolated from your host filesystem."
    read -p " Expose a host directory to the sandboxed GAIA environment? (y/N): " EXPOSE_HOST_DIR
    if [[ "$EXPOSE_HOST_DIR" =~ ^[Yy]$ ]]; then
        read -p " Enter absolute host path to expose (e.g., /home/your_user/Workspace): " HOST_PATH_TO_EXPOSE
    fi
fi

# =====================================================================
# Workspace mount detection and artifact staging
# =====================================================================
IS_REMOTE_MOUNT=false
LOCAL_TAR_STAGE=""

# Detect if the workspace directory is parked on a network mount
if [[ "$WORKSPACE_DIR" == /mnt/userver* ]]; then
    echo "---------------------------------------------------------------------"
    echo "INFO: Remote network mount detected."
    echo "      Enabling local cache staging for large artifacts."
    echo "---------------------------------------------------------------------"
    IS_REMOTE_MOUNT=true
    LOCAL_TAR_STAGE="/tmp/gaia-desktop_${GAIA_VERSION}_docker-image.tar"

    # Pre-flight scp transfer onto your Zenbook's native local SSD storage
    if [[ "$TOPOLOGY_CHOICE" =~ ^(3|4)$ ]]; then
        if [ ! -f "$LOCAL_TAR_STAGE" ]; then
            echo "INFO: Fetching Docker archive to local staging path."
            scp kevin@userver:/mnt/md0/backups/SoftwareDev/gaia-snap/gaia-desktop_${GAIA_VERSION}_docker-image.tar "$LOCAL_TAR_STAGE"
        else
            echo "INFO: Reusing local staged archive: $LOCAL_TAR_STAGE"
        fi
    fi
fi

# Locate local artifacts cleanly within the absolute workspace context
SNAP_PACKAGE=$(ls -t "${WORKSPACE_DIR}"/*.snap 2>/dev/null | head -n 1 || true)
LXD_TARBALL=$(ls -t "${WORKSPACE_DIR}"/*LXD-sandbox.tar.gz 2>/dev/null | head -n 1 || true)

# Resolve target container pathing based on current topology placement
if [ "$IS_REMOTE_MOUNT" = true ]; then
    DOCKER_TARBALL="$LOCAL_TAR_STAGE"
else
    DOCKER_TARBALL=$(ls -t "${WORKSPACE_DIR}"/*docker-image.tar 2>/dev/null | head -n 1 || true)
fi

# =====================================================================
# PHASE 2: ATOMIC TOPOLOGY CONFIGURATION MACHINE EXECUTION
# =====================================================================

# ---------------------------------------------------------------------
# OPTION 1: NATIVE DESKTOP SNAP ENVIRONMENT DEPLOYMENT
# ---------------------------------------------------------------------
if [[ "$TOPOLOGY_CHOICE" == "1" ]]; then
    echo "INFO: Installing GAIA as a native Snap."
    cleanup_gaia_environment
    if [ -z "$SNAP_PACKAGE" ]; then
        echo "ERROR: No local .snap artifact found in the working directory."
        exit 1
    fi
    sudo snap install "$SNAP_PACKAGE" --dangerous --classic
    sudo snap set gaia-desktop backend.url="$BACKEND_URL" backend.maxsteps="$AGENT_STEPS" keys.openai="$OPENAI_KEY" keys.anthropic="$ANTHROPIC_KEY" keys.groq="$GROQ_KEY" keys.tavily="$TAVILY_KEY" keys.serper="$SERPER_KEY"
    echo "INFO: GAIA Snap installation complete."

    # Restore previous installer behavior: launch the desktop app after install
    if [ -n "${DISPLAY}" ] || [ -n "${WAYLAND_DISPLAY}" ]; then
        echo "INFO: Launching GAIA desktop application."
        snap run gaia-desktop >/dev/null 2>&1 &
    else
        echo "INFO: No graphical session detected; skipping automatic launch."
    fi

    echo "=========================================================================="
    echo "✅ Snap deployment complete!"
    echo "   GAIA is now available in your application menu with system tray integration."
    echo "   Search for 'GAIA' in the application launcher, or run: gaia-desktop"
    echo "=========================================================================="

# ---------------------------------------------------------------------
# OPTION 2: SECURE ISOLATED LXD SANDBOX SYSTEM CONTAINER
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "2" ]]; then
    echo "INFO: Deploying GAIA into LXD container."
    cleanup_lxd_environment
    if ! command -v lxc &> /dev/null; then
        echo "ERROR: LXD CLI utility not found on this system."
        exit 1
    fi

    if [ -z "${LXD_TARBALL}" ]; then
        if ! lxc info gaia-runtime-sandbox >/dev/null 2>&1; then
            echo "ERROR: Portable archive 'gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz' not found."
            exit 1
        fi
    else
        FILE_M_TIME=$(stat -c %Y "${LXD_TARBALL}")
        LAST_M_TIME=$(cat ~/.gaia/.sandbox_timestamp 2>/dev/null || echo "0")
        if lxc info gaia-runtime-sandbox >/dev/null 2>&1 && [ "${FILE_M_TIME}" != "${LAST_M_TIME}" ]; then
            lxc delete gaia-runtime-sandbox --force >/dev/null 2>&1 || true
        fi
        if ! lxc info gaia-runtime-sandbox >/dev/null 2>&1; then
            lxc import "${LXD_TARBALL}" gaia-runtime-sandbox
            mkdir -p ~/.gaia/ && echo "${FILE_M_TIME}" > ~/.gaia/.sandbox_timestamp || true
        fi
    fi

    lxc start gaia-runtime-sandbox || true
    sleep 2

    RESOLVED_HOST_PATH=""
    if [ -n "$HOST_PATH_TO_EXPOSE" ]; then
        eval RESOLVED_HOST_PATH="$HOST_PATH_TO_EXPOSE"
        if [ -d "$RESOLVED_HOST_PATH" ]; then
            lxc config device remove gaia-runtime-sandbox host-workspace >/dev/null 2>&1 || true
            lxc exec gaia-runtime-sandbox -- mkdir -p "$RESOLVED_HOST_PATH"
            lxc config device add gaia-runtime-sandbox host-workspace disk source="$RESOLVED_HOST_PATH" path="$RESOLVED_HOST_PATH"
            lxc config set gaia-runtime-sandbox raw.idmap "both 1000 1000"
        fi
    fi

    echo "INFO: Mapping host display socket into container."
    xhost +local: >/dev/null 2>&1 || true
    lxc config device remove gaia-runtime-sandbox X0 >/dev/null 2>&1 || true
    lxc config device remove gaia-runtime-sandbox X11-Display-Socket >/dev/null 2>&1 || true
    sudo mkdir -p /tmp/.X11-unix && sudo chmod 1777 /tmp/.X11-unix
    lxc config device add gaia-runtime-sandbox X11-Display-Socket disk source=/tmp/.X11-unix path=/tmp/.X11-unix

    # Extract host and port from BACKEND_URL for conditional proxy setup
    BACKEND_HOST_PORT="${BACKEND_URL#http://}"
    BACKEND_HOST_PORT="${BACKEND_HOST_PORT#https://}"
    BACKEND_HOST="${BACKEND_HOST_PORT%%:*}"  # everything before first colon
    BACKEND_PORT="${BACKEND_HOST_PORT##*:}"  # everything after last colon
    if [ "$BACKEND_PORT" = "$BACKEND_HOST_PORT" ]; then
        BACKEND_PORT="13305"  # default port if not specified
    fi

    # Only add proxy device if backend is on localhost (isolated from container's localhost)
    # For remote hosts/IPs, the container has direct network access via its normal interface
    lxc config device remove gaia-runtime-sandbox lemonade-server >/dev/null 2>&1 || true
    if [[ "$BACKEND_HOST" =~ ^(localhost|127\.0\.0\.1|::1)$ ]]; then
        echo "INFO: Proxying Lemonade Server (${BACKEND_HOST}:${BACKEND_PORT}) into container."
        lxc config device add gaia-runtime-sandbox lemonade-server proxy \
            listen=tcp:${BACKEND_HOST}:${BACKEND_PORT} \
            connect=tcp:${BACKEND_HOST}:${BACKEND_PORT} \
            bind=container
    else
        echo "INFO: Backend URL is remote (${BACKEND_HOST}:${BACKEND_PORT}); container has direct network access."
    fi

    echo "INFO: Restarting container to apply updates."
    lxc restart gaia-runtime-sandbox
    sleep 3

    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop backend.url="$BACKEND_URL" backend.maxsteps="$AGENT_STEPS" keys.openai="$OPENAI_KEY" keys.anthropic="$ANTHROPIC_KEY" keys.groq="$GROQ_KEY" keys.tavily="$TAVILY_KEY" keys.serper="$SERPER_KEY"

    if [ -n "$RESOLVED_HOST_PATH" ]; then
        lxc exec gaia-runtime-sandbox -- mkdir -p /root/.gaia/cache
        lxc exec gaia-runtime-sandbox -- sh -c "cat << 'EOF' > /root/.gaia/cache/allowed_paths.json
{
  \"paths\": [
    \"/root\",
    \"${RESOLVED_HOST_PATH}\"
  ]
}
EOF"
    fi

    echo "=========================================================================="
    echo "Starting GAIA in LXD container"
    echo "=========================================================================="
    lxc exec gaia-runtime-sandbox -- env \
        DISPLAY="${DISPLAY:-:0}" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
        XDG_RUNTIME_DIR="/tmp" \
        GAIA_NETWORK_RELIABILITY_LOG="${GAIA_NETWORK_RELIABILITY_LOG}" \
        ALLOWED_PATHS="${RESOLVED_HOST_PATH}" \
        allowed_paths="${RESOLVED_HOST_PATH}" \
        GAIA_ALLOWED_PATHS="${RESOLVED_HOST_PATH}" \
        /snap/bin/gaia-desktop --no-sandbox

    # Create desktop launcher for LXD deployment
    LXD_LAUNCHER_CMD="if ! lxc info gaia-runtime-sandbox >/dev/null 2>&1; then echo 'LXD container not found. Run install_gaia.sh first.'; exit 1; fi; lxc start gaia-runtime-sandbox 2>/dev/null || true; sleep 1; lxc exec gaia-runtime-sandbox -- env DISPLAY=\${DISPLAY:-:0} WAYLAND_DISPLAY=\${WAYLAND_DISPLAY} XDG_RUNTIME_DIR=/tmp /snap/bin/gaia-desktop --no-sandbox"
    create_desktop_launcher "gaia-lxd" "$LXD_LAUNCHER_CMD" "GAIA Desktop (LXD Container)" "" "GAIA-LXD"
    echo "=========================================================================="
    echo "✅ LXD deployment complete!"
    echo "   GAIA is now available in your application menu as 'GAIA Desktop (LXD Container)'"
    echo "   Launch from terminal shortcut: gaia-lxd"
    echo "=========================================================================="

# ---------------------------------------------------------------------
# OPTION 3: Docker container deployment
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "3" ]]; then
    echo "====================================================================="
    echo " Deploying GAIA OCI image via Docker"
    echo "====================================================================="
    cleanup_container_environment "docker"
    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker CLI tool not found on this system."
        exit 1
    fi

    if [ -n "${DOCKER_TARBALL}" ]; then
        if [ "$IS_REMOTE_MOUNT" = false ]; then
            echo "INFO: Staging Docker archive on local storage."
            rsync -ah --progress "${DOCKER_TARBALL}" /tmp/gaia-docker-stage.tar
            LOCAL_STAGE_FILE="/tmp/gaia-docker-stage.tar"
        else
            LOCAL_STAGE_FILE="$DOCKER_TARBALL"
        fi

        echo "INFO: Loading Docker archive into local Docker daemon."
        cat "$LOCAL_STAGE_FILE" | docker load

        # Keep things clean on your laptop's local partition
        [ "$IS_REMOTE_MOUNT" = false ] && rm -f /tmp/gaia-docker-stage.tar
    fi

    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^gaia-desktop:${GAIA_VERSION}$"; then
        echo "ERROR: Image gaia-desktop:${GAIA_VERSION} is not present in local Docker daemon."
        exit 1
    fi

    docker rm -f gaia-docker-sandbox >/dev/null 2>&1 || true

    DISPLAY_FLAGS="-e DISPLAY=$DISPLAY"
    if [ -n "$WAYLAND_DISPLAY" ]; then
        DISPLAY_FLAGS="-e DISPLAY=$DISPLAY -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY -e XDG_RUNTIME_DIR=/tmp -v $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/tmp/$WAYLAND_DISPLAY:ro"
    else
        sudo mkdir -p /tmp/.X11-unix && sudo chmod 1777 /tmp/.X11-unix
        DISPLAY_FLAGS="-e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:ro"
    fi
    xhost +local:docker >/dev/null 2>&1 || true

    VOLUME_MAPPING=""
    [ -n "$HOST_PATH_TO_EXPOSE" ] && eval RESOLVED_HOST_PATH="$HOST_PATH_TO_EXPOSE"
    [ -d "$RESOLVED_HOST_PATH" ] && VOLUME_MAPPING="-v $RESOLVED_HOST_PATH:$RESOLVED_HOST_PATH"

    echo "=========================================================================="
    echo " Starting GAIA in Docker container"
    echo "=========================================================================="
    xhost +local:docker

    DOCKER_CONTAINER_ID=$(eval "docker run -d \
        --name gaia-docker-sandbox \
        --net=host \
        --ipc=host \
        --user $(id -u):$(id -g) \
        --device /dev/dri:/dev/dri \
        $DISPLAY_FLAGS \
        $VOLUME_MAPPING \
        -e SNAP=\"/opt/gaia_runtime\" \
        -e TARGET_EXEC=\"/opt/gaia_runtime/opt/GAIA/gaia-desktop\" \
        -e HOME=\"/opt/gaia_runtime/workspace\" \
        -e GAIA_HOME=\"/opt/gaia_runtime/workspace/.gaia\" \
        -e TMPDIR=\"/opt/gaia_runtime/workspace/tmp\" \
        -e DISPLAY=\"$DISPLAY\" \
        -e WAYLAND_DISPLAY=\"$WAYLAND_DISPLAY\" \
        -e backend_url=\"$BACKEND_URL\" \
        -e backend_maxsteps=\"$AGENT_STEPS\" \
        -e keys_openai=\"$OPENAI_KEY\" \
        -e keys_anthropic=\"$ANTHROPIC_KEY\" \
        -e keys_groq=\"$GROQ_KEY\" \
        -e keys_tavily=\"$TAVILY_KEY\" \
        -e keys_serper=\"$SERPER_KEY\" \
        -e GAIA_NETWORK_RELIABILITY_LOG=\"${GAIA_NETWORK_RELIABILITY_LOG}\" \
        -e ALLOWED_PATHS=\"${RESOLVED_HOST_PATH}\" \
        -e allowed_paths=\"${RESOLVED_HOST_PATH}\" \
        -e GAIA_ALLOWED_PATHS=\"${RESOLVED_HOST_PATH}\" \
        'gaia-desktop:${GAIA_VERSION}'")

    if [ -z "$DOCKER_CONTAINER_ID" ]; then
        echo "ERROR: Failed to launch Docker container gaia-docker-sandbox."
        exit 1
    fi

    sleep 2

    if ! docker ps --format '{{.Names}}' | grep -qx 'gaia-docker-sandbox'; then
        echo "ERROR: Docker container gaia-docker-sandbox exited during startup."
        echo "INFO: Recent container logs:"
        docker logs --tail 120 gaia-docker-sandbox || true
        exit 1
    fi

    if [ -n "$RESOLVED_HOST_PATH" ]; then
        docker exec gaia-docker-sandbox /usr/bin/bash -lc "mkdir -p /opt/gaia_runtime/workspace/.gaia/cache && cat << 'EOF' > /opt/gaia_runtime/workspace/.gaia/cache/allowed_paths.json
{
  \"paths\": [
    \"/root\",
    \"${RESOLVED_HOST_PATH}\"
  ]
}
EOF"
    fi

    echo "INFO: Docker deployment started."

    # Create desktop launcher for Docker deployment
    DOCKER_LAUNCHER_CMD="if ! docker inspect gaia-docker-sandbox >/dev/null 2>&1; then echo 'Docker container not found. Run install_gaia.sh first.'; exit 1; fi; docker start gaia-docker-sandbox 2>/dev/null || true; sleep 1; docker exec -e DISPLAY=\"\${DISPLAY}\" gaia-docker-sandbox /usr/bin/gaia-launcher"
    create_desktop_launcher "gaia-docker" "$DOCKER_LAUNCHER_CMD" "GAIA Desktop (Docker Container)" "" "GAIA-Docker"
    echo "=========================================================================="
    echo "✅ Docker deployment complete!"
    echo "   GAIA is now available in your application menu as 'GAIA-Docker'"
    echo "   Launch from terminal shortcut: gaia-docker"
    echo "=========================================================================="

# ---------------------------------------------------------------------
# OPTION 4: Podman container deployment
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "4" ]]; then
    echo "INFO: Deploying GAIA via rootless Podman container."
    cleanup_container_environment "podman"
    if ! command -v podman &> /dev/null; then
        echo "ERROR: Podman CLI not detected."
        exit 1
    fi

    if [ -n "${DOCKER_TARBALL}" ]; then
        if [ "$IS_REMOTE_MOUNT" = false ]; then
            echo "INFO: Staging OCI archive on local storage."
            rsync -ah --progress "${DOCKER_TARBALL}" /tmp/gaia-podman-stage.tar
            LOCAL_STAGE_FILE="/tmp/gaia-podman-stage.tar"
        else
            LOCAL_STAGE_FILE="$DOCKER_TARBALL"
        fi

        echo "INFO: Loading OCI archive into Podman image store."
        cat "$LOCAL_STAGE_FILE" | podman load

        [ "$IS_REMOTE_MOUNT" = false ] && rm -f /tmp/gaia-podman-stage.tar
    fi

    # Prevent Podman from auto-restarting containers after they are closed.
    sudo systemctl disable --now podman-restart.service >/dev/null 2>&1 || true

    podman rm -f gaia-podman-sandbox >/dev/null 2>&1 || true
    xhost +local:root >/dev/null 2>&1 || true

    DISPLAY_FLAGS="-e DISPLAY=$DISPLAY"
    if [ -n "$WAYLAND_DISPLAY" ]; then
        DISPLAY_FLAGS="-e DISPLAY=$DISPLAY -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY -e XDG_RUNTIME_DIR=/tmp -v $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/tmp/$WAYLAND_DISPLAY:ro"
    else
        sudo mkdir -p /tmp/.X11-unix && sudo chmod 1777 /tmp/.X11-unix
        DISPLAY_FLAGS="-e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:ro"
    fi

    VOLUME_MAPPING=""
    [ -n "$HOST_PATH_TO_EXPOSE" ] && eval RESOLVED_HOST_PATH="$HOST_PATH_TO_EXPOSE"
    [ -d "$RESOLVED_HOST_PATH" ] && VOLUME_MAPPING="-v $RESOLVED_HOST_PATH:$RESOLVED_HOST_PATH"

    PODMAN_CONTAINER_ID=$(eval "podman run -d \
        --name gaia-podman-sandbox \
        --restart=no \
        --userns=keep-id \
        --net=host \
        --ipc=host \
        --user $(id -u):$(id -g) \
        --device /dev/dri:/dev/dri \
        --security-opt label=disable \
        $DISPLAY_FLAGS \
        $VOLUME_MAPPING \
        -e SNAP=\"/opt/gaia_runtime\" \
        -e TARGET_EXEC=\"/opt/gaia_runtime/opt/GAIA/gaia-desktop\" \
        -e HOME=\"/opt/gaia_runtime/workspace\" \
        -e GAIA_HOME=\"/opt/gaia_runtime/workspace/.gaia\" \
        -e TMPDIR=\"/opt/gaia_runtime/workspace/tmp\" \
        -e DISPLAY=\"$DISPLAY\" \
        -e WAYLAND_DISPLAY=\"$WAYLAND_DISPLAY\" \
        -e backend_url=\"$BACKEND_URL\" \
        -e backend_maxsteps=\"$AGENT_STEPS\" \
        -e keys_openai=\"$OPENAI_KEY\" \
        -e keys_anthropic=\"$ANTHROPIC_KEY\" \
        -e keys_groq=\"$GROQ_KEY\" \
        -e keys_tavily=\"$TAVILY_KEY\" \
        -e keys_serper=\"$SERPER_KEY\" \
        -e GAIA_NETWORK_RELIABILITY_LOG=\"${GAIA_NETWORK_RELIABILITY_LOG}\" \
        -e ALLOWED_PATHS=\"${RESOLVED_HOST_PATH}\" \
        -e allowed_paths=\"${RESOLVED_HOST_PATH}\" \
        -e GAIA_ALLOWED_PATHS=\"${RESOLVED_HOST_PATH}\" \
        'gaia-desktop:${GAIA_VERSION}'")

    if [ -z "$PODMAN_CONTAINER_ID" ]; then
        echo "ERROR: Failed to launch Podman container gaia-podman-sandbox."
        exit 1
    fi

    sleep 2
    if ! podman ps --format '{{.Names}}' | grep -qx 'gaia-podman-sandbox'; then
        echo "ERROR: Podman container gaia-podman-sandbox exited during startup."
        echo "INFO: Recent container logs:"
        podman logs --tail 120 gaia-podman-sandbox || true
        exit 1
    fi

        if [ -n "$RESOLVED_HOST_PATH" ]; then
                podman exec gaia-podman-sandbox /usr/bin/bash -lc "mkdir -p /opt/gaia_runtime/workspace/.gaia/cache && cat << 'EOF' > /opt/gaia_runtime/workspace/.gaia/cache/allowed_paths.json
{
    \"paths\": [
        \"/root\",
        \"${RESOLVED_HOST_PATH}\"
    ]
}
EOF"
        fi

    echo "INFO: Podman deployment started."

    # Create desktop launcher for Podman deployment
        PODMAN_LAUNCHER_CMD="if ! podman inspect gaia-podman-sandbox >/dev/null 2>&1; then echo 'Podman container not found. Run install_gaia.sh first.'; exit 1; fi; podman start gaia-podman-sandbox 2>/dev/null || true; sleep 1; podman exec -e DISPLAY=\"\${DISPLAY}\" gaia-podman-sandbox /usr/bin/gaia-launcher"
    create_desktop_launcher "gaia-podman" "$PODMAN_LAUNCHER_CMD" "GAIA Desktop (Podman Container)" "" "GAIA-Podman"
    echo "=========================================================================="
    echo "✅ Podman deployment complete!"
    echo "   GAIA is now available in your application menu as 'GAIA-Podman'"
    echo "   Launch from terminal shortcut: gaia-podman"
    echo "=========================================================================="

# ---------------------------------------------------------------------
# OPTION 5: Kubernetes manifest generation
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "5" ]]; then
    echo "====================================================================="
    echo " Kubernetes deployment manifest"
    echo "====================================================================="
    echo "To deploy this image to Kubernetes, apply the manifest below."
    echo "Ensure you tag and push your image to your cluster's private container registry:"
    echo "   docker tag gaia-desktop:${GAIA_VERSION} internal-registry.local/gaia-desktop:${GAIA_VERSION}"
    echo "   docker push internal-registry.local/gaia-desktop:${GAIA_VERSION}"
    echo "---------------------------------------------------------------------"

    cat << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gaia-desktop-deployment
  labels:
    app: gaia-desktop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gaia-desktop
  template:
    metadata:
      labels:
        app: gaia-desktop
    spec:
      hostNetwork: true
      containers:
      - name: gaia-desktop
        image: internal-registry.local/gaia-desktop:${GAIA_VERSION}
        securityContext:
          privileged: true
        env:
        - name: DISPLAY
          value: "${DISPLAY}"
        - name: backend_url
          value: "${BACKEND_URL}"
        - name: backend_maxsteps
          value: "${AGENT_STEPS}"
        - name: keys_openai
          value: "${OPENAI_KEY}"
        - name: keys_anthropic
          value: "${ANTHROPIC_KEY}"
        - name: keys_groq
          value: "${GROQ_KEY}"
        - name: keys_tavily
          value: "${TAVILY_KEY}"
        - name: keys_serper
          value: "${SERPER_KEY}"
        volumeMounts:
        - name: x11-socket
          mountPath: /tmp/.X11-unix
      volumes:
      - name: x11-socket
        hostPath:
          path: /tmp/.X11-unix
EOF
    echo "====================================================================="
fi