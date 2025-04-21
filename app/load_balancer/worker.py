#!/usr/bin/env python3
import asyncio
import json
import logging
import base64
from pathlib import Path

import httpx
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

# configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(message)s",
)

# Kafka settings
BOOTSTRAP_SERVERS = "localhost:9092"
REQ_TOPIC = "inference-requests"
RES_TOPIC = "inference-responses"

# Round‑robin state
current_index = 0
index_lock = asyncio.Lock()

# Where your agents.json lives
AGENT_STATUS_FILE = Path(__file__).parent.parent / "agent" / "agent_status.json"
BACKEND_PORT = 8000   # as in your example

async def select_endpoint():
    """
    Load agent_status.json, pick only "online" agents,
    then round‑robin-select one and return its /infer URL.
    """
    global current_index

    try:
        agents = json.loads(AGENT_STATUS_FILE.read_text())
    except Exception as e:
        logging.error(f"Could not read agent status file: {e}")
        raise RuntimeError("Agent status unavailable") from e

    online = [
        f"http://{ip}:{BACKEND_PORT}/infer"
        for ip, info in agents.items()
        if info.get("status") == "online"
    ]
    if not online:
        raise RuntimeError("No online agents available")

    async with index_lock:
        endpoint = online[current_index % len(online)]
        current_index += 1

    logging.info(f"Round‑robin selected endpoint: {endpoint}")
    return endpoint

async def run_inference(data):
    """
    data is the dict you stored in Kafka:
      { "image": "<base64‑string>", … }
    We:
      • decode the image,
      • build a multipart/form‑data POST,
      • fetch the real /infer on the agent,
      • return its JSON.
    """
    endpoint = await select_endpoint()

    # decode the base64 image back to bytes
    try:
        img_bytes = base64.b64decode(data["image"])
    except Exception as e:
        logging.error(f"Failed to decode image payload: {e}")
        raise

    # send as multipart/form‑data
    files = {
        # the field name "image" must match your FastAPI handler's parameter
        "image": ("upload.jpg", img_bytes, "application/octet-stream")
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        logging.debug(f"Forwarding inference to {endpoint}")
        resp = await client.post(endpoint, files=files)
        resp.raise_for_status()
        result = resp.json()
        logging.debug(f"Agent responded: {result}")
        return result

async def inference_loop():
    consumer = AIOKafkaConsumer(
        REQ_TOPIC,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id="workers",
        enable_auto_commit=False,
        auto_offset_reset="earliest"
    )
    producer = AIOKafkaProducer(bootstrap_servers=BOOTSTRAP_SERVERS)

    await consumer.start()
    await producer.start()
    logging.info("Worker started, awaiting Kafka messages…")

    try:
        async for msg in consumer:
            req = json.loads(msg.value.decode())
            cid = req.get("correlation_id")
            payload = req.get("payload", {})
            logging.info(f"Processing request {cid}")

            try:
                result = await run_inference(payload)
            except Exception as e:
                logging.error(f"Inference error for {cid}: {e}")
                result = {"error": str(e)}

            response_msg = {"correlation_id": cid, "result": result}
            await producer.send_and_wait(RES_TOPIC, json.dumps(response_msg).encode())
            logging.info(f"Published response for {cid}")

            await consumer.commit()
    finally:
        await consumer.stop()
        await producer.stop()

if __name__ == "__main__":
    asyncio.run(inference_loop())
