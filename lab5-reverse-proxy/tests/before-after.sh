#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CA="component-1/certs/server.crt"
SECURE_COMPOSE=(docker compose -f docker-compose.yml)
INSECURE_COMPOSE=(docker compose -f docker-compose.insecure.yml)

cleanup() {
  "${SECURE_COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  "${INSECURE_COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

echo "== BEFORE: backends published directly =="
"${INSECURE_COMPOSE[@]}" up --build -d --scale component-2=3
orders_port="$("${INSECURE_COMPOSE[@]}" port component-2 5000 | head -n 1 | sed -E 's/.*:([0-9]+)$/\1/')"
catalog_port="$("${INSECURE_COMPOSE[@]}" port component-3 8000 | sed -E 's/.*:([0-9]+)$/\1/')"
test -n "$orders_port"
test -n "$catalog_port"
printf 'orders direct:  %s\n' "$(curl -fsS "http://127.0.0.1:${orders_port}/orders/")"
printf 'catalog direct: %s\n' "$(curl -fsS "http://127.0.0.1:${catalog_port}/catalog/")"
"${INSECURE_COMPOSE[@]}" down --remove-orphans

echo
echo "== AFTER: only nginx is published =="
MSYS_NO_PATHCONV=1 ./component-1/gen-certs.sh
"${SECURE_COMPOSE[@]}" up --build -d --scale component-2=3

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
"${SECURE_COMPOSE[@]}" exec -T component-1 nginx -T \
  | grep -F 'proxy_set_header X-Forwarded-For $remote_addr;'
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
echo "nginx configuration:"
"${SECURE_COMPOSE[@]}" exec -T component-1 nginx -t

echo
echo "Catalog cache:"
curl -fsS --cacert "$CA" -D /tmp/catalog-headers-1 -o /tmp/catalog-body-1 \
  -w 'first=%{time_total}s\n' 'https://localhost:8443/catalog/?cache=test'
curl -fsS --cacert "$CA" -D /tmp/catalog-headers-2 -o /tmp/catalog-body-2 \
  -w 'second=%{time_total}s\n' 'https://localhost:8443/catalog/?cache=test'
grep -i '^X-Cache-Status:' /tmp/catalog-headers-1 /tmp/catalog-headers-2

echo
echo "Gzip:"
curl -fsS --cacert "$CA" -H 'Accept-Encoding: gzip' \
  -D /tmp/catalog-gzip-headers -o /tmp/catalog-body-gzip \
  'https://localhost:8443/catalog/?gzip=test'
grep -Ei '^(Content-Encoding|Content-Length|Vary):' /tmp/catalog-gzip-headers || true
wc -c /tmp/catalog-body-gzip

echo
echo "Static file:"
curl -fsS --cacert "$CA" https://localhost:8443/static/index.html | head -n 3
