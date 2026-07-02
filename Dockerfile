# GAIA Desktop Container - Docker Build
# Multi-stage build: snap artifact → runtime container
# 
# Features:
#   - Network reliability tier-1/2/2.5/3 fallback (HTTP → lynx → chromium)
#   - Full ML/AI framework with PyTorch, FAISS, transformers
#   - Electron-based GUI runtime
#   - amd64 architecture
#
# Build: docker build -t gaia-desktop:0.21.2 -f Dockerfile .
# Run:   docker run -it --rm gaia-desktop:0.21.2
#
# Note: Requires gaia-desktop_0.21.2_amd64.snap artifact in build context

FROM ubuntu:24.04

LABEL maintainer="GAIA Team <gaia@amd.com>"
LABEL description="GAIA Desktop AI agent orchestration framework"
LABEL version="0.21.2"

# ============================================================================
# Stage 1: Extract snap artifact and prepare runtime
# ============================================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    squashfs-tools \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY gaia-desktop_0.21.2_amd64.snap /tmp/gaia-desktop.snap

RUN mkdir -p /tmp/snap-root && \
    unsquashfs -f -d /tmp/snap-root /tmp/gaia-desktop.snap && \
    mkdir -p /opt/gaia_runtime /root/.gaia && \
    cp -rf /tmp/snap-root/* /opt/gaia_runtime/ && \
    chmod -R 755 /opt/gaia_runtime && \
    chmod 777 /opt/gaia_runtime/workspace && \
    rm -rf /tmp/snap-root /tmp/gaia-desktop.snap

# ============================================================================
# Stage 2: Install runtime dependencies and tier-3 fallback browsers
# ============================================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    bash \
    coreutils \
    findutils \
    python3.12-full \
    \
    # Network reliability tier-2.5: lightweight text-browser
    #   - Handles JavaScript-free server-rendered HTML
    #   - Falls back to tier-3 (Chromium) on empty response
    lynx \
    \
    # Network reliability tier-3: full browser rendering
    #   - Ultimate fallback for JavaScript-heavy sites
    #   - Handles anti-bot measures, CAPTCHA pre-checks
    chromium-browser \
    \
    # Electron GUI runtime: core X11/display
    libglib-2.0-0 \
    libgobject-2.0-0 \
    libgio-2.0-0 \
    libgtk-3-0 \
    libgdk-pixbuf-2.0-0 \
    libgdk-pixbuf2.0-bin \
    libcanberra-gtk3-module \
    shared-mime-info \
    \
    # Electron GUI runtime: SSL/security
    libnspr4 \
    libnss3 \
    \
    # Electron GUI runtime: system integration
    libdbus-1-3 \
    libcups2 \
    \
    # Electron GUI runtime: graphics
    libcairo2 \
    libcairo-gobject2 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libpangoft2-1.0-0 \
    libx11-6 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libxcomposite1 \
    libxdamage1 \
    libxrender1 \
    libxcb1 \
    libxcb-render0 \
    libxcb-shm0 \
    libxkbcommon0 \
    libxi6 \
    libgbm1 \
    libdrm2 \
    libepoxy0 \
    \
    # Electron GUI runtime: audio/accessibility
    libasound2 \
    libatspi2.0-0 \
    \
    # Electron GUI runtime: fonts
    libfontconfig1 \
    libfreetype6 \
    libharfbuzz0b \
    libfribidi0 \
    libthai0 \
    libpixman-1-0 \
    libpng16-16t64 \
    \
    # System services
    libudev1 \
    libexpat1 \
    libkrb5-3 \
    libgnutls30 \
    libsystemd0 \
    libavahi-common3 \
    libavahi-client3 \
    \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Runtime Configuration
# ============================================================================

ENV SNAP=/opt/gaia_runtime
ENV PYTHONPATH=/opt/gaia_runtime/lib/python_patches:${PYTHONPATH}
ENV HOME=/root
ENV PATH=/opt/gaia_runtime/bin:${PATH}

WORKDIR /opt/gaia_runtime

# Create workspace and config directories
RUN mkdir -p \
    /root/.gaia \
    /opt/gaia_runtime/workspace \
    /opt/gaia_runtime/cache && \
    chmod -R 755 /opt/gaia_runtime && \
    chmod 777 /opt/gaia_runtime/workspace

# ============================================================================
# Entrypoint
# ============================================================================

# Launch GAIA backend and frontend
CMD ["/opt/gaia_runtime/bin/gaia-launcher.sh"]

# Health check: verify network-reliability module is loaded
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ps aux | grep -q '[n]etwork.reliability' || exit 1
