# Video/Images to 3D Gaussian Splat Pipeline

A complete pipeline to convert video files or image folders into 3D Gaussian Splat (`.splat`) files for 3D visualization.

## Overview

This pipeline automates the entire process of creating a 3D Gaussian Splat from a video or images:

1. **Frame Extraction** — Extracts evenly-spaced frames from your video *(skipped if using images)*
2. **Feature Extraction** — COLMAP detects SIFT features in each frame
3. **Feature Matching** — COLMAP matches features across all image pairs
4. **Sparse Reconstruction** — COLMAP reconstructs camera poses and sparse 3D points
5. **Gaussian Splatting** — OpenSplat trains a 3D Gaussian Splat model
6. **Cleanup** — Removes intermediate files, keeping only the final `.splat`

## Setup

### macOS

```bash
chmod +x setup_mac.sh
./setup_mac.sh
```

This installs dependencies via Homebrew and builds OpenSplat with Metal/MPS support.

### Linux

```bash
chmod +x setup_linux.sh
./setup_linux.sh
```

This installs dependencies via apt-get and builds OpenSplat with CUDA support (if available).

### Usage

```bash
# From video
./video_to_splat.sh -v <video_path> [-n <num_frames>] [-i <iterations>] [-s <downscale>] [-o <output_name>]

# From images folder
./video_to_splat.sh -d <images_dir> [-i <iterations>] [-s <downscale>] [-o <output_name>]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-v, --video` | Path to input video file | |
| `-d, --images-dir` | Path to folder of images (skips frame extraction) | |
| `-n, --num-frames` | Number of frames to extract from video | `100` |
| `-i, --iterations` | Number of OpenSplat training iterations | `7000` |
| `-s, --downscale` | Downscale factor (1=full, 2=half, 4=quarter) | `1` |
| `-o, --output` | Output name (without extension) | Input name |
| `--save-every` | Save checkpoint every N iterations (-1 to disable) | `200` |
| `--val` | Use validation image to track convergence | On |
| `-h, --help` | Show help message | |

> **Note:** You must provide either `-v` (video) or `-d` (images folder), but not both.

## Examples

### From Video

Convert a video using default settings (100 frames, 7000 iterations):

```bash
./video_to_splat.sh -v vids/IMG_2149.MOV
```

This will create `IMG_2149/IMG_2149.splat`.

Checkpoints are saved every 200 iterations by default (e.g., `IMG_2149_200.splat`, `IMG_2149_400.splat`, etc.).

### From Images Folder

Use an existing folder of images:

```bash
./video_to_splat.sh -d path/to/my_images/ -i 3000 -o my_model
```

This will create `my_model/my_model.splat`.

### With Downscaling (for large images)

Use `-s` to downscale images for faster processing and lower memory usage:

```bash
# Process at half resolution
./video_to_splat.sh -d path/to/my_images/ -s 2 -i 3000 -o my_model
```

| Downscale | Resolution | Speed | Memory |
|-----------|------------|-------|--------|
| `-s 1` | Full | Slowest | Highest |
| `-s 2` | Half | ~2x faster | ~4x less |
| `-s 4` | Quarter | ~4x faster | ~16x less |

### Custom Video Settings

Extract 200 frames and train for 10000 iterations:

```bash
./video_to_splat.sh -v vids/my_object.mp4 -n 200 -i 10000 -o my_3d_model
```

This will create `my_3d_model/my_3d_model.splat`.

### Monitor Convergence

Use validation to track when training has converged:

```bash
./video_to_splat.sh -v vids/my_object.mp4 --val -o my_model
```

This withholds one image and prints validation loss at the end. Combined with `--save-every`, you can identify the optimal number of iterations for your scene.

## Viewing Your Splat

Once generated, you can view your `.splat` file using:

- [PlayCanvas Viewer](https://playcanvas.com/viewer) — Drag & drop viewer
- [Antimatter15 Viewer](https://antimatter15.com/splat/) — Web-based viewer
- [SuperSplat Editor](https://playcanvas.com/supersplat/editor) — Edit and clean up your splat

## Project Structure

```
ML-GO/
├── setup_mac.sh           # macOS setup script
├── setup_linux.sh         # Linux setup script
├── video_to_splat.sh      # Main pipeline script
├── README.md              # This file
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

