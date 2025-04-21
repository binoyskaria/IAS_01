#!/bin/bash
# setup_nfs.sh - Install and configure NFS server with a shared directory.
# This script must be run on a Debian/Ubuntu system.
# It installs the NFS server, creates a shared directory, sets permissions,
# adds the export configuration with no_root_squash, exports the share, and restarts the NFS service.

set -e

echo "Installing NFS kernel server..."
sudo apt install -y nfs-kernel-server

# Create the shared directory
SHARE_DIR="/nfs_share"
echo "Creating shared directory: $SHARE_DIR"
sudo mkdir -p "$SHARE_DIR"

# Set ownership and permissions for the share
echo "Setting ownership to nobody:nogroup and permissions to 777 for $SHARE_DIR"
sudo chown nobody:nogroup "$SHARE_DIR"
sudo chmod 777 "$SHARE_DIR"

# Backup the current exports file
echo "Backing up /etc/exports to /etc/exports.bak"
sudo cp /etc/exports /etc/exports.bak

# Define the export line for the shared directory.
# The no_root_squash option allows remote root operations to be performed as the root user on the server.
EXPORT_LINE="$SHARE_DIR *(rw,sync,no_subtree_check,no_root_squash)"

# Check if the export entry already exists, if not, add it.
if grep -q "^$SHARE_DIR" /etc/exports; then
    echo "Export entry for $SHARE_DIR already exists in /etc/exports"
else
    echo "Adding export entry for $SHARE_DIR to /etc/exports"
    echo "$EXPORT_LINE" | sudo tee -a /etc/exports
fi

# Export the shared directory
echo "Exporting shared directory..."
sudo exportfs -ra

# Restart the NFS service to apply changes
echo "Restarting NFS server..."
sudo systemctl restart nfs-kernel-server

# Verify the export configuration
echo "Verifying NFS exports..."
sudo exportfs -v

echo "NFS server setup complete."
