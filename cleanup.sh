#!/bin/bash
# =====================================================================
# GAIA WORKSTATION DEEP CLEANUP & FILE SYSTEM OPTIMIZATION ENGINE
# =====================================================================
# Target: Safely reclaim hundreds of gigabytes of hidden caches,
# orphaned compiler layers, and stale logs while preserving production
# artifacts (*.snap, *.rock, *LXD-sandbox.tar.gz).
# =====================================================================

set -e

# Ensure the execution frame is running with root access privileges
if [ "$EUID" -ne 0 ]; then
    echo "❌ ERROR: This maintenance utility must be executed with root privileges." >&2
    echo "Please run via: sudo ./cleanup.sh" >&2
    exit 1
fi

INITIAL_SPACE=$(df -h / | awk 'NR==2 {print $4}')
echo "====================================================================="
echo "🧽 INITIALIZING SYSTEMIC RECLAIM SWEEP (Starting Free Space: $INITIAL_SPACE)"
echo "====================================================================="

# ---------------------------------------------------------------------
# PHASE 1: FORCE EVICT ACTIVE/ORPHANED BUILD WORKERS
# ---------------------------------------------------------------------
echo "LOG: Terminating active and orphaned build worker instances..."
if command -v lxc &> /dev/null; then
    lxc delete gaia-worker --force >/dev/null 2>&1 || true
    lxc image delete "amd-gaia/0.20.0" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------
# PHASE 2: PURGE HIDDEN SNAPCONTAINER/ROCKCONTAINER REPOS & ARCHIVES
# ---------------------------------------------------------------------
echo "LOG: Wiping untracked staging archives from system partitions..."
rm -rf /var/tmp/gaia-*
rm -rf /home/*/.local/share/Trash/files/*

# Clean out specific user-space snap staging directories if present
for user_home in /home/*; do
    if [ -d "${user_home}/snap/docker/common" ]; then
        echo "LOG: Clearing staging ground layers inside user workspace: ${user_home}"
        rm -rf "${user_home}"/snap/docker/common/gaia-lxd-staging-*
    fi
done

# ---------------------------------------------------------------------
# PHASE 3: ATOMIC PURGE OF HIDDEN LXD PROJECT NAMESPACES
# ---------------------------------------------------------------------
if command -v lxc &> /dev/null; then
    echo "LOG: Deep scanning hidden hypervisor project namespaces..."

    # Force isolate and prune orphaned elements within hidden compiler namespaces
    for proj in "snapcraft" "rockcraft"; do
        if lxc project list --format csv | grep -q "^${proj},"; then
            echo "LOG: Purging unreferenced build infrastructure inside project space [${proj}]..."

            # Delete any hidden, trailing build containers
            for inst in $(lxc list --project "$proj" -c n --format csv 2>/dev/null); do
                lxc delete --project "$proj" "$inst" --force >/dev/null 2>&1 || true
            done

            # Prune loose image layers blocking storage blocks
            lxc image prune --project "$proj" --force >/dev/null 2>&1 || true
        fi
    done

    # General pool image garbage collection sweep across all remaining profiles
    for proj in $(lxc project list --format csv | awk -F, '{print $1}'); do
        lxc image prune --project "$proj" --force >/dev/null 2>&1 || true
    done

    # Force system paths directory cleanup for uncknowledged block drivers
    echo "LOG: Evicting unlinked raw hypervisor caching directories..."
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/images/snapcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/containers/snapcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/images/rockcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/containers/rockcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/custom/snapcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/custom/rockcraft
fi

# ---------------------------------------------------------------------
# PHASE 4: RECLAIM CONFINED SYSTEM DAEMONhead CLONE HeadROOM
# ---------------------------------------------------------------------
echo "LOG: Evicting disabled duplicate revisions from the Snapd database..."
snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    if [ -n "$snapname" ] && [ -n "$revision" ]; then
        echo "Removing stale iteration: ${snapname} (rev ${revision})"
        snap remove "$snapname" --revision="$revision" >/dev/null 2>&1 || true
    fi
done

# Clear system-wide package downloader caches
echo "LOG: Vacuuming operating system package manager storage archives..."
apt-get autoremove -y >/dev/null 2>&1
apt-get clean -y >/dev/null 2>&1

# ---------------------------------------------------------------------
# PHASE 5: DOCKER BUILD ENGINE GARBAGE COLLECTION
# ---------------------------------------------------------------------
if command -v docker &> /dev/null; then
    echo "LOG: Running deep garbage collection pass across Docker build engines..."
    # Only purges dangling/unreferenced build caches and unused system layers.
    # Leaves your running active Ollama volumes safely intact.
    docker builder prune -f >/dev/null 2>&1 || true
    docker image prune -f >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------
# PHASE 6: HARDWARE CONCURRENCY FILE ALLOCATION SYNC
# ---------------------------------------------------------------------
echo "LOG: Signaling system kernel to commit deleted blocks to flash sectors..."
# Flushes memory maps and recalculates true available allocation space blocks on disk
sync
sleep 2

FINAL_SPACE=$(df -h / | awk 'NR==2 {print $4}')
echo "====================================================================="
echo "✨ SYSTEM DEEP CLEANUP PIPELINE PASS COMPLETE!"
echo "---------------------------------------------------------------------"
echo " Initial Headroom:   $INITIAL_SPACE"
echo " Current Headroom:   $FINAL_SPACE"
echo "====================================================================="