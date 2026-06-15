#!/bin/bash
set -e

# =====================================================================
# GLOBAL CONFIGURATION CONFIG/VERSION VARIABLES
# =====================================================================
GAIA_VERSION="0.20.0"  # Centralized single source of truth for installations

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
echo "    3) Bare Application Process Container (Docker Engine) [Roadmap]"
echo "    4) Rootless Application Process Container (Podman Engine) [Roadmap]"
echo "---------------------------------------------------------------------"

read -p " Enter Choice (1-4): " TOPOLOGY_CHOICE

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

# Handle Expose Directory Parameter for Choice 2 immediately while user is present
EXPOSE_HOST_DIR="n"
HOST_PATH_TO_EXPOSE=""
if [[ "$TOPOLOGY_CHOICE" == "2" ]]; then
    echo "---------------------------------------------------------------------"
    echo " The LXD Sandbox Container is isolated from your host filesystem."
    read -p " Expose a host directory to the sandboxed GAIA environment? (y/N): " EXPOSE_HOST_DIR
    if [[ "$EXPOSE_HOST_DIR" =~ ^[Yy]$ ]]; then
        read -p " Enter absolute host path to expose (e.g., /home/kevin/Workspace): " HOST_PATH_TO_EXPOSE
    fi
fi

# Locate local artifacts universally using wildcard patterns
SNAP_PACKAGE=$(ls *.snap 2>/dev/null | head -n 1 || true)
LXD_TARBALL=$(ls *LXD-sandbox.tar.gz 2>/dev/null | head -n 1 || true)

# =====================================================================
# PHASE 2: ATOMIC TOPOLOGY CONFIGURATION MACHINE EXECUTION
# =====================================================================

# ---------------------------------------------------------------------
# OPTION 1: NATIVE DESKTOP SNAP ENVIRONMENT DEPLOYMENT
# ---------------------------------------------------------------------
if [[ "$TOPOLOGY_CHOICE" == "1" ]]; then
    echo "====================================================================="
    echo " LOG: Initializing Native Ubuntu Desktop Snap Layer Installation..."
    echo "====================================================================="

    if [ -z "$SNAP_PACKAGE" ]; then
        echo "❌ ERROR: No local .snap artifact found in the working directory."
        echo "Please execute your compilation script first or fetch a signed build."
        exit 1
    fi

    echo "LOG: Detected snap artifact '$SNAP_PACKAGE'. Installing with dangerous flags..."
    sudo snap install "$SNAP_PACKAGE" --dangerous --classic

    echo "LOG: Synchronizing native Snap configuration parameters database..."
    sudo snap set gaia-desktop backend.url="$BACKEND_URL"
    sudo snap set gaia-desktop backend.maxsteps="$AGENT_STEPS"
    sudo snap set gaia-desktop keys.openai="$OPENAI_KEY"
    sudo snap set gaia-desktop keys.anthropic="$ANTHROPIC_KEY"
    sudo snap set gaia-desktop keys.groq="$GROQ_KEY"
    sudo snap set gaia-desktop keys.tavily="$TAVILY_KEY"
    sudo snap set gaia-desktop keys.serper="$SERPER_KEY"

    echo "====================================================================="
    echo " ✨ SUCCESS: GAIA Snap Topology Installed Successfully!"
    echo "====================================================================="

