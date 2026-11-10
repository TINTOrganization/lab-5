from fastapi import FastAPI, WebSocket, WebSocketDisconnect

app = FastAPI()
clients: set[WebSocket] = set()

async def broadcast(text: str):
    for ws in list(clients):
        try:
            await ws.send_text(text)
        except Exception:  # el cliente ya se desconectó
            clients.discard(ws)

@app.websocket("/ws")
async def chat(ws: WebSocket, user: str = "anon"):
    await ws.accept()
    clients.add(ws)
    # ERROR A PROPÓSITO: el nombre llega en la URL y se reenvía sin limpiarlo
    await broadcast(f"<b>{user}</b> entró al chat")
    try:
        while True:
            await broadcast(f"<b>{user}</b>: {await ws.receive_text()}")
    except WebSocketDisconnect:
        clients.discard(ws)
        await broadcast(f"<b>{user}</b> salió")
