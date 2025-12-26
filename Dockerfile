# =============================================================================
# Video to Splat Pipeline - Complete Docker Image
# =============================================================================
# This Dockerfile builds an image with all dependencies:
# - Python 3 + OpenCV
# - COLMAP
# - OpenSplat
#
# Build (CPU):
#   docker build -t video-to-splat .
#
# Build (CUDA - requires NVIDIA GPU):
#   docker build -t video-to-splat --build-arg USE_CUDA=ON .
#
# Run:
#   docker run -v /path/to/videos:/data video-to-splat \
#       -v /data/my_video.mp4 -n 100 -o my_model
# =============================================================================

ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION}

ARG UBUNTU_VERSION
ARG USE_CUDA=OFF
ARG TORCH_VERSION=2.2.1
ARG CUDA_VERSION=12.1.1
ARG CMAKE_BUILD_TYPE=Release

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# =============================================================================
# Install base dependencies
# =============================================================================
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    ninja-build \
    wget \
    unzip \
    curl \
    # Python
    python3 \
    python3-pip \
    python3-dev \
    # OpenCV dependencies
    libopencv-dev \
    python3-opencv \
    # COLMAP dependencies
    libboost-program-options-dev \
    libboost-filesystem-dev \
    libboost-graph-dev \
    libboost-system-dev \
    libeigen3-dev \
    libflann-dev \
    libfreeimage-dev \
    libmetis-dev \
    libgoogle-glog-dev \
    libgflags-dev \
    libsqlite3-dev \
    libglew-dev \
    qtbase5-dev \
    libqt5opengl5-dev \
    libcgal-dev \
    libceres-dev \
    # For headless OpenGL
    libegl1-mesa-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    xvfb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Install Python packages
# =============================================================================
RUN pip3 install --no-cache-dir \
    opencv-python-headless \
    numpy

# =============================================================================
# Install COLMAP
# =============================================================================
# Try apt first (available in Ubuntu 22.04+), otherwise build from source
RUN if apt-cache show colmap > /dev/null 2>&1; then \
        apt-get update && apt-get install -y colmap && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    else \
        git clone https://github.com/colmap/colmap.git /tmp/colmap && \
        cd /tmp/colmap && \
        git checkout 3.8 && \
        mkdir build && cd build && \
        cmake .. -GNinja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX=/usr/local && \
        ninja && ninja install && \
        rm -rf /tmp/colmap; \
    fi

# =============================================================================
# Install libtorch (CPU version by default)
# =============================================================================
RUN if [ "$USE_CUDA" = "ON" ]; then \
        TORCH_URL="https://download.pytorch.org/libtorch/cu121/libtorch-cxx11-abi-shared-with-deps-${TORCH_VERSION}%2Bcu121.zip"; \
    else \
        TORCH_URL="https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-${TORCH_VERSION}%2Bcpu.zip"; \
    fi && \
    wget --no-check-certificate -q "$TORCH_URL" -O /tmp/libtorch.zip && \
    unzip -q /tmp/libtorch.zip -d /opt && \
    rm /tmp/libtorch.zip

# =============================================================================
# Build OpenSplat
# =============================================================================
COPY OpenSplat /app/OpenSplat

RUN cd /app/OpenSplat && \
    mkdir -p build && cd build && \
    cmake .. \
        -GNinja \
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
        -DCMAKE_PREFIX_PATH=/opt/libtorch && \
    ninja

# =============================================================================
# Copy pipeline scripts
# =============================================================================
COPY utils /app/utils
COPY video_to_splat.sh /app/video_to_splat.sh
RUN chmod +x /app/video_to_splat.sh

# =============================================================================
# Setup working directory for data
# =============================================================================
RUN mkdir -p /data
WORKDIR /data

# Set library path for libtorch
ENV LD_LIBRARY_PATH=/opt/libtorch/lib:$LD_LIBRARY_PATH

# =============================================================================
# Entrypoint
# =============================================================================
ENTRYPOINT ["/app/video_to_splat.sh"]
CMD ["--help"]

