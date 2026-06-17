#!/bin/bash
set -e

# =====================================================================
# GLOBAL WORKSPACE VARIABLE DEFINITIONS
# =====================================================================
GLOBAL_DEFAULT_VERSION="0.21.0"  # Modify once here to upgrade versions globally

VERSION_CACHE_FILE=".last_version"
GAIA_VERSION=""                  # Holds the final resolved runtime variable

# 1. Parse incoming command-line arguments (Capture version flags first)
TEMP_ARGS=()
for arg in "$@"; do
    case $arg in
        --gaia-version=*)
            GAIA_VERSION="${arg#*=}"
            ;;
        *)
            TEMP_ARGS+=("$arg")   # Keep other build flags for step 4
            ;;
    esac
done
set -- "${TEMP_ARGS[@]}"          # Reset positional parameters without version flag

# 2. If NO flag was passed, fall back to interactive cache loop
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

# 3. Save the final resolved version to the cache
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

# Run the exact regex mappings seamlessly in a clean execution sequence
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
BUILD_LXD=false

if [ $# -eq 0 ]; then
    BUILD_SNAP=true
    BUILD_OCI=true
    BUILD_LXD=true
else
    while [ $# -gt 0 ]; do
        case "$1" in
            --snap) BUILD_SNAP=true ;;
            --oci)  BUILD_OCI=true ;;
            --lxd)  BUILD_LXD=true ;;
            *) echo "❌ ERROR: Unknown parameter: $1. Valid flags: --snap, --oci, --lxd" >&2; exit 1 ;;
        esac
        shift # Correctly increments through the argument indexes
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

if [ "$BUILD_OCI" = true ]; then
    echo "LOG: Clearing previous OCI packaging outputs..."
    sudo rm -f *.rock
fi

stty sane || true
clear

echo "====================================================="
echo "COMPILATION CORE TARGET MATRIX EXECUTION"
echo "====================================================="

# ---------------------------------------------------------------------
# TARGET 1: SNAPCRAFT BUILD ENGINE
# ---------------------------------------------------------------------
if [ "$BUILD_SNAP" = true ]; then
    echo "[BUILD ENGINE] Establishing transient core24 stage-gate..."

    # 1. Force clear old states and build the clean isolated structure
    rm -rf src_sideloads
    mkdir -p src_sideloads/snap/hooks

    # 2. Populate the gate from your single-source-of-truth root files
    cp gaia-launcher.sh src_sideloads/
    cp _gaia_sandbox_patch.py src_sideloads/
    cp snap/hooks/configure src_sideloads/snap/hooks/

    echo "[BUILD ENGINE] Packing production Snap architecture bundle..."
    # Snapcraft runs completely safely here because 'src_sideloads' exists!
    snapcraft pack

    echo "[BUILD ENGINE] Dissolving transient stage-gate..."
    # 3. Clean up the folder only AFTER the compilation pass is finished
    rm -rf src_sideloads
fi

SNAP_PACKAGE=$(ls -t *.snap 2>/dev/null | head -n 1 || true)

# ---------------------------------------------------------------------
# TARGET 2: ROCKCRAFT PACK ENGINE
# ---------------------------------------------------------------------
if [ "$BUILD_OCI" = true ]; then
    echo "[ROCKCRAFT ENGINE] Staging isolated build environment..."

    # Create a fresh, pristine staging folder
    rm -rf src_rock
    mkdir -p src_rock

    # Safely duplicate ONLY the snap and launcher into the isolation gate
    if [ -f "${SNAP_PACKAGE}" ]; then
        cp "${SNAP_PACKAGE}" src_rock/
    fi

    echo "[ROCKCRAFT ENGINE] Packing chiseled OCI container bundle..."
    rockcraft pack

    # Optional: Clean up the temporary local staging gate folder post-build
    rm -rf src_rock
fi

ROCK_FILE=$(ls -t *.rock 2>/dev/null | head -n 1 || true)

echo "====================================================="
echo "CORE ARTIFACT COMPILATION COMPLETE!"
echo "====================================================="
[ -n "${SNAP_PACKAGE}" ] && echo "Generated Snap: ./${SNAP_PACKAGE}"
[ -n "${ROCK_FILE}" ]     && echo "Generated Rock: ./${ROCK_FILE}"
echo "-----------------------------------------------------"

