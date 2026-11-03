#!/usr/bin/env bash
# Preparación del primer día: crea el entorno de Python con las dependencias y
# deja tu configuración personal lista. Es seguro repetirlo.
#
# Uso: scripts/setup.sh
#
# No arranca nada, no escribe en AWS y no toca los repos hermanos: solo crea
# `.venv/` aquí y, si no existe, `config.local`.
set -euo pipefail
source "$(dirname "$0")/env.sh"

command -v uv >/dev/null || { echo "Falta uv: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2; exit 1; }
[ -d "$DATASYNC" ] || { echo "Falta $DATASYNC. Clona adr-sgaPipeline-datasync junto a esta carpeta." >&2; exit 1; }

chmod +x "$RAIZ"/scripts/*.sh

if [ ! -x "$PY" ]; then
  echo "== Creando Python 3.12 en .venv"
  uv venv --python 3.12 "$RAIZ/.venv"
else
  echo "== .venv ya existe"
fi

echo "== Instalando dependencias"
uv pip install --python "$PY" \
  -r "$DATA_API/requirements.txt" \
  -r "$MOCKDATA/requirements.txt" \
  --quiet
"$PY" -c "import boto3, fastapi, httpx, uvicorn; print('librerías OK')"

if [ ! -f "$RAIZ/config.local" ]; then
  cp "$RAIZ/config.local.example" "$RAIZ/config.local"
  echo "== Creé config.local: ábrelo y pon tu correo de Keycloak (SGA_MI_CORREO)."
fi

echo
echo "Listo. Siguiente: scripts/doctor.sh (revisa qué falta) y luego scripts/visual.sh."
