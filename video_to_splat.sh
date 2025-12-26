#!/bin/bash

# =============================================================================
# Video to Splat Pipeline
# =============================================================================
# This script takes a video file and generates a .splat file by:
# 1. Extracting frames from the video
# 2. Running COLMAP for Structure-from-Motion
# 3. Running OpenSplat for 3D Gaussian Splatting
# =============================================================================

set -e  # Exit on error

# Default values
NUM_FRAMES=100
NUM_ITERATIONS=2000
OUTPUT_NAME=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print usage
usage() {
    echo "Usage: $0 -v <video_path> [-n <num_frames>] [-i <iterations>] [-o <output_name>]"
    echo ""
    echo "Options:"
    echo "  -v, --video       Path to input video file (required)"
    echo "  -n, --num-frames  Number of frames to extract (default: $NUM_FRAMES)"
    echo "  -i, --iterations  Number of training iterations for OpenSplat (default: $NUM_ITERATIONS)"
    echo "  -o, --output      Output name for project folder and .splat file (default: video filename)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -v /path/to/video.mp4 -n 150 -i 3000 -o my_model"
    exit 1
}

# Print step header
print_step() {
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
}

# Print success message
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Print warning message
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Print error message
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--video)
            VIDEO_PATH="$2"
            shift 2
            ;;
        -n|--num-frames)
            NUM_FRAMES="$2"
            shift 2
            ;;
        -i|--iterations)
            NUM_ITERATIONS="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check required arguments
if [ -z "$VIDEO_PATH" ]; then
    print_error "Video path is required"
    usage
fi

# Check if video file exists
if [ ! -f "$VIDEO_PATH" ]; then
    print_error "Video file not found: $VIDEO_PATH"
    exit 1
fi

# Set output name from video filename if not provided
if [ -z "$OUTPUT_NAME" ]; then
    OUTPUT_NAME=$(basename "$VIDEO_PATH" | sed 's/\.[^.]*$//')
fi

# Set up paths
PROJECT_DIR="${SCRIPT_DIR}/${OUTPUT_NAME}"
IMAGES_DIR="${PROJECT_DIR}/images"
SPARSE_DIR="${PROJECT_DIR}/sparse"
DATABASE_PATH="${PROJECT_DIR}/database.db"
OUTPUT_SPLAT="${PROJECT_DIR}/${OUTPUT_NAME}.splat"

# Check for required tools
print_step "Checking dependencies"

# Check for Python
if ! command -v python3 &> /dev/null; then
    print_error "python3 is required but not installed"
    exit 1
fi
print_success "Python3 found"

# Check for COLMAP
if ! command -v colmap &> /dev/null; then
    print_error "COLMAP is required but not installed"
    echo "Install with: brew install colmap (macOS) or see https://colmap.github.io/install.html"
    exit 1
fi
print_success "COLMAP found"

# Check for OpenSplat
OPENSPLAT_BIN="${SCRIPT_DIR}/OpenSplat/build/opensplat"
if [ ! -f "$OPENSPLAT_BIN" ]; then
    print_error "OpenSplat not found at: $OPENSPLAT_BIN"
    echo "Please build OpenSplat first. See OpenSplat/README.md for instructions."
    exit 1
fi
print_success "OpenSplat found"

# Check for frame extractor script
FRAME_EXTRACTOR="${SCRIPT_DIR}/utils/grame_extractor.py"
if [ ! -f "$FRAME_EXTRACTOR" ]; then
    print_error "Frame extractor script not found at: $FRAME_EXTRACTOR"
    exit 1
fi
print_success "Frame extractor script found"

# Create project directory
print_step "Setting up project directory"
mkdir -p "$PROJECT_DIR"
mkdir -p "$SPARSE_DIR"
print_success "Created project directory: $PROJECT_DIR"

# =============================================================================
# Step 1: Extract frames from video
# =============================================================================
print_step "Step 1: Extracting $NUM_FRAMES frames from video"

