#!/usr/bin/env bash
# Arranca Floci y, si está vacío, lo carga con los escenarios de mockdata.
#
# Uso: scripts/up.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "$RAIZ"
mkdir -p floci-data logs
docker compose up -d
for _ in $(seq 1 30); do
  curl -s -m 2 "$AWS_ENDPOINT_URL/_localstack/health" >/dev/null && break
  sleep 1
done
exigir_floci
echo "Floci listo en $AWS_ENDPOINT_URL"

# Con FLOCI_STORAGE_MODE=hybrid los datos sobreviven a reinicios: solo se
# siembra la primera vez (o tras scripts/reset.sh).
exigir_venv
if "$PY" -c 'import boto3,sys; sys.exit(0 if "adr-devs-sga-reclamaciones" in boto3.client("dynamodb").list_tables()["TableNames"] else 1)'; then
  echo "Datos ya cargados (usa scripts/seed.sh para recargar)."
else
  "$RAIZ/scripts/seed.sh"
fi
