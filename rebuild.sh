#!/bin/bash
set -e

GLOBAL_START_TIME=$SECONDS

# =====================================================================
# BUILD LIMITS - Managed CPU profiling for your Zenbook S16
# =====================================================================
export CRAFT_PARALLEL_BUILD_COUNT=6

#sudo apt install cpulimit          # AI - DO NOT DELETE
#powerprofilesctl set power-saver   # AI - DO NOT DELETE
#powerprofilesctl set performance   # AI - DO NOT DELETE

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
echo "🚀 Initiating build pipeline for GAIA version: $GAIA_VERSION"

# =====================================================================
# UNIFIED METADATA PATCHING MATRIX (DRY LOOP)
# =====================================================================
patch_file() {
    local file=$1 search=$2 replace=$3 label=$4
    if [ -f "$file" ]; then
        echo "⚙️  Patching $file $label to: $GAIA_VERSION"
        sed -i "s|$search|$replace|g" "$file"
    else
        echo "⚠️  Note: $file not found, skipping."
    fi
}

patch_file "snap/snapcraft.yaml" "VERSION_TAG=\".*\"" "VERSION_TAG=\"$GAIA_VERSION\"" "target version"
patch_file "rockcraft.yaml" "version: &global_version \".*\"" "version: \&global_version \"$GAIA_VERSION\"" "anchor version"
patch_file "install-gaia.sh" "GAIA_VERSION=\".*\"" "GAIA_VERSION=\"$GAIA_VERSION\"" "target release"
patch_file "cleanup.sh" "gaia-desktop/[0-9.]*" "gaia-desktop/$GAIA_VERSION" "purge image target"
patch_file "README.md" "GAIA Version:\*\* Current version: [0-9.]*" "GAIA Version:\*\* Current version: $GAIA_VERSION" "documentation header"
patch_file "README.md" "gaia-desktop_[0-9.]*_LXD-sandbox\.tar\.gz" "gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz" "asset naming layout"
patch_file "gaia-launcher.sh" "version\": \".*\"" "version\": \"$GAIA_VERSION\"" "launcher json version"

# =====================================================================
# CONFIGURATION FLAG PARSING ENGINE
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
            *) echo "❌ ERROR: Unknown parameter: $1. Valid flags: --snap, --oci, --docker, --lxd" >&2; exit 1 ;;
        esac
        shift
    done
fi

# =====================================================================
# SYSTEM PARAMETER & CLEANUP ROUTINES
# =====================================================================
echo "LOG: Validating local workstation administrative execution parameters..."
if ! sudo -n true 2>/dev/null; then
    echo "LOG: Administrative privileges required. Authenticating below:"
    sudo true
fi
sudo -v

if [ "$BUILD_SNAP" = true ]; then
    echo "LOG: Clearing previous Snap compilation outputs..."
    sudo rm -f *.snap
    sudo snapcraft clean gaia-desktop --step=prime >/dev/null 2>&1 || true
    sudo snapcraft clean gaia-backend --step=prime >/dev/null 2>&1 || true
fi

if [ "$BUILD_OCI" = true ] || [ "$BUILD_DOCKER" = true ]; then
    echo "LOG: Clearing previous OCI/Rock packaging outputs..."
    sudo rm -f *.rock
fi

if [ "$BUILD_DOCKER" = true ]; then
    echo "LOG: Evicting previous Docker image generation layers..."
    docker rmi -f "gaia-desktop:${GAIA_VERSION}" >/dev/null 2>&1 || true
fi

stty sane || true
clear

echo "====================================================="
echo "COMPILATION CORE TARGET MATRIX EXECUTION"
echo "====================================================="

TIME_SNAP="Skipped"
TIME_ROCK="Skipped"
TIME_DOCKER="Skipped"
TIME_LXD="Skipped"

# ---------------------------------------------------------------------
# TARGET 1: SNAPCRAFT BUILD ENGINE
# ---------------------------------------------------------------------
if [ "$BUILD_SNAP" = true ] || [ "$BUILD_OCI" = true ] || [ "$BUILD_DOCKER" = true ]; then
    START_SNAP=$SECONDS
    echo "[BUILD ENGINE] Building directly from native workspace root..."

    # Ensure launcher has executable permissions in place natively
    chmod +x gaia-launcher.sh

    echo "[BUILD ENGINE] Packing production Snap architecture bundle..."
    snapcraft pack

    DIFF_SNAP=$((SECONDS - START_SNAP))
    TIME_SNAP="$((DIFF_SNAP / 60))m $((DIFF_SNAP % 60))s"
fi

SNAP_PACKAGE=$(ls -t *.snap 2>/dev/null | head -n 1 || true)

# ---------------------------------------------------------------------
# TARGET 2: ROCKCRAFT PACK ENGINE (CHISELED OCI COMPILER)
# ---------------------------------------------------------------------
if [ "$BUILD_OCI" = true ] || [ "$BUILD_DOCKER" = true ]; then
    START_ROCK=$SECONDS
    echo "[ROCKCRAFT ENGINE] Staging isolated build environment..."
    rm -rf src_rock
    mkdir -p src_rock

    if [ -n "${SNAP_PACKAGE}" ] && [ -f "${SNAP_PACKAGE}" ]; then
        cp "${SNAP_PACKAGE}" src_rock/
    fi

    echo "[ROCKCRAFT ENGINE] Packing chiseled OCI container bundle..."
    rockcraft pack
    rm -rf src_rock

    DIFF_ROCK=$((SECONDS - START_ROCK))
    TIME_ROCK="$((DIFF_ROCK / 60))m $((DIFF_ROCK % 60))s"
