#!/usr/bin/env bash
# Vuelve al estado inicial: borra todo lo de Floci y recarga los escenarios.
# Útil después de probar acciones (levantar, ratificar, siguiente paso...).
#
# Uso: scripts/reset.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"
"$RAIZ/scripts/seed.sh"
