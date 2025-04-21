#!/usr/bin/env python3
import time
import requests
import sys

LIFECYCLE_MANAGER_URL = "http://192.168.43.151:9000/register"
HEARTBEAT_INTERVAL = 5  # seconds

def get_local_ip():
    # If an IP address is provided as the first argument, use it.
    if len(sys.argv) > 1:
        ip = sys.argv[1]
        print(f"[{time.ctime()}] Using provided IP: {ip}")
        return ip
    ip = "127.0.0.1"
    print(f"[{time.ctime()}] No IP provided. Using default IP: {ip}")
    return ip

def get_username():
    # If a username is provided as the second argument, use it.
    if len(sys.argv) > 2:
        username = sys.argv[2]
        print(f"[{time.ctime()}] Using provided username: {username}")
        return username
    username = "unknown"
    print(f"[{time.ctime()}] No username provided. Using default username: {username}")
    return username

def send_heartbeat():
    ip = get_local_ip()
    username = get_username()
    data = {"ip": ip, "username": username}
    try:
        print(f"[{time.ctime()}] Sending heartbeat with data: {data}")
        response = requests.post(LIFECYCLE_MANAGER_URL, json=data, timeout=5)
        if response.status_code == 200:
            print(f"[{time.ctime()}] Heartbeat sent successfully: {data}")
        else:
            print(f"[{time.ctime()}] Heartbeat failed with status code: {response.status_code}")
    except Exception as e:
        print(f"[{time.ctime()}] Heartbeat error: {e}")

def main():
    print(f"[{time.ctime()}] Starting agent heartbeat...")
    while True:
        send_heartbeat()
        time.sleep(HEARTBEAT_INTERVAL)

if __name__ == "__main__":
    main()