python3 "$FRAME_EXTRACTOR" "$VIDEO_PATH" -n "$NUM_FRAMES" -o "$IMAGES_DIR"

if [ ! -d "$IMAGES_DIR" ] || [ -z "$(ls -A "$IMAGES_DIR")" ]; then
    print_error "Frame extraction failed - no images found"
    exit 1
fi

EXTRACTED_COUNT=$(ls -1 "$IMAGES_DIR"/*.png 2>/dev/null | wc -l)
print_success "Extracted $EXTRACTED_COUNT frames to $IMAGES_DIR"

# =============================================================================
# Step 2: COLMAP Feature Extraction
# =============================================================================
print_step "Step 2: COLMAP Feature Extraction"

colmap feature_extractor \
    --database_path "$DATABASE_PATH" \
    --image_path "$IMAGES_DIR" \
    --ImageReader.single_camera 1 \
    --ImageReader.camera_model SIMPLE_RADIAL \
    --SiftExtraction.use_gpu 1

print_success "Feature extraction complete"

# =============================================================================
# Step 3: COLMAP Exhaustive Matching
# =============================================================================
print_step "Step 3: COLMAP Exhaustive Matching"

colmap exhaustive_matcher \
    --database_path "$DATABASE_PATH" \
    --SiftMatching.use_gpu 1

print_success "Feature matching complete"

# =============================================================================
# Step 4: COLMAP Mapper (Sparse Reconstruction)
# =============================================================================
print_step "Step 4: COLMAP Mapper (Sparse Reconstruction)"

colmap mapper \
    --database_path "$DATABASE_PATH" \
    --image_path "$IMAGES_DIR" \
    --output_path "$SPARSE_DIR"

# Check if reconstruction was successful
if [ ! -d "$SPARSE_DIR/0" ]; then
    print_error "COLMAP mapping failed - no reconstruction found"
    exit 1
fi

print_success "Sparse reconstruction complete"

# Move the reconstruction files to the expected location for OpenSplat
# OpenSplat expects cameras.bin, images.bin, points3D.bin in the project root or sparse/0
print_success "Reconstruction saved to $SPARSE_DIR/0"

# =============================================================================
# Step 5: Run OpenSplat
# =============================================================================
print_step "Step 5: Running OpenSplat (${NUM_ITERATIONS} iterations)"

# Change to project directory and run OpenSplat
cd "$PROJECT_DIR"

"$OPENSPLAT_BIN" "$SPARSE_DIR/0" \
    -n "$NUM_ITERATIONS" \
    -o "$OUTPUT_SPLAT"

if [ ! -f "$OUTPUT_SPLAT" ]; then
    print_error "OpenSplat failed - output file not found"
    exit 1
fi

print_success "OpenSplat training complete"

# =============================================================================
# Step 6: Cleanup intermediate files
# =============================================================================
print_step "Step 6: Cleaning up intermediate files"

# Remove images directory
if [ -d "$IMAGES_DIR" ]; then
    rm -rf "$IMAGES_DIR"
    print_success "Removed images directory"
fi

# Remove sparse reconstruction directory
if [ -d "$SPARSE_DIR" ]; then
    rm -rf "$SPARSE_DIR"
    print_success "Removed sparse reconstruction directory"
fi

# Remove COLMAP database
if [ -f "$DATABASE_PATH" ]; then
    rm -f "$DATABASE_PATH"
    print_success "Removed COLMAP database"
fi

print_success "Cleanup complete"

# =============================================================================
# Done!
# =============================================================================
print_step "Pipeline Complete!"

echo -e "Output splat file: ${GREEN}$OUTPUT_SPLAT${NC}"
echo ""
echo "You can view your .splat file at:"
echo "  - https://playcanvas.com/viewer"
echo "  - https://antimatter15.com/splat/"
echo "  - https://playcanvas.com/supersplat/editor (for editing)"
echo ""
print_success "All done!"

