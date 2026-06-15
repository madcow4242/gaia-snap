# 🚀 GAIA Desktop Framework Engine 
### (Classic Snap Build Environment)

**GAIA Version:** Current version: 0.20.0

This repository contains the production deployment blueprints for packaging [AMD's GAIA framework](https://github.com/amd/gaia) as a portable Linux Snap configured under Classic Confinement as `gaia-desktop`.  

> **NOTE:** GAIA is not tied exclusively to AMD hardware. As long as your chosen AI inference backend supports your execution hardware, GAIA will interact with it seamlessly. The companion `lemonade-server` engine, for example, natively supports acceleration across CPU, GPU, and NPU architectures from multiple hardware vendors (AMD, Intel, NVIDIA, etc.).

Classic confinement ensures `gaia-desktop` can natively interact with your host system's hardware acceleration profiles and absolute file paths while keeping the runtime environment insulated from upstream code drift.

---

## 📋 Prerequisites & System Requirements

### 1. The AI Processing Server (lemonade-server)
GAIA requires an OpenAI API-compatible inference engine to drive its internal intelligence blocks. This snap package is designed to pair directly with the companion `lemonade-server` snap package, which can be hosted locally on your workstation or offloaded to a high-performance machine inside your local network:

```bash
sudo snap install lemonade-server
```

### 🧠 VRAM & Hardware Allocation Guidelines
* **Systems with >= 24GB VRAM:** Can run standard default parent agent layouts out of the box. *(16GB desktop setups may work, but require verification based on your precise concurrency configurations)*.
* **Systems with < 24GB VRAM (e.g., 16GB laptops):** Select the "lite" agent variations inside the UI workspace to leverage optimized, lower-quantization models (e.g., `Gemma-4-E4B-it-GGUF`).

---

## 🌐 Deployment Topologies

The application features an interactive, frontloaded installer script (`install_gaia.sh`) that asks all hardware, routing, and access questions immediately upon execution so you can run the configuration and walk away.

```bash
chmod +x ./install_gaia.sh
./install_gaia.sh
```

### Option 1: Native Ubuntu Desktop Application (Snap Layer)
Select **Option 1** from the interactive setup menu. This instantly deploys the pre-compiled `.snap` package directly onto your host operating system using native unconfined system-layer integration flags.

### Option 2: Secure Isolated System Container Sandbox (LXD Engine) [Recommended]
Select **Option 2** from the interactive setup menu. This architecture deploys and boots GAIA portably inside an unprivileged system container while maintaining deep, identical host-level directory access. 

* **Autonomous Standalone Importing:** The installer automatically scans the workspace directory for the pre-baked container distribution package (`amd-gaia_0.20.0_LXD-sandbox.tar.gz`). If it is not registered on your machine yet, or if a fresh compilation update is detected via filesystem timestamp analysis, the installer automatically purges old instances and restores the environment instantly using `lxc import`.
* **GPU Passthrough:** Natively passes physical graphics device endpoints (`/dev/dri`) directly across the unprivileged sandbox partition boundary so the Electron window manager handles UI rendering via local hardware acceleration instead of draining host CPU cycles.
* **Direct Host Path Mirroring:** If you choose to expose a host folder workspace (e.g., `/home/kevin/Documents`), the engine maps an identical absolute file path layout inside the container using real-time kernel namespace shifts (`raw.idmap`).
* **Zero Translation Queries:** Your AI agents can read, process, and write files naturally using your actual host paths. Instructing an agent to write a document to `/home/kevin/Documents/report.txt` updates the true file on your host machine instantly with no path mapping conversion delay.

---

## ⚙️ User Configuration & Setup Guide

Swap your target inference backend or inject optional provider configurations on the fly via your native snap configuration database keys:

#### Option A: Route to a local Lemonade/Ollama instance (Default layout)
```bash
sudo snap set gaia-desktop backend.url="[http://127.0.0.1:13305](http://127.0.0.1:13305)"
```

#### Option B: Offload intensive inference processing to a dedicated LAN server
```bash
sudo snap set gaia-desktop backend.url="[http://192.168.1.109:13305](http://192.168.1.109:13305)"
```

#### Option C: Seed API provider keys for advanced cloud fallback search/triage tools
```bash
sudo snap set gaia-desktop keys.openai="sk-proj-..."
sudo snap set gaia-desktop keys.anthropic="sk-ant-..."
sudo snap set gaia-desktop keys.groq="gsk_..."
sudo snap set gaia-desktop keys.tavily="tvly-..."
sudo snap set gaia-desktop keys.serper="api-..."
```

### Configure Maximum Agent Plan Steps
The maximum number of discrete reasoning steps an agent is allowed to execute for any given query is locked to 20 by default within the snap database keyspace. To upgrade your execution budget, modify the `backend.maxsteps` key:
```bash
sudo snap set gaia-desktop backend.maxsteps=50
```

> **🚨 LXD SANDBOX CONFIGURATION NOTE:** If you deployed GAIA via the **LXD Sandbox Container (Option 2)**, all system configurations are isolated inside the container's nested snap management space. To modify runtime keys on a sandbox instance, you must prefix your standard configuration commands using the LXD execution engine array like this:
> ```bash
> lxc exec gaia-runtime-sandbox -- snap set gaia-desktop backend.url="[http://127.0.0.1:13305](http://127.0.0.1:13305)"
> lxc exec gaia-runtime-sandbox -- snap set gaia-desktop backend.maxsteps=50
> ```

---

## 🛠️ Developer Workspace & Local Compilation Guide

You can compile target application packages and bake baseline sandbox container environments using the modular `rebuild.sh` workspace runner.

### Run Full Pipeline Compilation
Executing the script with no parameters automatically triggers a full compilation: it builds the core host Snap, packs the chiseled OCI Rock bundle, configures base system dependencies, and streams the finished environment out to a compressed container backup file:
```bash
./rebuild.sh
```

### Run Targeted Module Rebuilds
If you are iteratively debugging specific topologies, pass individual flags to restrict compilation scopes and save disk operations:

* **Build Only Host Snap Bundle:**
  ```bash
  ./rebuild.sh --snap
  ```
* **Build Only OCI Chiseled Engine:**
  ```bash
  ./rebuild.sh --oci
  ```
* **Bake Portable Standalone Container Backup Bundle:**
  ```bash
  ./rebuild.sh --lxd
  ```
* **Target Specific Workspace Combinations (e.g., Snap + Standalone LXD Tarball):**
  ```bash
  ./rebuild.sh --snap --lxd
  ```

---

## 📐 Applied Architecture Workarounds (Why & How)

To deliver a portable deployment package that skips initial asset download phases and works out-of-the-box on clean target machines, the deployment framework applies four core interventions:

1. **Headless Execution Bypass (`_gaia_sandbox_patch.py`):** Upstream GAIA blocks on interactive UI confirmation popups for tool calls (like writing files). We inject an early-stage runtime patch via `sitecustomize.py`. This routes approve/deny responses safely through the internal snap environment and exposes a backup REST route (`/api/sandbox/resolve`) inside the local FastAPI engine.
2. **Upstream Asset Rewrite Defenses:** If the Electron UI spots an uninitialized home state or version drift, it automatically downloads a stock, unpatched copy of GAIA from PyPI into `~/.gaia/venv`. We mitigate this by declaring `GAIA_DISABLE_UPDATE=1` to kill network updaters, and using a native snap hook to drop complete state mock files into place, forcing the app to evaluate the environment as complete.
3. **Dynamic Environment Patching (PYTHONPATH):** Electron calls direct kernel functions to map its virtual environments, ignoring standard shell folder definitions. The launcher script explicitly appends our read-only snap patch folder to the shell `PYTHONPATH`. Whichever Python environment the framework runs, the runtime processes our custom memory hooks first.
4. **Automated Security Cache Seeding:** The Python core features a rigorous custom `PathValidator` class that blocks any file execution outside explicit safe paths by reading a dedicated local JSON file (`~/.gaia/cache/allowed_paths.json`). Because this file overrides snap database structures, `install_gaia.sh` dynamically builds and mounts this JSON data layout at runtime inside the container to safely clear host path permissions.

---

## 🔌 Zero-Rebuild Sideloading: Adding Custom Agents

Because this package utilizes Classic Confinement, adding your own custom high-performance agent modules is fully supported and requires absolutely zero recompilation or repackaging of the snap package.

### Step 1: Copy Your Agent Script
Copy your valid, GAIA-compliant Python agent file (incorporating the standard Agent class inheritance and `@register_agent` decorators) straight into your active user folder.

#### Topology 1: Native Host Snap Paths (Option 1)
```bash
# Method A: Update the default workspace folder
cp your_custom_agent.py ~/.gaia/agents/zoo-agent/agent.py

# Method B: Isolate multi-agent development projects
mkdir -p ~/.gaia/agents/my_agent
cp your_custom_agent.py ~/.gaia/agents/my_agent/agent.py
```

#### Topology 2: LXD Sandbox Container Paths (Option 2)
> **💡 LXD SANDBOX OVERRIDE:** Because the LXD environment runs as a root-owned isolated system workspace, its internal user folder configuration mounts are mapped underneath the container's root filesystem space (`/root/.gaia/...`). To inject custom scripts into your container sandbox without compiling anything, pipe your agent payload directly across the hypervisor boundary using `lxc file push`:
>
> ```bash
> # Method A: Overwrite the container's default zoo-agent script layer
> lxc file push your_custom_agent.py gaia-runtime-sandbox/root/.gaia/agents/zoo-agent/agent.py
>
> # Method B: Provision a clean multi-agent development project folder inside the sandbox
> lxc exec gaia-runtime-sandbox -- mkdir -p /root/.gaia/agents/my_agent
> lxc file push your_custom_agent.py gaia-runtime-sandbox/root/.gaia/agents/my_agent/agent.py
> lxc file push other_needed_files gaia-runtime-sandbox/root/.gaia/agents/my_agent/
> ```

### Step 2: Restart the Application
Simply close the GAIA desktop application and relaunch it from your application menu to force an internal file index scan.

* **For Native Host Snap Installs:** Right-click the system tray icon, select **Quit**, and reopen the application natively.
* **For LXD Sandbox Container Installs:** You can cleanly recycle the processing state engine directly from your host terminal by rebooting the container container space:
  ```bash
  lxc restart gaia-runtime-sandbox
  ```

*(Note: Closing the main UI window with the standard **X** window button merely hides the interface layer while the core processes continue executing in the background. You must restart the container or use the tray icon to exit completely so the backend engine re-scans your custom agent script configurations on startup!)*