"""
Sample instrumented web service.

Exposes:
  GET /          -> simple JSON payload (simulates "the product")
  GET /health    -> liveness/readiness probe target
  GET /metrics   -> Prometheus scrape target
"""
import os
import random
import time

from flask import Flask, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

APP_VERSION = os.getenv("APP_VERSION", "dev")

app = Flask(__name__)

REQUEST_COUNT = Counter(
    "app_requests_total",
    "Total number of requests received",
    ["endpoint", "http_status"],
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds",
    "Request latency in seconds",
    ["endpoint"],
)


@app.route("/")
def index():
    start = time.time()
    # simulate a little bit of variable work so latency graphs look real
    time.sleep(random.uniform(0.01, 0.08))
    payload = {
        "message": "Hello from the sample app!",
        "version": APP_VERSION,
        "hostname": os.getenv("HOSTNAME", "unknown"),
    }
    REQUEST_LATENCY.labels(endpoint="/").observe(time.time() - start)
    REQUEST_COUNT.labels(endpoint="/", http_status="200").inc()
    return jsonify(payload), 200


@app.route("/health")
def health():
    REQUEST_COUNT.labels(endpoint="/health", http_status="200").inc()
    return jsonify(status="ok", version=APP_VERSION), 200


@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
