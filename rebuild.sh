#!/bin/bash
set -e

if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: rebuild.sh must be run with bash (for example: bash ./rebuild.sh)." >&2
    exit 2
fi

# =====================================================================
# ERROR HANDLING: Trap failures and clean up on interrupt
# =====================================================================
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Build failed (exit code: $exit_code)."
        echo "INFO: Cleaning up intermediate build artifacts."
        rm -rf src_rock 2>/dev/null || true
        rm -f *.rock 2>/dev/null || true
    fi
}

trap cleanup_on_exit EXIT
trap 'echo "INFO: Build interrupted by user."; exit 130' INT TERM

# =====================================================================
# VALIDATION: Check required tools before starting
# =====================================================================
validate_required_tools() {
    local missing_tools=()
    
    if ! command -v snapcraft &>/dev/null; then
        missing_tools+=("snapcraft")
    fi
    
    if ! command -v rockcraft &>/dev/null; then
        missing_tools+=("rockcraft")
    fi
    
    if ! command -v skopeo &>/dev/null; then
        echo "WARNING: skopeo not found. Docker image generation will be skipped."
        echo "    Install with: sudo apt install skopeo"
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "ERROR: Required tools not found: ${missing_tools[*]}"
        echo ""
        echo "Install required tools with:"
        echo "  sudo apt install snapcraft rockcraft"
        exit 1
    fi
}

# =====================================================================
# VALIDATION: Validate version format (semver)
# =====================================================================
validate_version_format() {
    if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: Invalid version format: $1"
        echo "   Version must be in semantic versioning format (e.g., 0.20.0)"
        exit 1
    fi
}

GLOBAL_START_TIME=$SECONDS

# =====================================================================
# Build configuration
# =====================================================================
export CRAFT_PARALLEL_BUILD_COUNT=2

# Optional host tuning commands (disabled by default)
sudo apt install cpulimit
powerprofilesctl set power-saver
# powerprofilesctl set performance

# =====================================================================
# GLOBAL WORKSPACE VARIABLE DEFINITIONS
# =====================================================================
GLOBAL_DEFAULT_VERSION="0.20.0"

VERSION_CACHE_FILE=".last_version"
GAIA_VERSION=""

# 1. Parse incoming command-line arguments
TEMP_ARGS=()
for arg in "$@"; do
    case $arg in
        --gaia-version=*)
            GAIA_VERSION="${arg#*=}"
            ;;
        *)
            TEMP_ARGS+=("$arg")
            ;;
    esac
done
set -- "${TEMP_ARGS[@]}"

# 2. Fall back to interactive cache loop if no flag was passed
if [ -z "$GAIA_VERSION" ]; then
    if [ -f "$VERSION_CACHE_FILE" ]; then
        DEFAULT_VERSION=$(cat "$VERSION_CACHE_FILE")
    else
        DEFAULT_VERSION="$GLOBAL_DEFAULT_VERSION"
    fi

    echo "=================================================="
    read -p "Enter target GAIA version [$DEFAULT_VERSION]: " USER_VERSION
    echo "=================================================="

    GAIA_VERSION=${USER_VERSION:-$DEFAULT_VERSION}
fi

# 3. Save final version state
echo "$GAIA_VERSION" > "$VERSION_CACHE_FILE"
echo "INFO: Starting build pipeline for GAIA version: $GAIA_VERSION"

# Validate version format and required tools before proceeding
validate_version_format "$GAIA_VERSION"
validate_required_tools

# =====================================================================
# UNIFIED METADATA PATCHING MATRIX (DRY LOOP)
# =====================================================================
patch_file() {
    local file=$1 search=$2 replace=$3 label=$4
    if [ -f "$file" ]; then
        echo "INFO: Updating $file ($label) to: $GAIA_VERSION"
        sed -i "s|$search|$replace|g" "$file"
    else
        echo "WARNING: $file not found, skipping."
    fi
}

