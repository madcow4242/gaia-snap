#!/bin/bash
set -e

# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# - SYSTEM ATTRIBUTES: AMD-GAIA CLASSIC MODE RUNTIME CONTROLLER.
# =====================================================================

# 🎯 THE FIX: Directly evaluates standard cross-system exported runtime environment settings
RAW_LLM_URL="${TARGET_BACKEND_URL:-http://127.0.0.1:13305}"

TARGET_IP=$(echo "$RAW_LLM_URL" | grep -oP 'http://\K[^:]+' || true)
TARGET_PORT=$(echo "$RAW_LLM_URL" | grep -oP 'http://[^:]+:\K\d+' || true)

if [ -z "$TARGET_IP" ]; then TARGET_IP="127.0.0.1"; fi
if [ -z "$TARGET_PORT" ]; then TARGET_PORT="13305"; fi

if [[ "$TARGET_IP" != "127.0.0.1" && "$TARGET_IP" != "localhost" ]]; then
    echo "🛰️ Classic Mode: Routing inference processing metrics out to remote server http://${TARGET_IP}:${TARGET_PORT}"
    export LEMONADE_BASE_URL="http://${TARGET_IP}:${TARGET_PORT}/api/v1"
    export GAIA_LLM_URL="http://${TARGET_IP}:${TARGET_PORT}"
    export GAIA_LLM_EXTERNAL_URL="http://${TARGET_IP}:${TARGET_PORT}"
else
    echo "💻 Classic Mode: Utilizing local loopback context (127.0.0.1:13305)"
    export GAIA_LLM_URL="http://127.0.0.1:13305"
    export GAIA_LLM_EXTERNAL_URL="http://127.0.0.1:13305"
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
