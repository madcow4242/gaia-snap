#!/bin/bash
# =====================================================================
# GAIA WORKSTATION DEEP CLEANUP & FILE SYSTEM OPTIMIZATION ENGINE
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
echo "🧹 INITIALIZING SYSTEMIC RECLAIM SWEEP (Starting Free Space: $INITIAL_SPACE)"
echo "====================================================================="

# Read incoming argument $1, default to 0.20.0 if empty
TARGET_VERSION="${1:-0.20.0}"

# ---------------------------------------------------------------------
# PHASE 1: FORCE EVICT ACTIVE/ORPHANED BUILD WORKERS & LEGACY IMAGES
# ---------------------------------------------------------------------
echo "LOG: Terminating active and orphaned build worker instances..."
if command -v lxc &> /dev/null; then
    # Evict worker container instances
    lxc delete gaia-worker --force >/dev/null 2>&1 || true
    lxc delete gaia-runtime-sandbox --force >/dev/null 2>&1 || true

    # FIX: Corrected variable format interpolation string mapping
    lxc image delete "gaia-desktop/0.20.0${TARGET_VERSION}" >/dev/null 2>&1 || true

    # NEW: Surgical eviction of any lingering legacy namespaced images
    lxc image delete "amd-gaia/${TARGET_VERSION}" >/dev/null 2>&1 || true
    lxc image delete "amd-gaia/0.20.0" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------
# PHASE 2: PURGE HIDDEN SNAPCONTAINER/ROCKCONTAINER REPOS & USER CACHES
# ---------------------------------------------------------------------
echo "LOG: Wiping untracked staging archives from system partitions..."
rm -rf /var/tmp/gaia-*
rm -rf /home/*/.local/share/Trash/files/*

# NEW: Vacuum hidden tool downloader caches out of all local home directories
echo "LOG: Evicting hidden user-space build tool manager caches..."
rm -rf /home/*/.cache/snapcraft
rm -rf /home/*/.cache/rockcraft
rm -rf /root/.cache/snapcraft
rm -rf /root/.cache/rockcraft

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

    for proj in "snapcraft" "rockcraft"; do
        if lxc project list --format csv | grep -q "^${proj},"; then
            echo "LOG: Purging unreferenced build infrastructure inside project space [${proj}]..."

            for inst in $(lxc list --project "$proj" -c n --format csv 2>/dev/null); do
                lxc delete --project "$proj" "$inst" --force >/dev/null 2>&1 || true
            done

            lxc image prune --project "$proj" --force >/dev/null 2>&1 || true
        fi
    done

    for proj in $(lxc project list --format csv | awk -F, '{print $1}'); do
        lxc image prune --project "$proj" --force >/dev/null 2>&1 || true
    done

    echo "LOG: Evicting unlinked raw hypervisor caching directories..."
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/images/snapcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/containers/snapcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/images/rockcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/containers/rockcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/custom/snapcraft
    rm -rf /var/snap/lxd/common/lxd/storage-pools/default/custom/rockcraft
fi

# ---------------------------------------------------------------------
# PHASE 4: RECLAIM CONFINED SYSTEM DAEMON CLONE HEADROOM
# ---------------------------------------------------------------------
echo "LOG: Evicting disabled duplicate revisions from the Snapd database..."
snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    if [ -n "$snapname" ] && [ -n "$revision" ]; then
        echo "Removing stale iteration: ${snapname} (rev ${revision})"
        snap remove "$snapname" --revision="$revision" >/dev/null 2>&1 || true
    fi
done

echo "LOG: Vacuuming operating system package manager storage archives..."
apt-get autoremove -y >/dev/null 2>&1
apt-get clean -y >/dev/null 2>&1

# ---------------------------------------------------------------------
# PHASE 5: DOCKER BUILD ENGINE GARBAGE COLLECTION
# ---------------------------------------------------------------------
if command -v docker &> /dev/null; then
    echo "LOG: Running deep garbage collection pass across Docker build engines..."
    docker builder prune -f >/dev/null 2>&1 || true
    docker image prune -f >/dev/null 2>&1 || true
    # NEW: Wipe dangling microservices layers but preserve active databases
    docker system prune -f >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------
# PHASE 6: HARDWARE CONCURRENCY FILE ALLOCATION SYNC
# ---------------------------------------------------------------------
echo "LOG: Signaling system kernel to commit deleted blocks to flash sectors..."
sync
sleep 2

FINAL_SPACE=$(df -h / | awk 'NR==2 {print $4}')
echo "====================================================================="
echo "🎉 SYSTEM DEEP CLEANUP PIPELINE PASS COMPLETE!"
echo "---------------------------------------------------------------------"
echo " Initial Headroom:   $INITIAL_SPACE"
echo " Current Headroom:   $FINAL_SPACE"
echo "====================================================================="