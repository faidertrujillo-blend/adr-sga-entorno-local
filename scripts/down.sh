#!/usr/bin/env bash
# Detiene lo que lanzaron estos scripts en segundo plano (proxy, BFF, API local)
# y Floci. Los datos quedan en floci-data/ y vuelven con scripts/up.sh.
#
# Uso: scripts/down.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"

for nombre in proxy bff data-api; do
  pid_file="$RAIZ/logs/$nombre.pid"
  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    kill "$(cat "$pid_file")" && echo "$nombre detenido"
  fi
  rm -f "$pid_file"
done

cd "$RAIZ"
docker compose stop
