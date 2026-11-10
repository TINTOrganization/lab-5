import os
import socket
import time

from fastapi import FastAPI
from fastapi.responses import JSONResponse

SERVICE_NAME = os.environ.get("SERVICE_NAME", "catalog")
PORT = int(os.environ.get("PORT", "8000"))

app = FastAPI(title=f"{SERVICE_NAME} service")


def _payload():
    # `instance` = container hostname, so balancing / identity is visible.
    return {
        "service": SERVICE_NAME,
        "instance": socket.gethostname(),
        "data": [],
    }


@app.get("/")
@app.get("/catalog")
@app.get("/catalog/")
def catalog():
    # Simulate a small amount of backend work so the cache HIT (served by
    # nginx) is measurably faster than the MISS (served by this backend).
    time.sleep(0.5)
    return JSONResponse(content=_payload())


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
