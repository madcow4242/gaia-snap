#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------
# GAIA cleanup utility
#   Default mode: clean local build environment (artifacts + intermediates)
#   --total-purge: remove all GAIA artifacts, state, and cached downloads
# ---------------------------------------------------------------------

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAST_VERSION_FILE="${WORKSPACE_DIR}/.last_version"
DEFAULT_VERSION="0.22.0"
TARGET_VERSION=""
TOTAL_PURGE=false

usage() {
    cat <<'EOF'
Usage:
  ./cleanup.sh [<version>] [--version=<version>] [--total-purge]

Modes:
  Default (no flags):
    Cleans build outputs and intermediate state so the next build uses current
    source changes without stale local artifacts.

  --total-purge:
    Performs default cleanup plus removal of GAIA deployment/runtime state and
    cached download/build tool contents for a first-time-build baseline.

Examples:
  ./cleanup.sh
    ./cleanup.sh 0.22.0
    ./cleanup.sh --version=0.22.0
    sudo ./cleanup.sh --total-purge --version=0.22.0
EOF
}

log() {
    echo "INFO: $*"
}

warn() {
    echo "WARNING: $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "--total-purge requires root privileges."
        error "Run: sudo ./cleanup.sh --total-purge [--version=X.Y.Z]"
        exit 1
    fi
}

validate_version() {
    if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid version format: $1"
        error "Expected semantic version format X.Y.Z (example: 0.22.0)."
        exit 1
    fi
}

resolve_target_version() {
    if [[ -n "$TARGET_VERSION" ]]; then
        validate_version "$TARGET_VERSION"
        return
    fi

    if [[ -f "$LAST_VERSION_FILE" ]]; then
        TARGET_VERSION="$(cat "$LAST_VERSION_FILE")"
    else
        TARGET_VERSION="$DEFAULT_VERSION"
    fi

    validate_version "$TARGET_VERSION"
}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --total-purge)
                TOTAL_PURGE=true
                ;;
            --version=*)
                TARGET_VERSION="${arg#*=}"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    TARGET_VERSION="$arg"
                else
                    error "Unknown argument: $arg"
                    usage
                    exit 1
                fi
                ;;
        esac
    done
}

