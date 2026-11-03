#!/usr/bin/env bash
# Muestra qué está corriendo y hacia dónde apunta cada pieza.
#
# Uso: scripts/estado.sh
source "$(dirname "$0")/env.sh"

linea() { printf "%-34s %s\n" "$1" "$2"; }

if curl -s -m 2 "$AWS_ENDPOINT_URL/_localstack/health" >/dev/null; then
  linea "Floci ($AWS_ENDPOINT_URL)" "corriendo"
else
  linea "Floci ($AWS_ENDPOINT_URL)" "apagado  -> scripts/up.sh"
fi

API="http://127.0.0.1:$DATA_API_PUERTO"
if salud=$(curl -s -m 2 "$API/health"); then
  linea "data-access-api ($API)" "corriendo $salud"
else
  linea "data-access-api ($API)" "apagada  -> scripts/api.sh"
fi

for puerto in 8000 8080; do
  pid=$(ss -ltnp 2>/dev/null | grep ":$puerto " | grep -oP 'pid=\K[0-9]+' | head -1)
  [ -z "$pid" ] && { linea "Puerto $puerto" "libre"; continue; }
  destino=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -E '^(AWS_ENDPOINT_URL|RECLAMATIONS_API_URL)=' | tr '\n' ' ')
  linea "Puerto $puerto (pid $pid)" "${destino:-sin override (usa su .env)}"
done
