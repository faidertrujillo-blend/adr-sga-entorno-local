#!/usr/bin/env bash
# Crea tablas y buckets en Floci y carga los escenarios de mockdata.
#
# Uso: scripts/seed.sh            (borra y recarga todo: estado limpio)
#      scripts/seed.sh --sin-clean (solo agrega/actualiza)
#
# --clean es seguro aquí porque env.sh obliga a usar Floci local.
set -euo pipefail
source "$(dirname "$0")/env.sh"
exigir_floci
exigir_venv

LIMPIAR="--clean"
[ "${1:-}" = "--sin-clean" ] && LIMPIAR=""

cd "$MOCKDATA"
echo "== Tablas y buckets"
"$PY" moto_setup.py --env devs
echo "== Datos (reclamaciones, ítems, glosas, catálogo, config)"
"$PY" upload_dynamo.py --env devs sga_output $LIMPIAR --no-soportes
if [ -n "${SGA_MI_CORREO:-}" ]; then
  echo "== Tu usuario ($SGA_MI_CORREO) como auditor Médico"
  "$PY" "$RAIZ/scripts/asignar_auditor.py"
else
  echo "== (Omitido) Asignar tu usuario: define SGA_MI_CORREO en config.local"
fi
echo "== Listo"
