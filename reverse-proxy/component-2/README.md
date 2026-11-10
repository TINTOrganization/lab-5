# component-2 — orders (load balancing)

Flask orders service. Runs as 3 replicas behind nginx, which balances
requests across them and fails over when one stops.

## What this folder contains

| File | Purpose |
|---|---|
| `app/app.py` | Flask orders service. Returns the JSON below on `/`, `/orders`, `/orders/`; `GET /health` returns 200 (internal only). |
| `requirements.txt` | `flask==3.0.3`, `gunicorn==22.0.0`. |
| `Dockerfile` | `python:3.11-slim`, gunicorn on `0.0.0.0:5000` (2 workers, gthread). |

The nginx side (`upstream orders`, `location /orders/`) is in
`component-1/nginx.conf`.

## Contract

- Compose service `component-2`, internal port `5000`, **3 replicas**, **no published ports**.
- Env vars: `SERVICE_NAME=orders`, `PORT=5000`.
- Response JSON:

```json
{"service": "orders", "instance": "<container hostname>", "data": []}
```

- `GET /health` → `200 {"status": "ok"}`. Only for Docker healthchecks inside
  the internal network; the proxy answers 404 for it.
- No `container_name:` on this service: a fixed name cannot be scaled to 3 replicas.

## Load balancing checks

Run from the host, with the full stack up and nginx on `8443`.

### 20 requests rotate across the 3 hostnames

```bash
for i in $(seq 1 20); do curl -sk https://localhost:8443/orders/; echo; done \
  | grep -o '"instance":"[^"]*"' | sort | uniq -c
```

Expected: 3 different `instance` values, about 7 requests each.

### Stop one replica, client sees no errors

```bash
docker compose ps component-2          # get the 3 replica container names
docker stop <one-replica-name>         # e.g. reverse-proxy-component-2-2

for i in $(seq 1 20); do
  curl -sk -o /dev/null -w "%{http_code}\n" https://localhost:8443/orders/
done | sort | uniq -c
```

Expected: only `200` (no `502`/`504`); `instance` now rotates over the 2 remaining replicas.
Restore with `docker start <one-replica-name>`.

## Known limitations

- nginx resolves `component-2` only at startup. If a replica comes back with a
  different IP, nginx will not see it until it is reloaded
  (`docker exec component-1 nginx -s reload`).
- `proxy_next_upstream` only retries idempotent requests (GET, HEAD...). The
  service only exposes GET, so this is enough for the lab.
- Failover is not free: after a replica stops, the first request sent to it
  waits `proxy_connect_timeout` (2 s) before nginx retries on the next replica.
  The client gets `200`, just slower. Then `max_fails=1 fail_timeout=10s` takes
  that replica out of rotation, so the delay repeats at most once every 10 s.

## Local smoke test (standalone, no proxy)

```bash
docker build -t orders ./component-2
docker run --rm -e SERVICE_NAME=orders -e PORT=5000 -p 5000:5000 orders
curl -s http://localhost:5000/orders/
# -> {"service":"orders","instance":"<hostname>","data":[]}
```
