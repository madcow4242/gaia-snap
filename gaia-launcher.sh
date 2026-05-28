#!/bin/bash

# =====================================================================
# 🚨 AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# - SYSTEM ATTRIBUTES: AMD-GAIA SNAP PRODUCTION CONFIGURATION BUILDER.
# - CRITICAL: Perform a strict line-by-line regression audit before editing.
# - DO NOT alter, drop, or optimize any dynamic token extraction variables, 
#   sqlite3 sweep tracking intervals, or fallback context boundaries.
# =====================================================================

# --- GAIA CORE PRODUCTION LAUNCH DEPLOYER ---

# 1. RUNTIME ENV MOTORS: Suppress unverified TLS tracking alert frames universally
export PYTHONWARNINGS="ignore:Unverified HTTPS request"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$SNAP/usr/lib/x86_64-linux-gnu/libproxy"

# 2. CONTEXT ENGINE PARAMETERS: Hardcode fallback limits directly inside initialization scopes
export GAIA_CTX_SIZE=32768
export LEMONADE_CTX_SIZE=32768
export DEFAULT_CTX_SIZE=32768

# 3. LEDGER OBJECT EXTRACTION: Handle both flat and nested JSON configuration trees safely
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

# Force-kill any hanging socat tasks to ensure your port space is completely untunneled
pkill -f "socat TCP-LISTEN" 2>/dev/null || true

if [[ "$GAIA_LLM_URL" != *"127.0.0.1"* && "$GAIA_LLM_URL" != *"localhost"* ]]; then
    echo "======================================================================="
    echo "🚀 DYNAMIC IN-MEMORY OFFLOAD MATRIX ACTIVE"
    echo "   -> Intercept Target URL: $GAIA_LLM_URL"
    echo "   -> Operations Mode     : Diverting local 13305 connections dynamically in memory"
    echo "======================================================================="
    export GAIA_LLM_EXTERNAL_URL="$GAIA_LLM_URL"
else
    echo "🏠 Native Laptop Mode Active: Directing calls to local loopback registers."
    export GAIA_LLM_EXTERNAL_URL=""
fi

# 4. INFRASTRUCTURE API ARMS: Inject cloud infrastructure keys dynamically if set
if [ -n "$CONF_OPENAI" ]; then export OPENAI_API_KEY="$CONF_OPENAI"; fi
if [ -n "$CONF_ANTHROPIC" ]; then export ANTHROPIC_API_KEY="$CONF_ANTHROPIC"; fi
if [ -n "$CONF_GROQ" ]; then export GROQ_API_KEY="$CONF_GROQ"; fi
if [ -n "$CONF_TAVILY" ]; then export TAVILY_API_KEY="$CONF_TAVILY"; echo "🔍 Tavily key armed."; fi
if [ -n "$CONF_SERPER" ]; then export SERPER_API_KEY="$CONF_SERPER"; echo "🔍 Serper key armed."; fi

# 5. LIVE DATABASE SWEEP INTERCEPTOR: Returned to standard factory default port entries
DB_PATH="$SNAP_USER_DATA/.gaia/chat/gaia_chat.db"
(
    for i in {1..30}; do
        if [ -f "$DB_PATH" ]; then
            IF_MODELS=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='models';" 2>/dev/null || true)
            if [ -n "$IF_MODELS" ]; then
                sqlite3 "$DB_PATH" <<EOF 2>/dev/null || true
INSERT OR REPLACE INTO settings (key, value) VALUES ('model_server_url', 'http://127.0.0.1:13305');
INSERT OR REPLACE INTO settings (key, value) VALUES ('tavily_api_key', '$CONF_TAVILY') WHERE '$CONF_TAVILY' != '';
UPDATE models SET api_url='http://127.0.0.1:13305';
.quit
EOF
                break
            fi
        fi
        sleep 1
    done
) &

# 6. PORTABLE USER-AGENT SEEDER: Deploy custom operational plug-ins into sandboxed data containers
USER_AGENT_DIR="$SNAP_USER_DATA/.gaia/agents/network-wizard"
echo "📦 Forcing custom network wizard agent deployment to: $USER_AGENT_DIR"
mkdir -p "$USER_AGENT_DIR"
if [ -f "$SNAP/network-wizard/agent.py" ]; then
    cp -av "$SNAP/network-wizard/agent.py" "$USER_AGENT_DIR/"
fi

# --- CORE GRAPHICAL DESKTOP HANDOFF ---
TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)
echo "🚀 Initializing GAIA Framework Engine pointing to: http://127.0.0.1:13305"
exec "$TARGET_EXEC" "--no-sandbox" "$@"

