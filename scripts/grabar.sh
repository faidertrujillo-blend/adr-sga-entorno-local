#!/usr/bin/env bash
# Reinicia el proxy GRABANDO: cada GET exitoso que pase por él se guarda como
# mock en proxy/mocks/grabados/. Luego puedes usar el front sin backend con
# `scripts/mock.sh`.
#
# Uso: scripts/grabar.sh          (necesita BFF, API y Floci arriba: scripts/visual.sh)
#      scripts/grabar.sh --parar  (vuelve al modo normal, sin grabar)
#
# Solo graba si BFF y API son locales (así nunca se guardan datos de dev).
# No graba /presign, /auth ni /embed-url (URLs firmadas).
set -euo pipefail
source "$(dirname "$0")/env.sh"

PID_FILE="$RAIZ/logs/proxy.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  kill "$(cat "$PID_FILE")"; sleep 1
fi
if [ "${1:-}" = "--parar" ]; then
  "$RAIZ/scripts/proxy.sh" --fondo
else
  BFF_PUERTO="${BFF_PUERTO:-8002}" PROXY_GRABAR=1 "$RAIZ/scripts/proxy.sh" --fondo
  echo "Grabando. Navega por el front; las respuestas quedan en proxy/mocks/grabados/."
fi
echo "Estado: $(curl -s "http://127.0.0.1:${PROXY_PUERTO:-8010}/_proxy/estado")"
