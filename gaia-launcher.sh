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

# Bypass proxies for Lemonade / GAIA internal traffic
export NO_PROXY="127.0.0.1,localhost,${REMOTE_HOST},${NO_PROXY}"
export no_proxy="127.0.0.1,localhost,${REMOTE_HOST},${no_proxy}"

# =====================================================================
# AGENT STORAGE & SYMLINK ALIGNMENT
# =====================================================================
# Point agent storage to the standard ~/.gaia/agents expected by backend discovery
export GAIA_AGENTS_DIR="${GAIA_AGENTS_DIR:-$GAIA_HOME/agents}"

if [ -n "${SNAP_USER_COMMON}" ]; then
    export GAIA_CONFIG_DIR="${GAIA_CONFIG_DIR:-$SNAP_USER_COMMON/.config/gaia}"
elif [ -n "${SNAP_USER_DATA}" ]; then
    export GAIA_CONFIG_DIR="${GAIA_CONFIG_DIR:-$SNAP_USER_DATA/.config/gaia}"
else
    export GAIA_CONFIG_DIR="${GAIA_CONFIG_DIR:-$HOME/.config/gaia}"
fi

# Provision target directories and set executable permissions
mkdir -p "${GAIA_HOME}" "${GAIA_AGENTS_DIR}" "${GAIA_CONFIG_DIR}" 2>/dev/null || true
chmod 755 "${GAIA_HOME}" "${GAIA_AGENTS_DIR}" "${GAIA_CONFIG_DIR}" 2>/dev/null || true

# Symlink $SNAP_USER_COMMON/agents -> ~/.gaia/agents to resolve UI vs. Backend path mismatches
if [ -n "${SNAP_USER_COMMON}" ]; then
    mkdir -p "${SNAP_USER_COMMON}/agents" 2>/dev/null || true
    ln -sfn "${SNAP_USER_COMMON}/agents" "${GAIA_AGENTS_DIR}" 2>/dev/null || true
fi

# =====================================================================
# UPDATER HARDENING
# =====================================================================
# Keep application self-updater checks disabled in Python backend
export GAIA_DISABLE_UPDATE_CHECK="true"

# Leave GAIA_DISABLE_UPDATE unset so Electron registers its IPC listeners,
# but redirect update cache to writable snap common
unset GAIA_DISABLE_UPDATE

# UV package index behavior & caching inside writable snap space
export UV_INDEX_STRATEGY="unsafe-best-match"
export UV_EXTRA_INDEX_URL="https://pypi.org/simple"
if [ -n "${SNAP_USER_COMMON}" ]; then
    export UV_CACHE_DIR="${SNAP_USER_COMMON}/.cache/uv"
    mkdir -p "${UV_CACHE_DIR}" 2>/dev/null || true
fi

# TMPDIR used by runtime dependencies
export TMPDIR="${XDG_RUNTIME_DIR:-/tmp}"

# Path setup for staged runtime files and dynamically installed agents
export PYTHONPATH="${SNAP}/lib/python_patches:${SNAP}/venv/lib/python3.12/site-packages:${PYTHONPATH}"
export PATH="${GAIA_AGENTS_DIR}/bin:${SNAP}/venv/bin:${SNAP}/usr/bin:${PATH}:/usr/bin:/bin"

# =====================================================================
# HYBRID RESOLUTION ENGINE: BACKEND & REMOTE LEMONADE MAPPING
# =====================================================================
RAW_LLM_URL="${backend_url}"

# Read backend URL from global snap configuration if present
if [ -z "$RAW_LLM_URL" ] && [ -f "${SNAP_COMMON}/etc/gaia/config.json" ]; then
    RAW_LLM_URL=$(grep -o '"url": "[^"]*"' "${SNAP_COMMON}/etc/gaia/config.json" | head -n 1 | cut -d'"' -f4)
fi

if [ -z "$RAW_LLM_URL" ] && command -v snapctl &>/dev/null; then
    RAW_LLM_URL=$(snapctl get backend.url 2>/dev/null || true)
fi

if [ -z "$RAW_LLM_URL" ]; then
    RAW_LLM_URL="http://127.0.0.1:13305"
fi

# Validate critical LLM URL setting
if [ -z "$RAW_LLM_URL" ] || [ "$RAW_LLM_URL" = "null" ]; then
    echo "ERROR: Failed to resolve LLM backend URL from any source. This is a critical configuration error." >&2
    exit 1
fi

# Normalize URL slashes and set standard GAIA 0.23.0 environment routing variables
CLEAN_LLM_URL=$(echo "$RAW_LLM_URL" | sed 's:/*$::')

if [[ "$CLEAN_LLM_URL" == */api/v1* ]]; then
    EXPORT_BASE_URL="$CLEAN_LLM_URL"
    CLEAN_HOST_URL=$(echo "$CLEAN_LLM_URL" | sed 's|/api/v1||')
else
    EXPORT_BASE_URL="${CLEAN_LLM_URL}/api/v1"
    CLEAN_HOST_URL="$CLEAN_LLM_URL"
fi

export GAIA_LLM_URL="${CLEAN_HOST_URL}"
export LEMONADE_BASE_URL="${EXPORT_BASE_URL}"
export GAIA_BACKEND_URL="${EXPORT_BASE_URL}"

[ "${GAIA_DEBUG}" = "1" ] && echo "INFO [DEBUG]: Resolved LLM URL to: ${GAIA_LLM_URL} | Lemonade: ${LEMONADE_BASE_URL}" >&2
echo "INFO: Classic Mode: Directing outbound AI model traffic to target server layout: ${LEMONADE_BASE_URL}"

