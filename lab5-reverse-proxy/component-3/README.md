# component-3 — Catalog + Acceleration (Role C)

FastAPI catalog service and the acceleration pieces of the reverse-proxy lab.

## What this folder contains

| File | Purpose |
|---|---|
| `app/app.py` | FastAPI catalog service. Returns the contract JSON. |
| `requirements.txt` | `fastapi`, `uvicorn[standard]`. |
| `Dockerfile` | `python:3.11-slim` + uvicorn on `0.0.0.0:8000`. |
| `static/` | Static assets served **directly by nginx** (`/static/`). |
| `nginx-fragment.conf` | nginx snippets to hand off to **A** (cache, gzip, keep-alive, `/catalog/`, `/static/`). |

## Contract

- Service name: `catalog`, internal port `8000`, 1 instance, **no published ports**.
- Env vars: `SERVICE_NAME=catalog`, `PORT=8000`.
- Response JSON:

```json
{"service": "catalog", "instance": "<container hostname>", "data": []}
```

## Handoffs

- **To A (`component-1/nginx.conf`):** integrate `nginx-fragment.conf`
  - `proxy_cache_path` + gzip + `upstream catalog { ... keepalive 16; }` in `http {}`.
  - `location /catalog/` (proxied, cached, emits `X-Cache-Status`) and
    `location /static/` (served by nginx) in the HTTPS `server {}`.
- **To D (`docker-compose.yml`):**
  - Add the `component-3` service (build `./component-3`, env vars, `internal` network, no `ports`).
  - Mount the static assets into nginx:
    `./component-3/static:/usr/share/nginx/html/static:ro`.

## Acceleration checklist covered (items 9–11)

- **9 — cache:** 2nd GET to `/catalog/` returns `X-Cache-Status: HIT` and is faster than the first (`MISS`). The backend sleeps 0.5s per request, so the HIT (served from nginx cache) is visibly quicker.
- **10 — gzip:** `curl -H "Accept-Encoding: gzip"` to `/catalog/` returns a smaller, compressed body.
- **11 — static:** a file under `/static/` is served by nginx; the catalog backend never receives the request.

## Local smoke test (standalone, no proxy)

```bash
docker build -t catalog ./component-3
docker run --rm -e SERVICE_NAME=catalog -e PORT=8000 -p 8000:8000 catalog
curl -s http://localhost:8000/catalog/
# -> {"service":"catalog","instance":"<hostname>","data":[]}
```
