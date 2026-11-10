import os
import socket
import time

from fastapi import FastAPI
from fastapi.responses import JSONResponse

SERVICE_NAME = os.environ.get("SERVICE_NAME", "catalog")
PORT = int(os.environ.get("PORT", "8000"))

app = FastAPI(title=f"{SERVICE_NAME} service")

# A fixed catalog of products. It is intentionally large enough that the JSON
# response exceeds ~1 KB, so nginx actually compresses it (gzip_min_length is
# 256) — this is what makes checklist item 10 (gzip) observable.
_CATEGORIES = ["peripherals", "displays", "storage", "networking", "audio"]
_PRODUCTS = [
    {
        "id": i,
        "name": f"product-{i:03d}",
        "category": _CATEGORIES[i % len(_CATEGORIES)],
        "price": round(9.99 + i * 3.5, 2),
        "in_stock": i % 4 != 0,
        "description": (
            f"Catalog item number {i}. Part of the {_CATEGORIES[i % len(_CATEGORIES)]} "
            "line, used in the reverse-proxy acceleration demo."
        ),
    }
    for i in range(1, 31)
]


def _payload():
    # `instance` = container hostname, so balancing / identity is visible.
    # `data` carries the catalog so the body is big enough to be gzip'd.
    return {
        "service": SERVICE_NAME,
        "instance": socket.gethostname(),
        "data": _PRODUCTS,
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
