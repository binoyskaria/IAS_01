#!/bin/bash
# agent_install.sh - This script configures the remote machine to run the agent.
# It installs necessary packages, mounts the NFS share, creates a virtual environment,
# installs agent dependencies, and starts the agent.
#
# This version includes detailed logging and ensures that resources are only created if they do not exist.

set -e  # Exit immediately if any command fails

# Function to log messages with a timestamp
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Retrieve the agent IP and username passed as arguments.
REMOTE_AGENT_IP="$1"
REMOTE_AGENT_USERNAME="$2"

log "Starting agent installation. Remote agent IP: ${REMOTE_AGENT_IP}, Username: ${REMOTE_AGENT_USERNAME}"

# Check and install NFS client packages if not already installed.
log "Checking if nfs-common is installed..."
if ! dpkg -s nfs-common >/dev/null 2>&1; then
  log "nfs-common not found. Installing nfs-common packages..."
  sudo apt-get update && sudo apt-get install -y nfs-common
  log "nfs-common installation complete."
else
  log "nfs-common is already installed."
fi

# Ensure the mount point exists.
log "Ensuring mount point /mnt/nfs exists..."
if [ ! -d /mnt/nfs ]; then
  sudo mkdir -p /mnt/nfs
  log "Created mount point /mnt/nfs."
else
  log "Mount point /mnt/nfs already exists."
fi

# If the NFS share is already mounted, unmount it then remount it.
if mountpoint -q /mnt/nfs; then
  log "NFS share is already mounted on /mnt/nfs. Unmounting..."
  sudo umount /mnt/nfs
  log "Unmounted the NFS share."
fi

log "Mounting NFS share from 192.168.43.151:/nfs_share to /mnt/nfs..."
sudo mount -t nfs 192.168.43.151:/nfs_share /mnt/nfs
log "NFS share mounted successfully."

# Check and install Python3, python3-venv, and python3-pip if not installed.
log "Checking if Python3, python3-venv, and python3-pip are installed..."
if ! command -v python3 >/dev/null 2>&1; then
  log "Python3 is not installed. Installing Python3, python3-venv, and python3-pip..."
  sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip
  log "Python3, venv, and pip installation complete."
else
  log "Python3 is already installed."
fi

# Create a virtual environment for the agent only if it doesn't already exist.
AGENT_VENV="agent_venv"
if [ ! -d "$AGENT_VENV" ]; then
  log "Virtual environment '$AGENT_VENV' does not exist. Creating virtual environment..."
  python3 -m venv "$AGENT_VENV"
  log "Virtual environment created."
else
  log "Virtual environment '$AGENT_VENV' already exists. Skipping creation."
fi

# Activate the virtual environment.
log "Activating virtual environment..."
source "$AGENT_VENV/bin/activate"

# Upgrade pip and install the Python dependency.
log "Upgrading pip..."
pip install --upgrade pip

log "Installing Python dependency 'requests'..."
pip install requests

# Start the agent from the mounted NFS share.
log "Starting agent..."
nohup python3 /mnt/nfs/agent.py "$REMOTE_AGENT_IP" "$REMOTE_AGENT_USERNAME" &

log "Agent installation and startup complete."
