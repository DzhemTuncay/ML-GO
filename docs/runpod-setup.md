# Running Video-to-Splat on RunPod

RunPod offers affordable GPU cloud computing, often cheaper than GCP/AWS for GPU workloads.

## Option 1: Build and Push to Docker Hub

### 1. Build the RunPod-optimized image locally

```bash
docker build -f Dockerfile.runpod -t your-dockerhub-username/video-to-splat:runpod .
```

### 2. Push to Docker Hub

```bash
docker login
docker push your-dockerhub-username/video-to-splat:runpod
```

### 3. Create a RunPod Template

1. Go to [RunPod Templates](https://www.runpod.io/console/user/templates)
2. Click "New Template"
3. Fill in:
   - **Template Name:** video-to-splat
   - **Container Image:** `your-dockerhub-username/video-to-splat:runpod`
   - **Docker Command:** Leave empty (uses entrypoint)
   - **Container Disk:** 20 GB
   - **Volume Disk:** 50 GB (for input/output files)
   - **Volume Mount Path:** `/workspace`

### 4. Launch a Pod

1. Go to [GPU Cloud](https://www.runpod.io/console/gpu-cloud)
2. Select a GPU (RTX 3090, RTX 4090, or A100 recommended)
3. Choose your template
4. Deploy

### 5. Run the Pipeline

Connect via SSH or web terminal:

```bash
# Upload your video to /workspace (use RunPod's file manager or scp)

# Run the pipeline
/app/video_to_splat.sh -v /workspace/my_video.mp4 -n 150 -i 3000 -o my_model

# Output will be in /workspace/my_model/my_model.splat
```

---

## Option 2: Use RunPod's PyTorch Template + Manual Setup

If you don't want to build a custom image:

### 1. Deploy a Pod

1. Go to [RunPod GPU Cloud](https://www.runpod.io/console/gpu-cloud)
2. Select a GPU
3. Use template: **RunPod Pytorch 2.4.0**
4. Deploy

### 2. Install Dependencies

Connect via SSH or web terminal and run:

```bash
# Install system dependencies
apt-get update && apt-get install -y \
    cmake ninja-build libopencv-dev colmap \
    libboost-program-options-dev libboost-filesystem-dev \
    libboost-graph-dev libeigen3-dev libceres-dev

# Install Python packages
pip install opencv-python-headless

# Clone and build OpenSplat
cd /workspace
git clone https://github.com/pierotofy/OpenSplat.git
cd OpenSplat

# Download libtorch
wget -q "https://download.pytorch.org/libtorch/cu124/libtorch-cxx11-abi-shared-with-deps-2.4.0%2Bcu124.zip" -O libtorch.zip
unzip -q libtorch.zip
rm libtorch.zip

# Build
mkdir build && cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/workspace/OpenSplat/libtorch
ninja
```

### 3. Clone the Pipeline

```bash
cd /workspace
git clone YOUR_REPO_URL ML-GO
cd ML-GO
chmod +x video_to_splat.sh
```

### 4. Run

```bash
./video_to_splat.sh -v /workspace/my_video.mp4 -n 150 -o my_model
```

---

## GPU Recommendations for RunPod

| GPU | VRAM | Cost | Best For |
|-----|------|------|----------|
| RTX 3090 | 24GB | ~$0.44/hr | Good value |
| RTX 4090 | 24GB | ~$0.74/hr | Fast, recommended |
| A100 40GB | 40GB | ~$1.64/hr | Large scenes |
| A100 80GB | 80GB | ~$2.29/hr | Very large scenes |

## Tips

- **Use Spot instances** for ~50% savings (may be interrupted)
- **Volume storage** persists between sessions - save your outputs there
- **Upload via RunPod UI** - easier than scp for large files
- **Stop pods when done** to avoid charges

## Typical Run Time

| Frames | Iterations | RTX 4090 | RTX 3090 |
|--------|------------|----------|----------|
| 100 | 2000 | ~10 min | ~15 min |
| 200 | 3000 | ~25 min | ~40 min |
| 200 | 5000 | ~40 min | ~60 min |