patch_file "snap/snapcraft.yaml" "VERSION_TAG=\".*\"" "VERSION_TAG=\"$GAIA_VERSION\"" "target version"
patch_file "rockcraft.yaml" "version: &global_version \".*\"" "version: \&global_version \"$GAIA_VERSION\"" "anchor version"
patch_file "install_gaia.sh" "GAIA_VERSION=\".*\"" "GAIA_VERSION=\"$GAIA_VERSION\"" "target release"
patch_file "README.md" "GAIA Version:\*\* Current version: [0-9.]*" "GAIA Version:\*\* Current version: $GAIA_VERSION" "documentation header"
patch_file "README.md" "gaia-desktop_[0-9.]*_LXD-sandbox\.tar\.gz" "gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz" "asset naming layout"
patch_file "gaia-launcher.sh" "version\": \".*\"" "version\": \"$GAIA_VERSION\"" "launcher json version"

# =====================================================================
# Build flag parsing
# =====================================================================
BUILD_SNAP=false
BUILD_OCI=false
BUILD_DOCKER=false
BUILD_LXD=false

if [ $# -eq 0 ]; then
    BUILD_SNAP=true
    BUILD_OCI=true
    BUILD_DOCKER=true
    BUILD_LXD=true
else
    while [ $# -gt 0 ]; do
        case "$1" in
            --snap)   BUILD_SNAP=true ;;
            --oci)    BUILD_OCI=true ;;
            --docker) BUILD_DOCKER=true ;;
            --lxd)    BUILD_LXD=true ;;
            *) echo "ERROR: Unknown parameter: $1. Valid flags: --snap, --oci, --docker, --lxd" >&2; exit 1 ;;
        esac
        shift
    done
fi

# =====================================================================
# SYSTEM PARAMETER & CLEANUP ROUTINES
# =====================================================================
echo "INFO: Validating administrative prerequisites."
if ! sudo -n true 2>/dev/null; then
    echo "INFO: Administrative privileges required."
    sudo true
fi
sudo -v

if [ "$BUILD_SNAP" = true ]; then
    echo "INFO: Cleaning previous Snap build outputs."
    sudo rm -f *.snap
    sudo snapcraft clean gaia-desktop --step=prime >/dev/null 2>&1 || true
    sudo snapcraft clean gaia-backend --step=prime >/dev/null 2>&1 || true
fi

if [ "$BUILD_OCI" = true ] || [ "$BUILD_DOCKER" = true ]; then
    echo "INFO: Cleaning previous OCI/Rock build outputs."
    sudo rm -f *.rock
fi

if [ "$BUILD_DOCKER" = true ]; then
    echo "INFO: Cleaning previous Docker image layers."
    docker rmi -f "gaia-desktop:${GAIA_VERSION}" >/dev/null 2>&1 || true
fi

stty sane || true
clear

echo "====================================================="
echo "BUILD TARGET EXECUTION"
echo "====================================================="

TIME_SNAP="Skipped"
TIME_ROCK="Skipped"
TIME_DOCKER="Skipped"
TIME_LXD="Skipped"

# ---------------------------------------------------------------------
# Target 1: Snap package
# ---------------------------------------------------------------------
if [ "$BUILD_SNAP" = true ] || [ "$BUILD_OCI" = true ] || [ "$BUILD_DOCKER" = true ]; then
    START_SNAP=$SECONDS
    echo "INFO: Building Snap package from workspace."

    # Ensure launcher has executable permissions in place natively
    chmod +x gaia-launcher.sh

    echo "INFO: Running snapcraft pack."
    snapcraft pack

    DIFF_SNAP=$((SECONDS - START_SNAP))
    TIME_SNAP="$((DIFF_SNAP / 60))m $((DIFF_SNAP % 60))s"
fi

SNAP_PACKAGE=$(ls -t *.snap 2>/dev/null | head -n 1 || true)

