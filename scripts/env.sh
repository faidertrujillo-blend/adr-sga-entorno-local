# Variables comunes del entorno local. Se carga con `source`, no se ejecuta.
#
# Lo más importante: apunta boto3 a Floci y borra cualquier credencial real,
# para que ningún script (en especial `upload_dynamo.py --clean`) toque AWS dev.

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SGA="$(cd "$RAIZ/.." && pwd)"
DATASYNC="$SGA/adr-sgaPipeline-datasync"
MOCKDATA="$DATASYNC/mockdata"
DATA_API="$DATASYNC/data-access-api"
PY="$RAIZ/.venv/bin/python"

# Configuración personal (no se sube al repo). Ver config.local.example.
# Define SGA_MI_CORREO y SGA_MI_NOMBRE: tu usuario de Keycloak.
if [ -f "$RAIZ/config.local" ]; then
  # shellcheck disable=SC1091
  source "$RAIZ/config.local"
fi
# Sin `export`, los scripts de Python que lanzamos no verían estas variables.
export SGA_MI_CORREO="${SGA_MI_CORREO:-}" SGA_MI_NOMBRE="${SGA_MI_NOMBRE:-Mi usuario}"

# 4567 y 8081: los puertos "normales" (4566 y 8080) suelen estar en uso por
# otro Floci y por la data-access-api apuntando a dev.
FLOCI_PUERTO="${FLOCI_PUERTO:-4567}"
DATA_API_PUERTO="${DATA_API_PUERTO:-8081}"

# boto3 lee AWS_ENDPOINT_URL para todos los servicios.
export AWS_ENDPOINT_URL="http://127.0.0.1:${FLOCI_PUERTO}"
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
unset AWS_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN

# Corta el script si el endpoint no es local o Floci no responde.
exigir_floci() {
  case "$AWS_ENDPOINT_URL" in
    http://127.0.0.1:*|http://localhost:*) ;;
    *) echo "ABORTADO: AWS_ENDPOINT_URL no es local ($AWS_ENDPOINT_URL)." >&2; exit 1 ;;
  esac
  if ! curl -s -m 3 "$AWS_ENDPOINT_URL/_localstack/health" >/dev/null; then
    echo "ABORTADO: Floci no responde en $AWS_ENDPOINT_URL. Corre scripts/up.sh." >&2
    exit 1
  fi
}

exigir_venv() {
  if [ ! -x "$PY" ]; then
    echo "Falta el entorno de Python. Corre: scripts/setup.sh" >&2
    exit 1
  fi
}
