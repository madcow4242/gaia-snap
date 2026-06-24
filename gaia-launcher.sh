#!/bin/bash
set -e

stty sane 2>/dev/null || true
printf "\033[K"

# Runtime environment setup
export HOME="${HOME}"
export GAIA_HOME="${HOME}/.gaia"
export GAIA_ALLOW_ORIGINS="*"
export PYTHONWARNINGS="default"
export PYTHONNOUSERSITE=1

# Disable updater behavior inside packaged runtime
export GAIA_DISABLE_UPDATE=1
export GAIA_DISABLE_UPDATE_CHECK="true"

# UV package index behavior
export UV_INDEX_STRATEGY="unsafe-best-match"
export UV_EXTRA_INDEX_URL="https://pypi.org/simple"

# TMPDIR used by runtime dependencies
export TMPDIR=$XDG_RUNTIME_DIR

# Path setup for staged runtime files
export PYTHONPATH="${SNAP}/lib/python_patches:${PYTHONPATH}"
export PATH="${SNAP}/venv/bin:${SNAP}/usr/bin:${PATH}:/usr/bin:/bin"

# HYBRID RESOLUTION ENGINE: Pull from environment vars or fall back to snapctl
RAW_LLM_URL="${backend_url}"
if [ -z "$RAW_LLM_URL" ] && command -v snapctl &>/dev/null; then
    RAW_LLM_URL=$(snapctl get backend.url 2>/dev/null || true)
fi
if [ -z "$RAW_LLM_URL" ]; then
    RAW_LLM_URL="http://127.0.0.1:13305"
fi

# Validate critical LLM URL setting
if [ -z "$RAW_LLM_URL" ] || [ "$RAW_LLM_URL" = "null" ]; then
    echo "ERROR: Failed to resolve LLM backend URL from any source (env var, snapctl, hardcoded default). This is a critical configuration error." >&2
    echo "DEBUG: Attempted sources: backend_url env var, snapctl backend.url, hardcoded default http://127.0.0.1:13305" >&2
    exit 1
fi

export GAIA_LLM_URL="${RAW_LLM_URL}"
export LEMONADE_BASE_URL="${RAW_LLM_URL}/api/v1"

[ "${GAIA_DEBUG}" = "1" ] && echo "INFO [DEBUG]: Resolved LLM URL to: ${GAIA_LLM_URL} (from backend_url env var or snapctl)" >&2
echo "INFO: Classic Mode: Directing outbound AI model traffic to target server layout: ${GAIA_LLM_URL}"

# Resolve optional provider API keys from env vars or snapctl
for service in openai anthropic groq tavily serper; do
    VAL=""
    case "$service" in
        openai)    VAL="${keys_openai:-$(command -v snapctl &>/dev/null && snapctl get keys.openai || echo '')}" ;;
        anthropic) VAL="${keys_anthropic:-$(command -v snapctl &>/dev/null && snapctl get keys.anthropic || echo '')}" ;;
        groq)      VAL="${keys_groq:-$(command -v snapctl &>/dev/null && snapctl get keys.groq || echo '')}" ;;
        tavily)    VAL="${keys_tavily:-$(command -v snapctl &>/dev/null && snapctl get keys.tavily || echo '')}" ;;
        serper)    VAL="${keys_serper:-$(command -v snapctl &>/dev/null && snapctl get keys.serper || echo '')}" ;;
    esac

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

# Resolve max-steps from env vars or snapctl
MAX_STEPS="${backend_maxsteps}"
if [ -z "$MAX_STEPS" ] && command -v snapctl &>/dev/null; then
    MAX_STEPS=$(snapctl get backend.maxsteps 2>/dev/null || true)
fi
if [ -z "$MAX_STEPS" ]; then
    MAX_STEPS=20
fi

# Validate MAX_STEPS is a positive integer
if ! [[ "$MAX_STEPS" =~ ^[0-9]+$ ]] || [ "$MAX_STEPS" -lt 1 ]; then
    echo "WARNING: Invalid MAX_STEPS value '$MAX_STEPS'. Resetting to default (20)." >&2
    MAX_STEPS=20
fi

export GAIA_MAX_STEPS="${MAX_STEPS}"
[ "${GAIA_DEBUG}" = "1" ] && echo "INFO [DEBUG]: Resolved max-steps to: $GAIA_MAX_STEPS" >&2
echo "[CONFIG] Set max-steps to $GAIA_MAX_STEPS "

export HTTP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
export REBUILD_USER_AGENT="${HTTP_USER_AGENT}"

TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)
if [ -z "$TARGET_EXEC" ]; then
    echo "ERROR: Failed to locate core executable launcher binary inside packaged opt footprint tree." >&2
    exit 1
fi

echo "LOG: Synchronizing local workspace sentinel states..."
if [ -z "$SNAP_VERSION" ]; then
    SNAP_VERSION="0.21.2"
fi

if [ "$(id -u)" -ne 0 ]; then
    if [ -n "${GAIA_HOME}" ] && [ "${GAIA_HOME}" != "/" ] && [ "${GAIA_HOME}" != "/home" ]; then
        echo "INFO: Ensuring user ownership of ${GAIA_HOME}."
        sudo chown -R "$(id -u):$(id -g)" "${GAIA_HOME}" 2>/dev/null || true
    else
        echo "ERROR: GAIA_HOME target path is invalid or unbound! Aborting ownership sync to protect host."
        exit 1
    fi
fi

rm -rf "${GAIA_HOME}/venv"
mkdir -p "${GAIA_HOME}/venv/bin"

cat << EOF > "${GAIA_HOME}/electron-install-state.json"
{
  "status": "ready",
  "version": "0.21.2"
}
EOF

cat << EOF > "${GAIA_HOME}/venv/bin/gaia"
#!/bin/bash
if [ "\$1" = "--version" ]; then
    echo "${SNAP_VERSION}"
    exit 0
fi

if [ "\$1" = "chat" ]; then
    DYNAMIC_PORT=34681
    args=(\"\$@\")
    for ((i=0; i<\${#args[@]}; i++)); do
        if [ "\${args[i]}" = "--ui-port" ]; then
            # Clean and strip quotes/whitespace from the port input string safely
            DYNAMIC_PORT=\$(echo "\${args[i+1]}" | tr -d '"\r\n ')
        fi
    done

    # Absolute fallback routing drop-out preventing cyclic interpreter wrapper loops
    "${SNAP}/venv/bin/python3" "${SNAP}/venv/bin/gaia" "\$@" &
    BACKEND_PID=\$!

    timeout=40
    # Clean evaluation string ensures nc interprets an exact integer port
    while ! nc -z 127.0.0.1 "\$DYNAMIC_PORT" && [ \$timeout -gt 0 ]; do
        sleep 0.2
        timeout=\$((timeout - 1))
    done

    wait \$BACKEND_PID
    exit \$?
fi

exec "${SNAP}/venv/bin/gaia" "\$@"
EOF

chmod +x "${GAIA_HOME}/venv/bin/gaia"

echo "INFO: Launching GAIA desktop runtime."

# Electron stability flags for constrained environments
export ELECTRON_DISABLE_GPU=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1

exec "$TARGET_EXEC" \
    --no-sandbox \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-dev-shm-usage \
    --disable-gpu-sandbox \
    --color-profile=srgb