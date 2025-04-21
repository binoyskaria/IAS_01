#!/usr/bin/env python3
import json
import time
import uuid
import base64
import logging

from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from aiokafka import AIOKafkaProducer, AIOKafkaConsumer

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(message)s",
)

app = FastAPI(title="Load Balancer Server (REST over Kafka)")

# Add CORS middleware to allow frontend access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Kafka settings
KAFKA_BOOTSTRAP = "localhost:9092"
REQ_TOPIC = "inference-requests"
RES_TOPIC = "inference-responses"

@app.on_event("startup")
async def startup_event():
    # Initialize Kafka producer
    app.state.producer = AIOKafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP)
    await app.state.producer.start()
    # Initialize Kafka consumer for responses
    app.state.consumer = AIOKafkaConsumer(
        RES_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id="api-response-waiter",
        enable_auto_commit=False,
        auto_offset_reset="latest"
    )
    await app.state.consumer.start()

@app.on_event("shutdown")
async def shutdown_event():
    await app.state.producer.stop()
    await app.state.consumer.stop()

@app.post("/infer")
async def infer(
    # If you have other text fields, list them here, e.g. some_text: str = Form(None)
    image: UploadFile = File(None),
):
    """
    Accepts a multipart/form-data upload. Reads the image,
    encodes to base64, wraps in the usual correlation-id message
    and publishes to Kafka.
    """
    # 1) Build payload
    payload = {}
    if image:
        raw = await image.read()
        payload["image"] = base64.b64encode(raw).decode()
    else:
        raise HTTPException(status_code=400, detail="No image file provided")

    # 2) Correlate
    correlation_id = str(uuid.uuid4())
    message = {
        "correlation_id": correlation_id,
        "payload": payload,
        "timestamp": time.time()
    }

    # 3) Publish to Kafka
    await app.state.producer.send_and_wait(REQ_TOPIC, json.dumps(message).encode())
    logging.info(f"Published request {correlation_id} to Kafka topic {REQ_TOPIC}")

    # 4) Wait for the matching response
    timeout = 10.0  # seconds
    deadline = time.time() + timeout
    async for msg in app.state.consumer:
        resp = json.loads(msg.value.decode())
        if resp.get("correlation_id") == correlation_id:
            await app.state.consumer.commit()
            logging.info(f"Received response for {correlation_id}")
            return JSONResponse(content=resp.get("result", {}))
        if time.time() > deadline:
            break

    raise HTTPException(status_code=504, detail="Inference request timed out")

if __name__ == "__main__":
    import uvicorn
    logging.info("Starting Load Balancer on port 8081")
    uvicorn.run(app, host="0.0.0.0", port=8081)
