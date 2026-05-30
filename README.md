# GAIA Desktop Framework Engine (Snap Build Environment)

Gaia version: v0.19.0

This repository contains the **un-official** Snap encapsulation environment recipes for **GAIA**, an advanced local AI worker orchestration architecture featuring multi-agent execution frameworks and hardware-accelerated machine learning layers.

Check out the [GAIA Repository](https://github.com/amd/gaia) on GitHub.

---

## 🚀 Deployment Status & Capabilities

> ⚠️ **Production Architecture Milestone:** This Snap utilizes an isolated network loopback container proxy. It allows seamless, dynamic toggling between local machine resources and heavy remote inference server clusters without modifying upstream source code.

### Verified Tracks
* **All Primary Agents (`web`, `chat`, `doc`, `file`, `data`):** **Fully Verified Operational.** Capable of orchestrating large language models (such as `Qwen3.5-35B`) smoothly by offloading token processing workloads.
* **Web Track Automation (`web`, `web-lite`):** Fully equipped with an active client-side identity mask and global routing overrides to bypass Content Delivery Network (CDN) anti-bot restrictions safely.

---

## ⚙️ Network Configuration Guide (Dynamic Switching)

The architecture natively supports the `snap set` feature. You can hot-swap your model processing backend on the fly. The snap will automatically adjust its internal networking layer depending on your chosen target destination.

### Option A: Offloading to a Remote Inference Rig
To route heavy multi-agent queries across your local network to a high-performance server cluster, update the configuration URL parameter to target your remote machine coordinates:

```bash
sudo snap set amd-gaia backend.url="[http://192.168.1.109:13305](http://192.168.1.109:13305)"