remove_workspace_artifacts() {
    log "Removing workspace build artifacts."

    shopt -s nullglob
    local files=(
        "${WORKSPACE_DIR}"/*.snap
        "${WORKSPACE_DIR}"/*.rock
        "${WORKSPACE_DIR}"/*_docker-image.tar
        "${WORKSPACE_DIR}"/*_LXD-sandbox.tar.gz
    )

    if (( ${#files[@]} > 0 )); then
        rm -f "${files[@]}"
    fi
    shopt -u nullglob

    rm -rf "${WORKSPACE_DIR}/src_rock"
}

clean_build_intermediates() {
    log "Cleaning snapcraft/rockcraft intermediates (preserving download caches)."

    if command -v snapcraft >/dev/null 2>&1; then
        snapcraft clean gaia-desktop --step=prime >/dev/null 2>&1 || true
        snapcraft clean gaia-backend --step=prime >/dev/null 2>&1 || true
    fi

    if command -v rockcraft >/dev/null 2>&1; then
        rockcraft clean gaia-container-runtime >/dev/null 2>&1 || true
        rockcraft clean >/dev/null 2>&1 || true
    fi
}

clean_staging_paths() {
    log "Removing temporary GAIA staging files from /tmp and /var/tmp."

    rm -f /tmp/gaia-desktop_*_docker-image.tar 2>/dev/null || true
    rm -f /tmp/gaia-docker-stage.tar /tmp/gaia-podman-stage.tar 2>/dev/null || true
    rm -rf /var/tmp/gaia-* 2>/dev/null || true
}

clean_build_workers() {
    log "Cleaning ephemeral build worker state."

    if command -v lxc >/dev/null 2>&1; then
        lxc delete gaia-worker --force >/dev/null 2>&1 || true
        lxc image delete "gaia-desktop/${TARGET_VERSION}" >/dev/null 2>&1 || true
    fi

    if command -v docker >/dev/null 2>&1; then
        docker image rm -f "gaia-desktop:${TARGET_VERSION}" >/dev/null 2>&1 || true
    fi
}

normal_cleanup() {
    remove_workspace_artifacts
    clean_build_intermediates
    clean_staging_paths
    clean_build_workers
}

purge_user_state() {
    log "Removing GAIA user/runtime state and tool caches."

    rm -rf /root/.gaia /root/.cache/@amd-gaiaagent-ui-updater 2>/dev/null || true
    rm -rf /root/.cache/snapcraft /root/.cache/rockcraft 2>/dev/null || true
    rm -rf /root/snap/gaia-desktop 2>/dev/null || true

    for user_home in /home/*; do
        [[ -d "$user_home" ]] || continue
        rm -rf "${user_home}/.gaia" 2>/dev/null || true
        rm -rf "${user_home}/.cache/@amd-gaiaagent-ui-updater" 2>/dev/null || true
        rm -rf "${user_home}/.cache/snapcraft" "${user_home}/.cache/rockcraft" 2>/dev/null || true
        rm -rf "${user_home}/snap/gaia-desktop" 2>/dev/null || true
    done
}

purge_deployments() {
    log "Removing deployed GAIA runtimes and images."

    if command -v snap >/dev/null 2>&1; then
        snap remove --purge gaia-desktop >/dev/null 2>&1 || true
    fi

    if command -v docker >/dev/null 2>&1; then
        docker rm -f gaia-docker-sandbox >/dev/null 2>&1 || true
        docker image rm -f "gaia-desktop:${TARGET_VERSION}" >/dev/null 2>&1 || true
        docker image rm -f $(docker images -q "gaia-desktop" 2>/dev/null) >/dev/null 2>&1 || true
        docker builder prune -f >/dev/null 2>&1 || true
        docker system prune -a -f >/dev/null 2>&1 || true
    fi

    if command -v podman >/dev/null 2>&1; then
        podman rm -f gaia-podman-sandbox >/dev/null 2>&1 || true
        podman image rm -f "gaia-desktop:${TARGET_VERSION}" >/dev/null 2>&1 || true
        podman image rm -f $(podman images -q "gaia-desktop" 2>/dev/null) >/dev/null 2>&1 || true
        podman system prune -a -f >/dev/null 2>&1 || true
    fi

    if command -v lxc >/dev/null 2>&1; then
        lxc delete gaia-worker --force >/dev/null 2>&1 || true
        lxc delete gaia-runtime-sandbox --force >/dev/null 2>&1 || true
        lxc image delete "gaia-desktop/${TARGET_VERSION}" >/dev/null 2>&1 || true
        lxc image delete "amd-gaia/${TARGET_VERSION}" >/dev/null 2>&1 || true

        for proj in snapcraft rockcraft; do
            if lxc project list --format csv | awk -F, '{print $1}' | grep -qx "$proj"; then
                while IFS= read -r inst; do
                    [[ -n "$inst" ]] || continue
                    lxc delete --project "$proj" "$inst" --force >/dev/null 2>&1 || true
                done < <(lxc list --project "$proj" -c n --format csv 2>/dev/null || true)
                lxc image prune --project "$proj" --force >/dev/null 2>&1 || true
            fi
        done

        while IFS= read -r proj; do
            [[ -n "$proj" ]] || continue
            lxc image prune --project "$proj" --force >/dev/null 2>&1 || true
        done < <(lxc project list --format csv | awk -F, '{print $1}')
    fi
}

total_purge_cleanup() {
    require_root
    normal_cleanup
    purge_deployments
    purge_user_state

    if command -v apt-get >/dev/null 2>&1; then
        log "Cleaning apt package cache."
        apt-get clean -y >/dev/null 2>&1 || true
    fi
}

main() {
    parse_args "$@"
    resolve_target_version

    if [[ "$TOTAL_PURGE" == true ]]; then
        log "Running TOTAL PURGE for version ${TARGET_VERSION}."
        total_purge_cleanup
        log "Total purge complete. System is reset to a first-time-build baseline."
    else
        log "Running NORMAL cleanup for version ${TARGET_VERSION}."
        normal_cleanup
        log "Normal cleanup complete. Build environment is ready for a fresh rebuild."
    fi
}

main "$@"
