#!/bin/bash

# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# - SYSTEM ATTRIBUTES: AMD-GAIA SNAP PRODUCTION CONFIGURATION BUILDER.
# - CRITICAL: Perform a strict line-by-line regression audit before editing.
# =====================================================================

export PYTHONWARNINGS="ignore:Unverified HTTPS request"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$SNAP/usr/lib/x86_64-linux-gnu/libproxy"
export GAIA_CTX_SIZE=32768
export LEMONADE_CTX_SIZE=32768
export DEFAULT_CTX_SIZE=32768

RAW_BACKEND="$(snapctl get backend 2>/dev/null || true)"

get_snap_value() {
    local key="$1"
    local val="$(snapctl get backend.$key 2>/dev/null || true)"
    if [ -z "$val" ] && [ -n "$RAW_BACKEND" ]; then
        val=$(echo "$RAW_BACKEND" | grep -oP '"'"$key"'"\s*:\s*"\K[^"]+' || true)
    fi
    echo "$val"
}

CONF_URL=$(get_snap_value "url")
CONF_TAVILY=$(get_snap_value "tavily-key")
CONF_SERPER=$(get_snap_value "serper-key")
CONF_OPENAI=$(get_snap_value "openai-key")
CONF_ANTHROPIC=$(get_snap_value "anthropic-key")
CONF_GROQ=$(get_snap_value "groq-key")

export GAIA_LLM_URL="${CONF_URL:-http://127.0.0.1:13305}"
export GAIA_LLM_EXTERNAL_URL="$GAIA_LLM_URL"

pkill -f "socat TCP-LISTEN" 2>/dev/null || true

TARGET_IP=$(echo "$GAIA_LLM_URL" | grep -oP 'http://\K[^:]+' || true)
TARGET_PORT=$(echo "$GAIA_LLM_URL" | grep -oP 'http://[^:]+:\K\d+' || true)

if [ -z "$TARGET_IP" ]; then TARGET_IP="127.0.0.1"; fi
if [ -z "$TARGET_PORT" ]; then TARGET_PORT="13305"; fi

if [[ "$TARGET_IP" != "127.0.0.1" && "$TARGET_IP" != "localhost" ]]; then
    echo "======================================================================="
    echo "🛰️ DEPLOYING HARD CONTAINER INTERCEPT MATRIX"
    echo "   -> Intercept Target (Internal Container): http://127.0.0.1:13305"
    echo "   -> Remote Rig Destination Address       : http://${TARGET_IP}:${TARGET_PORT}"
    echo "======================================================================="
    $SNAP/bin/socat TCP-LISTEN:13305,bind=127.0.0.1,fork,reuseaddr TCP:${TARGET_IP}:${TARGET_PORT} &
else
    echo "💻 Local Host Mode Active: Letting internal traffic pass natively out to host machine port 13305"
fi

if [ -n "$CONF_OPENAI" ]; then export OPENAI_API_KEY="$CONF_OPENAI"; fi
if [ -n "$CONF_ANTHROPIC" ]; then export ANTHROPIC_API_KEY="$CONF_ANTHROPIC"; fi
if [ -n "$CONF_GROQ" ]; then export GROQ_API_KEY="$CONF_GROQ"; fi
if [ -n "$CONF_TAVILY" ]; then export TAVILY_API_KEY="$CONF_TAVILY"; echo "🔑 Tavily key armed."; fi
if [ -n "$CONF_SERPER" ]; then export SERPER_API_KEY="$CONF_SERPER"; echo "🔑 Serper key armed."; fi

REAL_USER=$(logname 2>/dev/null || echo $USER)

# 🗺️ NATIVE COMPLIANT 3-TIER CONTROL LEDGER
if snapctl is-connected home 2>/dev/null; then
    echo "🔓 SECURITY MATRIX TIER 3: Unrestricted NATIVE READ-WRITE home folder access active."
elif snapctl is-connected home-read-only 2>/dev/null; then
    echo "🔒 SECURITY MATRIX TIER 2: Kernel-enforced READ-ONLY home access active."
    mkdir -p "/home/${REAL_USER}/GaiaShares" 2>/dev/null || true
else
    echo "❌ SECURITY MATRIX TIER 1: Total isolation active. Home folder reading and writing BLOCKED."
fi

# Securely bind the internal agent generation engine straight to the sandboxed runtime directory
USER_AGENT_DIR="${SNAP_USER_DATA}/.gaia/agents/network-wizard"
echo "📡 Forcing custom network wizard agent deployment to: $USER_AGENT_DIR"
mkdir -p "$USER_AGENT_DIR"
if [ -f "$SNAP/network-wizard/agent.py" ]; then
    cp -av "$SNAP/network-wizard/agent.py" "$USER_AGENT_DIR/"
fi

# Pre-seed user cache path structures generics
mkdir -p "$SNAP_USER_DATA/.gaia/cache"
HOST_USER_SNAP_DIR="/home/${REAL_USER}/snap/amd-gaia/x1"
mkdir -p "$HOST_USER_SNAP_DIR/.gaia/cache" 2>/dev/null || true

# Pre-seed the verified structured allowlist path template matching GAIA's data model properties exactly
cat <<EOF > /tmp/allowed_paths.tmp
{
  "paths": [
    "/home/${REAL_USER}/Documents",
    "/home/${REAL_USER}/Downloads",
    "/home/${REAL_USER}/Desktop"
  ]
}
EOF
cp -a /tmp/allowed_paths.tmp "$SNAP_USER_DATA/.gaia/cache/allowed_paths.json"
cp -a /tmp/allowed_paths.tmp "$HOST_USER_SNAP_DIR/.gaia/cache/allowed_paths.json" 2>/dev/null || true
chmod 666 "$HOST_USER_SNAP_DIR/.gaia/cache/allowed_paths.json" 2>/dev/null || true
rm -f /tmp/allowed_paths.tmp

echo "🛡️ Generic Security Allowlist initialized cleanly for user [${REAL_USER}]"

# =====================================================================
# ⚡ THE SYSTEM-WIDE INTERPROCESS BOOTSTRAP INJECTION
# Deploy our bootstrap module and force-prepend it to Python's environment paths.
# This forces BOTH process namespaces to implement our patches before initialization!
# =====================================================================
BOOTSTRAP_DIR="${SNAP_USER_DATA}/.gaia/bootstrap"
mkdir -p "$BOOTSTRAP_DIR"
cp -af "$SNAP/_gaia_sandbox_patch.py" "$BOOTSTRAP_DIR/sitecustomize.py"

export PYTHONPATH="$BOOTSTRAP_DIR:$PYTHONPATH"
echo "🔌 Interprocess Concurrency Bootstrap Matrix wired to environment context path maps."

# --- CORE GRAPHICAL DESKTOP HANDOFF ---
TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)
echo "🚀 Initializing GAIA Framework Engine..."
exec "$TARGET_EXEC" "--no-sandbox" "$@"
