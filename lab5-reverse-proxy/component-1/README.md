# component-1 — nginx reverse proxy (Role A)

Stock nginx placed in front of orders (component-2) and catalog (component-3).
It is the only component that publishes ports: `8443` (HTTPS) and `8080`
(redirects to HTTPS).

> **Status.** Tested **outside Docker**: this exact `nginx.conf` and both
> snippets ran on nginx 1.24 against B's Flask app (3 processes) and C's
> FastAPI app. Checklist items 3–11 passed there and `nginx -t` gave no
> warnings. **Not run yet:** the Docker image build and the compose stack
> (items 1–2 belong to D), so the commands below still need one real run to
> collect the output for the guide.

## What this folder contains

| File | Purpose |
|---|---|
| `nginx.conf` | Full nginx config: TLS, 301 redirect, routes, 404 for everything else. Integrates B's and C's fragments. |
| `snippets/security-headers.conf` | Response headers sent to the client (HSTS, `nosniff`, `X-Frame-Options`, `Referrer-Policy`, CSP). |
| `snippets/proxy-headers.conf` | Request headers sent to the backends (`X-Forwarded-For` overwritten, keep-alive). |
| `gen-certs.sh` | Creates the self-signed certificate in `certs/` (`localhost`, `127.0.0.1`). |
| `certs/` | Generated; `.key` and `.crt` are git-ignored. |
| `static/` | Static files owned by C, served by nginx at `/static/`. |
| `Dockerfile` | `nginx:1.28-alpine` + the files above. |

## Routes

| Route | Result |
|---|---|
| `http://…:8080/*` | `301` to `https://…:8443/*` |
| `/orders/` | orders, balanced across 3 replicas, with failover (B) |
| `/catalog/` | catalog, cached, with `X-Cache-Status` (C) |
| `/static/` | file served by nginx (C) |
| `/health`, `/orders/health`, `/catalog/docs`, `/catalog/redoc`, `/catalog/openapi.json` | `404` |
| anything else | `404` |

## What changed when integrating the fragments

- **Forwarding headers** (B and C): the per-location `proxy_set_header` lines
  were replaced by `include snippets/proxy-headers.conf`. Same values
  (`X-Forwarded-For $remote_addr`), plus the client's `Forwarded` header is
  dropped.
- **Security headers in `/catalog/`** (C): the placeholder `add_header` lines
  were replaced by `include snippets/security-headers.conf`, so the location
  and the server always send the same set.
- **Internal endpoints** (new): `/orders/` and `/catalog/` strip their prefix,
  so `/orders/health` reached Flask's `/health` (200) and `/catalog/docs`,
  `/catalog/redoc`, `/catalog/openapi.json` reached FastAPI's default pages.
  One regex location now answers `404` for them.

## Handoffs

- **To D (`docker-compose.yml`):**

  ```yaml
  services:
    component-1:
      build: ./component-1
      container_name: component-1
      ports:
        - "8443:8443"
        - "8080:8080"
      networks:
        - edge
        - internal
      depends_on:
        - component-2
        - component-3

  networks:
    edge: {}
    internal:
      internal: true
  ```

  - nginx needs a second, non-internal network (`edge`): a container that is
    only on an `internal: true` network cannot publish ports to the host.
  - The published ports must be `8443` and `8080` on both sides: the redirect
    and nginx's own redirects use port `8443`.
  - `depends_on` is required: nginx resolves `component-2` and `component-3`
    when it starts and exits with `host not found in upstream` otherwise.
  - Run `./component-1/gen-certs.sh` once before `docker compose up --build`
    (the Dockerfile copies `certs/server.crt` and `certs/server.key`).
  - For checklist 5, add `FORWARDED_ALLOW_IPS: "*"` to the environment of
    `component-3`. uvicorn then logs the client address it reads from
    `X-Forwarded-For`, which is the evidence that the spoofed value was
    replaced. It is safe because only nginx can reach that container.
- **To C (optional):** `FastAPI(docs_url=None, redoc_url=None, openapi_url=None)`
  would also remove the default pages at the source. The proxy already hides them.

## Security checklist covered (items 3, 4, 5, 8)

Run from `lab5-reverse-proxy/`, with the stack up. `--cacert` makes curl
verify the certificate instead of skipping the check with `-k`.

```bash
CA=component-1/certs/server.crt
```

### 3 — HTTPS works, HTTP returns 301, security headers, no version

```bash
curl -s  --cacert $CA https://localhost:8443/orders/
curl -sI http://localhost:8080/orders/
curl -sI --cacert $CA https://localhost:8443/orders/
```

Expected: the orders JSON; `301` with `Location: https://localhost:8443/orders/`;
`Server: nginx` (no version, no Werkzeug/uvicorn) and the five headers of
`snippets/security-headers.conf`.

### 4 — `/health` and unknown paths return 404

```bash
for p in /health /orders/health /catalog/docs /catalog/openapi.json / /admin; do
  printf '%-24s %s\n' "$p" "$(curl -s --cacert $CA -o /dev/null -w '%{http_code}' https://localhost:8443$p)"
done
```

Expected: `404` on every line.

### 5 — a spoofed `X-Forwarded-For` is overwritten

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

### 8 — `nginx -t` passes

```bash
docker exec component-1 nginx -t
```

Expected: `syntax is ok` and `test is successful`, with no warnings.

## Known limitations

- The certificate is self-signed: browsers warn, and curl needs `--cacert` or `-k`.
- `Server: nginx` is still sent; stock nginx can hide the version but not the name.
- `curl -I` on `/catalog/` works only through the proxy (nginx turns the HEAD
  into a GET for the cache); the FastAPI app itself answers 405 to HEAD.
