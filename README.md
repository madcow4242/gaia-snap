# 🤖 GAIA Desktop Framework Engine 
### (Classic Snap Build Environment)

**GAIA Version:** Current version: 0.20.0

This repository contains the un-official production deployment blueprints for packaging [AMD's GAIA framework](https://github.com/amd/gaia) as a portable Linux Snap configured under Classic Confinement. 

Classic confinement ensures GAIA can natively interact with your host system's hardware acceleration profiles and absolute file paths while keeping it insulated from upstream code drift.

---

## ⚙️ Prerequisites & System Requirements

### 1. The AI Processing Server (lemonade-server)
GAIA requires an OpenAI API-compatible inference engine. It is designed to pair directly with the companion lemonade-server snap package, which can be hosted locally or on a dedicated machine inside your network:

  <pre><code>sudo snap install lemonade-server</code></pre>

### 🧠 VRAM & Hardware Allocation Guidelines
* Systems with >= 24GB VRAM: Can run standard default agents.
* Systems with < 24GB VRAM (e.g., 16GB laptops): Select the "lite" agent variations inside the UI to leverage optimized, smaller models (e.g., Gemma-4-E4B-it-GGUF).

---

## 🔧 User Configuration & Setup Guide

### Managing AI Backend Connections
Swap your target inference backend or add optional credential configurations on the fly via the native snap set utility:

  #### Option A: Route to a local Lemonade/Ollama instance (Default)
  <pre><code>sudo snap set amd-gaia backend.url="http://127.0.0.1:13305"</code></pre>

  #### Option B: Offload processing to a high-performance LAN server
  <pre><code>sudo snap set amd-gaia backend.url="http://192.168.1.109:13305"</code></pre>

  #### Option C: Seed optional API provider keys for advanced search/triage tools
  <pre><code>  sudo snap set amd-gaia keys.openai="sk-proj-..."
  sudo snap set amd-gaia keys.anthropic="sk-ant-..."
  sudo snap set amd-gaia keys.tavily="tvly-..."
  sudo snap set amd-gaia keys.serper="api-..."</code></pre>

---

## 🛠️ Applied Architecture Workarounds (Why & How)

To deliver a portable package that skips initial asset download phases and works out-of-the-box on clean target machines, the snap applies three high-level interventions:

1. **Headless Execution Bypass** (_gaia_sandbox_patch.py): Upstream GAIA blocks on interactive UI confirmation popups for tool calls (like writing files). We inject an early-stage runtime patch via sitecustomize.py. This is necessary to account for the effects of snap packaging constraints on the inter-process-communications that Gaia natively uses, and ensure approve/deny responses from the user are successfully routed. It also exposes a backup REST route (/api/sandbox/resolve) inside the local FastAPI engine.
2. **Upstream Asset Rewrite Defenses:** If the Electron UI spots an uninitialized home state or version drift, it automatically downloads a stock, unpatched copy of GAIA from PyPI into ~/.gaia/venv - which would revert the patches necessary to allow Gaia to run in a snap. We mitigate this by declaring GAIA_DISABLE_UPDATE=1 and GAIA_DISABLE_UPDATE_CHECK="true" to kill the network updaters, and by using a native snap configure hook to drop static backend.json and config.json mock files into the user directory on install, forcing the app to evaluate the local environment as already complete.
3. **Dynamic Environment Patching (PYTHONPATH):** Electron calls direct kernel functions (os.homedir()) to map its virtual environments, ignoring standard shell folder definitions. The launcher script explicitly appends our read-only snap patch folder to the shell PYTHONPATH. This guarantees that whichever Python environment the framework ultimately runs (host or snap), the runtime is forced to process our custom memory hook first.

---

## 💻 Developer Workspace & Local Compilation Guide

You can compile, pack, and test the package files locally on your workstation using Snapcraft:

  #### Execute the automated compilation, cache cleanup, and local deployment loop
  <pre><code>./rebuild.sh</code></pre>

---

## 🧙‍♂️ Zero-Rebuild Sideloading: Adding Custom Agents

Because this package utilizes Classic Confinement, adding your own custom high-performance agent modules is fully supported and requires absolutely zero recompilation or repackaging of the snap package.

### Step 1: Copy Your Agent Script
Copy your valid, GAIA-compliant Python agent file (incorporating the standard Agent class inheritance and @register_agent decorators) straight into your active user folder:

  #### Copy your custom python file to the application's active agent folder
  <pre><code>cp your_custom_agent.py ~/.gaia/agents/zoo-agent/agent.py</code></pre>

### Step 2: Restart the Gaia snap
Flush active background run states to force the engine to index and load your script:

  <pre><code>snap restart amd-gaia</code></pre>

When GAIA boots back open, it will dynamically register your custom capabilities and expose them cleanly inside the desktop chat selector dropdown menus!