# ---------------------------------------------------------------------
# OPTION 2: SECURE ISOLATED SYSTEM CONTAINER SANDBOX (LXD ENGINE)
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "2" ]]; then
    echo "====================================================================="
    echo " LOG: Deploying Secure Isolated LXD Sandbox System Container..."
    echo "====================================================================="

    # 1. Verify local LXD subsystem availability
    if ! command -v lxc &> /dev/null; then
        echo "❌ ERROR: LXD command line interface tool not found on this system."
        echo "Please configure your host via: sudo snap install lxd && sudo lxd init --auto"
        exit 1
    fi

    # 2. Process container image validations & incremental timestamp upgrades
    if [ -z "${LXD_TARBALL}" ]; then
        if ! lxc info gaia-runtime-sandbox >/dev/null 2>&1; then
            echo "❌ ERROR: Portable archive 'gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz' not found in workspace."
            echo "Please place the pre-baked tarball artifact here or compile it using: ./rebuild.sh --snap --lxd"
            exit 1
        fi
        echo "LOG: Running deployment from existing pre-registered container instance block."
    else
        FILE_M_TIME=$(stat -c %Y "./${LXD_TARBALL}")
        LAST_M_TIME=$(cat ~/.gaia/.sandbox_timestamp 2>/dev/null || echo "0")

        # Evict existing instance if a fresh container tarball is dropped into the directory
        if lxc info gaia-runtime-sandbox >/dev/null 2>&1 && [ "${FILE_M_TIME}" != "${LAST_M_TIME}" ]; then
            echo "LOG: 🔄 Detected a fresh update to ./${LXD_TARBALL}. Evicting stale container instance..."
            lxc delete gaia-runtime-sandbox --force >/dev/null 2>&1 || true
        fi

        # Materialize container layout directly from backup stream if not present
        if ! lxc info gaia-runtime-sandbox >/dev/null 2>&1; then
            echo "LOG: Materializing container instance from compressed standalone backup: ./${LXD_TARBALL}"
            lxc import "./${LXD_TARBALL}" gaia-runtime-sandbox
            mkdir -p ~/.gaia/
            echo "${FILE_M_TIME}" > ~/.gaia/.sandbox_timestamp || true
            echo "LOG: Sandbox container infrastructure imported successfully."
        fi
    fi

    # 3. Boot the standalone sandbox instance container cleanly
    echo "LOG: Booting up the standalone sandbox instance container..."
    lxc start gaia-runtime-sandbox || true
    sleep 2

    # 4. Handle dynamic host directory pass-through mapping
    RESOLVED_HOST_PATH=""
    if [ -n "$HOST_PATH_TO_EXPOSE" ]; then
        eval RESOLVED_HOST_PATH="$HOST_PATH_TO_EXPOSE"

        if [ -d "$RESOLVED_HOST_PATH" ]; then
            echo "LOG: Mirroring absolute host path structural blueprint '$RESOLVED_HOST_PATH' into sandbox..."

            # Wipe out old structural disk maps to prevent device naming conflicts
            lxc config device remove gaia-runtime-sandbox host-workspace >/dev/null 2>&1 || true

            # Materialize path blueprints natively inside container namespace
            lxc exec gaia-runtime-sandbox -- mkdir -p "$RESOLVED_HOST_PATH"
            lxc config device add gaia-runtime-sandbox host-workspace disk source="$RESOLVED_HOST_PATH" path="$RESOLVED_HOST_PATH"
            lxc config set gaia-runtime-sandbox raw.idmap "both 1000 1000"

            echo "LOG: Rebooting sandbox engine to settle kernel space maps..."
            lxc restart gaia-runtime-sandbox
            sleep 3
        else
            echo "⚠️ WARNING: Provided host path '$RESOLVED_HOST_PATH' does not exist. Skipping custom mirror mapping."
            RESOLVED_HOST_PATH=""
        fi
    fi

    # 5. Authorize loopback graphical transactions on local X server
    xhost +local: >/dev/null 2>&1 || true

    # 6. Synchronize configuration keys directly into internal Snap database
    echo "LOG: Populating native nested Snap configuration engine database..."
    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop backend.url="$BACKEND_URL"
    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop backend.maxsteps="$AGENT_STEPS"
    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop keys.openai="$OPENAI_KEY"
    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop keys.anthropic="$ANTHROPIC_KEY"
    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop keys.groq="$GROQ_KEY"
    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop keys.tavily="$TAVILY_KEY"
    lxc exec gaia-runtime-sandbox -- snap set gaia-desktop keys.serper="$SERPER_KEY"

    # 7. Provision paths validation cache JSON to satisfy internal security policies
    if [ -n "$RESOLVED_HOST_PATH" ]; then
        echo "LOG: Provisioning application-level security path cache exceptions..."
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

    echo "LOG: All infrastructure synchronized successfully!"
    echo "=========================================================================="
    echo "🚀 BOOTING GAIA WORKSTATION PORTABLY VIA LXD CONTAINER SANDBOX"
    echo "=========================================================================="

    # 8. Start the execution app interface with environment parameters
    lxc exec gaia-runtime-sandbox -- env \
        DISPLAY=:0 \
        ALLOWED_PATHS="${RESOLVED_HOST_PATH}" \
        allowed_paths="${RESOLVED_HOST_PATH}" \
        GAIA_ALLOWED_PATHS="${RESOLVED_HOST_PATH}" \
        /snap/bin/gaia-desktop --no-sandbox

# ---------------------------------------------------------------------
# ROADMAP TOPOLOGIES
# ---------------------------------------------------------------------
elif [[ "$TOPOLOGY_CHOICE" == "3" ]]; then
    echo "LOG: Docker topology blueprint selected. Current state: Under construction."
    exit 0
elif [[ "$TOPOLOGY_CHOICE" == "4" ]]; then
    echo "LOG: Podman topology blueprint selected. Current state: Under construction."
    exit 0
else
    echo "❌ ERROR: Invalid choice selected ($TOPOLOGY_CHOICE). Exiting execution frame."
    exit 1
fi