# GAIA Desktop Framework Engine (Snap Build Environment)

**GAIA Version Compliance:** Dynamic Environment Variable Injected (Current version: 0.20.0)

This repository contains the UN-official production deployment blueprints for packaging AMD's [**GAIA**](https://github.com/amd/gaia) as a secure, strictly confined Snap. 

**Requirements:**

* **AI Processing Server:** Lemonade Server or another OpenAI API-compatible back end like Ollama—running locally on the same computer (default), or on a remote system (see config below). You can install (separately) the Lemonade Server snap version (`snap install lemonade-server`), the deb package (`sudo apt install lemonade-server`), build from source, or connect to an external hosted service.

**NOTES**

Many of the "normal" agents use very large models by default, such as 35B models that consume large amounts of VRAM. This is fine on a system with 24–32GB of GPU memory, but will seriously bog down or crash systems with less hardware allocation.

If your system (or remote AI server) has less than 24GB of GPU memory, it is highly suggested that you use the "lite" agents instead, which default to a smaller model size. (16GB may be enough, but YMMV).

---

## ⚙️ User Configuration & Setup Guide

### 1. Connecting to an AI Processing Backend
By default, the Snap attempts to route all model inference traffic out to your local machine. You can hot-swap your target model backend on the fly using the `snap set` framework:

#### Option A: Local Laptop Resources (Default)
To point traffic to a local instance of Lemonade Server or Ollama running natively on your host machine's port 13305, set your target to loopback:

<pre><code>sudo snap set amd-gaia backend.url="[http://127.0.0.1:13305](http://127.0.0.1:13305)"</code></pre>

If your backend uses a different port, that can be set using this method as well.

#### Option B: Offloading to a Remote Inference Server Rig
To offload heavy token processing and agent loops to a dedicated server cluster elsewhere on your local area network, change the target address:

<pre><code>sudo snap set amd-gaia backend.url="[http://192.168.1.109:13305](http://192.168.1.109:13305)"</code></pre>

#### Option C: External Search Services (Beta / Untested)
To arm search agents with live web-scraping capabilities, seed your external API provider credentials into the configuration registry:

<pre><code># Note: External Search integrations are currently UNTESTED
sudo snap set amd-gaia backend.tavily-key="your-tavily-api-key-here"
sudo snap set amd-gaia backend.serper-key="your-serper-api-key-here"</code></pre>

---

### 2. Home Directory File Access Levels
The Snap implements a strict **3-Tier Compliant Security Control Ledger** to govern how AI agents interact with your computer's storage space. This can be configured via standard Ubuntu system interface connections:

* **Tier 1: Total Isolation (Default Setup)** Reading and writing to your local files is completely blocked. Agents function inside an empty, sterile environment memory footprint. You can reset to this state if needed via:
  <pre><code>sudo snap disconnect amd-gaia:home</code></pre>

* **Tier 2: Read-Only System Protection** Grants kernel-enforced read-only exposure. Agents can ingest and parse documents but are locked from altering or deleting them. Enable via:
  <pre><code>sudo snap connect amd-gaia:home-read-only</code></pre>

* **Tier 3: Full Native Read-Write Privileges** Grants unrestricted read and write privileges inside standard user directories (`Documents`, `Downloads`, `Desktop`). **NOTE:** When specifying these directories inside the app, you must use the full absolute path (e.g., `/home/myuser/Documents`) and **NOT** relative shortcuts like `~/Documents`, or it will write to an isolated sandbox cache folder within the snap itself instead. Enable via:
  <pre><code>sudo snap connect amd-gaia:home</code></pre>

---

### 3. Agent Verification Status Matrix

The following table tracks the operational functionality of the custom agent suites validated inside this build release:

| Agent Identity | Verification Status | Operational Notes |
| :--- | :--- | :--- |
| **Chat Agent** | **PASSED** | Local conversational contexts execute smoothly. |
| **File Agent** | **PASSED** | Parses and indexes data blocks; requires Tier 3 home connection. |
| **Browser Agent** | **PASSED** | Navigates modern web layouts cleanly without interface crashes. |
| **Web Lite Agent** | **PASSED** | Lightweight text-based scraping execution routines verified. |

Other agents have been lightly tested and appear to function as intended—but deep system-level tool integrations have not yet been heavily exercised. If you find edge-case issues, please submit a bug report or a Pull Request.

---

## 🛠️ Deep Dive: Applied Architecture Patches (Why & How)

To run a complex multi-process AI environment inside a strictly sandboxed container without breaking the upstream source repository code, this package injects **seven specific self-healing patches** automatically at execution time:

