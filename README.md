# GAIA Packaging Workspace

This repository packages AMD GAIA for multiple deployment targets, with Snap as the primary distribution path.

Targets built by this workspace:
- Classic-confinement Snap (`gaia-desktop`)
- OCI rock image (Rockcraft)
- Docker archive/image (converted from OCI with `skopeo`)
- LXD importable sandbox archive

Current default GAIA version in rebuild.sh: 0.21.2

## Quick Start

```bash
# 1) Build all artifacts
./rebuild.sh --gaia-version=<version>

# 2) Validate workspace consistency
bash test.sh

# 3) Install/run with interactive topology selection
./install_gaia.sh
```

## Build Artifacts

Running [rebuild.sh](rebuild.sh) can generate:
- `gaia-desktop_<version>_amd64.snap`
- `gaia-desktop_<version>_amd64.rock`
- `gaia-desktop_<version>_docker-image.tar`
- `gaia-desktop_<version>_LXD-sandbox.tar.gz`

If you do not pass topology flags, `rebuild.sh` builds all targets.

## Prerequisites

For full pipeline builds:
- `snapcraft`
- `rockcraft`
- `skopeo` (required for Docker conversion)
- `lxc` / LXD (required for LXD archive generation)
- `docker` (optional; needed only if you want `docker load` in the build step)

Ubuntu example:

```bash
sudo apt update
sudo apt install -y snapcraft rockcraft skopeo lxd docker.io
```

## Build Commands

Full build (all targets):

```bash
./rebuild.sh --gaia-version=<version>
```

Interactive version prompt (all targets):

```bash
./rebuild.sh
```

Targeted builds:

```bash
./rebuild.sh --gaia-version=<version> --snap
./rebuild.sh --gaia-version=<version> --oci
./rebuild.sh --gaia-version=<version> --docker
./rebuild.sh --gaia-version=<version> --lxd
```

## Install and Run

Use [install_gaia.sh](install_gaia.sh):

```bash
./install_gaia.sh
```

Installer topology options:
1. Native Snap
2. LXD container
3. Docker container
4. Podman container
5. Kubernetes manifest output

Notes:
- Topology-specific preflight checks run before deployment.
- Ubuntu is the primary supported host. Non-Ubuntu hosts show warnings.
- Kubernetes mode outputs a manifest template; it does not apply resources directly.

## Runtime Configuration

For native Snap installs:

```bash
sudo snap set gaia-desktop backend.url="http://127.0.0.1:13305"
sudo snap set gaia-desktop backend.maxsteps=50
sudo snap set gaia-desktop keys.openai="sk-..."
```

For LXD installs, set values inside the container namespace:

```bash
lxc exec gaia-runtime-sandbox -- snap set gaia-desktop backend.url="http://127.0.0.1:13305"
lxc exec gaia-runtime-sandbox -- snap set gaia-desktop backend.maxsteps=50
```

## Validation

Run smoke tests:

```bash
bash test.sh
```

See [TESTING.md](TESTING.md) for full validation guidance.

## Cleanup

Clean build state before another rebuild (default mode):

```bash
./cleanup.sh
```

Reset to a first-time-build baseline (artifacts, deployments, and cached downloads):

```bash
sudo ./cleanup.sh --total-purge
```

## Snap Store Readiness

This project is preparing `gaia-desktop` for Snap Store publication.

Before publishing:
- `bash test.sh` passes
- Snap build succeeds
- Metadata in [snap/snapcraft.yaml](snap/snapcraft.yaml) is complete

## Contributing

Contribution standards and workflow: [CONTRIBUTING.md](CONTRIBUTING.md)
