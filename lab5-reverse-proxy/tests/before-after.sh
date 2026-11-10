#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CA="component-1/certs/server.crt"
SECURE_COMPOSE=(docker compose -f docker-compose.yml)
INSECURE_COMPOSE=(docker compose -f docker-compose.insecure.yml)
TMP=""

cleanup() {
  "${SECURE_COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  "${INSECURE_COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  if [ -n "$TMP" ]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT
cleanup
TMP="$(mktemp -d)"

echo "== BEFORE: backends published directly =="
"${INSECURE_COMPOSE[@]}" up --build -d
# Retry while the backends start; assign first so a failure stops the script.
orders_direct="$(curl -fsS --retry 15 --retry-delay 1 --retry-all-errors http://localhost:5000/orders/)"
catalog_direct="$(curl -fsS --retry 15 --retry-delay 1 --retry-all-errors http://localhost:8000/catalog/)"
printf 'orders direct:  %s\n' "$orders_direct"
printf 'catalog direct: %s\n' "$catalog_direct" | cut -c1-120
"${INSECURE_COMPOSE[@]}" down --remove-orphans

echo
echo "== AFTER: only nginx is published =="
MSYS_NO_PATHCONV=1 ./component-1/gen-certs.sh
"${SECURE_COMPOSE[@]}" up --build -d --scale component-2=3

echo
echo "Backend host ports after secure topology:"
if curl -sS --connect-timeout 2 http://localhost:5000/orders/ >/dev/null; then
  echo "ERROR: orders is reachable at localhost:5000" >&2
  exit 1
fi
echo "localhost:5000 is not reachable"

published="$("${SECURE_COMPOSE[@]}" ps --format '{{.Service}} {{.Ports}}')"
printf '%s\n' "$published"
if ! printf '%s\n' "$published" | awk '
  ($1 == "component-2" || $1 == "component-3") && NF > 1 { bad=1 }
  END { exit bad }
'; then
  echo "ERROR: a backend is publishing a host port" >&2
  exit 1
fi

echo
echo "HTTPS:"
curl -fsS --cacert "$CA" https://localhost:8443/orders/
echo

echo
echo "HTTP redirect:"
curl -fsSI http://localhost:8080/orders/ | sed -n '1,5p'

echo
echo "Unknown routes:"
for path in /health /orders/health /catalog/docs /unknown; do
  code="$(curl -sS --cacert "$CA" -o /dev/null -w '%{http_code}' "https://localhost:8443${path}")"
  printf '%-22s %s\n' "$path" "$code"
  test "$code" = 404
done

echo
echo "Security headers and banner:"
curl -fsSI --cacert "$CA" https://localhost:8443/orders/ \
  | grep -Ei '^(HTTP/|server:|strict-transport|x-content-type|x-frame|referrer-policy|content-security)'

echo
echo "Forwarded-header evidence:"
curl -fsS --cacert "$CA" -H 'X-Forwarded-For: 1.2.3.4' \
  'https://localhost:8443/catalog/?xff=spoof' >/dev/null
"${SECURE_COMPOSE[@]}" logs --no-color component-1 \
  | grep -E 'xff_in="1\.2\.3\.4"'
MSYS_NO_PATHCONV=1 "${SECURE_COMPOSE[@]}" exec -T component-1 \
  grep -F 'X-Forwarded-For' \
  /etc/nginx/snippets/proxy-headers.conf
if "${SECURE_COMPOSE[@]}" logs --no-color component-3 \
  | grep -q '1\.2\.3\.4'; then
  echo "ERROR: the spoofed address reached catalog" >&2
  exit 1
fi

echo
echo "Orders rotation (20 requests):"
for _ in $(seq 1 20); do
  curl -fsS --cacert "$CA" https://localhost:8443/orders/
  echo
done | grep -o '"instance":"[^"]*"' | sort | uniq -c

echo
echo "Orders failover:"
stopped_replica="$("${SECURE_COMPOSE[@]}" ps -q component-2 | head -n 1)"
test -n "$stopped_replica"
docker stop "$stopped_replica" >/dev/null
for _ in $(seq 1 10); do
  code="$(curl -sS --cacert "$CA" -o /dev/null -w '%{http_code}' \
    https://localhost:8443/orders/)"
  test "$code" = 200
done
docker start "$stopped_replica" >/dev/null
echo "10/10 requests returned 200 while one orders replica was stopped"

echo
echo "nginx configuration:"
"${SECURE_COMPOSE[@]}" exec -T component-1 nginx -t

echo
echo "Catalog cache:"
curl -fsS --cacert "$CA" -D "$TMP/catalog-headers-1" -o /dev/null \
  -w 'first=%{time_total}s\n' 'https://localhost:8443/catalog/?cache=test'
curl -fsS --cacert "$CA" -D "$TMP/catalog-headers-2" -o /dev/null \
  -w 'second=%{time_total}s\n' 'https://localhost:8443/catalog/?cache=test'
grep -i '^X-Cache-Status:' "$TMP/catalog-headers-1" "$TMP/catalog-headers-2"

echo
echo "Gzip:"
plain_size="$(curl -fsS --cacert "$CA" -o /dev/null -w '%{size_download}' \
  'https://localhost:8443/catalog/?gzip=test')"
gzip_size="$(curl -fsS --cacert "$CA" -H 'Accept-Encoding: gzip' \
  -D "$TMP/catalog-gzip-headers" -o /dev/null -w '%{size_download}' \
  'https://localhost:8443/catalog/?gzip=test')"
grep -Ei '^(Content-Encoding|Vary):' "$TMP/catalog-gzip-headers"
printf 'without gzip: %s bytes\nwith gzip:    %s bytes\n' "$plain_size" "$gzip_size"
test "$gzip_size" -lt "$plain_size"

echo
echo "Static file:"
curl -fsS --cacert "$CA" https://localhost:8443/static/index.html | head -n 3
# upstream=- in the access log: nginx answered by itself, no backend involved.
"${SECURE_COMPOSE[@]}" logs --no-color component-1 \
  | grep -E '"GET /static/index\.html HTTP/[0-9.]+" 200 [0-9]+ upstream=- '