# ---------------------------------------------------------------------
# TARGET 3: PORTABLE LXD IMAGE PROVISIONING LAYERS
# ---------------------------------------------------------------------
if [ "$BUILD_LXD" = true ]; then
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
    # FIX: Corrected namespace to track gaia-desktop instead of the legacy amd-gaia name
    lxc image delete "gaia-desktop/${GAIA_VERSION}" >/dev/null 2>&1 || true

    echo "LOG: Launching fresh, unprivileged Ubuntu base system container..."
    lxc launch ubuntu:24.04 gaia-worker -c security.nesting=true -c security.privileged=false

    echo "LOG: Mapping host hardware GPU acceleration resources..."
    lxc config device add gaia-worker GPU gpu gid=44 >/dev/null 2>&1 || true

    echo "LOG: Materializing abstract graphical communication infrastructure..."
    lxc config device add gaia-worker X0 proxy \
        listen=unix:@/tmp/.X11-unix/X0 \
        connect=unix:@/tmp/.X11-unix/X0 \
        bind=container security.uid=0 security.gid=0 >/dev/null 2>&1 || true

    echo "LOG: Synchronizing internal container package definitions..."
    lxc exec gaia-worker -- apt-get update -y >/dev/null 2>&1

    echo "LOG: Injecting base modern GTK, Chromium & Audio dependency tree..."
    lxc exec gaia-worker -- apt-get install -y \
        snapd libatk1.0-0 libatk-bridge2.0-0 libxcomposite1 libxdamage1 \
        libgl1 libgtk-3-0 libasound2t64 libnspr4 libnss3 >/dev/null 2>&1

    echo "LOG: Shipping compiled production Snap bundle across container boundary..."
    cat "$SNAP_PACKAGE" | lxc exec gaia-worker -- sh -c "cat > /tmp/gaia.snap"

    echo "LOG: Deploying Snap natively into sandbox base workspace..."
    lxc exec gaia-worker -- snap install --classic --dangerous /tmp/gaia.snap

    echo "LOG: Freezing container state matrix for publication..."
    lxc stop gaia-worker || lxc stop gaia-worker --force
    sleep 1

    echo "LOG: Generating portable, standalone LXD distribution artifact..."
    LXD_OUTPUT_NAME="gaia-desktop_${GAIA_VERSION}_LXD-sandbox.tar.gz"
    rm -f "./${LXD_OUTPUT_NAME}"

    lxc export gaia-worker "./${LXD_OUTPUT_NAME}" --optimized-storage

    if [ -f "./${LXD_OUTPUT_NAME}" ]; then
        echo "🎉 SUCCESS: Standalone container image baked completely!"
        echo "Artifact Location: ./${LXD_OUTPUT_NAME} ($(du -sh ./${LXD_OUTPUT_NAME} | awk '{print $1}'))"
    else
        echo "❌ ERROR: Standalone LXD container export transaction failed." >&2
        exit 1
    fi

    lxc delete gaia-worker --force >/dev/null 2>&1 || true
    echo "====================================================================="
    echo " 🎉 ALL CORE COMPILATION TARGETS COMPLETE!"
    echo "====================================================================="
fi

# =====================================================================
# POST-COMPILATION SANITIZATION PRUNING (DISK SPACE PROTECTION)
# =====================================================================
if [ "$BUILD_SNAP" = true ] || [ "$BUILD_OCI" = true ]; then
    echo "LOG: Launching surgical cleanup engine to reclaim workspace space..."
    sudo snapcraft clean --step=prime >/dev/null 2>&1 || true
    sudo snapcraft clean --step=stage >/dev/null 2>&1 || true

    for instance in $(lxc list -c n --format csv 2>/dev/null | grep -E "snapcraft-|rockcraft-" || true); do
        echo "LOG: Evicting stale compiler instance: $instance"
        lxc delete "$instance" --force >/dev/null 2>&1 || true
    done
    echo "LOG: Cleanup complete! Drive space protected successfully."
    echo "-----------------------------------------------------"
fi

echo "Execute: ./install_gaia.sh to configure and run target topologies."