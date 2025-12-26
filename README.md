# Video to 3D Gaussian Splat Pipeline

A complete pipeline to convert video files into 3D Gaussian Splat (`.splat`) files for 3D visualization.

## Overview

This pipeline automates the entire process of creating a 3D Gaussian Splat from a video:

1. **Frame Extraction** — Extracts evenly-spaced frames from your video
2. **Feature Extraction** — COLMAP detects SIFT features in each frame
3. **Feature Matching** — COLMAP matches features across all image pairs
4. **Sparse Reconstruction** — COLMAP reconstructs camera poses and sparse 3D points
5. **Gaussian Splatting** — OpenSplat trains a 3D Gaussian Splat model
6. **Cleanup** — Removes intermediate files, keeping only the final `.splat`

## Quick Start with Docker

The easiest way to run the pipeline is using Docker — no manual dependency installation required.

### Build the Docker Image

```bash
# CPU version (works everywhere)
docker build -t video-to-splat .

# CUDA version (requires NVIDIA GPU)
docker build -t video-to-splat --build-arg USE_CUDA=ON .
```

### Run with Docker

```bash
# Basic usage
docker run -v $(pwd):/data video-to-splat -v /data/my_video.mp4

# With custom parameters
docker run -v $(pwd):/data video-to-splat \
    -v /data/my_video.mp4 \
    -n 150 \
    -i 3000 \
    -o my_model

# The output .splat file will be in your current directory
```

### Docker with NVIDIA GPU

```bash
docker run --gpus all -v $(pwd):/data video-to-splat -v /data/my_video.mp4
```

### Run on Cloud GPUs

For faster processing, run on cloud GPU instances:

#### RunPod (Recommended - cheapest for GPU)

```bash
# Build the RunPod-optimized image
docker build -f Dockerfile.runpod -t video-to-splat-runpod .
```

See [docs/runpod-setup.md](docs/runpod-setup.md) for full instructions.

#### Google Cloud Platform

```bash
# Create a GPU VM
gcloud compute instances create video-to-splat-vm \
    --machine-type=n1-standard-8 \
    --accelerator=type=nvidia-tesla-t4,count=1 \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=100GB
```

See [docs/gcp-gpu-setup.md](docs/gcp-gpu-setup.md) for full instructions.

---

## Manual Installation

If you prefer to run without Docker:

### Requirements

- **Python 3** with OpenCV (`pip install opencv-python`)
- **COLMAP** — Install via `brew install colmap` (macOS) or see [COLMAP installation guide](https://colmap.github.io/install.html)
- **OpenSplat** — Must be built in `OpenSplat/build/`. See `OpenSplat/README.md` for build instructions.

### Usage

```bash
./video_to_splat.sh -v <video_path> [-n <num_frames>] [-i <iterations>] [-o <output_name>]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-v, --video` | Path to input video file | **(required)** |
| `-n, --num-frames` | Number of frames to extract from video | `100` |
| `-i, --iterations` | Number of OpenSplat training iterations | `2000` |
| `-o, --output` | Output name for the `.splat` file | Video filename |
| `-h, --help` | Show help message | |

## Example

### Basic Usage

Convert a video using default settings (100 frames, 2000 iterations):

```bash
./video_to_splat.sh -v vids/IMG_2149.MOV
```

This will create `IMG_2149/IMG_2149.splat`.

### Custom Settings

Extract 200 frames and train for 5000 iterations:

```bash
./video_to_splat.sh -v vids/my_object.mp4 -n 200 -i 5000 -o my_3d_model
```

This will create `my_3d_model/my_3d_model.splat`.

## Tips for Best Results

### Recording Your Video

- **Move slowly** around the object/scene
- **Overlap** — Ensure each frame shares ~60-80% content with adjacent frames
- **Lighting** — Use consistent, diffuse lighting (avoid harsh shadows)
- **Avoid motion blur** — Keep the camera steady while moving
- **Full coverage** — Capture the object from multiple angles (360° if possible)

### Choosing Parameters

| Scenario | Frames | Iterations |
|----------|--------|------------|
| Quick preview | 50-100 | 1000 |
| Standard quality | 100-200 | 2000-3000 |
| High quality | 200-300 | 5000+ |

More frames and iterations = better quality but longer processing time.

## Viewing Your Splat

Once generated, you can view your `.splat` file using:

- [PlayCanvas Viewer](https://playcanvas.com/viewer) — Drag & drop viewer
- [Antimatter15 Viewer](https://antimatter15.com/splat/) — Web-based viewer
- [SuperSplat Editor](https://playcanvas.com/supersplat/editor) — Edit and clean up your splat

## Troubleshooting

### COLMAP fails with "No good initial image pair found"
- Try extracting more frames (`-n 200`)
- Ensure your video has enough visual features and camera movement

### OpenSplat crashes or runs out of memory
- Reduce the number of frames
- Reduce training iterations

### Poor reconstruction quality
- Record video with more overlap between frames
- Ensure good lighting and sharp images
- Avoid reflective or transparent surfaces

## Project Structure

```
ML-GO/
├── Dockerfile             # Docker build file (CPU/CUDA)
├── Dockerfile.runpod      # RunPod-optimized Dockerfile
├── video_to_splat.sh      # Main pipeline script
├── README.md              # This file
├── docs/
│   ├── gcp-gpu-setup.md   # GCP deployment guide
│   └── runpod-setup.md    # RunPod deployment guide
├── utils/
│   └── grame_extractor.py # Frame extraction utility
├── OpenSplat/
│   └── build/
│       └── opensplat      # OpenSplat binary
└── <output_name>/
    └── <output_name>.splat # Generated splat file
```

## License

See individual component licenses:
- OpenSplat: AGPLv3
- COLMAP: BSD

