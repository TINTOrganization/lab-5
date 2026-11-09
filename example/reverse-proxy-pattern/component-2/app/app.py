import os
from flask import Flask, jsonify, request
from pymongo import MongoClient

app = Flask(__name__)

client = MongoClient(os.environ["DB_HOST"])
collection = client[os.environ["DB_NAME"]]["items"]

@app.route("/items", methods=["GET"])
def get_items():
    items = [
        {"id": str(i["_id"]), "name": i["name"], "description": i["description"]}
        for i in collection.find()
    ]
    return jsonify(items)

@app.route("/items", methods=["POST"])
def create_item():
    data = request.json
    name = data.get("name")
    description = data.get("description")

    if not name or not description:
        return jsonify({"error": "Missing name or description"}), 400

    collection.insert_one({"name": name, "description": description})
    return jsonify({"status": "Item created"}), 201

# Endpoint sensible: solo debe usarse desde la red interna
@app.route("/admin/stats", methods=["GET"])
def admin_stats():
    return jsonify({
        "total_items": collection.count_documents({}),
        "db_host": os.environ["DB_HOST"]
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
