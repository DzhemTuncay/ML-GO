#!/bin/bash

# =============================================================================
# macOS Setup Script
# =============================================================================
# Run this script on macOS to install all dependencies needed for the
# video-to-splat pipeline.
#
# Based on: https://github.com/pierotofy/OpenSplat
#
# Usage:
#   chmod +x setup_mac.sh
#   ./setup_mac.sh
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_step "Video-to-Splat macOS Setup"
echo "Script directory: $SCRIPT_DIR"

# =============================================================================
# Check for Homebrew
# =============================================================================
print_step "Checking for Homebrew"

if ! command -v brew &> /dev/null; then
    print_error "Homebrew not found. Please install it first:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi
print_success "Homebrew found"

# =============================================================================
# Check for Xcode (required for Metal support)
# =============================================================================
print_step "Checking for Xcode"

if ! xcode-select -p &> /dev/null; then
    print_warning "Xcode command line tools not found. Installing..."
    xcode-select --install
    echo "Please complete the Xcode installation and re-run this script."
    exit 1
fi

# Check if pointing to full Xcode (required for Metal)
XCODE_PATH=$(xcode-select --print-path)
if [[ "$XCODE_PATH" == "/Library/Developer/CommandLineTools" ]]; then
    print_warning "Xcode is pointing to CommandLineTools, not full Xcode."
    echo "For Metal/MPS support, install Xcode from App Store and run:"
    echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    echo ""
    echo "Continuing with CPU-only build..."
    GPU_RUNTIME=""
else
    print_success "Xcode found at $XCODE_PATH"
    GPU_RUNTIME="MPS"
fi

# =============================================================================
# Install system dependencies
# =============================================================================
print_step "Installing system dependencies via Homebrew"

brew install cmake opencv pytorch

# Fix libomp if needed (common issue on macOS)
if brew list libomp &> /dev/null; then
    brew link libomp --force 2>/dev/null || true
fi

print_success "System dependencies installed"

# =============================================================================
# Install Python packages
# =============================================================================
print_step "Installing Python packages"

pip3 install opencv-python numpy

print_success "Python packages installed"

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

# Get libtorch path from Homebrew pytorch
LIBTORCH_DIR="$(brew --prefix pytorch)"

if [ -n "$GPU_RUNTIME" ]; then
    echo "Building with Metal/MPS support..."
    cmake .. \
        -DCMAKE_PREFIX_PATH="$LIBTORCH_DIR" \
        -DGPU_RUNTIME=MPS \
        -DCMAKE_BUILD_TYPE=Release
else
    echo "Building CPU-only (no Metal support)..."
    cmake .. \
        -DCMAKE_PREFIX_PATH="$LIBTORCH_DIR" \
        -DCMAKE_BUILD_TYPE=Release
fi

make -j$(sysctl -n hw.logicalcpu)

print_success "OpenSplat built successfully"

# =============================================================================
# Make scripts executable
# =============================================================================
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

# Check for Apple Silicon
if [[ $(uname -m) == "arm64" ]]; then
    print_success "Apple Silicon detected"
else
    print_warning "Intel Mac detected"
fi

if [ -n "$GPU_RUNTIME" ]; then
    print_success "Metal/MPS acceleration enabled"
else
    print_warning "CPU-only mode (install full Xcode for Metal support)"
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
echo -e "${YELLOW}NOTE: On first run, you may see security warnings about libc10.dylib.${NC}"
echo -e "${YELLOW}Go to System Settings > Privacy & Security and click 'Allow'.${NC}"
echo -e "${YELLOW}You may need to repeat this several times for all torch libraries.${NC}"
echo ""
