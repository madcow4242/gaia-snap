# GAIA Desktop Framework Engine (Snap Build Environment)

**GAIA Version Compliance:** Dynamic Environment Variable Injected

This repository contains the official production deployment blueprints for packaging **GAIA** as a secure, strictly confined Snap. 

---

## 🚀 User Configuration & Setup Guide

### 1. Connecting to an AI Processing Backend
By default, the Snap attempts to route all model inference traffic out to your local machine. You can hot-swap your target model backend on the fly using the `snap set` framework:

#### Option A: Local Laptop Resources (Default)
To point traffic to a local instance of Lemonade Server or Ollama running natively on your host machine's port 13305, set your target to loopback:

    sudo snap set amd-gaia backend.url="http://127.0.0.1:13305"

#### Option B: Offloading to a Remote Inference Server Rig
To offload heavy token processing and agent loops to a dedicated server cluster elsewhere on your local area network, change the target address:

    sudo snap set amd-gaia backend.url="http://192.168.1.109:13305"

#### Option C: External Search Services (Beta / Untested)
To arm search agents with live web-scraping capabilities, seed your external API provider credentials into the configuration registry:

    # Note: External Search integrations are currently UNTESTED
    sudo snap set amd-gaia backend.tavily-key="your-tavily-api-key-here"
    sudo snap set amd-gaia backend.serper-key="your-serper-api-key-here"

---

### 2. Home Directory File Access Levels
The Snap implements a strict **3-Tier Compliant Security Control Ledger** to govern how AI agents interact with your computer's storage space. This can be configured via standard Ubuntu system interface connections:

* **Tier 1: Total Isolation (Default Setup)** Reading and writing to your local files is completely blocked. Agents function inside an empty, sterile environment memory footprint.
* **Tier 2: Read-Only System Protection** Grants kernel-enforced read-only exposure. Agents can ingest and parse documents but are locked from altering or deleting them. Enable via:

    sudo snap connect amd-gaia:home-read-only

* **Tier 3: Full Native Read-Write Privileges** Grants unrestricted read and write privileges inside standard user directories (`Documents`, `Downloads`, `Desktop`). Enable via:

    sudo snap connect amd-gaia:home

---

### 3. Agent Verification Status Matrix

The following table tracks the operational functionality of the custom agent suites validated inside this build release:

| Agent Identity | Verification Status | Operational Notes |
| :--- | :--- | :--- |
| **Chat Agent** | **PASSED** | Local conversational contexts execute smoothly. |
| **File Agent** | **PASSED** | Parses and indexes data blocks; requires Tier 3 home connection. |
| **Browser Agent** | **PASSED** | Navigates modern web layouts cleanly without interface crashes. |
| **Web Lite Agent** | **PASSED** | Lightweight text-based scraping execution routines verified. |

---

## 🛠️ Deep Dive: Applied Architecture Patches (Why & How)

To run a complex multi-process AI environment inside a strictly sandboxed container without breaking the upstream source repository code, this package injects **four specific self-healing patches** automatically at execution time:

### 1. In-Memory Token Approval Bridge (`_gaia_sandbox_patch.py`)
* **The Problem:** The stock application relies on complex file-polling disk loops to communicate tool execution permissions across the sandbox barrier, generating excessive disk I/O and random main-thread UI lockups.
* **The Hotfix:** Sideloaded as a low-level Python runtime hook (`sitecustomize.py`). It dynamically intercepts class constructors on boot and implements a high-performance, thread-safe memory matrix signal framework (`threading.Event()`).

### 2. Post-Build UI Splicing Matrix (`rebuild.sh`)
* **The Problem:** Upstream changes to `notification-service.cjs` frequently break static file overrides across version upgrades.
* **The Hotfix:** The custom deployment script intercepts the compiled Snap package post-build, pulls down a pristine UI layer package from the web, and uses an automated inline Node.js runner to inject a dynamic network forwarder right into the method signature block. If the upstream repository changes, your build automatically self-heals.

### 3. Loopback Proxy Interceptor (`socat`)
* **The Problem:** Hardcoding network endpoints inside strict container walls triggers host-level port allocation failures (`Address already in use`).
* **The Hotfix:** When configured for a remote rig, `gaia-launcher.sh` stands up a private `socat` bridge completely isolated inside the snap's private network namespace. The local AI engine fires calls to localhost, unaware that the proxy is tunneling packets smoothly to your server rig.

### 4. Browser Fingerprint Emulator (`agent.py`)
* **The Problem:** Sandboxed Python scraping tools drop requests or trigger `403 Forbidden` responses when confronting Content Delivery Network (CDN) bot-blockers.
* **The Hotfix:** The network wizard agent intercepts outgoing `urllib3` network calls, safely injecting standard Chrome browser identity markers, platform hints, and secure TLS cryptographic handshakes into the payload headers.

---

## 🧑‍💻 Developer Workspace & Hackers' Guide

### Build Pipeline Automation
The entire build lifecycle is unified inside a single, automated deployment script. To clear stale caches, build the source files, apply the runtime code injections, and deploy the fresh bundle locally, run:

    ./rebuild.sh

To run a deep, un-cached clean from scratch, pass the clean parameter flag:

    ./rebuild.sh --clean

### Local Target Customization
To prevent your private environment URLs, live API keys, and target build