#!/bin/bash

# 1. Silently suppress unverified TLS sandbox tracking warning alerts
export PYTHONWARNINGS="ignore:Unverified HTTPS request"

# 2. Force core24 proxy mechanics to natively resolve libpxbackend paths
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$SNAP/usr/lib/x86_64-linux-gnu/libproxy"

# 3. CONTEXT OVERRIDES: Force hardcoded fallback bounds right inside environment definitions
export GAIA_CTX_SIZE=32768
export LEMONADE_CTX_SIZE=32768
export DEFAULT_CTX_SIZE=32768

# 4. PORT PRESERVATION: Restored your preferred lemonade target address mapping
export GAIA_LLM_URL="http://127.0.0.1:13305" 

# 5. DYNAMIC SEEDER: Mount our custom agent folder inside user data before boot execution
USER_AGENT_DIR="$SNAP_USER_DATA/.gaia/agents/network-wizard"
if [ ! -d "$USER_AGENT_DIR" ]; then
    echo "📦 Seeding custom network wizard agent into configuration space..."
    mkdir -p "$SNAP_USER_DATA/.gaia/agents"
    cp -av "$SNAP/usr/share/gaia-agents/network-wizard" "$SNAP_USER_DATA/.gaia/agents/"
fi

# 6. Securely search and execute the primary graphic binary sitting inside opt/GAIA/
TARGET_EXEC=$(find "$SNAP/opt/GAIA" -maxdepth 1 -type f -executable | head -n 1)

if [ -n "$TARGET_EXEC" ] && [ -f "$TARGET_EXEC" ]; then
    echo "🚀 Initializing GAIA Framework Engine: $TARGET_EXEC"
    exec "$TARGET_EXEC" "--no-sandbox" "$@"
else
    echo "❌ CRITICAL: Could not find the core desktop binary inside $SNAP/opt/GAIA/"
    exit 1
fi