# ---------------------------------------------------------------------
# Target 2: OCI rock image
# ---------------------------------------------------------------------
if [ "$BUILD_OCI" = true ] || [ "$BUILD_DOCKER" = true ]; then
    START_ROCK=$SECONDS
    echo "INFO: Preparing temporary staging directory for rockcraft."
    rm -rf src_rock
    mkdir -p src_rock

    if [ -n "${SNAP_PACKAGE}" ] && [ -f "${SNAP_PACKAGE}" ]; then
        cp "${SNAP_PACKAGE}" src_rock/
    fi

    echo "INFO: Running rockcraft pack."
    rockcraft pack
    rm -rf src_rock

    DIFF_ROCK=$((SECONDS - START_ROCK))
    TIME_ROCK="$((DIFF_ROCK / 60))m $((DIFF_ROCK % 60))s"
fi

ROCK_FILE=$(ls -t *.rock 2>/dev/null | head -n 1 || true)

# ---------------------------------------------------------------------
# Target 3: Docker archive/image
# ---------------------------------------------------------------------
if [ "$BUILD_DOCKER" = true ]; then
    START_DOCKER=$SECONDS
    echo "INFO: Validating OCI rock artifact for Docker conversion."
    if [ -z "${ROCK_FILE}" ]; then
        echo "ERROR: Docker target requires a pre-built local OCI .rock artifact."
        exit 1
    fi

    if ! command -v skopeo &> /dev/null; then
        echo "INFO: Installing skopeo dependency."
        sudo apt-get update && sudo apt-get install -y skopeo >/dev/null 2>&1
    fi

    DOCKER_OUTPUT_NAME="gaia-desktop_${GAIA_VERSION}_docker-image.tar"
    echo "INFO: Converting OCI archive to Docker archive."
    rm -f "./${DOCKER_OUTPUT_NAME}"

    skopeo copy "oci-archive:${ROCK_FILE}" "docker-archive:./${DOCKER_OUTPUT_NAME}:gaia-desktop:${GAIA_VERSION}"

    if [ -x "$(command -v docker)" ]; then
        echo "INFO: Loading Docker archive into local Docker daemon."
        docker load -i "./${DOCKER_OUTPUT_NAME}"
    fi

    echo "INFO: OCI archive converted to Docker image archive."

    DIFF_DOCK=$((SECONDS - START_DOCKER))
    TIME_DOCK="$((DIFF_DOCK / 60))m $((DIFF_DOCK % 60))s"
fi

# ---------------------------------------------------------------------
# Target 4: LXD sandbox image
# ---------------------------------------------------------------------
if [ "$BUILD_LXD" = true ]; then
    START_LXD=$SECONDS
    echo "INFO: Validating LXD availability."
    if ! command -v lxc &> /dev/null; then
        echo "ERROR: LXD command-line interface (lxc) not found."
        exit 1
    fi

    if [ -z "${SNAP_PACKAGE}" ]; then
        echo "ERROR: LXD target requires a pre-built local snap package artifact."
        exit 1
    fi

    echo "INFO: Removing previous LXD worker/image state."
    lxc delete gaia-worker --force >/dev/null 2>&1 || true
    lxc image delete "gaia-desktop/${GAIA_VERSION}" >/dev/null 2>&1 || true

    echo "INFO: Launching temporary Ubuntu 24.04 LXD worker container."
    lxc launch ubuntu:24.04 gaia-worker -c security.nesting=true -c security.privileged=false
    lxc config device add gaia-worker GPU gpu gid=44 >/dev/null 2>&1 || true

    lxc config device add gaia-worker X0 proxy \
        listen=unix:@/tmp/.X11-unix/X0 \
        connect=unix:@/tmp/.X11-unix/X0 \
        bind=container security.uid=0 security.gid=0 >/dev/null 2>&1 || true

    # Add Lemonade Server proxy (configurable via LEMONADE_URL env var, defaults to localhost:13305)
    LEMONADE_URL="${LEMONADE_URL:-http://127.0.0.1:13305}"
    LEMONADE_HOST_PORT="${LEMONADE_URL#http://}"
    LEMONADE_HOST_PORT="${LEMONADE_HOST_PORT#https://}"
    LEMONADE_HOST="${LEMONADE_HOST_PORT%%:*}"
    LEMONADE_PORT="${LEMONADE_HOST_PORT##*:}"
    if [ "$LEMONADE_PORT" = "$LEMONADE_HOST_PORT" ]; then
        LEMONADE_PORT="13305"
    fi

    lxc config device add gaia-worker lemonade-server proxy \
        listen=tcp:${LEMONADE_HOST}:${LEMONADE_PORT} \
        connect=tcp:${LEMONADE_HOST}:${LEMONADE_PORT} \
        bind=container >/dev/null 2>&1 || true

    lxc exec gaia-worker -- apt-get update -y >/dev/null 2>&1
    lxc exec gaia-worker -- apt-get install -y \
        snapd libatk1.0-0 libatk-bridge2.0-0 libxcomposite1 libxdamage1 \
        libgl1 libgtk-3-0 libasound2t64 libnspr4 libnss3 >/dev/null 2>&1

    cat "$SNAP_PACKAGE" | lxc exec gaia-worker -- sh -c "cat > /tmp/gaia.snap"
    lxc exec gaia-worker -- snap install --classic --dangerous /tmp/gaia.snap

    lxc stop gaia-worker || lxc stop gaia-worker --force
    sleep 1

    LXD_OUTPUT_NAME="gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz"
    rm -f "./${LXD_OUTPUT_NAME}"
    lxc export gaia-worker "./${LXD_OUTPUT_NAME}"

    lxc delete gaia-worker --force >/dev/null 2>&1 || true

    DIFF_LXD=$((SECONDS - START_LXD))
    TIME_LXD="$((DIFF_LXD / 60))m $((DIFF_LXD % 60))s"
