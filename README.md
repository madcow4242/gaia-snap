# 🚀 GAIA Desktop Framework Engine 
### (Classic Snap Build Environment)

**GAIA Version:** Current version: 0.21.2

This repository contains the production deployment blueprints for packaging [AMD's GAIA framework](https://github.com/amd/gaia) as a portable Linux Snap configured under Classic Confinement as `gaia-desktop`.  It also builds an OCI-compliant container image (Rock) and LXD-, Docker-, and Podman-compatible container images.  There is an installer script to help automate installing via your preferred route.

> **NOTE:** GAIA is not tied exclusively to AMD hardware. As long as your chosen AI inference backend supports your execution hardware, GAIA will interact with it seamlessly. The companion `lemonade-server` engine, for example, natively supports acceleration across CPU, GPU, and NPU architectures from multiple hardware vendors (AMD, Intel, NVIDIA, etc.).

The classic confinement Snap package ensures `gaia-desktop` can natively interact with your host system's hardware acceleration profiles and absolute file paths while keeping the runtime environment insulated from upstream code drift.  The other container formats are more restrictive and help isolate agent access to only the folder(s) that you specify.

> **NOTE:** to use the software in this archive, you must first clone the project to your local system and build the desired packages using the rebuild.sh script, as detailed below in the "Developer Workspace & Local Compilation Guide" section.  The snap package is intended to be distributed via the snap store, and will eventually be available pre-built by simply typing "snap install gaia-desktop" at the command line.  The other packages may or may not be distributed as pre-built artifacts as well, but are not yet today.

---
## Quick Start Guide
To install GAIA via one of the installation packaging options as quickly as possible, here are the basic steps.  See below for details on configuration options and operation.

```bash
# create a directory for the project
mkdir MyGaiaProject
cd MyGaiaProject

# clone the repo
gh repo clone madcow4242/gaia-snap
cd gaia-snap

# install required build tools
snap install snapcraft
snap install rockcraft
sudo apt update
sudo apt install skopeo

# make the rebuild script executable and start it
sudo chmod +x rebuild.sh
#./rebuild.sh           # interactive - this builds ALL package types
./rebuild.sh --snap     # interactive, but only builds snap package
#./rebuild.sh --lxd     # interactive, but only builds LXD package
#./rebuild.sh --docker  # interactive, but only builds Docker package
#./rebuild.sh --podman  # interactive, but only builds Podman package

# install OPTIONAL packages that help with successful web retrieval
# NOTE: these only need to be separately installed for the snap package,
#        while the other package types have them automatically baked in.
sudo apt install lynx
snap install chromium

# run the installer and choose your preferred package type
sudo chmod +x install_gaia.sh
./install_gaia.sh   # this is interactive - requires user input

# ensure you have a local back-end running and configured for gaia, like lemonade-server
snap install lemonade-server
#sudo apt install lemonade-server  # if you want it on the host system directly instead of in a snap

# launch Gaia using the icon created in the App Menu (one is installed per container type that you install)
# gaia-dektop = snap
# gaia-lxd    = LXD container
# gaia-docker = Docker container
# gaia-podman = Podman container
#
# the installer may auto-launch the container after installation, depending on the installation option chosen.
```

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

The application features an interactive, frontloaded installer script (`install_gaia.sh`) that asks all hardware, routing, and access questions.

```bash
chmod +x ./install_gaia.sh
./install_gaia.sh
```

### Option 1: Native Ubuntu Desktop Application (Snap Layer)
Select **Option 1** from the interactive setup menu. This deploys the pre-compiled `.snap` package directly onto your host operating system using native unconfined system-layer integration flags.

### Option 2: Secure Isolated System Container Sandbox (LXD Engine) [Recommended]
Select **Option 2** from the interactive setup menu. This architecture deploys and boots GAIA portably inside an unprivileged system container while granting optional directory access to a host system folder you specify on installation. 

* **Autonomous Standalone Importing:** The installer automatically scans the workspace directory for the pre-baked container distribution package (`gaia-desktop_0.21.2_LXD-sandbox.tar.gz`). If it is not registered on your machine yet, or if a fresh compilation update is detected via filesystem timestamp analysis, the installer automatically purges old instances and restores the environment using `lxc import`.
* **GPU Passthrough:** Natively passes physical graphics device endpoints (`/dev/dri`) directly across the unprivileged sandbox partition boundary so the Electron window manager handles UI rendering via local hardware acceleration instead of draining host CPU cycles.
* **Direct Host Path Mirroring:** If you choose to expose a host folder workspace (e.g., `/home/my_user/Documents`), the engine maps an identical absolute file path layout inside the container using real-time kernel namespace shifts (`raw.idmap`).
* **Zero Translation Queries:** Your AI agents can read, process, and write files naturally using your actual host paths. Instructing an agent to write a document to `/home/my_user/Documents/report.txt` updates the true file on your host machine with no path mapping conversion delay.

### Option 3: Docker Container Sandbox
Select **Option 3** from the interactive setup menu. This deploys GAIA inside a Docker container using the OCI-compliant Rock package. Docker provides process isolation while allowing optional host directory mounting.

### Option 4: Podman Rootless Container Sandbox
Select **Option 4** from the interactive setup menu. This deploys GAIA inside a rootless Podman container, providing security benefits without requiring root privileges for container execution.

### Option 5: Kubernetes Production Deployment
Select **Option 5** from the interactive setup menu to generate a Kubernetes deployment manifest. This is suitable for enterprise production deployments with orchestration requirements.

---

## ⚙️ User Configuration & Setup Guide

Swap your target inference backend or inject optional provider configurations on the fly via your native snap configuration database keys (this is also done automatically by the installer script if you choose to enter those options):

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
Executing the script with no parameters automatically triggers a full compilation: it builds the core host Snap, packs the chiseled OCI Rock bundle, configures base system dependencies, and streams the finished environment out to a compressed container backup file for LXD.  If you do not flag a specific version of Gaia, you will be prompted for it when the script runs:
```bash
./rebuild.sh
```
or for automated pipelines you can specify the Gaia version to package as a flag:
```bash
./rebuild.sh --gaia-version=0.21.0
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
* **Build Docker Image Directly:**
  ```bash
  ./rebuild.sh --docker
  ```
* **Bake Portable Standalone Container Backup Bundle:**
  ```bash
  ./rebuild.sh --lxd
  ```
* **Target Specific Workspace Combinations (e.g., Snap + Docker):**
  ```bash
  ./rebuild.sh --snap --docker
  ```

---

## 📐 Applied Architecture Workarounds (Why & How)

To deliver a portable deployment package that skips initial asset download phases and works out-of-the-box on clean target machines, the deployment framework applies four core interventions:

1. **Headless Execution Bypass (`_gaia_sandbox_patch.py`):** Upstream GAIA blocks on interactive UI confirmation popups for tool calls (like writing files). We inject an early-stage runtime patch via `sitecustomize.py`. This routes approve/deny responses safely through the internal snap environment and exposes a backup REST route (`/api/sandbox/resolve`) inside the local FastAPI engine.
2. **Upstream Asset Rewrite Defenses:** If the Electron UI spots an uninitialized home state or version drift, it automatically downloads a stock, unpatched copy of GAIA from PyPI into `~/.gaia/venv`. We mitigate this by declaring `GAIA_DISABLE_UPDATE=1` to kill network updaters, and using a native snap hook to drop complete state mock files into place, forcing the app to evaluate the environment as complete.
3. **Dynamic Environment Patching (PYTHONPATH):** Electron calls direct kernel functions to map its virtual environments, ignoring standard shell folder definitions. The launcher script explicitly appends our read-only snap patch folder to the shell `PYTHONPATH`. Whichever Python environment the framework runs, the runtime processes our custom memory hooks first.
4. **Automated Security Cache Seeding:** The Python core features a rigorous custom `PathValidator` class that blocks any file execution outside explicit safe paths by reading a dedicated local JSON file (`~/.gaia/cache/allowed_paths.json`). Because this file overrides snap database structures, `install_gaia.sh` dynamically builds and mounts this JSON data layout at runtime inside the container to safely clear host path permissions.
5. **Network Reliability Patch:** To improve the reliability of web document retrieval and avoid common issues that prevent automatic web scraping, a custom monkeypatch is included in THIS distribution of GAIA (which is not a standard feature of GAIA itself). See the "🌐 Network Reliability Patch" section at the bottom of this document for full implementation details.

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

---

## 🌐 Network Reliability Patch (v0.21.2+)

This implementation of GAIA implements a **four-tier network reliability fallback strategy** to handle challenging web environments where direct HTTP requests fail due to JavaScript rendering requirements, anti-bot measures, or server-side protections.

### The Four-Tier Strategy

| Tier | Method | Tool | Characteristics | Best For |
|------|--------|------|-----------------|----------|
| **1** | Direct HTTP/HTTPS | Python `requests` / `httpx` | Fast, efficient, no browser overhead | 95%+ of URLs; local APIs |
| **2** | Standard HTTP with retries | Python `requests`/`httpx` + backoff | Split timeouts, retry logic, per-domain cooldowns | Transient failures; rate limits |
| **2.5** | Text-based Browser | `lynx` / `w3m` | Handles server-side rendering, JavaScript detection | Server-rendered HTML; bypasses basic bot detection |
| **3** | Full Browser Engine | Chromium (headless) | Complete JS execution, cookie handling, interstitials | JS-heavy sites; anti-bot measures; auth flows |

### Fallback Logic Flow

```
Request URL
    ↓
[Tier-1] Direct HTTP/HTTPS via requests/httpx
    ├─ Success (200, has content > 512 bytes) → Return
    ├─ Error/Empty → Check escalation rules
    └─ Timeout/Blocked → Escalate
        ↓
[Tier-2] Standard HTTP with retries + backoff+jitter
    ├─ Success → Return
    ├─ Challenge/Block → Escalate to tier-2.5
    └─ Timeout → Record event, escalate if threshold reached
        ↓
[Tier-2.5] Lynx text-browser (bundled in all topologies)
    ├─ Success (content > 512 bytes) → Return
    ├─ Empty/Useless → Escalate to tier-3
    └─ Error/Timeout → Cooldown + escalate
        ↓
[Tier-3] Chromium headless (bundled in OCI/Docker/LXD/Podman/K8s)
    ├─ Success (DOM rendered) → Return
    ├─ Error page (net-error, CAPTCHA) → Cooldown
    └─ Timeout → Record failure, promote domain to browser-required
```

### Topology Parity

All deployment topologies now achieve **full network reliability capability parity**:

| Topology | Tier-1 | Tier-2 | Tier-2.5 (lynx) | Tier-3 (chromium) | Status |
|----------|--------|--------|-----------------|-------------------|--------|
| **Snap** | ✅ | ✅ | ✅ (bundled) | ✅ (via host /snap/bin/chromium) | Full |
| **Docker** | ✅ | ✅ | ✅ (bundled) | ✅ (bundled) | Full ✓ |
| **LXD** | ✅ | ✅ | ✅ (bundled) | ✅ (bundled) | Full ✓ |
| **Podman** | ✅ | ✅ | ✅ (bundled) | ✅ (bundled) | Full ✓ |
| **Kubernetes** | ✅ | ✅ | ✅ (bundled) | ✅ (bundled) | Full ✓ |

The snap installation of GAIA will use the Lynx, chromium, or w3m packages from the host system, _if installed_ - it is highly recommended that you also install these packages to improve the success rate of web retrievals.  

  ```bash
  sudo apt update && sudo apt install lynx w3m
  snap install chromium
  ```

### Implementation Details

The `_gaia_network_reliability.py` module patches both `requests` and `httpx` transports to inject the fallback chain:

* **Automatic Escalation**: Empty responses from tier-1/2 trigger tier-2.5 (lynx) for server-rendered content
* **Browser Promotion**: Repeated timeouts on a domain auto-promote to tier-3 (chromium) for future requests
* **Domain Cooldowns**: Challenge responses (captcha, bot verification) trigger per-domain cooldown periods
* **Logging**: All fallback decisions are logged with `[network-reliability]` prefix when `GAIA_NETWORK_RELIABILITY_LOG=1`

### Container Image Updates

All OCI-derived containers (Docker, LXD, Podman, Kubernetes) bundle the network reliability browsers:

* **Dockerfile**: Installs `lynx` and `chromium-browser` as system dependencies
* **rockcraft.yaml**: Includes `lynx`, `w3m`, and `xdg-utils` in stage-packages
* **snap/snapcraft.yaml**: Bundles `lynx` for tier-2.5 text-browser fallback

### Configuration Options

Network reliability behavior can be controlled via environment variables:

```bash
# Enable/disable network reliability hooks (default: enabled)
export GAIA_ENABLE_NETWORK_RELIABILITY=1

# Enable/disable browser retriever (tier-3) (default: enabled)
export GAIA_ENABLE_BROWSER_RETRIEVER=1

# Enable/disable text browser (tier-2.5) (default: enabled)
export GAIA_ENABLE_TEXT_BROWSER=1

# Enable logging for diagnostics (default: enabled)
export GAIA_NETWORK_RELIABILITY_LOG=1

# Custom browser executable path (override auto-detection)
export GAIA_BROWSER_EXECUTABLE=/usr/bin/chromium-browser

# Domains that always require browser fallback
export GAIA_BROWSER_REQUIRED_DOMAINS="example.com,another-site.org"
```

### Testing Network Reliability

To verify tier availability in your deployment:

**Snap**:
```bash
which lynx chromium
```

**Docker/LXD/Podman**:
```bash
docker run gaia-desktop:0.21.2 which lynx chromium-browser
lxc exec gaia-runtime -- which lynx chromium-browser
podman run gaia-desktop:0.21.2 which lynx chromium-browser
```

**Kubernetes**:
```bash
kubectl exec -n gaia deployment/gaia-desktop -- which lynx chromium-browser
```

To test the full fallback chain, run a query like "Compare weather from at least 5 different weather sources" and check logs for tier escalation patterns:

```
[network-reliability] requests timeout domain=www.accuweather.com
[network-reliability] tier-2.5 empty-page domain=www.accuweather.com browser=lynx bytes=0 → escalating to tier-3
[network-reliability] tier-3 ok domain=www.accuweather.com executable=/usr/bin/chromium-browser bytes=89432
```

---
