# How to run

1. **Setup NFS (assuming local system itself is NFS server)**

   First, change to the `nfs` folder:
   ```
   cd ./app/nfs
   ```

   Then, run the NFS setup script:
   ```
   ./setup_nfs.sh
   ```

2. **Spin up lifecycle manager to monitor agents**

   Change to the `app` directory:
   ```
   cd ./app
   ```

   Then, run the lifecycle manager:
   ```
   ./run_lifecycle_manager.sh
   ```

3. **Spin up agents (in Inference-servers) to make them online**

   Change to the `agent` directory:
   ```
   cd ./app/agent
   ```

   Then, deploy the agents:
   ```
   ./agent_deploy.sh
   ```

4. **Deploy the model to all agents**

   Again, change to the `app` directory:
   ```
   cd ./app
   ```

   Then, deploy the model:
   ```
   ./deploy/model_deploy.sh
   ```

5. **Spin up the load balancer**

   Change to the `load_balancer` directory:
   ```
   cd ./app/load_balancer
   ```

   Then, run the load balancer:
   ```
   ./load_balancer.sh
   ```

6. **Access frontend.html to run the model**

   Simply open the `frontend.html` file in a browser. 

# Server Types - Report

## Internal API server
An internal API server built with FastAPI (`lifecycle_manager.py`). It collects heartbeat data from agent servers, maintains an up-to-date registry of online agents, and exposes endpoints (like `/agents`).

## Inference Server
The backend service that actually hosts the machine learning model. Each model inference server runs on a remote machine (using FastAPI in your model serve code).

## Load Balancer Server
A dedicated FastAPI service (`load_balancer_server.py`) that sits between clients and the model inference servers. It reads the list of online agents from the lifecycle manager, using a round-robin algorithm to distribute incoming inference requests across available model servers.

## Web Server
The server that delivers your static frontend (HTML, CSS, JavaScript) to users. In this case, it’s a simple static HTML file.

## NFS Server
The server that serves the shared file system. In this case, we have the `/nfs_share` directory on the local system.

