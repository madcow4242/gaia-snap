# Testing Guide

This repository uses a fast smoke-test-first workflow, then targeted manual topology checks.

## 1) Fast Smoke Tests

Run from repo root:

```bash
bash test.sh
```

What this validates:
- Required files exist and are executable
- YAML syntax for snap and rock configs
- Shell and Python syntax checks
- Version consistency across key files
- Snap metadata readiness checks
- Presence of topology/preflight validation logic

## 2) Build Validation

Quick build test for snap artifact:

```bash
./rebuild.sh --gaia-version=0.20.0 --snap
```

If you run `./rebuild.sh` with no flags, all build targets are attempted.

Recommended full-pipeline validation command:

```bash
./rebuild.sh --gaia-version=0.20.0
```

This should produce Snap, OCI rock, Docker archive, and LXD archive artifacts.

## 3) Manual Topology Checks

Use `install_gaia.sh` and validate one topology at a time.

### Native Snap (Option 1)
- Confirm install succeeds
- Confirm launch path works
- Confirm backend URL and max-steps settings apply

### LXD (Option 2)
- Confirm container starts and can launch GAIA
- Confirm host path exposure (if enabled)
- Confirm display socket mapping

### Docker (Option 3)
- Confirm image exists and container starts
- Confirm environment variables are passed
- Confirm display and `/dev/dri` mapping

### Podman (Option 4)
- Confirm rootless container starts
- Confirm display and volume mapping behavior

## 4) Cleanup Between Test Cycles

Use default cleanup between normal build/test cycles:

```bash
./cleanup.sh
```

Use full cleanup when you want a first-time-build baseline:

```bash
sudo ./cleanup.sh --total-purge
```

## 5) Snap Store Readiness (Pre-publish)

Before upload:
- `bash test.sh` passes
- Snap builds cleanly
- Required metadata in `snap/snapcraft.yaml` is present (`name`, `summary`, `description`, `license`, `icon`, `grade`, `confinement`)
- Version format is semantic (`X.Y.Z`)

Suggested publish flow:

```bash
snapcraft login
snapcraft upload --release=edge gaia-desktop_<version>_amd64.snap
# promote to stable when validated
```

## 6) Notes on Build Environment

- `rebuild.sh` requires Bash.
- `rebuild.sh` may prompt for sudo to run cleanup/build helper steps.
- Docker conversion requires `skopeo`.
- LXD archive generation requires a working `lxc`/LXD setup.
