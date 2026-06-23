#!/bin/bash
set -e

# =====================================================================
# GLOBAL CONFIGURATION CONFIG/VERSION VARIABLES
# =====================================================================
GAIA_VERSION="0.20.0"  # Centralized single source of truth for installations

# Capture the absolute path of the directory where the script is located
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =====================================================================
# PHASE 1: FRONTLOADED USER INTERACTIVE DATA COLLECTION
# =====================================================================

clear
echo "====================================================================="
echo "        GAIA ULTRA-PORTABLE EMULATED DEPLOYMENT WORKSTATION"
echo "====================================================================="
echo " Select your target deployment topology execution framework:"
echo "    1) Native Ubuntu Desktop Application (Snap Layer)"
echo "    2) Secure Isolated System Container Sandbox (LXD Engine)"
echo "    3) Dedicated Standalone Desktop Sandbox (Docker Engine)"
echo "    4) Rootless OCI Process Container Sandbox (Podman Engine)"
echo "    5) Enterprise Production Orchestration Blueprint (Kubernetes Core)"
echo "---------------------------------------------------------------------"

read -p " Enter Choice (1-5): " TOPOLOGY_CHOICE

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
# 🎯 INTELLIGENT WORKSPACE MOUNT DETECTION & STAGING ENGINE
# =====================================================================
IS_REMOTE_MOUNT=false
LOCAL_TAR_STAGE=""

# Detect if the workspace directory is parked on a network mount
if [[ "$WORKSPACE_DIR" == /mnt/userver* ]]; then
    echo "---------------------------------------------------------------------"
    echo "💡 DETECTED: Script running inside a remote network mount partition."
    echo "             Activating isolated local asset caching layer..."
    echo "---------------------------------------------------------------------"
    IS_REMOTE_MOUNT=true
    LOCAL_TAR_STAGE="/tmp/gaia-desktop_${GAIA_VERSION}_docker-image.tar"

    # Pre-flight scp transfer onto your Zenbook's native local SSD storage
    if [[ "$TOPOLOGY_CHOICE" =~ ^(3|4)$ ]]; then
        if [ ! -f "$LOCAL_TAR_STAGE" ]; then
            echo "LOG: Fetching large deployment archive securely over network link..."
            scp kevin@userver:/mnt/md0/backups/SoftwareDev/gaia-snap/gaia-desktop_${GAIA_VERSION}_docker-image.tar "$LOCAL_TAR_STAGE"
        else
            echo "LOG: Utilizing existing local target cache: $LOCAL_TAR_STAGE"
        fi
    fi
fi

