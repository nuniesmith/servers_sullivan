#!/bin/bash
set -euo pipefail

# Configure NVIDIA GPU for Docker after reboot
# Run this script after rebooting to complete GPU setup

echo "==> Checking NVIDIA driver installation..."
if ! nvidia-smi &>/dev/null; then
    echo "ERROR: NVIDIA driver not loaded. Checking DKMS status..."
    sudo dkms status
    
    echo "==> Building NVIDIA kernel module..."
    sudo dkms autoinstall -k $(uname -r)
    
    echo "==> Loading NVIDIA kernel module..."
    sudo modprobe nvidia
fi

echo "==> Verifying NVIDIA GPU detection..."
nvidia-smi

echo "==> Configuring Docker for NVIDIA runtime..."
sudo nvidia-ctk runtime configure --runtime=docker

echo "==> Restarting Docker service..."
sudo systemctl restart docker

echo "==> Waiting for Docker to be ready..."
sleep 5

echo "==> Testing NVIDIA GPU in Docker..."
docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.0.0-base-ubuntu20.04 nvidia-smi

echo "==> Recreating Emby and Plex with GPU support..."
cd /home/jordan/sullivan
docker compose up -d --force-recreate emby plex

echo ""
echo "✅ NVIDIA GPU configuration complete!"
echo ""
echo "Verify GPU is being used:"
echo "  - Emby: Check transcoding settings in dashboard"
echo "  - Plex: Settings > Transcoder > Use hardware acceleration when available"
echo ""
echo "Monitor GPU usage: watch -n 1 nvidia-smi"
