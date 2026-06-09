#!/bin/bash
set -e

stty sane 2>/dev/null || true
printf "\033[K"

export HOME="${HOME}"
export GAIA_HOME="${HOME}/.gaia"
export GAIA_ALLOW_ORIGINS="*"
export PYTHONWARNINGS="default"

export PYTHONPATH="${HOME}/.gaia/bootstrap:$PYTHONPATH"

RAW_LLM_URL=$(snapctl get backend.url)
if [ -z "$RAW_LLM_URL" ]; then RAW_LLM_URL="http://127.0.0.1:13305"; fi

TARGET_IP=$(echo "$RAW_LLM_URL" | grep -oP 'http://\K[^:]+' || true)
TARGET_PORT=$(echo "$RAW_LLM_URL" | grep -oP 'http://[^:]+:\K\d+' || true)

if [ -z "$TARGET_IP" ]; then TARGET_IP="127.0.0.1"; fi
if [ -z "$TARGET_PORT" ]; then TARGET_PORT="13305"; fi

echo "🛰️ Classic Mode: Directing outbound AI model traffic to remote server target http://${TARGET_IP}:${TARGET_PORT}"
export GAIA_LLM_URL="http://${TARGET_IP}:${TARGET_PORT}"
export LEMONADE_BASE_URL="http://${TARGET_IP}:${TARGET_PORT}/api/v1"

K_OPENAI=$(snapctl get keys.openai)
K_ANTHROPIC=$(snapctl get keys.anthropic)
K_GROQ=$(snapctl get keys.groq)
K_TAVILY=$(snapctl get keys.tavily)
K_SERPER=$(snapctl get keys.serper)

if [ -n "$K_OPENAI" ]; then export OPENAI_API_KEY="$K_OPENAI"; fi
if [ -n "$K_ANTHROPIC" ]; then export ANTHROPIC_API_KEY="$K_ANTHROPIC"; fi
if [ -n "$K_GROQ" ]; then export GROQ_API_KEY="$K_GROQ"; fi
if [ -n "$K_TAVILY" ]; then export TAVILY_API_KEY="$K_TAVILY"; fi
if [ -n "$K_SERPER" ]; then export SERPER_API_KEY="$K_SERPER"; fi

export HTTP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
export REBUILD_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"

export PATH="${SNAP}/venv/bin:${PATH}"
TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)
echo "🚀 Launching GAIA..."
exec "$TARGET_EXEC" --no-sandbox --disable-gpu-sandbox "$@"