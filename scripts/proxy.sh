#!/usr/bin/env bash
# Proxy local para el front: completa lo que el BFF aún no tiene llamando a la
# data-access-api local. Ver proxy/proxy.py.
#
# Uso: scripts/proxy.sh          (primer plano)
#      scripts/proxy.sh --fondo  (segundo plano; log en logs/proxy.log)
#
# Variables: PROXY_PUERTO (8010), PROXY_BFF_URL, PROXY_DATA_API_URL,
#            PROXY_ACTUAR_COMO (correo de auditor para firmar acciones).
set -euo pipefail
source "$(dirname "$0")/env.sh"
exigir_venv
PROXY_PUERTO="${PROXY_PUERTO:-8010}"
export PROXY_BFF_URL="${PROXY_BFF_URL:-http://127.0.0.1:${BFF_PUERTO:-8002}}"
export PROXY_DATA_API_URL="${PROXY_DATA_API_URL:-http://127.0.0.1:$DATA_API_PUERTO}"

if ss -ltn | grep -q ":$PROXY_PUERTO "; then
  echo "ABORTADO: el puerto $PROXY_PUERTO ya está en uso." >&2
  exit 1
fi

cd "$RAIZ/proxy"
ARGS=(-m uvicorn proxy:app --port "$PROXY_PUERTO")
echo "Proxy en :$PROXY_PUERTO -> BFF $PROXY_BFF_URL | data-api $PROXY_DATA_API_URL${PROXY_ACTUAR_COMO:+ | actúa como $PROXY_ACTUAR_COMO}"
if [ "${1:-}" = "--fondo" ]; then
  mkdir -p "$RAIZ/logs"
  nohup "$PY" "${ARGS[@]}" > "$RAIZ/logs/proxy.log" 2>&1 &
  echo $! > "$RAIZ/logs/proxy.pid"
  sleep 2
  kill -0 "$(cat "$RAIZ/logs/proxy.pid")" 2>/dev/null || { tail -5 "$RAIZ/logs/proxy.log"; exit 1; }
else
  exec "$PY" "${ARGS[@]}" --reload
fi
