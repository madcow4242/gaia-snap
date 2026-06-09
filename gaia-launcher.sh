#!/bin/bash
set -e

stty sane 2>/dev/null || true
printf "\033[K"

# Configure local application workspace filesystem registries
export HOME="${HOME}"
export GAIA_HOME="${HOME}/.gaia"
export GAIA_ALLOW_ORIGINS="*"
export PYTHONWARNINGS="default"
export PYTHONNOUSERSITE=1

# The officially supported updater suppression hooks
export GAIA_DISABLE_UPDATE=1
export GAIA_DISABLE_UPDATE_CHECK="true"

# 🎯 THE UNIVERSAL PORTABLE PATCH INJECTOR
# We append the read-only snap environment folder to PYTHONPATH.
# This forces whichever Python interpreter GAIA launches (host or snap)
# to load our sitecustomize memory hook on boot automatically!
export PYTHONPATH="${SNAP}/lib/python_patches:${PYTHONPATH}"

# Append the self-contained python execution path cleanly to top-level shells
export PATH="${SNAP}/venv/bin:/usr/bin:/bin:/usr/sbin:/sbin"

RAW_LLM_URL=$(snapctl get backend.url)
if [ -z "$RAW_LLM_URL" ]; then
    RAW_LLM_URL="http://127.0.0.1:13305"
fi

export GAIA_LLM_URL="${RAW_LLM_URL}"
export LEMONADE_BASE_URL="${RAW_LLM_URL}/api/v1"

echo "INFO: Classic Mode: Directing outbound AI model traffic to target server layout: ${GAIA_LLM_URL}"

for service in openai anthropic groq tavily serper; do
    VAL=$(snapctl get "keys.${service}")
    if [ -n "$VAL" ]; then
        case "$service" in
            openai)    export OPENAI_API_KEY="$VAL" ;;
            anthropic) export ANTHROPIC_API_KEY="$VAL" ;;
            groq)      export GROQ_API_KEY="$VAL" ;;
            tavily)    export TAVILY_API_KEY="$VAL" ;;
            serper)    export SERPER_API_KEY="$VAL" ;;
        esac
    fi
done

export HTTP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
export REBUILD_USER_AGENT="${HTTP_USER_AGENT}"

TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)
if [ -z "$TARGET_EXEC" ]; then
    echo "ERROR: Failed to locate core executable launcher binary inside packaged opt footprint tree." >&2
    exit 1
fi

echo "LOG: Initializing GAIA Portable Production Core Infrastructure Engine..."
exec "$TARGET_EXEC" --no-sandbox --disable-dev-shm-usage "$@"