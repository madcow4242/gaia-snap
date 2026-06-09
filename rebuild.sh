#!/bin/bash
set -e

# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# =====================================================================

TARGET_BACKEND_URL="http://192.168.1.109:13305"
OPENAI_API_KEY="sk-proj-openai-test-key-vector-abcde12345"
ANTHROPIC_API_KEY="sk-ant-api53-test-key-tokens-67890fghij"
GROQ_API_KEY=""
TAVILY_API_KEY="tvly-workstation-test-token-12345"
SERPER_API_KEY="api-serper-local-routing-56789"

echo "🔐 Validating execution environment administrative parameters..."
if ! sudo -n true 2>/dev/null; then
    echo "🔐 Sudo authorization required. Please authenticate below:"
    sudo true
fi
sudo -v

echo "🛑 Sweeping lingering dependencies..."
sudo pkill -9 -f "amd-gaia" || true
sudo pkill -9 -f "gaia" || true
sudo rm -f *.snap

# 🧹 [1/3] THE ULTRA-PARANOID SYSTEM DAEMON PURGE
echo "🧹 Wiping active snap deployment states and local configuration histories..."
sudo snap remove --purge amd-gaia || true
sudo rm -rf "${HOME}/.config/GAIA" || true

echo "🧹 Deep cleaning ALL cached compilation components..."
sudo snapcraft clean gaia-desktop >/dev/null 2>&1 || true
sudo snapcraft clean gaia-backend >/dev/null 2>&1 || true
sudo snapcraft clean gaia-sideloads >/dev/null 2>&1 || true

stty sane || true
clear

echo "📦 [2/3] Compiling and packaging standardized production Classic Snap package..."
# 🚀 Reverted back to the standard native packaging flow!
sudo snapcraft pack

SNAP_FILE=$(ls -t *.snap | head -n 1)

echo "🚀 [3/3] Installing newly compiled container onto system mounts natively..."
sudo snap install "./$SNAP_FILE" --classic --dangerous

echo "⚙️ Synchronizing permanent user parameters..."
sudo snap set amd-gaia backend.url="$TARGET_BACKEND_URL"
sudo snap set amd-gaia keys.openai="$OPENAI_API_KEY"
sudo snap set amd-gaia keys.anthropic="$ANTHROPIC_API_KEY"
sudo snap set amd-gaia keys.groq="$GROQ_API_KEY"
sudo snap set amd-gaia keys.tavily="$TAVILY_API_KEY"
sudo snap set amd-gaia keys.serper="$SERPER_API_KEY"

# Maintain the local bootstrap mirror fallback as a developer safety net
BOOTSTRAP_DIR="${HOME}/.gaia/bootstrap"
mkdir -p "$BOOTSTRAP_DIR"
cp -af "_gaia_sandbox_patch.py" "$BOOTSTRAP_DIR/sitecustomize.py"

echo "✨ Pipeline loop complete! Launching package..."
amd-gaia