#!/bin/bash
set -e 

echo "🔐 Cache validation required. Please enter your sudo password once:"
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
echo "🚀 Autonomous mode locked in. You can walk away!"

echo "🧹 [1/6] Purging old tracking states universally..."
rm -rf "$HOME/snap/amd-gaia/common/.cache/" "$HOME/snap/amd-gaia/current/.cache/"

echo "🧼 [2/6] Deep cleaning all Snapcraft cache layers..."
sudo snapcraft clean

echo "📦 [3/6] Compiling and packaging fresh production Snap..."
sudo snapcraft pack

echo "💀 [4/6] Terminating lingering background GAIA and Python processes..."
sudo killall -9 gaia .gaia-desktop-bin python3 chromium-browser 2>/dev/null || true

echo "🗑️ [5/6] Uninstalling previous system Snap hooks..."
sudo snap remove amd-gaia || true

echo "🚀 [6/6] Deploying unified snap bundle locally..."
SNAP_FILE=$(ls -t *.snap | head -n 1)
sudo snap install "./$SNAP_FILE" --dangerous

echo "🎯 Pre-seeding system parameters to host metadata ledger..."
sudo snap set amd-gaia backend.url="http://192.168.1.109:13305"
sudo snap set amd-gaia backend.tavily-key="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"

echo "⚙️ Re-linking broken OS symlinks and formatting data containers..."
rm -rf "$HOME/snap/amd-gaia/current"
mkdir -p "$HOME/snap/amd-gaia/x1/.gaia/chat"
ln -s "$HOME/snap/amd-gaia/x1" "$HOME/snap/amd-gaia/current"

echo "✅ Pipeline complete! Let's watch it fly:"
amd-gaia

