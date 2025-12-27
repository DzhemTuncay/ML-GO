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
NUM_ITERATIONS=7000
DOWNSCALE_FACTOR=1
OUTPUT_NAME=""
INPUT_IMAGES_DIR=""
SAVE_EVERY=200
USE_VALIDATION=true

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
    echo "Usage: $0 <-v video_path | -d images_dir> [-n <num_frames>] [-i <iterations>] [-s <downscale>] [-o <output_name>] [--save-every <N>] [--val]"
    echo ""
    echo "Options:"
    echo "  -v, --video        Path to input video file"
    echo "  -d, --images-dir   Path to folder containing images (skips frame extraction)"
    echo "  -n, --num-frames   Number of frames to extract from video (default: $NUM_FRAMES)"
    echo "  -i, --iterations   Number of training iterations for OpenSplat (default: $NUM_ITERATIONS)"
    echo "  -s, --downscale    Downscale factor for images: 1=full, 2=half, 4=quarter (default: $DOWNSCALE_FACTOR)"
    echo "  -o, --output       Output name for project folder and .splat file (default: input name)"
    echo "  --save-every       Save checkpoint every N iterations (default: $SAVE_EVERY, use -1 to disable)"
    echo "  --val              Use validation image to track convergence"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -v /path/to/video.mp4 -n 150 -i 3000 -o my_model"
    echo "  $0 -v /path/to/video.mp4 --save-every 1000 --val -o my_model  # Monitor convergence"
    echo "  $0 -d /path/to/images/ -i 3000 -s 2 -o my_model"
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
        -d|--images-dir)
            INPUT_IMAGES_DIR="$2"
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
        -s|--downscale)
            DOWNSCALE_FACTOR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_NAME="$2"
            shift 2
            ;;
        --save-every)
            SAVE_EVERY="$2"
            shift 2
            ;;
        --val)
            USE_VALIDATION=true
            shift
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

# Check required arguments - need either video or images directory
if [ -z "$VIDEO_PATH" ] && [ -z "$INPUT_IMAGES_DIR" ]; then
    print_error "Either video path (-v) or images directory (-d) is required"
    usage
fi

if [ -n "$VIDEO_PATH" ] && [ -n "$INPUT_IMAGES_DIR" ]; then
    print_error "Cannot specify both video (-v) and images directory (-d)"
    usage
fi

# Determine input mode
if [ -n "$INPUT_IMAGES_DIR" ]; then
    INPUT_MODE="images"
    # Check if images directory exists
    if [ ! -d "$INPUT_IMAGES_DIR" ]; then
        print_error "Images directory not found: $INPUT_IMAGES_DIR"
        exit 1
    fi
    # Set output name from directory name if not provided
    if [ -z "$OUTPUT_NAME" ]; then
        OUTPUT_NAME=$(basename "$INPUT_IMAGES_DIR")
    fi
else
    INPUT_MODE="video"
    # Check if video file exists
    if [ ! -f "$VIDEO_PATH" ]; then
        print_error "Video file not found: $VIDEO_PATH"
        exit 1
    fi
    # Set output name from video filename if not provided
    if [ -z "$OUTPUT_NAME" ]; then
        OUTPUT_NAME=$(basename "$VIDEO_PATH" | sed 's/\.[^.]*$//')
    fi
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

# Check for frame extractor script (only needed for video input)
FRAME_EXTRACTOR="${SCRIPT_DIR}/utils/grame_extractor.py"
if [ "$INPUT_MODE" = "video" ]; then
    if [ ! -f "$FRAME_EXTRACTOR" ]; then
        print_error "Frame extractor script not found at: $FRAME_EXTRACTOR"
        exit 1
    fi
    print_success "Frame extractor script found"
else
    print_success "Using existing images directory (frame extraction skipped)"
fi

# Create project directory
print_step "Setting up project directory"
mkdir -p "$PROJECT_DIR"
mkdir -p "$SPARSE_DIR"
print_success "Created project directory: $PROJECT_DIR"

