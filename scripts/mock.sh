#!/usr/bin/env bash
# Reinicia el proxy con respuestas simuladas (mocks). Ver proxy/mocks_engine.py.
#
# Uso: scripts/mock.sh              solo-mock: no llama a BFF, API ni Floci
#      scripts/mock.sh mock-primero  usa el mock si existe; si no, el backend real
#      scripts/mock.sh normal        vuelve al funcionamiento normal (ignora mocks)
#
# En `solo-mock` el front funciona con SOLO el proxy encendido (y el login de
# Keycloak, que no pasa por aquí). Lo que no tenga mock responde 501.
set -euo pipefail
source "$(dirname "$0")/env.sh"
MODO="${1:-solo-mock}"

PID_FILE="$RAIZ/logs/proxy.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  kill "$(cat "$PID_FILE")"; sleep 1
fi
PROXY_MODO="$MODO" "$RAIZ/scripts/proxy.sh" --fondo
echo "Estado: $(curl -s "http://127.0.0.1:${PROXY_PUERTO:-8010}/_proxy/estado")"
