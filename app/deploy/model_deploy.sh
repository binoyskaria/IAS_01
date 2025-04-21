#!/bin/bash
# model_deploy.sh - Remotely deploys the model serve script on designated machines.
# Updated version: Instead of a single model.zip, we now work with a models folder containing:
# - model_xxx folders (each with config.json and model.zip)
# - a live_models.json file, e.g.:
#   {
#       "live_models": []
#   }
# The script checks each model_xxx folder for its id (from config.json) and if it is not present in live_models,
# it deploys the first non-live model found. If deployment to all online agents succeeds,
# the model id is added to live_models.json.

# Set paths for models and live_models file, NFS share directory, and agents JSON
NFS_SHARE_DIR="/nfs_share/models"
MNT_NFS_DIR="/mnt/nfs/models"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MODEL_BASE_DIR="$SCRIPT_DIR/../models"
LIVE_MODELS_JSON="$MODEL_BASE_DIR/live_models.json"
AGENTS_JSON="$SCRIPT_DIR/../agent/agent_status.json"

# Log function to add timestamps and log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_message "Starting model deployment process..."

# Ensure live_models.json exists
if [ ! -f "$LIVE_MODELS_JSON" ]; then
    log_message "live_models.json not found at $LIVE_MODELS_JSON." >&2
    exit 1
fi

# Initialize selected model variables
SELECTED_MODEL_DIR=""
SELECTED_MODEL_ID=""

# Loop through each model_xxx folder in the models directory
for d in "$MODEL_BASE_DIR"/model_*; do
    if [ -d "$d" ]; then
        if [ ! -f "$d/config.json" ]; then
            log_message "config.json not found in $d. Skipping."
            continue
        fi
        # Extract model id from config.json using jq
        model_id=$(jq -r '.id' "$d/config.json")
        if [ -z "$model_id" ]; then
            log_message "Model ID is empty in $d/config.json. Skipping."
            continue
        fi
        
        # Check if the model id is present in live_models.json
        is_live=$(jq --arg id "$model_id" '.live_models[] | select(. == $id)' "$LIVE_MODELS_JSON")
        if [ -n "$is_live" ]; then
            log_message "Model [$model_id] is already live. Skipping $d."
        else
            SELECTED_MODEL_DIR="$d"
            SELECTED_MODEL_ID="$model_id"
            log_message "Selected model [$SELECTED_MODEL_ID] from directory $SELECTED_MODEL_DIR for deployment."
            break
        fi
    fi
done

if [ -z "$SELECTED_MODEL_DIR" ]; then
    log_message "No non-live model found for deployment. Exiting."
    exit 0
fi

# Set the model file path from the selected model directory
MODEL_FILE_PATH="$SELECTED_MODEL_DIR/$SELECTED_MODEL_ID.zip"

log_message "Model file path: $MODEL_FILE_PATH"
log_message "Agents JSON: $AGENTS_JSON"

# Create the models directory on the NFS share if it does not exist and set permissions to 777
if [ ! -d "$NFS_SHARE_DIR" ]; then
    log_message "Models directory does not exist on NFS share. Creating $NFS_SHARE_DIR..."
    if [ "$(id -u)" -ne 0 ]; then
        sudo mkdir -p "$NFS_SHARE_DIR"
        sudo chmod 777 "$NFS_SHARE_DIR"
    else
        mkdir -p "$NFS_SHARE_DIR"
        chmod 777 "$NFS_SHARE_DIR"
    fi

    if [ ! -d "$NFS_SHARE_DIR" ]; then
        log_message "Failed to create models directory at $NFS_SHARE_DIR" >&2
        exit 1
    else
        log_message "Successfully created models directory at $NFS_SHARE_DIR."
    fi
else
    log_message "Models directory already exists at $NFS_SHARE_DIR. Skipping creation."
    chmod 777 "$NFS_SHARE_DIR" 2>/dev/null
fi

# Check if model.zip exists in the selected model folder
if [ ! -f "$MODEL_FILE_PATH" ]; then
    log_message "model.zip not found at $MODEL_FILE_PATH." >&2
    exit 1
fi

# Copy the selected model.zip to the NFS share.
# Use the model id as the filename so it can be identified later.
DEST_MODEL_FILE="$NFS_SHARE_DIR/${SELECTED_MODEL_ID}.zip"
log_message "Copying model.zip to NFS share as $DEST_MODEL_FILE..."
install -m 777 "$MODEL_FILE_PATH" "$DEST_MODEL_FILE"
if [ $? -eq 0 ]; then
    log_message "Successfully copied model.zip to NFS share."
else
    log_message "Failed to copy model.zip to NFS share." >&2
    exit 1
fi

# Check for agent status JSON file
log_message "Using agents JSON file at: $AGENTS_JSON"
if [ -f "$AGENTS_JSON" ]; then
    log_message "Contents of $AGENTS_JSON:"
    cat "$AGENTS_JSON"
else
    log_message "Agents JSON file not found." >&2
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_message "jq command not found. Please install jq to proceed." >&2
    exit 1
fi

# Fetch online agents from the agent status JSON file
ONLINE_AGENTS=$(jq -c '. | to_entries[] | select(.value.status=="online")' "$AGENTS_JSON")
log_message "Fetched online agents: $ONLINE_AGENTS"

if [ -z "$ONLINE_AGENTS" ]; then
    log_message "No online agents found in JSON. Exiting."
    exit 1
fi

# Array to hold background process PIDs
PIDS=()

tmpfile=$(mktemp)
if jq --arg id "$SELECTED_MODEL_ID" '.live_models += [$id]' "$LIVE_MODELS_JSON" > "$tmpfile"; then
    mv "$tmpfile" "$LIVE_MODELS_JSON"
    log_message "live_models.json updated successfully with model id [$SELECTED_MODEL_ID]."
else
    log_message "Failed to update live_models.json." >&2
    rm -f "$tmpfile"
    exit 1
fi
# Iterate through each online agent using process substitution
while IFS= read -r AGENT; do
    log_message "Processing agent JSON: $AGENT"
    AGENT_IP=$(echo "$AGENT" | jq -r '.key')
    USERNAME=$(echo "$AGENT" | jq -r '.value.username')
    
    log_message "Extracted agent details - IP: [$AGENT_IP], Username: [$USERNAME]"
    
    if [ -z "$AGENT_IP" ] || [ -z "$USERNAME" ]; then
        log_message "One or more agent details are missing. Skipping this agent."
        continue
    fi

    log_message "Deploying to ($AGENT_IP) as user $USERNAME"

    # Redirect each SSH command's output to its own log file and run it in background.
    LOGFILE="$SCRIPT_DIR/model_serve_${AGENT_IP}.log"
    ssh "$USERNAME@$AGENT_IP" "bash -s" < "$SCRIPT_DIR/model_serve.sh" \
        "$MNT_NFS_DIR/${SELECTED_MODEL_ID}.zip" "$MNT_NFS_DIR/extracted_model_files" "$SELECTED_MODEL_ID" \
        > "$LOGFILE" 2>&1 &
    pid=$!
    PIDS+=($pid)
    log_message "Deployment initiated for $USERNAME at $AGENT_IP (PID: $pid). Output logged to $LOGFILE."
done < <(echo "$ONLINE_AGENTS")



log_message "Model deployment process completed on all agents."
