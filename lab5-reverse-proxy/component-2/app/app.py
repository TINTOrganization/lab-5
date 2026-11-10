import os
import socket

from flask import Flask, jsonify

SERVICE_NAME = os.environ.get("SERVICE_NAME", "orders")
PORT = int(os.environ.get("PORT", "5000"))

app = Flask(__name__)
# Keep the contract key order (service, instance, data) instead of sorting.
app.json.sort_keys = False


def _payload():
    # `instance` = container hostname, so each replica is identifiable and
    # load balancing across the 3 replicas is visible to the client.
    return {
        "service": SERVICE_NAME,
        "instance": socket.gethostname(),
        "data": [],
    }


@app.route("/")
@app.route("/orders")
@app.route("/orders/")
def orders():
    return jsonify(_payload())


@app.route("/health")
def health():
    # Internal liveness endpoint for Docker healthchecks only.
    # Not part of the contract: the proxy answers 404 for /health.
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
