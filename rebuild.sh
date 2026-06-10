#!/bin/bash
set -e

# =====================================================================
# LOCAL WORKSTATION REBUILD & RAPID INTEGRATION LOOP UTILITY
# =====================================================================

# Baseline target environment parameters
TARGET_BACKEND_URL="http://192.168.1.109:13305"
OPENAI_API_KEY="sk-proj-openai-test-key-vector-abcde12345"
ANTHROPIC_API_KEY="sk-ant-api53-test-key-tokens-67890fghij"
GROQ_API_KEY=""
TAVILY_API_KEY="tvly-workstation-test-token-12345"
SERPER_API_KEY="api-serper-local-routing-56789"

echo "LOG: Validating local workstation administrative execution parameters..."
if ! sudo -n true 2>/dev/null; then
    echo "LOG: Administrative privileges required. Authenticating below:"
    sudo true
fi
sudo -v

echo "LOG: Terminating lingering background process daemons..."
sudo pkill -9 -f "amd-gaia" || true
sudo pkill -9 -f "gaia" || true
sudo rm -f *.snap

echo "LOG: Purging previous snap cluster mounts and local app data storage caches..."
sudo snap remove --purge amd-gaia || true
sudo rm -rf "${HOME}/.config/GAIA" || true

echo "LOG: Executing deep cache eviction on intermediate snapcraft parts staging areas..."
sudo snapcraft clean gaia-desktop >/dev/null 2>&1 || true
sudo snapcraft clean gaia-backend >/dev/null 2>&1 || true
sudo snapcraft clean gaia-sideloads >/dev/null 2>&1 || true

stty sane || true
clear

echo "[BUILD ENGINE] Executing native Snapcraft generation pipeline loop..."
if ! sudo snapcraft pack; then
    echo "ERROR: Native compilation pipeline failed to generate snap target bundle artifact cleanly." >&2
    exit 1
fi

# Track down the freshly minted compilation target package
SNAP_FILE=$(ls -t *.snap | head -n 1)
if [ -z "$SNAP_FILE" ]; then
    echo "ERROR: Target snap package package lookup returned empty folder state index." >&2
    exit 1
fi

echo "[DEPLOYMENT] Installing freshly compiled local archive bundle onto system mounts..."
sudo snap install "./$SNAP_FILE" --classic --dangerous

echo "[DEPLOYMENT] Provisioning administrative runtime environment state parameters..."
sudo snap set amd-gaia backend.url="$TARGET_BACKEND_URL"
sudo snap set amd-gaia keys.openai="$OPENAI_API_KEY"
sudo snap set amd-gaia keys.anthropic="$ANTHROPIC_API_KEY"
sudo snap set amd-gaia keys.groq="$GROQ_API_KEY"
sudo snap set amd-gaia keys.tavily="$TAVILY_API_KEY"
sudo snap set amd-gaia keys.serper="$SERPER_API_KEY"

echo "[DEPLOYMENT] snap set backend.maxsteps=60..."
sudo snap set amd-gaia backend.maxsteps=60

# Maintain local file fallback synchronization framework as a backup testbed safety net
BOOTSTRAP_DIR="${HOME}/.gaia/bootstrap"
mkdir -p "$BOOTSTRAP_DIR"
cp -af "_gaia_sandbox_patch.py" "$BOOTSTRAP_DIR/sitecustomize.py"

echo "LOG: Core workstation environment initialization cycle complete. Spawning binary entrypoint..."
amd-gaia