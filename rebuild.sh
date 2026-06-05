#!/bin/bash
set -e

# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# =====================================================================

# 🎯 YOUR PRIVATE WORKSTATION PARAMETERS
export TARGET_BACKEND_URL="http://192.168.1.109:13305"
export GAIA_VERSION="0.20.0"

echo "🔐 Validating execution environment administrative parameters..."
if ! sudo -n true 2>/dev/null; then
    echo "🔐 Sudo authorization required. Please authenticate below:"
    sudo true
fi
sudo -v

echo "🛑 Sweeping lingering dependencies..."
sudo pkill -9 -x "amd-gaia" || true
sudo pkill -9 -x "gaia" || true

sudo rm -f *.snap

if [ "$1" == "--clean" ]; then
    echo "🧹 [1/2] Deep cleaning ALL compilation caching sectors..."
    sudo snapcraft clean
else
    echo "🔄 [1/2] Incremental Mode: Resetting module caches..."
    sudo snapcraft clean gaia-backend
    sudo snapcraft clean gaia-sideloads
fi

echo "📦 [2/2] Compiling and packaging fresh production Classic Snap package..."
sudo snapcraft pack

SNAP_FILE=$(ls -t *.snap | head -n 1)

echo "🗑️ Removing old local deployment traces..."
sudo snap remove amd-gaia || true

echo "🚀 Installing optimized classic snap bundle locally..."
sudo snap install "./$SNAP_FILE" --classic --dangerous

echo "✨ Pipeline loop complete! Launching package..."
# 🎯 THE FIX: Launches the application natively while preserving your exported session variable
amd-gaia
