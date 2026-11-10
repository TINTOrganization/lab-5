# Lab 5 (Reverse Proxy), SwArch 2026-II

Shared context for everyone on the team working on Lab 5 (with or without Claude). 

## Goal
Implement the **Reverse Proxy** security pattern using **nginx as a ready-made component**: configure it, run it in Docker, and place it between other components to show it working. Then write a technical guide so other teams can replicate it.

- Deadline: Monday 2026-11-09, before 23:59, through MiCampus (one member submits).
- Deliverable: `l5_2a.md` exported to `l5_2a.pdf`
- The PDF must contain: full names, an architectural view where the pattern is evident, and the guide (pattern description and purpose, quality scenario, implementation steps, config/code snippets, results, recommendations).

## Scope
Only these three areas:
- **Confidentiality/security:** backends unreachable from outside, TLS termination, server banners and internal endpoints hidden, forwarding headers not spoofable.
- **Load balancing:** one entry point spreading requests over several instances, with failover when one stops.
- **Acceleration:** response caching (`proxy_cache`, with an `X-Cache-Status` header), gzip compression, static files served by the proxy, and keep-alive connections to the backends.

Out of scope: rate limiting, connection limits, custom-built proxy code. The services are original code; the proxy is stock nginx.

## Repo state
- `example/` is a finished example from a teammate (Spanish guide, one Flask API + Mongo, nginx with rate limiting, HTTP only). Keep it as a reference; do not edit it.
- `lab5-reverse-proxy/` is the real work. Merged into `main` (2026-11-09):
  - PR #1 `component-3/`: catalog (FastAPI), cache/gzip fragment; static files in `component-1/static/`.
  - PR #2 `component-2/`: orders (Flask + gunicorn gthread), 3 replicas, failover.
  - PR #3 `component-1/`: nginx with TLS, security headers in `snippets/`, B and C fragments integrated.
  - Tested together with Docker (temporary compose): checklist items 3 to 11 pass.
- Still missing (role D): `docker-compose.yml`, `docker-compose.insecure.yml`, `tests/before-after.sh`, `img/`, `l5_2a.md`.
- `upstream orders` has `zone orders 64k;`: without it each nginx worker keeps its own round-robin counter and item 6 comes out uneven (15/7/8 instead of 10/10/10). Keep it.
- Gotchas for the guide:
  - Run `component-1/gen-certs.sh` before `docker compose up --build`, or the nginx build fails.
  - Test item 2 through published ports (`curl localhost:5000`), not container IPs: on Linux the Docker host can reach containers on `internal: true` networks.
  - Test item 9 with GET (`curl -s -o /dev/null -D -`), not `curl -I`: the cache key includes the method.
  - Failover: the first request to a stopped replica waits `proxy_connect_timeout` (2 s), but returns 200.
- The GitHub repo moved to `TINTOrganization/lab-5`; the old `CamiloLM/lab-5` remote no longer works.
- `[SwArch_2026ii] - Laboratory 5.pdf` is the assignment.

## Layout
```
lab5-reverse-proxy/
  docker-compose.yml            # secure topology: only nginx publishes ports
  docker-compose.insecure.yml   # baseline "before": backends published directly
  component-1/                  # nginx (Dockerfile, nginx.conf, gen-certs.sh, certs/)
  component-2/                  # orders service, Flask, 3 replicas, internal only
  component-3/                  # catalog service, FastAPI, 1 instance, internal only
  tests/before-after.sh         # curl evidence
  img/                          # architectural view PNGs
  l5_2a.md                      # the guide
```
Static files for the acceleration demo are served by nginx from `component-1/`.
Topology: client → nginx (8443 TLS, 8080 redirect) → services on an `internal: true` network. Each service response includes its instance hostname so balancing is visible.

## Conventions (same as Labs 1, 2, 4)
- Python + Docker; `component-N` folders; lowercase names.
- `docker-compose.yml` without a `version:` key.
- Config through environment variables; trivial passwords (`123`) only if a database is ever added.
- Numbered sections in the guide, with commands and code inline.
- Manual testing with curl; no automated test framework required.

## Verification checklist (collect output for the "results" section)
1. `docker compose up --build`; `docker ps` shows only nginx publishing ports.
2. Backends not reachable directly (works in the insecure baseline).
3. HTTPS works; HTTP returns 301; `curl -I` shows security headers and no nginx/framework version.
4. `/health` and unknown paths return 404 via the proxy.
5. A spoofed `X-Forwarded-For` is overwritten.
6. 20 requests to orders rotate across the 3 instance hostnames.
7. Stopping one orders replica causes no client-visible errors.
8. `docker exec component-1 nginx -t` passes.
9. The second identical GET shows `X-Cache-Status: HIT` and is faster than the first (`MISS`).
10. `curl -H "Accept-Encoding: gzip"` returns a smaller, compressed response than without it.
11. A static file is served by nginx without the backend receiving the request.

## Working agreements
- Keep the guide reproducible: every step and snippet in it must match the files in the repo.
- Architectural view: a C&C view plus a deployment view, exported as PNG so it survives the PDF export.
- Before editing a shared file (`nginx.conf`, compose files, the guide), tell the team to avoid conflicting edits.
