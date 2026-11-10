#!/bin/sh
# Generates the self-signed certificate nginx uses for TLS termination.
# Lab use only: valid for "localhost" and 127.0.0.1, 365 days.
#
#   ./gen-certs.sh           create certs/server.crt and certs/server.key
#   ./gen-certs.sh --force   replace them if they already exist
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)/certs"
mkdir -p "$DIR"

if [ -f "$DIR/server.crt" ] && [ -f "$DIR/server.key" ] && [ "${1:-}" != "--force" ]; then
    echo "certs already exist in $DIR (use --force to replace them)"
    exit 0
fi

openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
    -keyout "$DIR/server.key" \
    -out "$DIR/server.crt" \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

chmod 600 "$DIR/server.key"
echo "created $DIR/server.crt and $DIR/server.key"
