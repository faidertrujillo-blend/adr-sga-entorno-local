#!/usr/bin/env bash
# Levanta data-access-api contra Floci (no contra AWS dev).
#
# Uso: scripts/api.sh          (primer plano, sin recarga)
#      scripts/api.sh --fondo  (segundo plano; log en logs/data-api.log)
#
# Toma KEYCLOAK_* del .env del repo (los JWT se validan contra el Keycloak real).
# Las variables de aquí deben ganar sobre ese .env (AWS va a Floci, auditores
# salen del directorio sembrado, sin chaos testing). Pero app/main.py hace
# load_dotenv(override=True), que las pisaría; por eso se lanza con run_api.py,
# que anula esa carga sin tocar el repo. Consecuencia: no hay --reload.
set -euo pipefail
source "$(dirname "$0")/env.sh"
exigir_floci
exigir_venv

export AUDITORES_FUENTE=directorio
export ERROR_RATE=0

# Si el puerto ya está tomado, el /health respondería otro proceso (quizá una
# API apuntando a dev). Mejor fallar claro.
if ss -ltn | grep -q "127.0.0.1:$DATA_API_PUERTO \|:$DATA_API_PUERTO "; then
  echo "ABORTADO: el puerto $DATA_API_PUERTO ya está en uso. Usa DATA_API_PUERTO=otro." >&2
  exit 1
fi

cd "$DATA_API"
if [ "${1:-}" = "--fondo" ]; then
  mkdir -p "$RAIZ/logs"
  nohup "$PY" "$RAIZ/scripts/run_api.py" "$DATA_API_PUERTO" \
    > "$RAIZ/logs/data-api.log" 2>&1 &
  echo $! > "$RAIZ/logs/data-api.pid"
  for _ in $(seq 1 30); do
    curl -s -m 2 "http://127.0.0.1:$DATA_API_PUERTO/health" >/dev/null && break
    sleep 1
  done
  curl -s "http://127.0.0.1:$DATA_API_PUERTO/health"; echo
  echo "data-access-api en http://127.0.0.1:$DATA_API_PUERTO (PID $(cat "$RAIZ/logs/data-api.pid"))"
else
  exec "$PY" "$RAIZ/scripts/run_api.py" "$DATA_API_PUERTO"
fi
