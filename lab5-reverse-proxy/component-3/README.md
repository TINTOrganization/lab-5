# component-3 — Catalog + Acceleration (Role C)

FastAPI catalog service and the acceleration pieces of the reverse-proxy lab.

## What this folder contains

| File | Purpose |
|---|---|
| `app/app.py` | FastAPI catalog service. Returns the contract JSON. |
| `requirements.txt` | `fastapi==0.115.0`, `uvicorn[standard]==0.30.6` (pinned). |
| `Dockerfile` | `python:3.11-slim` + uvicorn on `0.0.0.0:8000`. |
| `nginx-fragment.conf` | nginx snippets to hand off to **A** (cache, gzip, keep-alive, `/catalog/`, `/static/`). |

> Static assets live in **`component-1/static/`** (A's folder, served by nginx) — see handoffs.

## Contract

- Service name: `catalog`, internal port `8000`, 1 instance, **no published ports**.
- Env vars: `SERVICE_NAME=catalog`, `PORT=8000`.
- Response JSON (same shape as the group contract; `data` is populated with the
  catalog so the body exceeds ~1 KB and nginx actually gzips it):

```json
{"service": "catalog", "instance": "<container hostname>", "data": [ /* catalog items */ ]}
```

## Handoffs

- **To A (`component-1/`):** integrate `nginx-fragment.conf`
  - `proxy_cache_path` + gzip + `upstream catalog { ... keepalive 16; }` in `http {}`.
  - `location /catalog/` (proxied, cached, emits `X-Cache-Status`) and
    `location /static/` (served by nginx) in the HTTPS `server {}`.
  - **Security headers:** the `add_header X-Cache-Status` inside `/catalog/`
    cancels the server-level `add_header` inheritance, so A's security headers
    are re-declared inside that location (keep them in sync). See the fragment.
  - Static assets are in `component-1/static/`; COPY them into the nginx image
    (`COPY static/ /usr/share/nginx/html/static/`) or let D mount them.
- **To D (`docker-compose.yml`):**
  - Add the `component-3` service (build `./component-3`, env vars, `internal` network, no `ports`).
  - If not copied in the Dockerfile, mount the static assets into nginx:
    `./component-1/static:/usr/share/nginx/html/static:ro`.

## Acceleration checklist covered (items 9–11)

- **9 — cache:** 2nd GET to `/catalog/` returns `X-Cache-Status: HIT` and is faster than the first (`MISS`). The backend sleeps 0.5s per request, so the HIT (served from nginx cache) is visibly quicker.
- **10 — gzip:** `curl -H "Accept-Encoding: gzip"` to `/catalog/` returns a smaller, compressed body. `data` is populated so the response is >1 KB (well above `gzip_min_length 256`).
- **11 — static:** a file under `/static/` is served by nginx; the catalog backend never receives the request.

## Local smoke test (standalone, no proxy)

```bash
docker build -t catalog ./component-3
docker run --rm -e SERVICE_NAME=catalog -e PORT=8000 -p 8000:8000 catalog
curl -s http://localhost:8000/catalog/
# -> {"service":"catalog","instance":"<hostname>","data":[ ...catalog items... ]}
```