# Locate local artifacts cleanly within the absolute workspace context
SNAP_PACKAGE=$(ls "${WORKSPACE_DIR}"/*.snap 2>/dev/null | head -n 1 || true)
LXD_TARBALL=$(ls "${WORKSPACE_DIR}"/*LXD-sandbox.tar.gz 2>/dev/null | head -n 1 || true)

# Resolve target container pathing based on current topology placement
if [ "$IS_REMOTE_MOUNT" = true ]; then
    DOCKER_TARBALL="$LOCAL_TAR_STAGE"
else
    DOCKER_TARBALL=$(ls "${WORKSPACE_DIR}"/*docker-image.tar 2>/dev/null | head -n 1 || true)
fi

# =====================================================================
# PHASE 2: ATOMIC TOPOLOGY CONFIGURATION MACHINE EXECUTION
# =====================================================================

# ---------------------------------------------------------------------
# OPTION 1: NATIVE DESKTOP SNAP ENVIRONMENT DEPLOYMENT
# ---------------------------------------------------------------------
if [[ "$TOPOLOGY_CHOICE" == "1" ]]; then
    echo "LOG: Initializing Native Ubuntu Desktop Snap Layer Installation..."
    if [ -z "$SNAP_PACKAGE" ]; then
        echo "❌ ERROR: No local .snap artifact found in the working directory."
        exit 1
    fi
    sudo snap install "$SNAP_PACKAGE" --dangerous --classic
    sudo snap set gaia-desktop backend.url="$BACKEND_URL" backend.maxsteps="$AGENT_STEPS" keys.openai="$OPENAI_KEY" keys.anthropic="$ANTHROPIC_KEY" keys.groq="$GROQ_KEY" keys.tavily="$TAVILY_KEY" keys.serper="$SERPER_KEY"
    echo "✨ SUCCESS: GAIA Snap Topology Installed Successfully!"

# ---------------------------------------------------------------------
# OPTION 2: SECURE ISOLATED LXD SANDBOX SYSTEM CONTAINER
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "2" ]]; then
    echo "LOG: Deploying Secure Isolated LXD Sandbox System Container..."
    if ! command -v lxc &> /dev/null; then
        echo "❌ ERROR: LXD CLI utility not found on this system."
        exit 1
    fi

    if [ -z "${LXD_TARBALL}" ]; then
        if ! lxc info gaia-runtime-sandbox >/dev/null 2>&1; then
            echo "❌ ERROR: Portable archive 'gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz' not found."
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

    echo "LOG: Mapping local host display socket channels directly into container frame..."
    xhost +local: >/dev/null 2>&1 || true
    lxc config device remove gaia-runtime-sandbox X11-Display-Socket >/dev/null 2>&1 || true
    sudo mkdir -p /tmp/.X11-unix && sudo chmod 1777 /tmp/.X11-unix
    lxc config device add gaia-runtime-sandbox X11-Display-Socket disk source=/tmp/.X11-unix path=/tmp/.X11-unix

    echo "LOG: Settling container subsystems..."
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
    echo "🚀 BOOTING GAIA WORKSTATION VIA LXD CONTAINER SANDBOX"
    echo "=========================================================================="
    lxc exec gaia-runtime-sandbox -- env \
        DISPLAY="${DISPLAY:-:0}" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
        XDG_RUNTIME_DIR="/tmp" \
        ALLOWED_PATHS="${RESOLVED_HOST_PATH}" \
        allowed_paths="${RESOLVED_HOST_PATH}" \
        GAIA_ALLOWED_PATHS="${RESOLVED_HOST_PATH}" \
        /snap/bin/gaia-desktop --no-sandbox

# ---------------------------------------------------------------------
# OPTION 3: DEDICATED STANDALONE DESKTOP SANDBOX (DOCKER ENGINE)
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "3" ]]; then
    echo "====================================================================="
    echo " LOG: Deploying Chiseled OCI Rock via Docker Engine..."
    echo "====================================================================="
    if ! command -v docker &> /dev/null; then
        echo "❌ ERROR: Docker CLI engine tool not found on this system."
        exit 1
    fi

    if [ -n "${DOCKER_TARBALL}" ]; then
        if [ "$IS_REMOTE_MOUNT" = false ]; then
            echo "LOG: Streaming archive directly onto local storage partition via rsync..."
            rsync -ah --progress "${DOCKER_TARBALL}" /tmp/gaia-docker-stage.tar
            LOCAL_STAGE_FILE="/tmp/gaia-docker-stage.tar"
        else
            LOCAL_STAGE_FILE="$DOCKER_TARBALL"
        fi

        echo "LOG: Loading native structural OCI-transposed archive image layout via socket pipe..."
        cat "$LOCAL_STAGE_FILE" | docker load

        # Keep things clean on your laptop's local partition
        [ "$IS_REMOTE_MOUNT" = false ] && rm -f /tmp/gaia-docker-stage.tar
    fi

    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^gaia-desktop:${GAIA_VERSION}$"; then
        echo "❌ ERROR: Image gaia-desktop:${GAIA_VERSION} was not registered inside your local daemon."
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
    echo " 🚀 BOOTING GAIA DESKTOP APPLICATION VIA DOCKER PROCESS SANDBOX"
    echo "=========================================================================="
    xhost +local:docker

    eval "docker run -d \
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
        -e GAIA_ALLOWED_PATHS=\"${RESOLVED_HOST_PATH}\" \
        'gaia-desktop:${GAIA_VERSION}'"

    echo "🎉 SUCCESS: Chiseled OCI Rock deployed via Docker process containment!"

# ---------------------------------------------------------------------
# OPTION 4: ROOTLESS APPLICATION PROCESS CONTAINER (PODMAN ENGINE)
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "4" ]]; then
    echo "LOG: Deploying Rootless OCI Process Container Sandbox via Podman Engine..."
    if ! command -v podman &> /dev/null; then
        echo "❌ ERROR: Podman engine execution footprint not detected."
        exit 1
    fi

    if [ -n "${DOCKER_TARBALL}" ]; then
        if [ "$IS_REMOTE_MOUNT" = false ]; then
            echo "LOG: Streaming archive directly onto local storage partition via rsync..."
            rsync -ah --progress "${DOCKER_TARBALL}" /tmp/gaia-podman-stage.tar
            LOCAL_STAGE_FILE="/tmp/gaia-podman-stage.tar"
        else
            LOCAL_STAGE_FILE="$DOCKER_TARBALL"
        fi

        echo "LOG: Unpacking OCI-archive image structures natively via socket pipe..."
        cat "$LOCAL_STAGE_FILE" | podman load

        [ "$IS_REMOTE_MOUNT" = false ] && rm -f /tmp/gaia-podman-stage.tar
    fi

    podman rm -f gaia-podman-sandbox >/dev/null 2>&1 || true
    xhost +local:root >/dev/null 2>&1 || true

    VOLUME_MAPPING=""
    [ -n "$HOST_PATH_TO_EXPOSE" ] && eval RESOLVED_HOST_PATH="$HOST_PATH_TO_EXPOSE"
    [ -d "$RESOLVED_HOST_PATH" ] && VOLUME_MAPPING="-v $RESOLVED_HOST_PATH:$RESOLVED_HOST_PATH:Z"

    eval "podman run -d \
        --name gaia-podman-sandbox \
        --net=host \
        --ipc=host \
        --security-opt label=disable \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
        $VOLUME_MAPPING \
        -e backend_url=\"$BACKEND_URL\" \
        -e backend_maxsteps=\"$AGENT_STEPS\" \
        -e keys_openai=\"$OPENAI_KEY\" \
        -e keys_anthropic=\"$ANTHROPIC_KEY\" \
        -e keys_groq=\"$GROQ_KEY\" \
        -e keys_tavily=\"$TAVILY_KEY\" \
        -e keys_serper=\"$SERPER_KEY\" \
        'gaia-desktop:${GAIA_VERSION}'"

    echo "🎉 SUCCESS: OCI Rock deployed via Podman cleanly!"

# ---------------------------------------------------------------------
# OPTION 5: ENTERPRISE PRODUCTION ORCHESTRATION BLUEPRINT (KUBERNETES)
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "5" ]]; then
    echo "====================================================================="
    echo " 🚀 KUBERNETES DEPLOYMENT MANIFEST ENGINE MANIFEST"
    echo "====================================================================="
    echo "To deploy your chiseled OCI Rock into Kubernetes, apply the manifest below."
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