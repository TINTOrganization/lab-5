# component-1 — nginx reverse proxy

Stock nginx placed in front of orders (component-2) and catalog (component-3).
It is the only component that publishes ports: `8443` (HTTPS) and `8080`
(redirects to HTTPS).

## What this folder contains

| File | Purpose |
|---|---|
| `nginx.conf` | Full nginx config: TLS, 301 redirect, load balancing, cache, gzip, routes, 404 for everything else. |
| `snippets/security-headers.conf` | Response headers sent to the client (HSTS, `nosniff`, `X-Frame-Options`, `Referrer-Policy`, CSP). |
| `snippets/proxy-headers.conf` | Request headers sent to the backends (`X-Forwarded-For` overwritten, keep-alive). |
| `gen-certs.sh` | Creates the self-signed certificate in `certs/` (`localhost`, `127.0.0.1`). |
| `certs/` | Generated; `.key` and `.crt` are git-ignored. |
| `static/` | Static files served by nginx at `/static/`. |
| `Dockerfile` | `nginx:1.28-alpine` + the files above. |

## Routes

| Route | Result |
|---|---|
| `http://…:8080/*` | `301` to `https://…:8443/*` |
| `/orders/` | orders, balanced across 3 replicas, with failover |
| `/catalog/` | catalog, cached, with `X-Cache-Status` |
| `/static/` | file served by nginx |
| `/health`, `/orders/health`, `/catalog/docs`, `/catalog/redoc`, `/catalog/openapi.json` | `404` |
| anything else | `404` |

`/orders/` and `/catalog/` strip their prefix, so without the regex location
in `nginx.conf` `/orders/health` would reach Flask's `/health` and
`/catalog/docs` would reach FastAPI's default pages.

## Notes for `docker-compose.yml`

- nginx needs a second, non-internal network (`edge`): a container that is
  only on an `internal: true` network cannot publish ports to the host.
- The published ports must be `8443` and `8080` on both sides: the redirect
  uses port `8443`.
- nginx resolves `component-2` and `component-3` when it starts and exits with
  `host not found in upstream` if they are not up, hence `depends_on` with
  `condition: service_healthy`.
- Run `./component-1/gen-certs.sh` once before `docker compose up --build`
  (the Dockerfile copies `certs/server.crt` and `certs/server.key`).
- `FORWARDED_ALLOW_IPS: "*"` on `component-3` makes uvicorn log the address it
  reads from `X-Forwarded-For`, which is the evidence for check 5. It is safe
  because only nginx can reach that container.

## Security checks

Run from `reverse-proxy/`, with the stack up. `--cacert` makes curl
verify the certificate instead of skipping the check with `-k`.

```bash
CA=component-1/certs/server.crt
```

### HTTPS works, HTTP returns 301, security headers, no version

```bash
curl -s  --cacert $CA https://localhost:8443/orders/
curl -sI http://localhost:8080/orders/
curl -sI --cacert $CA https://localhost:8443/orders/
```

Expected: the orders JSON; `301` with `Location: https://localhost:8443/orders/`;
`Server: nginx` (no version, no gunicorn/uvicorn) and the five headers of
`snippets/security-headers.conf`.

### `/health` and unknown paths return 404

```bash
for p in /health /orders/health /catalog/docs /catalog/openapi.json / /admin; do
  printf '%-24s %s\n' "$p" "$(curl -s --cacert $CA -o /dev/null -w '%{http_code}' https://localhost:8443$p)"
done
```

Expected: `404` on every line.

### A spoofed `X-Forwarded-For` is overwritten

```bash
curl -s --cacert $CA -o /dev/null -H "X-Forwarded-For: 1.2.3.4" \
  "https://localhost:8443/catalog/?xff=spoof"
docker compose logs component-1 | grep xff=spoof    # what the client sent
docker compose logs component-3 | grep xff=spoof    # what the backend received
```

Expected: the nginx line shows `xff_in="1.2.3.4"`; the uvicorn line starts
with the real client address (the Docker gateway, e.g. `172.x.0.1`), not
`1.2.3.4`. The query string makes the request skip the cache so it reaches
the backend.

### `nginx -t` passes

```bash
docker exec component-1 nginx -t
```

Expected: `syntax is ok` and `test is successful`, with no warnings.

## Known limitations

- The certificate is self-signed: browsers warn, and curl needs `--cacert` or `-k`.
- `Server: nginx` is still sent; stock nginx can hide the version but not the name.
- `curl -I` on `/catalog/` works only through the proxy (nginx turns the HEAD
  into a GET for the cache); the FastAPI app itself answers 405 to HEAD.