fi

# =====================================================================
# PERMISSION HARDENING MATRIX
# =====================================================================
echo "INFO: Applying permissions to generated artifacts."
chmod 755 gaia-launcher.sh install_gaia.sh cleanup.sh rebuild.sh || true

[ -n "${SNAP_PACKAGE}" ] && sudo chmod 644 "${SNAP_PACKAGE}" && sudo chown $(id -u):$(id -g) "${SNAP_PACKAGE}"
[ -n "${ROCK_FILE}" ]   && sudo chmod 644 "${ROCK_FILE}"   && sudo chown $(id -u):$(id -g) "${ROCK_FILE}"

if [ -f "./gaia-desktop_${GAIA_VERSION}_docker-image.tar" ]; then
    sudo chmod 644 "./gaia-desktop_${GAIA_VERSION}_docker-image.tar"
    sudo chown $(id -u):$(id -g) "./gaia-desktop_${GAIA_VERSION}_docker-image.tar"
fi

if [ -f "./gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz" ]; then
    sudo chmod 644 "./gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz"
    sudo chown $(id -u):$(id -g) "./gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz"
fi

echo "====================================================="
echo "Build completed."
echo "====================================================="
[ -n "${SNAP_PACKAGE}" ]   && echo "Snap package: ./${SNAP_PACKAGE} (${TIME_SNAP})"
[ -n "${ROCK_FILE}" ]     && echo "OCI rock: ./${ROCK_FILE} (${TIME_ROCK})"
[ -f "./gaia-desktop_${GAIA_VERSION}_docker-image.tar" ] && echo "Docker archive: ./gaia-desktop_${GAIA_VERSION}_docker-image.tar (${TIME_DOCK})"
[ -f "./gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz" ] && echo "LXD archive: ./gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz (${TIME_LXD})"
echo "-----------------------------------------------------"

GLOBAL_DURATION=$((SECONDS - GLOBAL_START_TIME))
echo "Build completed successfully in $((GLOBAL_DURATION / 60))m $((GLOBAL_DURATION % 60))s."
echo ""

if [ "$BUILD_SNAP" = true ] || [ "$BUILD_OCI" = true ]; then
    echo "INFO: Cleaning temporary build resources."
    sudo snapcraft clean --step=prime >/dev/null 2>&1 || true
    sudo snapcraft clean --step=stage >/dev/null 2>&1 || true

    for instance in $(lxc list -c n --format csv 2>/dev/null | grep -E "snapcraft-|rockcraft-" || true); do
        lxc delete "$instance" --force >/dev/null 2>&1 || true
    done
fi

echo "Next step: run ./install_gaia.sh to configure and launch a target topology."