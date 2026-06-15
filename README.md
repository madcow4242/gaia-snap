# 🤖 GAIA Desktop Framework Engine 
### (Classic Snap Build Environment)

**GAIA Version:** Current version: 0.20.0

This repository contains the production deployment blueprints for packaging [AMD's GAIA framework](https://github.com/amd/gaia) as a portable Linux Snap configured under Classic Confinement.  

NOTE: Gaia is not tied just to AMD hardware.  As long as your AI backend supports your hardware, Gaia will work with it.  Lemonade-Server for example supports CPU, GPU, NPU from multiple vendors (AMD, Intel, NVIDIA, etc.).

Classic confinement ensures GAIA can natively interact with your host system's hardware acceleration profiles and absolute file paths while keeping it insulated from upstream code drift.

---

## 📋 Prerequisites & System Requirements

### 1. The AI Processing Server (lemonade-server)
GAIA requires an OpenAI API-compatible inference engine. This snap package is designed to pair directly with the companion lemonade-server snap package, which can be hosted locally or on a dedicated machine inside your network:

`‌`‌`bash
sudo snap install lemonade-server
`‌`‌`

### 🧠 VRAM & Hardware Allocation Guidelines
* Systems with >= 24GB VRAM: Can run standard default agents. (16GB may work, but requires confirmation on your particular system)
* Systems with < 24GB VRAM (e.g., 16GB laptops): Select the "lite" agent variations inside the UI to leverage optimized, smaller models (e.g., Gemma-4-E4B-it-GGUF).

---

## 🚀 Deployment Topologies

### Option 1: Native Ubuntu Desktop Application (Snap Layer)

`‌`‌`bash
chmod +x ./install_gaia.sh
./install_gaia.sh
`‌`‌`
Select **Option 1** from the menu. This installs the `.snap` package directly onto your host system using native unconfined layering flags.

### Option 2: Secure Isolated System Container Sandbox (LXD Engine) [Recommended]

This architecture launches GAIA inside a sandbox container while maintaining deep host-level integration. 

* **GPU Passthrough:** Natively passes physical graphics device endpoints (`/dev/dri`) into the unprivileged sandbox so the Electron window manager renders with hardware acceleration instead of burning CPU cycles.
* **Direct Host Path Mirroring:** If you choose to expose a host folder (e.g., `/home/kevin/Documents`), the LXD engine maps the exact absolute file path structure inside the container using kernel ID-shifts (`raw.idmap`).
* **Zero Translation Queries:** Your AI agents can read and write files naturally using your real host paths. Asking the agent to write a file to `/home/kevin/Documents/file.txt` modifies the true file on your host machine instantly.

To configure and boot the sandbox environment:
`‌`‌`bash
chmod +x ./install_gaia.sh
./install_gaia.sh
`‌`‌`
Select **Option 2** from the interactive menu prompts.

---

## ⚙️ User Configuration & Setup Guide

### Managing AI Backend Connections
Swap your target inference backend or add optional credential configurations on the fly via the native configuration database keys:

#### Option A: Route to a local Lemonade/Ollama instance (Default)
`‌`‌`bash
sudo snap set amd-gaia backend.url="http://127.0.0.1:13305"
`‌`‌`

#### Option B: Offload processing to a high-performance LAN server
`‌`‌`bash
sudo snap set amd-gaia backend.url="http://192.168.1.109:13305"
`‌`‌`

#### Option C: Seed optional API provider keys for advanced search/triage tools
`‌`‌`bash
sudo snap set amd-gaia keys.openai="sk-proj-..."
sudo snap set amd-gaia keys.anthropic="sk-ant-..."
sudo snap set amd-gaia keys.tavily="tvly-..."
sudo snap set amd-gaia keys.serper="api-..."
`‌`‌`

### Configure max-steps
The default number of discreet steps that an agent is allowed to take for each query is defaulted to 20 in this deployment configuration keyspace. To update it to your preferred budget:
`‌`‌`bash
sudo snap set amd-gaia agent.steps=50
`‌`‌`

---

## 🛠️ Developer Workspace & Local Compilation Guide

You can compile target application packages and bake baseline sandbox container environments using the modular `rebuild.sh` workspace runner.

### Run Full Pipeline Compilation
By default, executing the script with no parameters compiles the core Snap, packs the chiseled OCI Rock bundle, configures base container packages, and provisions the LXD image layer completely back-to-back:
`‌`‌`bash
./rebuild.sh
`‌`‌`

### Run Targeted Module Rebuilds
If you are iteratively debugging specific topologies, pass individual flags to restrict compilation scopes and save time:

* **Build Only Host Snap Bundle:**
  `‌`‌`bash
  ./rebuild.sh --snap
  `‌`‌`
* **Build Only OCI Chiseled Engine:**
  `‌`‌`bash
  ./rebuild.sh --oci
  `‌`‌`
* **Bake Pre-Built Sandbox Container Image:**
  `‌`‌`bash
  ./rebuild.sh --lxd
  `‌`‌`
* **Target Specific Workspace Combinations:**
  `‌`‌`bash
  ./rebuild.sh --snap --lxd
  `‌`‌`

---

## 🏗️ Applied Architecture Workarounds (Why & How)

To deliver a portable package that skips initial asset download phases and works out-of-the-box on clean target machines, the deployment framework applies four high-level interventions:

1. **Headless Execution Bypass** (`_gaia_sandbox_patch.py`): Upstream GAIA blocks on interactive UI confirmation popups for tool calls (like writing files). We inject an early-stage runtime patch via `sitecustomize.py`. This routes approve/deny responses safely through the internal snap environment and exposes a backup REST route (`/api/sandbox/resolve`) inside the local FastAPI engine.
2. **Upstream Asset Rewrite Defenses:** If the Electron UI spots an uninitialized home state or version drift, it automatically downloads a stock, unpatched copy of GAIA from PyPI into `~/.gaia/venv`. We mitigate this by declaring `GAIA_DISABLE_UPDATE=1` to kill network updaters, and using a native snap hook to drop complete state mock files into place, forcing the app to evaluate the environment as complete.
3. **Dynamic Environment Patching (PYTHONPATH):** Electron calls direct kernel functions to map its virtual environments, ignoring standard shell folder definitions. The launcher script explicitly appends our read-only snap patch folder to the shell `PYTHONPATH`. Whichever Python environment the framework runs, the runtime processes our custom memory hooks first.
4. **Automated Security Cache Seeding:** The Python core features a rigorous custom `PathValidator` class that blocks any file execution outside explicit safe paths by reading a dedicated local JSON file (`~/.gaia/cache/allowed_paths.json`). Because this file overrides snap database structures, `install_gaia.sh` dynamically builds and mounts this JSON data layout at runtime inside the container to safely clear host path permissions.

---

## 📋 Zero-Rebuild Sideloading: Adding Custom Agents

Because this package utilizes Classic Confinement, adding your own custom high-performance agent modules is fully supported and requires absolutely zero recompilation or repackaging of the snap package.

### Step 1: Copy Your Agent Script
Copy your valid, GAIA-compliant Python agent file (incorporating the standard Agent class inheritance and `@register_agent` decorators) straight into your active user folder:

#### Method A: Update the default workspace folder
`‌`‌`bash
cp your_custom_agent.py ~/.gaia/agents/zoo-agent/agent.py
`‌`‌`

#### Method B: Isolate multi-agent development projects
Create a dedicated subfolder for your project under the central `.gaia/agents/` tree. The core execution script inside that folder must be named `agent.py` for the framework to index it natively:
`‌`‌`bash
mkdir -p ~/.gaia/agents/my_agent
cp your_custom_agent.py ~/.gaia/agents/my_agent/agent.py
cp other_needed_files ~/.gaia/agents/my_agent/
`‌`‌`

### Step 2: Restart the Application
Simply close the GAIA desktop application (click **Quit** from the system tray icon) and relaunch it from your application menu. 

*(Note: Closing the main window with the **X** button merely hides the interface while the processes keep running in the background. You must use the tray icon to exit completely so the engine re-scans your script configurations on startup!)*