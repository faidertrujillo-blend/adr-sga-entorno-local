#!/usr/bin/env bash
# Asigna tu auditor real (Keycloak) como Médico en las reclamaciones de Floci y
# lo agrega al directorio de auditores. Ver asignar_auditor.py.
#
# Uso: scripts/asignar_auditor.sh [--correo otro@adres.gov.co] [--nombre "Nombre"]
#                                  [--en-turno ID ...]
#
# La data-access-api guarda el directorio en caché ~5 min, así que si la lanzaste
# con `api.sh --fondo` este script la reinicia para que lo vea al instante.
set -euo pipefail
source "$(dirname "$0")/env.sh"
exigir_floci
exigir_venv

"$PY" "$RAIZ/scripts/asignar_auditor.py" "$@"

PID_FILE="$RAIZ/logs/data-api.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Reiniciando data-access-api para refrescar el directorio..."
  kill "$(cat "$PID_FILE")"
  for _ in $(seq 1 20); do ss -ltn | grep -q ":$DATA_API_PUERTO " || break; sleep 0.5; done
  "$RAIZ/scripts/api.sh" --fondo | tail -1
fi
