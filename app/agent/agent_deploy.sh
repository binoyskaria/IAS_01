#!/bin/bash
# deploy_agent.sh - Remotely deploys the agent_install.sh script on designated machines.
# It first copies agent.py from the central system into the NFS share so that remote machines can access it.

# Set paths for agent file and NFS share directory (update these paths if necessary)
AGENT_FILE_PATH="./agent.py"
NFS_SHARE_DIR="/nfs_share"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
AGENTS_JSON="$SCRIPT_DIR/agent_status.json"



# Log function to add timestamps to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_message "AGENT_FILE_PATH: $AGENT_FILE_PATH"
log_message "NFS_SHARE_DIR: $NFS_SHARE_DIR"
log_message "SCRIPT_DIR: $SCRIPT_DIR"
log_message "AGENTS_JSON: $AGENTS_JSON"

log_message "Starting agent deployment process..."

# Verify the existence of agent.py before copying
if [ ! -f "$AGENT_FILE_PATH" ]; then
    log_message "agent.py not found at $AGENT_FILE_PATH." >&2
    exit 1
fi

# Copy agent.py to the NFS share
log_message "Copying agent.py from $AGENT_FILE_PATH to $NFS_SHARE_DIR/agent.py..."
cp "$AGENT_FILE_PATH" "$NFS_SHARE_DIR/agent.py"
if [ $? -eq 0 ]; then
    log_message "Successfully copied agent.py to NFS share."
else
    log_message "Failed to copy agent.py to NFS share." >&2
    exit 1
fi

# Verify the existence of the agents JSON file
if [ ! -f "$AGENTS_JSON" ]; then
    log_message "Agents JSON file not found at $AGENTS_JSON." >&2
    exit 1
fi

log_message "Using agents JSON file at: $AGENTS_JSON"
log_message "Contents of $AGENTS_JSON:"
cat "$AGENTS_JSON"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_message "jq command not found. Please install jq to proceed." >&2
    exit 1
fi

# Select agents with status "unknown" for deployment
UNKNOWN_AGENTS=$(jq -c '. | to_entries[] | select(.value.status=="unknown")' "$AGENTS_JSON")
log_message "Fetched unknown agents: $UNKNOWN_AGENTS"

# Check if any unknown agents were found
if [ -z "$UNKNOWN_AGENTS" ]; then
    log_message "No unknown agents found in JSON. Exiting."
    exit 0
fi

# Process each unknown agent using process substitution to avoid SSH consuming the loop's STDIN.
while IFS= read -r AGENT; do
    log_message "Processing agent JSON: $AGENT"
    AGENT_IP=$(echo "$AGENT" | jq -r '.key')
    USERNAME=$(echo "$AGENT" | jq -r '.value.username')

    log_message "Extracted agent details - IP: [$AGENT_IP], Username: [$USERNAME]"

    if [ -z "$AGENT_IP" ] || [ -z "$USERNAME" ]; then
        log_message "One or more agent details are missing. Skipping this agent."
        continue
    fi

    log_message "Deploying to agent ($AGENT_IP) as user [$USERNAME]"

    # Create a dedicated log file for the agent's deployment output.
    LOGFILE="$SCRIPT_DIR/agent_install_${AGENT_IP}.log"

    # Launch SSH in background so the infinite running remote script doesn't block the loop.
    ssh "$USERNAME@$AGENT_IP" "bash -s" < <(cat "$SCRIPT_DIR/agent_install.sh") "$AGENT_IP" "$USERNAME" \
        > "$LOGFILE" 2>&1 &
    DEPLOY_PID=$!
    log_message "Deployment initiated for $USERNAME at $AGENT_IP (PID: $DEPLOY_PID). Output logged to $LOGFILE."
done < <(echo "$UNKNOWN_AGENTS")

log_message "Agent deployment process initiated on all agents."