### 1. D-Bus Mediation & Permission Matrix (`_gaia_sandbox_patch.py`)
* **The Problem:** The stock application relies on native Linux desktop D-Bus signaling pathways to broadcast tool execution authorization requests from the background engine to the user interface. Under strict Snap confinement, arbitrary unmediated D-Bus communication is explicitly blocked by the kernel AppArmor security subsystem, causing tool execution loops to hang indefinitely.
* **The Hotfix:** Sideloaded as an early-stage Python runtime hook via `sitecustomize.py`. It dynamically overrides the platform class constructors on boot, establishing an inline FastAPI-based endpoint matrix alongside a thread-safe memory signaling loop (`threading.Event()`). This completely routes tool permission handshakes away from system IPC buses and into a sandboxed, memory-confined network loop.

### 2. Embedded ASAR Splicing & Repackaging Matrix (`rebuild.sh`)
* **The Problem:** To hook the user interface side of the custom FastAPI permission engine created in Item 1, specific code injections must be introduced directly into `notification-service.cjs`. However, this file is sealed within a compiled Electron `app.asar` archive distributed inside the pristine application payload, making static file overrides fragile across version upgrades.
* **The Hotfix:** The custom deployment script intercepts the compiled Snap package post-build, dynamically pulls down the pristine upstream UI layer, and utilizes `npx asar` to completely extract the source tree. An inline Node.js script surgically injects our custom HTTP approval bridge directly into the target function signature block, repacks the ASAR archive, and splices it cleanly back into the final Snap container payload.

### 3. Hardcoded Endpoint Translation Matrix (`socat`)
* **The Problem:** Upstream GAIA code contains hardcoded configuration profiles designed to communicate exclusively with an inference backend bound to `localhost:13305`. This prevents users from pointing the application to an alternative port or offloading token processing loops to a high-performance external server rig.
* **The Hotfix:** When a custom remote server or custom loopback port is defined in the local configuration ledger, `gaia-launcher.sh` automatically spins up a private, low-overhead `socat` proxy bridge isolated entirely inside the Snap's private network namespace. The local AI application continues firing standard calls to `localhost:13305`, unaware that the underlying proxy layer is tunneling packets to your custom server coordinates.

### 4. Direct IP-to-Host SNI Recovery Engine (`agent.py`)
* **The Problem:** When secondary agents attempt to connect to external web resources, the underlying Python tracking frame frequently passes raw destination IP addresses instead of qualified domain names. This causes secure HTTPS handshakes to fail immediately because the remote web server cannot map the Server Name Indication (SNI) back to a valid SSL certificate.
* **The Hotfix:** Implemented an active execution-frame tracer (`sys._getframe`) inside the `transform_connection_targets` loop. The engine dynamically climbs the active call stack when an outbound socket opens, extracts the string attributes (`url`, `endpoint`, `uri`) from local parent frames, parses the true target domain string via regex, and restores the correct domain context right before the socket binds.

### 5. Automated Browser Fingerprint Emulator (`agent.py`)
* **The Problem:** Sandboxed scraping utilities firing raw HTTP requests trigger immediate `403 Forbidden` drop blocks from Content Delivery Networks (CDNs) like Cloudflare, which easily identify the signature footprint of automated sandboxed scripts.
* **The Hotfix:** Monkeypatched `urllib3.connection.HTTPConnection.__init__` and `HTTPSConnection.__init__` globally. Every outbound connection automatically intercepts its own request payload headers on the fly, injecting realistic Google Chrome identities, platform hints (`Sec-Ch-Ua`), fallback browser parameters, and human-like request headers to blend into standard consumer traffic profiles.

### 6. Foundational TLS Cryptographic Aligner (`agent.py`)
* **The Problem:** The default Python SSL sockets inside a bare Core24 runtime container negotiate connections using a minimal, restrictive cipher suite. This triggers cryptographic handshakes failures or timeout drops when confronting modern optimized web targets.
* **The Hotfix:** Hijacked the native `ssl.create_default_context` instance routine. The modified method injects a curated collection of modern, high-security ciphers (including `CHACHA20-POLY1305` and `AES-GCM` suites) and explicitly disables insecure legacy protocols (`SSLv3`, `TLSv1.0`, `TLSv1.1`), ensuring flawless compatibility with edge infrastructure.

