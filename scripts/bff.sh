#!/usr/bin/env bash
# Levanta el BFF apuntando a la data-access-api local (Floci) sin editar su .env.
#
# Uso: scripts/bff.sh          (primer plano, con recarga)
#      scripts/bff.sh --fondo  (segundo plano; log en logs/bff.log)
#
# Puerto 8002 por defecto, para no chocar con tu BFF de dev en el 8000.
#
# pydantic-settings da prioridad a las variables de entorno sobre el .env, así
# que RECLAMATIONS_API_URL de aquí gana. Todo lo demás (Keycloak, Secrets
# Manager, S3 de soportes...) sigue saliendo del .env del BFF y de AWS real:
# por eso este script NO carga env.sh ni apunta AWS a Floci.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
BFF="$(cd "$RAIZ/.." && pwd)/adr-sgaReclamation-bff"
BFF_PUERTO="${BFF_PUERTO:-8002}"
DATA_API_PUERTO="${DATA_API_PUERTO:-8081}"
PERFIL_REAL="${PERFIL_REAL:-ADRES-TEST-Medicalaudit1}"

if ss -ltn | grep -q ":$BFF_PUERTO "; then
  echo "ABORTADO: el puerto $BFF_PUERTO ya está en uso. Usa BFF_PUERTO=otro." >&2
  exit 1
fi
if ! curl -s -m 2 "http://127.0.0.1:$DATA_API_PUERTO/health" >/dev/null; then
  echo "ABORTADO: la data-access-api local no responde en :$DATA_API_PUERTO. Corre scripts/api.sh --fondo." >&2
  exit 1
fi

unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AWS_PROFILE="$PERFIL_REAL"
export RECLAMATIONS_API_URL="http://localhost:$DATA_API_PUERTO"

cd "$BFF"
echo "BFF en :$BFF_PUERTO -> data-access-api local $RECLAMATIONS_API_URL"
if [ "${1:-}" = "--fondo" ]; then
  mkdir -p "$RAIZ/logs"
  nohup .venv/bin/uvicorn app.main:app --port "$BFF_PUERTO" > "$RAIZ/logs/bff.log" 2>&1 &
  echo $! > "$RAIZ/logs/bff.pid"
  for _ in $(seq 1 40); do
    curl -s -m 2 -o /dev/null "http://127.0.0.1:$BFF_PUERTO/openapi.json" && break
    sleep 1
  done
  kill -0 "$(cat "$RAIZ/logs/bff.pid")" 2>/dev/null || { tail -5 "$RAIZ/logs/bff.log"; exit 1; }
  echo "BFF listo (PID $(cat "$RAIZ/logs/bff.pid"))"
else
  exec .venv/bin/uvicorn app.main:app --reload --port "$BFF_PUERTO"
fi
