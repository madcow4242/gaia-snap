#!/bin/bash
set -e

# =====================================================================
# GLOBAL WORKSPACE VARIABLE DEFINITIONS
# =====================================================================
GAIA_VERSION="0.20.0"  # Modify once here to upgrade versions globally

# =====================================================================
# CONFIGURATION FLAG PARSING ENGINE
# =====================================================================

# Initialize binary configuration flags
BUILD_SNAP=false
BUILD_OCI=false
BUILD_LXD=false

# If the user passes no arguments, build everything by default
if [ $# -eq 0 ]; then
    BUILD_SNAP=true
    BUILD_OCI=true
    BUILD_LXD=true
else
    # Parse incoming CLI parameters loops
    while [ $# -gt 0 ]; do
        case "$1" in
            --snap) BUILD_SNAP=true ;;
            --oci)  BUILD_OCI=true ;;
            --lxd)  BUILD_LXD=true ;;
            *) echo "❌ ERROR: Unknown parameter: $1. Valid flags: --snap, --oci, --lxd" >&2; exit 1 ;;
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

# Determine file cleanups based on active targets
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
# TARGET 1: SNAPCRAFT PACK ENGINE
# ---------------------------------------------------------------------
if [ "$BUILD_SNAP" = true ]; then
    echo "[BUILD ENGINE] Packing production Snap architecture bundle..."
    sudo snapcraft pack
fi

# Fixed Bracket Target: Safely pull string layouts
SNAP_PACKAGE=$(ls -t *.snap 2>/dev/null | head -n 1 || true)

# ---------------------------------------------------------------------
# TARGET 2: ROCKCRAFT PACK ENGINE
# ---------------------------------------------------------------------
if [ "$BUILD_OCI" = true ]; then
    echo "[ROCKCRAFT ENGINE] Packing chiseled OCI container bundle..."
    rockcraft pack
fi

ROCK_FILE=$(ls -t *.rock 2>/dev/null | head -n 1 || true)

# Print current compiled artifact summary mapping with safe string quoting
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
        echo "Please install it using: sudo snap install lxd && sudo lxd init --auto"
        exit 1
    fi

    # Confirm we have a snap package to inject before blowing away the baseline image
    if [ -z "${SNAP_PACKAGE}" ]; then
        echo "❌ ERROR: LXD sandbox construction requires a pre-built local snap package artifact."
        echo "Please run compilation with the --snap option enabled first: ./rebuild.sh --snap --lxd"
        exit 1
    fi

    echo "LOG: Executing deep cleanup engine to evict prior image states..."
    lxc delete gaia-worker --force >/dev/null 2>&1 || true
    lxc image delete "amd-gaia/${GAIA_VERSION}" >/dev/null 2>&1 || true

    echo "LOG: Launching fresh, unprivileged Ubuntu base system container..."
    lxc launch ubuntu:24.04 gaia-worker \
      -c security.nesting=true \
      -c security.privileged=false

    echo "LOG: Mapping host hardware GPU acceleration resources..."
    lxc config device add gaia-worker GPU gpu gid=44 >/dev/null 2>&1 || true

    echo "LOG: Materializing abstract graphical communication infrastructure..."
    lxc config device add gaia-worker X0 proxy \
        listen=unix:@/tmp/.X11-unix/X0 \
        connect=unix:@/tmp/.X11-unix/X0 \
        bind=container \
        security.uid=0 \
        security.gid=0 >/dev/null 2>&1 || true

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

    # 1. Stop the instance cleanly so its storage layers are frozen
    echo "LOG: Freezing container state matrix for publication..."
    lxc stop gaia-worker || lxc stop gaia-worker --force
    sleep 1

    echo "LOG: Generating portable, standalone LXD distribution artifact..."

    # Define the uniform output file layout pattern containing "LXD" clearly in the title
    LXD_OUTPUT_NAME="amd-gaia_${GAIA_VERSION}_LXD-sandbox.tar.gz"

    # Clean up any stale legacy export files if present in the workspace directory
    rm -f "./${LXD_OUTPUT_NAME}"

    # 2. Export the container directly to a standalone backup tarball file.
    # This completely circumvents the broken host-side /tmp metadata bundler gates.
    lxc export gaia-worker "./${LXD_OUTPUT_NAME}" --optimized-storage

    if [ -f "./${LXD_OUTPUT_NAME}" ]; then
        echo "✨ SUCCESS: Standalone container image baked completely!"
        echo "Artifact Location: ./${LXD_OUTPUT_NAME} ($(du -sh ./${LXD_OUTPUT_NAME} | awk '{print $1}'))"
    else
        echo "❌ ERROR: Standalone LXD container export transaction failed to map file to directory." >&2
        exit 1
    fi

    # 3. Final worker cleanup sweep (removes the worker container entirely)
    lxc delete gaia-worker --force >/dev/null 2>&1 || true
    echo "====================================================================="
    echo " ✨ ALL CORE COMPILATION TARGETS COMPLETE!"
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