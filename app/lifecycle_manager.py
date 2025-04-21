#!/usr/bin/env python3
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import time
import uvicorn
import json
import threading
import os

app = FastAPI(title="Lifecycle Manager")
AGENTS_JSON_PATH = "./agent/agent_status.json"

class AgentRegistration(BaseModel):
    ip: str
    username: str

# Initialize a lock for synchronizing access to agents_status
agents_lock = threading.Lock()

# Load or initialize JSON file with logging
def load_agents_status():
    if not os.path.exists(AGENTS_JSON_PATH):
        print(f"[{time.ctime()}] JSON file not found at {AGENTS_JSON_PATH}. Initializing empty agents status.")
        return {}
    with open(AGENTS_JSON_PATH, "r") as file:
        data = json.load(file)
        print(f"[{time.ctime()}] Loaded agents status from {AGENTS_JSON_PATH}: {data}")
        return data

# Save JSON file with logging
def save_agents_status(status):
    with open(AGENTS_JSON_PATH, "w") as file:
        json.dump(status, file, indent=4)
    print(f"[{time.ctime()}] Agents status saved to {AGENTS_JSON_PATH}: {status}")

# Global agents_status shared between threads
agents_status = load_agents_status()

@app.post("/register")
def register_agent(agent: AgentRegistration):
    now = time.time()
    agents_status = load_agents_status()
    print(f"[{time.ctime()}] Received registration for agent: {agent}. Current timestamp: {now}")
    print(f"[{time.ctime()}] Old timestamp: {agents_status[agent.ip]['last_seen']}")

    with agents_lock:
        agents_status[agent.ip] = {
            "username": agent.username,
            "status": "online",
            "last_seen": now
        }
        print(f"[{time.ctime()}] Updated agents_status for IP {agent.ip}: {agents_status[agent.ip]}")
        save_agents_status(agents_status)
    print(f"[{time.ctime()}] Agent {agent.ip} registered successfully.")
    return {"message": "Agent registered successfully", "agent": agent}

@app.get("/agents")
def list_agents():
    with agents_lock:
        print(f"[{time.ctime()}] Listing agents: {agents_status}")
        return agents_status

# Background thread to periodically check heartbeat and set offline status
def check_heartbeats():
    while True:
        agents_status = load_agents_status()
        current_time = time.time()
        print(f"[{time.ctime()}] Heartbeat check initiated. Current timestamp: {current_time}")
        with agents_lock:
            # Iterate over a copy of items to avoid issues during iteration
            for ip, details in list(agents_status.items()):
                last_seen = details.get("last_seen", 0)
                elapsed = current_time - last_seen
                print(f"[{time.ctime()}] Checking agent {ip}: last_seen = {last_seen} ({time.ctime(last_seen)}), elapsed = {elapsed:.2f} seconds.")
                if elapsed > (2 * 60):  # 2-minute threshold
                    if agents_status[ip]["status"] != "offline":
                        agents_status[ip]["status"] = "offline"
                        print(f"[{time.ctime()}] Agent {ip} marked as offline due to elapsed time {elapsed:.2f} seconds.")
            save_agents_status(agents_status)
        print(f"[{time.ctime()}] Heartbeat check completed. Sleeping for 10 seconds.")
        time.sleep(10)  # Check every minute

if __name__ == "__main__":
    # heartbeat_thread = threading.Thread(target=check_heartbeats, daemon=True)
    # heartbeat_thread.start()
    print(f"[{time.ctime()}] Heartbeat monitoring thread started.")
    uvicorn.run("lifecycle_manager:app", host="0.0.0.0", port=9000,workers=1,reload=False)
