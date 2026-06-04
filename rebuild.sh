#!/bin/bash
set -e

# =====================================================================
# 🌐 CONFIGURATION ENVIRONMENT AGGREGATION LAYER
# =====================================================================
# Dynamically load variables from a local .env wrapper if present
if [ -f .env ]; then
    export $(echo $(grep -v '^#' .env | xargs) | envsubst)
fi

# Apply generic fallback defaults to protect against null-pointer exceptions
FINAL_BACKEND_URL="${TARGET_BACKEND_URL:-http://127.0.0.1:13305}"
FINAL_TAVILY_KEY="${TAVILY_API_KEY:-}"

# Fallback baseline version number if GAIA_VERSION isn't explicitly defined in .env
export GAIA_VERSION="${GAIA_VERSION:-0.20.0}"

# 🌟 AUTOMATED CLEAN RESTORE CLEANUP TRAP: Guarantees your master file rolls back safely even on early exit errors
cleanup_yaml_token() {
    echo "🧼 Restoring snapcraft.yaml placeholder matrices..."
    sed -i "s/releases\/download\/v${GAIA_VERSION}/releases\/download\/v@GAIA_VERSION@/g" snap/snapcraft.yaml || true
    sed -i "s/gaia-agent-ui-${GAIA_VERSION}-amd64.deb/gaia-agent-ui-@GAIA_VERSION@-amd64.deb/g" snap/snapcraft.yaml || true
    sed -i "s/source-tag: v${GAIA_VERSION}/source-tag: v@GAIA_VERSION@/g" snap/snapcraft.yaml || true
    sed -i "s/set version=\"${GAIA_VERSION}\"/set version=\"@GAIA_VERSION@\"/g" snap/snapcraft.yaml || true
}
trap cleanup_yaml_token EXIT

echo "📝 Injecting dynamic target build version parameter context: v${GAIA_VERSION}"
sed -i "s/releases\/download\/v@GAIA_VERSION@/releases\/download\/v${GAIA_VERSION}/g" snap/snapcraft.yaml
sed -i "s/gaia-agent-ui-@GAIA_VERSION@-amd64.deb/gaia-agent-ui-${GAIA_VERSION}-amd64.deb/g" snap/snapcraft.yaml
sed -i "s/source-tag: v@GAIA_VERSION@/source-tag: v${GAIA_VERSION}/g" snap/snapcraft.yaml
sed -i "s/set version=\"@GAIA_VERSION@\"/set version=\"${GAIA_VERSION}\"/g" snap/snapcraft.yaml

echo "🔍 Validating administrative credentials..."
if ! sudo -n true 2>/dev/null; then
    echo "🔑 Sudo authorization required. Please enter your password below:"
    sudo true
fi
sudo -v

echo "💀 Killing any active or lingering zombie processes across namespaces..."
{
    sudo pkill -9 -f "amd-gaia" || true
    sudo pkill -9 -f "socat" || true
    sudo pkill -9 -f "gaia" || true
    sudo pkill -9 -f ".gaia-desktop-bin" || true
} >/dev/null 2>&1

wait 2>/dev/null || true
printf "\033[K"
stty sane

echo "🧹 [1/6] Purging old tracking states universally..."
rm -rf "$HOME/snap/amd-gaia/common/.cache/" "$HOME/snap/amd-gaia/current/.cache/"
rm -rf "$HOME/snap/amd-gaia/x1/.gaia/venv"
rm -f "$HOME/snap/amd-gaia/x1/.gaia/backend.pid"

echo "🔓 Clearing root-owned file locks from current working directory..."
sudo chown -R $(id -u):$(id -g) .

if [ "$1" == "--clean" ]; then
    echo "🧼 [2/6] Deep cleaning ALL Snapcraft cache layers from scratch..."
    sudo snapcraft clean
else
    echo "🏎️ [2/6] Incremental Mode: Resetting Python backend module targets only..."
    sudo snapcraft clean gaia-backend
    sudo snapcraft clean gaia-sideloads
fi

echo "📦 [3/6] Compiling and packaging fresh production Snap..."
sudo snapcraft pack

# =====================================================================
# ⚡ DYNAMIC UPGRADE-PROOF INTERCEPT MATRIX
# =====================================================================
echo "⚡ [3.5/6] Intercepting production Snap to inject Custom HTTP API Bridge..."

SNAP_FILE=$(ls -t *.snap | head -n 1)
WORK_DIR=$(mktemp -d)
echo "📂 Created temporary workspace container: $WORK_DIR"

DEB_URL="https://github.com/amd/gaia/releases/download/v${GAIA_VERSION}/gaia-agent-ui-${GAIA_VERSION}-amd64.deb"
echo "🌐 Downloading pristine v${GAIA_VERSION} UI layer mapping matrix..."
curl -L -s -o "$WORK_DIR/gaia-ui.deb" "$DEB_URL"

