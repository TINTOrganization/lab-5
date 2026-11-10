# component-3 — catalog (acceleration)

FastAPI catalog service. nginx caches and compresses its responses.

## What this folder contains

| File | Purpose |
|---|---|
| `app/app.py` | FastAPI catalog service. Returns the JSON below on `/`, `/catalog`, `/catalog/`. |
| `requirements.txt` | `fastapi==0.115.0`, `uvicorn[standard]==0.30.6`. |
| `Dockerfile` | `python:3.11-slim` + uvicorn on `0.0.0.0:8000`. |

The nginx side (cache, gzip, keep-alive, `location /catalog/`) is in
`component-1/nginx.conf`. The static files for `/static/` are in
`component-1/static/`, because nginx serves them without this service.

## Contract

- Compose service `component-3`, internal port `8000`, 1 instance, **no published ports**.
- Env vars: `SERVICE_NAME=catalog`, `PORT=8000`.
- Response JSON (`data` holds 30 products, so the body is ~6 KB and nginx
  actually gzips it):

```json
{"service": "catalog", "instance": "<container hostname>", "data": [ /* catalog items */ ]}
```

- Each request sleeps 0.5 s to simulate backend work, so a cache HIT is
  visibly faster than a MISS.

## Acceleration checks

Run from `reverse-proxy/`, with the stack up.

```bash
CA=component-1/certs/server.crt

# Cache: first MISS, second HIT and faster. Use GET (-D -), not curl -I:
# the cache key includes the method.
for i in 1 2; do
  curl -s --cacert $CA -o /dev/null -D - -w 'time=%{time_total}s\n' \
    'https://localhost:8443/catalog/?demo=cache' | grep -Ei 'x-cache-status|time='
done

# Gzip: compressed body is much smaller.
curl -s --cacert $CA -o /dev/null -w '%{size_download}\n' https://localhost:8443/catalog/
curl -s --cacert $CA -o /dev/null -w '%{size_download}\n' -H 'Accept-Encoding: gzip' https://localhost:8443/catalog/

# Static: served by nginx, the access log shows upstream=-.
curl -s --cacert $CA https://localhost:8443/static/index.html | head -n 3
docker compose logs component-1 | grep 'GET /static/'
```

## Local smoke test (standalone, no proxy)

```bash
docker build -t catalog ./component-3
docker run --rm -e SERVICE_NAME=catalog -e PORT=8000 -p 8000:8000 catalog
curl -s http://localhost:8000/catalog/
# -> {"service":"catalog","instance":"<hostname>","data":[ ...catalog items... ]}
```
