#!/bin/bash
set -e

# Name for the virtual environment
VENV_NAME="venv_lb"

# Create the virtual environment if it doesn't exist
if [ ! -d "$VENV_NAME" ]; then
  echo "Creating virtual environment '$VENV_NAME'..."
  python3 -m venv "$VENV_NAME"
fi

# Activate the virtual environment
source "$VENV_NAME/bin/activate"

# Upgrade pip to the latest version
pip install --upgrade pip

# Install required dependencies for the load balancer
echo "Installing dependencies from requirements.txt..."
pip install -r requirements.txt

# Start the load balancer server using uvicorn
echo "Starting Load Balancer Server on port 8081..."
uvicorn load_balancer:app --host 0.0.0.0 --port 8081