### 7. Containerized CA Certificate Authority Anchor (`agent.py`)
* **The Problem:** Strictly confined applications are completely cut off from the host operating system's global trust stores located at `/etc/ssl/certs`. Lacking verified certification lists, all outgoing Python API calls to external services instantly fail with untrusted root authority exceptions.
* **The Hotfix:** The initialization loop detects the sandboxed root namespace (`$SNAP`) and manually anchors the runtime global bundle variables (`CURL_CA_BUNDLE` and `REQUESTS_CA_BUNDLE`) straight to the read-only certificate engine mapping matrix located at `/snap/amd-gaia/current/etc/ssl/certs/ca-certificates.crt`. This restores absolute chain-of-trust verification inside the sandbox.

---

## 💻 Developer Workspace & Hackers' Guide

### Build Pipeline Automation
The entire build lifecycle is unified inside a single, automated deployment script. To clear stale caches, build the source files, apply the runtime code injections, and deploy the fresh bundle locally, run:

<pre><code>./rebuild.sh</code></pre>

To run a deep, un-cached clean from scratch, pass the clean parameter flag:

<pre><code>./rebuild.sh --clean</code></pre>

### Local Target Customization (.env configuration)
To prevent your private environment URLs, live API keys, and target build parameters from leaking into source control logs, you should manage configurations inside a local, untracked environment file. 

Create a file named exactly `.env` in the repository's root development directory. The pipeline script reads these attributes instantly on launch:

<pre><code># Master Local Build Flags (.env)
GAIA_VERSION=0.20.0
TARGET_BACKEND_URL=[http://192.168.1.109:13305](http://192.168.1.109:13305)
TAVILY_API_KEY=tvly-your-custom-key-string</code></pre>

---

## 🧙‍♂️ How to Inject a Custom AI Agent Suite

If you have engineered a custom GAIA-compliant agent (e.g., a `.py` file implementing the core `Agent` abstract class structure), you can easily sideload it into this custom Snap environment. 

To ensure the GAIA compiler registry successfully discovers, validates, and mounts your agent without throwing sandbox initialization faults, you must place the asset in the specific paths outlined below.

### Method A: Permanent Build-Time Integration (Recommended)
To bake your custom agent directly into the production `.snap` package so that it deploys cleanly across clean installations, drop the files directly into your local build workspace directory before running the pipeline compiler.

#### 1. Place the Source Asset
Move your custom python script into the `network-wizard` companion folder inside your root project folder structure:
<pre><code>cp your_custom_agent.py network-wizard/</code></pre>

#### 2. Register the Module Payload
Open `network-wizard/__init__.py` and add an explicit import statement at the bottom of the file to force the python compiler runtime engine to execute your class tracking decorators on boot:
<pre><code># network-wizard/__init__.py
from . import your_custom_agent</code></pre>

#### 3. Compile the Deployment Bundle
Fire off the master build script to automatically stage, compress, patch, and install the updated sandbox application globally:
<pre><code>./rebuild.sh</code></pre>

---

### Method B: Hot-Sideloading for Real-Time Debugging (No Recompiles)
If you are rapidly modifying agent prompts, validation tools, or system parameters, you can bypass the lengthy 5-minute Snap compilation loop entirely by injecting the file straight into your user data tracking directory profile workspace.

#### 1. Inject into the Writable Sandboxed Runtime Path
Copy your script directly into the active, user-owned configuration runtime storage namespace directory mapping:
<pre><code>cp your_custom_agent.py ~/snap/amd-gaia/current/.gaia/agents/network-wizard/</code></pre>

#### 2. Force-Reload Active Memory Headers
To make the background Python orchestration daemon evaluate the updated workspace registry layout, terminate any lingering active engine tasks across namespaces:
<pre><code>sudo killall -9 gaia python3</code></pre>
The GAIA desktop launcher environment will automatically cycle its process trees and reload with your fresh agent configurations active in memory.

> ⚠️ **CRITICAL DEVELOPER GUARDRAIL:** Because everything inside the `~/snap/amd-gaia/current` namespace directory mapping is untracked by Git, **always copy your stabilized script assets back into your root development folder (`/network-wizard/`)** before executing your final repository commits!

---

### 💡 Why this works under strict confinement
During the `override-build` step of `gaia-sideloads` inside `snapcraft.yaml`, the builder mirrors the entire `/network-wizard` directory straight into the Snap's internal system discovery layer:

<pre><code>/usr/share/gaia-agents/network-wizard/</code></pre>

When GAIA launches, our `_gaia_sandbox_patch.py` hook forces Python's system path manager (`sys.path`) to evaluate that exact folder. By organizing your new files alongside the `network-wizard` payload directory structure, you inherit all our pre-configured network overrides, browser fingerprint emulators, and containerized SSL certificate authorities completely for free!