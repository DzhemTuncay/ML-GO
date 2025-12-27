#!/bin/bash

# =============================================================================
# Linux Setup Script (with CUDA support)
# =============================================================================
# Run this script on a Linux machine or cloud GPU VM to install all
# dependencies needed for the video-to-splat pipeline.
#
# Based on: https://github.com/pierotofy/OpenSplat
#
# Usage:
#   chmod +x setup_linux.sh
#   ./setup_linux.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Detect workspace directory
if [ -d "/workspace" ]; then
    WORKSPACE="/workspace"
elif [ -d "$HOME" ]; then
    WORKSPACE="$HOME"
else
    WORKSPACE="$(pwd)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_step "Video-to-Splat Linux Setup"
echo "Workspace: $WORKSPACE"
echo "Script directory: $SCRIPT_DIR"

# =============================================================================
# Install system dependencies
# =============================================================================
print_step "Installing system dependencies"

sudo apt-get update && sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    unzip \
    libopencv-dev \
    python3-opencv \
    python3-pip \
    colmap \
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
    libceres-dev

print_success "System dependencies installed"

# =============================================================================
# Install Python packages
# =============================================================================
print_step "Installing Python packages"

pip3 install --no-cache-dir opencv-python-headless numpy

print_success "Python packages installed"

# =============================================================================
# Download libtorch
# =============================================================================
print_step "Downloading libtorch"

LIBTORCH_DIR="$WORKSPACE/libtorch"

if [ -d "$LIBTORCH_DIR" ]; then
    print_warning "libtorch already exists at $LIBTORCH_DIR, skipping download"
else
    # Detect CUDA version
    if command -v nvcc &> /dev/null; then
        CUDA_VERSION=$(nvcc --version | grep "release" | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p')
        echo "Detected CUDA version: $CUDA_VERSION"
        HAS_CUDA=true
    else
        HAS_CUDA=false
        print_warning "CUDA not detected, will download CPU version"
    fi

    # Map CUDA version to libtorch URL (using versions from OpenSplat docs)
    if [ "$HAS_CUDA" = false ]; then
        TORCH_URL="https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-2.4.0%2Bcpu.zip"
    else
        case "$CUDA_VERSION" in
            12.4*)
                TORCH_URL="https://download.pytorch.org/libtorch/cu124/libtorch-cxx11-abi-shared-with-deps-2.4.0%2Bcu124.zip"
                ;;
            12.1*)
                TORCH_URL="https://download.pytorch.org/libtorch/cu121/libtorch-cxx11-abi-shared-with-deps-2.2.1%2Bcu121.zip"
                ;;
            11.8*)
                TORCH_URL="https://download.pytorch.org/libtorch/cu118/libtorch-cxx11-abi-shared-with-deps-2.2.1%2Bcu118.zip"
                ;;
            *)
                print_warning "Unknown CUDA version $CUDA_VERSION, using CUDA 12.4 libtorch"
                TORCH_URL="https://download.pytorch.org/libtorch/cu124/libtorch-cxx11-abi-shared-with-deps-2.4.0%2Bcu124.zip"
                ;;
        esac
    fi

    echo "Downloading libtorch from: $TORCH_URL"
    wget -q --show-progress "$TORCH_URL" -O /tmp/libtorch.zip
    unzip -q /tmp/libtorch.zip -d "$WORKSPACE"
    rm /tmp/libtorch.zip
    print_success "libtorch downloaded to $LIBTORCH_DIR"
fi

# =============================================================================
# Clone/Update OpenSplat
# =============================================================================
print_step "Setting up OpenSplat"

OPENSPLAT_DIR="$SCRIPT_DIR/OpenSplat"

if [ ! -d "$OPENSPLAT_DIR" ]; then
    echo "Cloning OpenSplat..."
    git clone https://github.com/pierotofy/OpenSplat.git "$OPENSPLAT_DIR"
    print_success "OpenSplat cloned"
else
    print_warning "OpenSplat directory already exists"
fi

# =============================================================================
# Build OpenSplat
# =============================================================================
print_step "Building OpenSplat"

cd "$OPENSPLAT_DIR"
mkdir -p build && cd build

# Build with CUDA if available
if command -v nvcc &> /dev/null; then
    echo "Building with CUDA support..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$LIBTORCH_DIR" \
        -DCMAKE_CUDA_ARCHITECTURES="70;75;80;86;89;90"
else
    echo "Building CPU-only..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$LIBTORCH_DIR"
fi

make -j$(nproc)

print_success "OpenSplat built successfully"

# =============================================================================
# Setup environment
# =============================================================================
print_step "Setting up environment"

# Add to bashrc for persistence
BASHRC_ENTRY="export LD_LIBRARY_PATH=$LIBTORCH_DIR/lib:\$LD_LIBRARY_PATH"

if ! grep -q "libtorch" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# libtorch library path for OpenSplat" >> ~/.bashrc
    echo "$BASHRC_ENTRY" >> ~/.bashrc
    print_success "Added libtorch to ~/.bashrc"
fi

# Set for current session
export LD_LIBRARY_PATH="$LIBTORCH_DIR/lib:$LD_LIBRARY_PATH"

# Make pipeline script executable
chmod +x "$SCRIPT_DIR/video_to_splat.sh"

# =============================================================================
# Verify installation
# =============================================================================
print_step "Verifying installation"

# Check COLMAP
if command -v colmap &> /dev/null; then
    print_success "COLMAP: $(colmap --version 2>&1 | head -1)"
else
    print_error "COLMAP not found"
fi

# Check OpenSplat
if [ -f "$OPENSPLAT_DIR/build/opensplat" ]; then
    print_success "OpenSplat: $OPENSPLAT_DIR/build/opensplat"
else
    print_error "OpenSplat binary not found"
fi

# Check GPU
if command -v nvidia-smi &> /dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    print_success "GPU: $GPU_NAME"
else
    print_warning "No NVIDIA GPU detected (will run on CPU)"
fi

# =============================================================================
# Done!
# =============================================================================
print_step "Setup Complete!"

echo ""
echo "You can now run the pipeline:"
echo ""
echo -e "  ${GREEN}cd $SCRIPT_DIR${NC}"
echo -e "  ${GREEN}./video_to_splat.sh -v /path/to/video.mp4 -n 100 -o my_model${NC}"
echo ""
echo "If running in a new terminal, first run:"
echo -e "  ${YELLOW}export LD_LIBRARY_PATH=$LIBTORCH_DIR/lib:\$LD_LIBRARY_PATH${NC}"
echo ""
