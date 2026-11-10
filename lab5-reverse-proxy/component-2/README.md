# component-2 — Orders + Load balancing (Role B)

Flask orders service (3 replicas) and the load-balancing / failover pieces of the reverse-proxy lab.

> **Status.** Tested with Docker behind A's `nginx.conf` (PR #3), 3 replicas:
> `nginx -t` passes, item 6 rotates over the 3 hostnames and item 7 returns
> only `200` with one replica stopped.

## What this folder contains

| File | Purpose |
|---|---|
| `app/app.py` | Flask orders service. Returns the contract JSON on `/`, `/orders`, `/orders/`; `GET /health` returns 200 (internal only). |
| `requirements.txt` | `flask==3.0.3`, `gunicorn==22.0.0`. |
| `Dockerfile` | `python:3.11-slim`, gunicorn on `0.0.0.0:5000` (2 workers, gthread). |
| `nginx-fragment.conf` | nginx snippets to hand off to **A** (`upstream orders`, failover, `location /orders/`). |

## Contract

- Service name: `orders`, compose service `component-2`, internal port `5000`, **3 replicas**, **no published ports**.
- Env vars: `SERVICE_NAME=orders`, `PORT=5000`.
- Response JSON:

```json
{"service": "orders", "instance": "<container hostname>", "data": []}
```

- `GET /health` → `200 {"status": "ok"}`. Only for Docker healthchecks inside the internal network; it is **not** part of the contract and the proxy answers 404 for `/health` (checklist 4, owned by A).

## Handoffs

- **To A (`component-1/nginx.conf`):** integrate `nginx-fragment.conf`
  - `upstream orders { zone orders 64k; server component-2:5000 max_fails=1 fail_timeout=10s; keepalive 16; }` in `http {}`. The `zone` makes all nginx workers share one round-robin counter.
  - `location /orders/` (round-robin + `proxy_next_upstream` failover, `proxy_connect_timeout 2s`, keep-alive, forwarding headers) in the HTTPS `server {}`.
- **To D (compose files):**
  - `docker-compose.yml`: service `component-2` with `build: ./component-2`, the env vars above, `deploy.replicas: 3`, network `internal`, **no `ports:`**.
  - Do **not** use `container_name:` on this service: a fixed name cannot be scaled to 3 replicas.
  - `docker-compose.insecure.yml`: do not publish the same fixed host port for the 3 replicas (`"5000:5000"` fails on the second one). Use an ephemeral host port (`"5000"`) or a range (`"5001-5003:5000"`).
  - Optional healthcheck (the slim image has no `curl`):
    `test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"]`

## Load balancing checklist covered (items 6–7)

Run from the host, with the full stack up (`docker compose up --build`) and nginx on `8443`.

### 6 — 20 requests rotate across the 3 hostnames

```bash
for i in $(seq 1 20); do
  curl -sk https://localhost:8443/orders/
  echo
done
```

Expected: the `instance` field takes 3 different values. Count them with:

```bash
for i in $(seq 1 20); do curl -sk https://localhost:8443/orders/; echo; done \
  | grep -o '"instance":"[^"]*"' | sort | uniq -c
```

### 7 — stop one replica, client sees no errors

```bash
docker compose ps component-2          # get the 3 replica container names
docker stop <one-replica-name>         # e.g. lab5-reverse-proxy-component-2-2

for i in $(seq 1 20); do
  curl -sk -o /dev/null -w "%{http_code}\n" https://localhost:8443/orders/
done | sort | uniq -c
```

Expected: only `200` (no `502`/`504`); `instance` now rotates over the 2 remaining replicas.
Restore with `docker start <one-replica-name>`.

## Known limitations

- nginx resolves `component-2` only at startup. If nginx starts before the replicas, it may fail with `host not found in upstream`; and if a replica comes back with a different IP, nginx will not see it until it is reloaded (`docker exec component-1 nginx -s reload`).
- `proxy_next_upstream` only retries idempotent requests (GET, HEAD...). The service only exposes GET, so this is enough for the lab.
- Failover is not free: after a replica stops, the first request sent to it waits `proxy_connect_timeout` (2 s) before nginx retries on the next replica. The client gets `200`, just slower. Then `max_fails=1 fail_timeout=10s` takes that replica out of rotation, so the delay repeats at most once every 10 s.

## Local smoke test (standalone, no proxy)

```bash
docker build -t orders ./component-2
docker run --rm -e SERVICE_NAME=orders -e PORT=5000 -p 5000:5000 orders
curl -s http://localhost:5000/orders/
# -> {"service":"orders","instance":"<hostname>","data":[]}
```
