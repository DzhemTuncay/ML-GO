# Running Video-to-Splat on GCP with GPU

This guide shows how to run the pipeline on Google Cloud Platform using a GPU-enabled VM.

## Prerequisites

- GCP account with billing enabled
- `gcloud` CLI installed locally ([Install guide](https://cloud.google.com/sdk/docs/install))
- GPU quota in your project (you may need to request an increase)

## Quick Start

### 1. Set Up gcloud

```bash
# Login to GCP
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID

# Set default zone (choose one with GPU availability)
gcloud config set compute/zone us-central1-a
```

### 2. Create a GPU-Enabled VM

```bash
# Create VM with NVIDIA T4 GPU (good balance of cost/performance)
gcloud compute instances create video-to-splat-vm \
    --machine-type=n1-standard-8 \
    --accelerator=type=nvidia-tesla-t4,count=1 \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=100GB \
    --boot-disk-type=pd-ssd \
    --maintenance-policy=TERMINATE \
    --metadata="install-nvidia-driver=True"
```

**Alternative GPU options:**
| GPU | Use Case | Cost |
|-----|----------|------|
| `nvidia-tesla-t4` | Good balance, recommended | ~$0.35/hr |
| `nvidia-tesla-v100` | Faster training | ~$2.48/hr |
| `nvidia-tesla-a100` | Fastest, large scenes | ~$3.67/hr |
| `nvidia-l4` | Newer, efficient | ~$0.81/hr |

### 3. SSH into the VM

```bash
gcloud compute ssh video-to-splat-vm
```

### 4. Install NVIDIA Drivers & Docker

Run these commands on the VM:

```bash
# Install NVIDIA drivers
sudo apt-get update
sudo apt-get install -y linux-headers-$(uname -r)
sudo apt-get install -y nvidia-driver-535

# Reboot to load drivers
sudo reboot
```

After reboot, SSH back in:

```bash
gcloud compute ssh video-to-splat-vm
```

Continue with Docker setup:

```bash
# Verify GPU is detected
nvidia-smi

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Log out and back in for group changes
exit
```

SSH back in:
```bash
gcloud compute ssh video-to-splat-vm
```

### 5. Clone and Build the Container

```bash
# Clone your repo (or copy files)
git clone YOUR_REPO_URL
cd ML-GO

# Build with CUDA support
docker build -t video-to-splat --build-arg USE_CUDA=ON .
```

### 6. Upload Your Video

From your local machine:

```bash
# Copy video to VM
gcloud compute scp /path/to/your/video.mp4 video-to-splat-vm:~/
```

### 7. Run the Pipeline

On the VM:

```bash
# Create output directory
mkdir -p ~/output

# Run with GPU
docker run --gpus all \
    -v ~/output:/data \
    -v ~/video.mp4:/data/video.mp4 \
    video-to-splat \
    -v /data/video.mp4 -n 150 -i 3000 -o my_model
```

### 8. Download Results

From your local machine:

```bash
# Download the .splat file
gcloud compute scp video-to-splat-vm:~/output/my_model/my_model.splat ./
```

### 9. Clean Up (Important - Stop Billing!)

```bash
# Stop the VM when not in use (preserves data)
gcloud compute instances stop video-to-splat-vm

# Or delete it entirely
gcloud compute instances delete video-to-splat-vm
```

---

## One-Liner Setup Script

Save this as `setup-gcp-vm.sh` and run on a fresh VM:

```bash
#!/bin/bash
set -e

echo "Installing NVIDIA drivers..."
sudo apt-get update
sudo apt-get install -y linux-headers-$(uname -r) nvidia-driver-535

echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

echo "Installing NVIDIA Container Toolkit..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

echo "Setup complete! Please reboot: sudo reboot"
```

---

## Using Pre-emptible/Spot VMs (Save ~70% Cost)

For long training jobs, use spot VMs which are much cheaper but can be terminated:

```bash
gcloud compute instances create video-to-splat-vm \
    --machine-type=n1-standard-8 \
    --accelerator=type=nvidia-tesla-t4,count=1 \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=100GB \
    --boot-disk-type=pd-ssd \
    --maintenance-policy=TERMINATE \
    --provisioning-model=SPOT \
    --metadata="install-nvidia-driver=True"
```

---

## Troubleshooting

### "GPU quota exceeded"
Request quota increase at: https://console.cloud.google.com/iam-admin/quotas

### "nvidia-smi: command not found"
Reboot the VM after driver installation: `sudo reboot`

### Docker permission denied
Run: `newgrp docker` or log out and back in

### CUDA out of memory
- Use fewer frames (`-n 50`)
- Use a GPU with more VRAM (V100 or A100)

---

## Cost Estimate

| Component | Cost/Hour |
|-----------|-----------|
| n1-standard-8 VM | ~$0.38 |
| NVIDIA T4 GPU | ~$0.35 |
| **Total** | **~$0.73/hr** |

A typical run (100 frames, 2000 iterations) takes 15-30 minutes = ~$0.25-0.50

Using Spot VMs reduces this to ~$0.08-0.15 per run.

