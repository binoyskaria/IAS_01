#!/bin/bash
# model_serve.sh - Starts the model server after preparing the model files.
# Expects three parameters:
#   1. Path to model.zip on the NFS share (MODEL_NFS)
#   2. Local directory to extract model files (LOCAL_MODEL_DIR)
#   3. Subdirectory within the extracted directory containing the FastAPI server (MODEL_SUBDIR)
#
# Usage:
#   ./model_serve.sh /mnt/nfs/models/model.zip /mnt/nfs/models/extracted_model_files model

# Exit immediately if a command exits with a non-zero status.
set -e

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <MODEL_NFS> <LOCAL_MODEL_DIR> <MODEL_SUBDIR>" >&2
    exit 1
fi

MODEL_NFS="$1"
LOCAL_MODEL_DIR="$2"
MODEL_SUBDIR="$3"

# Function to print error and exit.
function error_exit {
    echo "$1" >&2
    exit 1
}

echo "Parameters:"
echo "MODEL_NFS: $MODEL_NFS"
echo "LOCAL_MODEL_DIR: $LOCAL_MODEL_DIR"
echo "MODEL_SUBDIR: $MODEL_SUBDIR"

# Check if the virtual environment exists; if not, create it.
if [ ! -d "model_venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv model_venv || error_exit "Failed to create virtual environment. Make sure python3-venv is installed."
fi

# Verify the activation script exists.
if [ ! -f "model_venv/bin/activate" ]; then
    error_exit "Virtual environment activation script not found in model_venv/bin/activate."
fi

# Activate virtual environment.
source model_venv/bin/activate
echo "Virtual environment activated. Using python: $(which python)"


# Check for the zipped model package on the NFS share and extract if found.
if [ -f "$MODEL_NFS" ]; then
    echo "Found model.zip in NFS share at $MODEL_NFS. Extracting to $LOCAL_MODEL_DIR..."
    mkdir -p "$LOCAL_MODEL_DIR"
    unzip -o "$MODEL_NFS" -d "$LOCAL_MODEL_DIR" || error_exit "Failed to extract model.zip"
    echo "Model extracted successfully."
else
    echo "No model.zip found at $MODEL_NFS. Using local model files if available."
fi

# Change to the directory where the server file is located.
TARGET_DIR="$LOCAL_MODEL_DIR/$MODEL_SUBDIR"
if [ -d "$TARGET_DIR" ]; then
    echo "Changing to model server directory: $TARGET_DIR"
    cd "$TARGET_DIR"
else
    error_exit "Model server directory not found at $TARGET_DIR."
fi



# Ensure pip is available; install it using ensurepip if necessary.
python3 -m ensurepip --upgrade || error_exit "Failed to run ensurepip. Please ensure pip is installed."
python3 -m pip install --upgrade pip

# Install CPU-only PyTorch and other dependencies.
echo "Installing CPU-only version of PyTorch, torchvision, and torchaudio..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Create requirements.txt if it doesn't exist.
if [ ! -f "$TARGET_DIR/requirements.txt" ]; then
    echo "requirements.txt not found. Creating default requirements.txt..."
    cat <<EOT > requirements.txt
fastapi
uvicorn[standard]
pillow
python-multipart
EOT
else
    echo "used default requirements.txt"
fi

# Install required dependencies.
python3 -m pip install -r requirements.txt



# Start the FastAPI server.
echo "Starting FastAPI server on port 8000..."
python3 server.py
