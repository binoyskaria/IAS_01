#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# Function to print error and exit.
function error_exit {
    echo "$1" >&2
    exit 1
}

# Check if the virtual environment exists; if not, create it.
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv || error_exit "Failed to create venv. Make sure python3-venv is installed."
fi

# Verify the activation script exists.
if [ ! -f "venv/bin/activate" ]; then
    error_exit "Virtual environment activation script not found in venv/bin/activate."
fi

# Activate the virtual environment.
source venv/bin/activate
echo "Virtual environment activated. Using python: $(which python)"

python3 -m pip install --upgrade pip

# Create requirements.txt if it doesn't exist.
if [ ! -f "requirements.txt" ]; then
    echo "requirements.txt not found. Creating default requirements.txt..."
    cat <<EOT > requirements.txt
fastapi
uvicorn[standard]
EOT
fi

# Install required dependencies.
python3 -m pip install -r requirements.txt

# Start the Lifecycle Manager on port 9000.
echo "Starting Lifecycle Manager on port 9000..."
python3 lifecycle_manager.py
