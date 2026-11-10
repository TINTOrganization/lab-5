import sqlite3
from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # el frontend está en otro puerto (4321)

def db():
    return sqlite3.connect("chat.db")

with db() as c:
    c.execute("CREATE TABLE IF NOT EXISTS messages (user TEXT, text TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS users (name TEXT, secret TEXT)")
    if not c.execute("SELECT 1 FROM users").fetchone():
        c.execute("INSERT INTO users VALUES ('admin', 'clave-super-secreta')")
        c.execute("INSERT INTO messages VALUES ('admin', 'Bienvenidos al chat')")

@app.get("/messages")
def search():
    q = request.args.get("q", "")
    # ERROR A PROPÓSITO: el texto del usuario se pega dentro del SQL
    sql = f"SELECT user, text FROM messages WHERE text LIKE '%{q}%'"
    rows = db().execute(sql).fetchall()
    return jsonify([{"user": u, "text": t} for u, t in rows])

@app.post("/messages")
def create():
    data = request.get_json(force=True)
    with db() as c:  # ERROR A PROPÓSITO: se guarda el texto sin limpiarlo
        c.execute("INSERT INTO messages VALUES (?, ?)", (data.get("user", "anon"), data["text"]))
    return jsonify({"status": "created"}), 201

app.run(host="0.0.0.0", port=5000)