fi

ROCK_FILE=$(ls -t *.rock 2>/dev/null | head -n 1 || true)

# ---------------------------------------------------------------------
# TARGET 3: NATIVE OCI-TO-DOCKER IMAGE TRANSFORMER
# ---------------------------------------------------------------------
if [ "$BUILD_DOCKER" = true ]; then
    START_DOCKER=$SECONDS
    echo "[DOCKER ENGINE] Verifying local rock dependencies..."
    if [ -z "${ROCK_FILE}" ]; then
        echo "❌ ERROR: Docker compilation target requires a pre-built local OCI .rock asset."
        exit 1
    fi

    if ! command -v skopeo &> /dev/null; then
        echo "[DOCKER ENGINE] Installing Skopeo pipeline utility..."
        sudo apt-get update && sudo apt-get install -y skopeo >/dev/null 2>&1
    fi

    DOCKER_OUTPUT_NAME="gaia-desktop_${GAIA_VERSION}_docker-image.tar"
    echo "[DOCKER ENGINE] Converting Chiseled OCI Rock directly into portable Docker layout..."
    rm -f "./${DOCKER_OUTPUT_NAME}"

    skopeo copy "oci-archive:${ROCK_FILE}" "docker-archive:./${DOCKER_OUTPUT_NAME}:gaia-desktop:${GAIA_VERSION}"

    if [ -x "$(command -v docker)" ]; then
        echo "[DOCKER ENGINE] Seeding converted OCI image into host's Docker daemon registry..."
        docker load -i "./${DOCKER_OUTPUT_NAME}"
    fi

    echo "🐳 Successfully finalized native OCI-to-Docker asset transposition portfolio!"

    DIFF_DOCK=$((SECONDS - START_DOCKER))
    TIME_DOCK="$((DIFF_DOCK / 60))m $((DIFF_DOCK % 60))s"
fi

# ---------------------------------------------------------------------
# TARGET 4: PORTABLE LXD IMAGE PROVISIONING LAYERS
# ---------------------------------------------------------------------
if [ "$BUILD_LXD" = true ]; then
    START_LXD=$SECONDS
    echo "LOG: Checking local LXD container system footprint..."
    if ! command -v lxc &> /dev/null; then
        echo "❌ ERROR: LXD command line interface not detected on your host machine."
        exit 1
    fi

    if [ -z "${SNAP_PACKAGE}" ]; then
        echo "❌ ERROR: LXD sandbox construction requires a pre-built local snap package artifact."
        exit 1
    fi

    echo "LOG: Executing deep cleanup engine to evict prior image states..."
    lxc delete gaia-worker --force >/dev/null 2>&1 || true
    lxc image delete "gaia-desktop/${GAIA_VERSION}" >/dev/null 2>&1 || true

    echo "LOG: Launching fresh, unprivileged Ubuntu base system container..."
    lxc launch ubuntu:24.04 gaia-worker -c security.nesting=true -c security.privileged=false
    lxc config device add gaia-worker GPU gpu gid=44 >/dev/null 2>&1 || true

    lxc config device add gaia-worker X0 proxy \
        listen=unix:@/tmp/.X11-unix/X0 \
        connect=unix:@/tmp/.X11-unix/X0 \
        bind=container security.uid=0 security.gid=0 >/dev/null 2>&1 || true

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
echo "LOG: Hardening file permission masks across generated assets..."
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
echo "🎉 ALL ARTIFACT TARGET COMPILATIONS COMPLETED!"
echo "====================================================="
[ -n "${SNAP_PACKAGE}" ]   && echo "📦 Snap Package: ./${SNAP_PACKAGE} (${TIME_SNAP})"
[ -n "${ROCK_FILE}" ]     && echo "🪨 Chiseled Rock: ./${ROCK_FILE} (${TIME_ROCK})"
[ -f "./gaia-desktop_${GAIA_VERSION}_docker-image.tar" ] && echo "🐳 Converted Docker Image: ./gaia-desktop_${GAIA_VERSION}_docker-image.tar (${TIME_DOCK})"
[ -f "./gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz" ] && echo "📦 LXD System Tarball: ./gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz (${TIME_LXD})"
echo "-----------------------------------------------------"

GLOBAL_DURATION=$((SECONDS - GLOBAL_START_TIME))
echo "Build completed successfully in $((GLOBAL_DURATION / 60))m $((GLOBAL_DURATION % 60))s."
echo ""

if [ "$BUILD_SNAP" = true ] || [ "$BUILD_OCI" = true ]; then
    echo "LOG: Launching surgical cleanup engine to reclaim workspace space..."
    sudo snapcraft clean --step=prime >/dev/null 2>&1 || true
    sudo snapcraft clean --step=stage >/dev/null 2>&1 || true

    for instance in $(lxc list -c n --format csv 2>/dev/null | grep -E "snapcraft-|rockcraft-" || true); do
        lxc delete "$instance" --force >/dev/null 2>&1 || true
    done
fi

echo "Execute: ./install_gaia.sh to configure and run target topologies."