# =============================================================================
# Step 1: Extract frames from video (or use existing images)
# =============================================================================
if [ "$INPUT_MODE" = "video" ]; then
    print_step "Step 1: Extracting $NUM_FRAMES frames from video"

    python3 "$FRAME_EXTRACTOR" "$VIDEO_PATH" -n "$NUM_FRAMES" -o "$IMAGES_DIR"

    if [ ! -d "$IMAGES_DIR" ] || [ -z "$(ls -A "$IMAGES_DIR")" ]; then
        print_error "Frame extraction failed - no images found"
        exit 1
    fi

    EXTRACTED_COUNT=$(ls -1 "$IMAGES_DIR"/*.png 2>/dev/null | wc -l)
    print_success "Extracted $EXTRACTED_COUNT frames to $IMAGES_DIR"
    CLEANUP_IMAGES=true
else
    print_step "Step 1: Copying images to project directory"
    
    # Count images in source directory (png, jpg, jpeg)
    IMAGE_COUNT=$(find "$INPUT_IMAGES_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | wc -l)
    
    if [ "$IMAGE_COUNT" -eq 0 ]; then
        print_error "No images found in: $INPUT_IMAGES_DIR"
        exit 1
    fi
    
    # Copy images to project directory so OpenSplat can find them
    mkdir -p "$IMAGES_DIR"
    cp "$INPUT_IMAGES_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG} "$IMAGES_DIR/" 2>/dev/null || true
    
    COPIED_COUNT=$(find "$IMAGES_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | wc -l)
    print_success "Copied $COPIED_COUNT images to $IMAGES_DIR"
    CLEANUP_IMAGES=true
fi

# =============================================================================
# Step 2: COLMAP Feature Extraction
# =============================================================================
print_step "Step 2: COLMAP Feature Extraction"

colmap feature_extractor \
    --database_path "$DATABASE_PATH" \
    --image_path "$IMAGES_DIR" \
    --ImageReader.single_camera 1 \
    --ImageReader.camera_model SIMPLE_RADIAL

print_success "Feature extraction complete"

# =============================================================================
# Step 3: COLMAP Exhaustive Matching
# =============================================================================
print_step "Step 3: COLMAP Exhaustive Matching"

colmap exhaustive_matcher \
    --database_path "$DATABASE_PATH"

print_success "Exhaustive matching complete"

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
print_step "Step 5: Running OpenSplat (${NUM_ITERATIONS} iterations, downscale=${DOWNSCALE_FACTOR}x)"

# Create symlink so OpenSplat can find images relative to sparse/0
# OpenSplat looks for images at ../images/ relative to the .bin files
ln -sfn "$IMAGES_DIR" "$SPARSE_DIR/0/images"

# Change to project directory and run OpenSplat
cd "$PROJECT_DIR"

# Build OpenSplat command with optional flags
OPENSPLAT_CMD="$OPENSPLAT_BIN $SPARSE_DIR/0 -n $NUM_ITERATIONS -d $DOWNSCALE_FACTOR -o $OUTPUT_SPLAT"

if [ "$SAVE_EVERY" -gt 0 ] 2>/dev/null; then
    OPENSPLAT_CMD="$OPENSPLAT_CMD --save-every $SAVE_EVERY"
    print_success "Saving checkpoints every $SAVE_EVERY iterations"
fi

if [ "$USE_VALIDATION" = true ]; then
    OPENSPLAT_CMD="$OPENSPLAT_CMD --val"
    print_success "Using validation image to track convergence"
fi

eval $OPENSPLAT_CMD

if [ ! -f "$OUTPUT_SPLAT" ]; then
    print_error "OpenSplat failed - output file not found"
    exit 1
fi

print_success "OpenSplat training complete"

# =============================================================================
# Step 6: Cleanup intermediate files
# =============================================================================
print_step "Step 6: Cleaning up intermediate files"

# Remove images directory (only if we extracted them from video)
if [ "$CLEANUP_IMAGES" = true ] && [ -d "$IMAGES_DIR" ]; then
    rm -rf "$IMAGES_DIR"
    print_success "Removed extracted images directory"
else
    print_success "Kept original images directory"
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