echo "📦 Extracting pristine app.asar from download package..."
dpkg-deb -x "$WORK_DIR/gaia-ui.deb" "$WORK_DIR/deb_extracted"
cp "$WORK_DIR/deb_extracted/opt/GAIA/resources/app.asar" "$WORK_DIR/app.asar"

echo "🔧 Unpacking native ASAR source tree structure..."
npx asar extract "$WORK_DIR/app.asar" "$WORK_DIR/asar_extracted"

TARGET_CJS=$(find "$WORK_DIR/asar_extracted" -name "notification-service.cjs" | head -n 1)

if [ -z "$TARGET_CJS" ]; then
    echo "❌ Error: Could not locate notification-service.cjs inside the ASAR tree!"
    exit 1
fi

echo "💉 Surgically splicing custom HTTP Matrix Hook into native function signature..."
node -e '
const fs = require("fs");
const filePath = process.argv[1];
let content = fs.readFileSync(filePath, "utf8");

const targetAnchor = "_respondToPermission(notifId, action, remember) {";

const injectionPayload = `
    console.log(\`[notif-debug] Intercepting Token Approval Matrix via Dynamic Injected HTTP Bridge: "\${notifId}"\`);
    try {
      if (this.mainWindow && this.mainWindow.webContents) {
        const fullWindowUrlStr = this.mainWindow.webContents.getURL();
        const parsedUrlObj = new URL(fullWindowUrlStr.replace("file://", "http://localhost"));
        const apiParamValue = parsedUrlObj.searchParams.get("api");
        if (apiParamValue) {
          const apiEndpointUrl = new URL(apiParamValue);
          const targetApiUrl = \`http://127.0.0.1:\${apiEndpointUrl.port}/api/sandbox/resolve\`;
          const payload = { confirm_id: notifId, approved: action === "allow" };
          const { net } = require("electron");
          const request = net.request({ method: "POST", url: targetApiUrl });
          request.setHeader("Content-Type", "application/json");
          request.on("error", () => {}); // Catch safely to ensure no main-thread panics
          request.write(JSON.stringify(payload));
          request.end();
          console.log(\`[notif-debug] Injected Matrix transaction dispatched successfully to port: \${apiEndpointUrl.port}\`);
        }
      }
    } catch (err) {
      console.error(\`[notif-debug] Injected dynamic bridge exception:\`, err.message);
    }
`;

if (content.includes(targetAnchor)) {
    content = content.replace(targetAnchor, targetAnchor + injectionPayload);
    fs.writeFileSync(filePath, content, "utf8");
    console.log("✅ Code spliced into notification-service.cjs seamlessly.");
} else {
    console.error("❌ Error: Target function anchor was not found inside notification-service.cjs!");
    process.exit(1);
}
' "$TARGET_CJS"

echo "🔒 Repacking custom app.asar file asset..."
npx asar pack "$WORK_DIR/asar_extracted" "$WORK_DIR/app.asar"

echo "💾 Unsquashing the compiled .snap container archive..."
sudo unsquashfs -d "$WORK_DIR/snap_extracted" "$SNAP_FILE"

echo "🔄 Swapping native app.asar inside the target Snap payload tree..."
sudo cp "$WORK_DIR/app.asar" "$WORK_DIR/snap_extracted/opt/GAIA/resources/app.asar"

echo "🗜️ Re-compressing the final optimized Snap container bundle..."
rm -f "$SNAP_FILE"
sudo mksquashfs "$WORK_DIR/snap_extracted" "$SNAP_FILE" -comp xz

sudo rm -rf "$WORK_DIR"
echo "✨ Dynamic self-healing injection complete! Package sealed successfully."
# =====================================================================

echo "💀 [4/6] Sweeping and terminating remaining background GAIA/Python processes..."
sudo killall -9 gaia .gaia-desktop-bin socat python3 chromium-browser 2>/dev/null || true

echo "🗑️ [5/6] Uninstalling previous system Snap hooks..."
sudo snap remove amd-gaia || true

echo "🚀 [6/6] Deploying unified snap bundle locally..."
sudo snap install "./$SNAP_FILE" --dangerous

echo "📋 Pre-seeding generic system parameter routing configurations..."
sudo snap set amd-gaia backend.url="$FINAL_BACKEND_URL"
if [ -n "$FINAL_TAVILY_KEY" ]; then
    sudo snap set amd-gaia backend.tavily-key="$FINAL_TAVILY_KEY"
fi

echo "🔗 Re-linking broken OS symlinks and formatting data containers..."
rm -rf "$HOME/snap/amd-gaia/current"
mkdir -p "$HOME/snap/amd-gaia/x1/.gaia/chat"
ln -s "$HOME/snap/amd-gaia/x1" "$HOME/snap/amd-gaia/current"

echo "🏁 Pipeline complete! Let's watch it fly:"
amd-gaia