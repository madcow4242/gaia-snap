#!/bin/bash

# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# - SYSTEM ATTRIBUTES: AMD-GAIA SNAP PRODUCTION CONFIGURATION BUILDER.
# - CRITICAL: Perform a strict line-by-line regression audit before editing.
# - DO NOT alter, drop, or optimize any dynamic token extraction variables,
#   sqlite3 sweep tracking intervals, or fallback context boundaries.
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

# Dynamically parse the target configuration setting from the snap ledger metadata
export GAIA_LLM_URL="${CONF_URL:-http://127.0.0.1:13305}"
export GAIA_LLM_EXTERNAL_URL="$GAIA_LLM_URL"

pkill -f "socat TCP-LISTEN" 2>/dev/null || true

# Extract target coordinates safely using regular expressions
TARGET_IP=$(echo "$GAIA_LLM_URL" | grep -oP 'http://\K[^:]+' || true)
TARGET_PORT=$(echo "$GAIA_LLM_URL" | grep -oP 'http://[^:]+:\K\d+' || true)

if [ -z "$TARGET_IP" ]; then TARGET_IP="127.0.0.1"; fi
if [ -z "$TARGET_PORT" ]; then TARGET_PORT="13305"; fi

# Check if we should activate the network bypass or let the local host handle it
if [[ "$TARGET_IP" != "127.0.0.1" && "$TARGET_IP" != "localhost" ]]; then
    echo "======================================================================="
    echo "🚀 DEPLOYING HARD CONTAINER INTERCEPT MATRIX"
    echo "   -> Intercept Target (Internal Container): http://127.0.0.1:13305"
    echo "   -> Remote Rig Destination Address       : http://${TARGET_IP}:${TARGET_PORT}"
    echo "======================================================================="

    # Launch a persistent background forwarder inside the private container environment.
    $SNAP/bin/socat TCP-LISTEN:13305,bind=127.0.0.1,fork,reuseaddr TCP:${TARGET_IP}:${TARGET_PORT} &
else
    echo "💡 Local Host Mode Active: Letting internal traffic pass natively out to host machine port 13305"
fi

if [ -n "$CONF_OPENAI" ]; then export OPENAI_API_KEY="$CONF_OPENAI"; fi
if [ -n "$CONF_ANTHROPIC" ]; then export ANTHROPIC_API_KEY="$CONF_ANTHROPIC"; fi
if [ -n "$CONF_GROQ" ]; then export GROQ_API_KEY="$CONF_GROQ"; fi
if [ -n "$CONF_TAVILY" ]; then export TAVILY_API_KEY="$CONF_TAVILY"; echo "? Tavily key armed."; fi
if [ -n "$CONF_SERPER" ]; then export SERPER_API_KEY="$CONF_SERPER"; echo "? Serper key armed."; fi

REAL_USER=$(logname 2>/dev/null || echo $USER)
USER_AGENT_DIR="/home/${REAL_USER}/snap/amd-gaia/x1/.gaia/agents/network-wizard"
echo "? Forcing custom network wizard agent deployment to: $USER_AGENT_DIR"
mkdir -p "$USER_AGENT_DIR"
if [ -f "$SNAP/network-wizard/agent.py" ]; then
    cp -av "$SNAP/network-wizard/agent.py" "$USER_AGENT_DIR/"
fi

# --- CORE GRAPHICAL DESKTOP HANDOFF ---
TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)
echo "? Initializing GAIA Framework Engine..."
exec "$TARGET_EXEC" "--no-sandbox" "$@"