# Write config manifest directly into user context to guarantee isolation safety
cat << EOF > "${GAIA_HOME}/config.json"
{
  "llm_url": "${CLEAN_HOST_URL}",
  "backend": {
    "url": "${EXPORT_BASE_URL}",
    "max_steps": ${GAIA_MAX_STEPS:-50}
  },
  "profile": "minimal"
}
EOF
cp "${GAIA_HOME}/config.json" "${GAIA_CONFIG_DIR}/config.json" 2>/dev/null || true

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
echo "[CONFIG] Set max-steps to $GAIA_MAX_STEPS"

export HTTP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
export REBUILD_USER_AGENT="${HTTP_USER_AGENT}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        cat <<'EOF'
Usage: gaia-desktop

Launches the GAIA desktop application from the snap runtime.

Environment toggles:
    GAIA_DEBUG=1                 Enable launcher debug logging
    GAIA_HOME=/path              Override GAIA home directory (default ~/.gaia)
    GAIA_AGENTS_DIR=/path        Override directory for installed agents (default ~/.gaia/agents)
    GAIA_MAX_STEPS=<int>         Override backend max steps
    GAIA_DISABLE_UPDATE=1        Disable auto-update checks
EOF
        exit 0
fi

# Select the desktop entrypoint deterministically
if [ -x "$SNAP/opt/GAIA/.gaia-desktop-bin" ]; then
    TARGET_EXEC="$SNAP/opt/GAIA/.gaia-desktop-bin"
elif [ -x "$SNAP/opt/GAIA/gaia-desktop" ]; then
    TARGET_EXEC="$SNAP/opt/GAIA/gaia-desktop"
else
    echo "ERROR: Failed to locate GAIA desktop executable in $SNAP/opt/GAIA." >&2
    exit 1
fi

echo "LOG: Synchronizing local workspace sentinel states..."
if [ -z "$SNAP_VERSION" ]; then
    SNAP_VERSION="0.23.0"
fi

if [ "$(id -u)" -ne 0 ]; then
    if [ -n "${GAIA_HOME}" ] && [ "${GAIA_HOME}" != "/" ] && [ "${GAIA_HOME}" != "/home" ]; then
        echo "INFO: Ensuring user ownership of ${GAIA_HOME}."
        sudo -n chown -R "$(id -u):$(id -g)" "${GAIA_HOME}" 2>/dev/null || true
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
  "version": "0.23.0"
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
            DYNAMIC_PORT=\$(echo "\${args[i+1]}" | tr -d '"\r\n ')
        fi
    done

    "${SNAP}/venv/bin/python3" "${SNAP}/venv/bin/gaia" "\$@" &
    BACKEND_PID=\$!

    _forward_exit() {
        kill "\$BACKEND_PID" 2>/dev/null || true
        wait "\$BACKEND_PID" 2>/dev/null || true
        exit 0
    }
    trap _forward_exit INT TERM

    timeout=40
    while [ \$timeout -gt 0 ]; do
        if "${SNAP}/venv/bin/python3" - "\$DYNAMIC_PORT" <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(0.2)
try:
    sock.connect(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    sock.close()
sys.exit(0)
PY
        then
            break
        fi
        sleep 0.2
        timeout=\$((timeout - 1))
    done

    wait \$BACKEND_PID
    BACKEND_STATUS=\$?
    trap - INT TERM
    exit \$BACKEND_STATUS
fi

exec "${SNAP}/venv/bin/gaia" "\$@"
EOF

chmod +x "${GAIA_HOME}/venv/bin/gaia"

echo "INFO: Launching GAIA desktop runtime."

# Electron stability flags for constrained environments
export ELECTRON_DISABLE_GPU=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1


# Transparently forward local port 13305 to remote Lemonade Server if using remote host
REMOTE_HOST=$(echo "$LEMONADE_BASE_URL" | sed -E 's|https?://([^:/]+).*|\1|')
REMOTE_PORT=$(echo "$LEMONADE_BASE_URL" | sed -E 's|https?://[^:]+:([0-9]+).*|\1|')
REMOTE_PORT=${REMOTE_PORT:-13305}

if [ "$REMOTE_HOST" != "127.0.0.1" ] && [ "$REMOTE_HOST" != "localhost" ]; then
    echo "INFO: Enabling local loopback proxy (127.0.0.1:13305 -> ${REMOTE_HOST}:${REMOTE_PORT}) for UI health checks..."
    
    python3 -c "
import socket, threading

def forward(src, dst):
    while True:
        data = src.recv(4096)
        if not data: break
        dst.sendall(data)

def handle(cli, r_host, r_port):
    try:
        srv = socket.create_connection((r_host, r_port))
        threading.Thread(target=forward, args=(cli, srv), daemon=True).start()
        threading.Thread(target=forward, args=(srv, cli), daemon=True).start()
    except Exception:
        cli.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 13305))
    s.listen(10)
    while True:
        cli, _ = s.accept()
        threading.Thread(target=handle, args=(cli, '${REMOTE_HOST}', ${REMOTE_PORT}), daemon=True).start()

main()
" &
fi



exec "$TARGET_EXEC" \
    --no-sandbox \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-dev-shm-usage \
    --disable-gpu-sandbox \
    --color-profile=srgb \
    --ui \
    --ui-port 4200