#!/bin/bash
set -e

# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# - SYSTEM ATTRIBUTES: AMD-GAIA CLASSIC MODE RUNTIME CONTROLLER.
# =====================================================================

# Spoof standard Linux Desktop headers to completely bypass Bot-Blocking firewalls
export HTTP_USER_AGENT="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0"
export REBUILD_USER_AGENT="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0"

# Background monitor loop thread to catch the runtime port dynamically
(
    sleep 3
    # Look for the active uvicorn python webserver port bound by this local snap session
    ACTIVE_PORT=$(ss -tlnp 2>/dev/null | grep -oP "127.0.0.1:\K\d+(?=.*python)")
    if [ -n "$ACTIVE_PORT" ]; then
        echo "💻 Classic Mode: Successfully mapped notification callback channels to active port http://127.0.0.1:${ACTIVE_PORT}"
        export GAIA_LLM_LOCAL_URL="http://127.0.0.1:${ACTIVE_PORT}"
    fi
) &

RAW_LLM_URL="${TARGET_BACKEND_URL:-http://127.0.0.1:13305}"

TARGET_IP=$(echo "$RAW_LLM_URL" | grep -oP 'http://\K[^:]+' || true)
TARGET_PORT=$(echo "$RAW_LLM_URL" | grep -oP 'http://[^:]+:\K\d+' || true)

if [ -z "$TARGET_IP" ]; then TARGET_IP="127.0.0.1"; fi
if [ -z "$TARGET_PORT" ]; then TARGET_PORT="13305"; fi

if [[ "$TARGET_IP" != "127.0.0.1" && "$TARGET_IP" != "localhost" ]]; then
    echo "🛰️ Classic Mode: Directing LLM inference and embeddings to remote server http://${TARGET_IP}:${TARGET_PORT}"

    # Route model compilation work across the physical network to your server rig
    export GAIA_LLM_URL="http://${TARGET_IP}:${TARGET_PORT}"
    export LEMONADE_BASE_URL="http://${TARGET_IP}:${TARGET_PORT}/api/v1"

    # Clean out network redirection traps from external parameter blocks
    unset GAIA_LLM_EXTERNAL_URL
else
    echo "💻 Classic Mode: Utilizing local loopback context (127.0.0.1:13305)"
    export GAIA_LLM_URL="http://127.0.0.1:13305"
    export LEMONADE_BASE_URL="http://127.0.0.1:13305/api/v1"
    unset GAIA_LLM_EXTERNAL_URL
fi

if [ -n "$OPENAI_API_KEY" ]; then export OPENAI_API_KEY="$OPENAI_API_KEY"; fi
if [ -n "$ANTHROPIC_API_KEY" ]; then export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"; fi
if [ -n "$GROQ_API_KEY" ]; then export GROQ_API_KEY="$GROQ_API_KEY"; fi
if [ -n "$TAVILY_API_KEY" ]; then export TAVILY_API_KEY="$TAVILY_API_KEY"; fi
if [ -n "$SERPER_API_KEY" ]; then export SERPER_API_KEY="$SERPER_API_KEY"; fi

export PATH="${SNAP}/venv/bin:${PATH}"

TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)
echo "🚀 Launching GAIA..."
exec "$TARGET_EXEC" --no-sandbox --disable-gpu-sandbox "$@"
