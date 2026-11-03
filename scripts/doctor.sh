#!/usr/bin/env bash
# Revisa si tu máquina tiene todo lo necesario y dice cómo arreglar lo que falte.
# Solo LEE: no instala, no arranca ni cambia nada.
#
# Uso: scripts/doctor.sh
source "$(dirname "$0")/env.sh"

FALLAS=0
AVISOS=0
ok()    { printf "  \033[32m✓\033[0m %s\n" "$1"; }
falla() { printf "  \033[31m✗\033[0m %s\n      → %s\n" "$1" "$2"; FALLAS=$((FALLAS+1)); }
aviso() { printf "  \033[33m!\033[0m %s\n      → %s\n" "$1" "$2"; AVISOS=$((AVISOS+1)); }

echo "Herramientas"
command -v docker >/dev/null && docker info >/dev/null 2>&1 \
  && ok "Docker funcionando" \
  || falla "Docker no está instalado o no responde" "Instálalo y asegúrate de poder correr 'docker ps' sin sudo."
command -v uv >/dev/null && ok "uv instalado" \
  || falla "Falta uv (crea el Python 3.12 del entorno)" "curl -LsSf https://astral.sh/uv/install.sh | sh"
command -v aws >/dev/null && ok "AWS CLI instalado" \
  || falla "Falta la AWS CLI" "Instálala (la usan bff.sh y smoke.sh para leer secretos)."
command -v node >/dev/null && ok "Node instalado ($(node --version))" \
  || aviso "No se encontró Node" "Lo necesitas para correr el front (npm run dev)."

echo "Repos hermanos (deben estar junto a esta carpeta, en $SGA)"
[ -d "$DATA_API" ] && ok "adr-sgaPipeline-datasync (data-access-api y mockdata)" \
  || falla "Falta adr-sgaPipeline-datasync" "Clónalo en $SGA/adr-sgaPipeline-datasync"
[ -d "$SGA/adr-sgaReclamation-bff" ] && ok "adr-sgaReclamation-bff" \
  || aviso "Falta adr-sgaReclamation-bff" "Solo lo necesitas para el modo con BFF; clónalo en $SGA/adr-sgaReclamation-bff"
[ -d "$SGA/adr-sgaReclamation-front" ] && ok "adr-sgaReclamation-front" \
  || aviso "Falta adr-sgaReclamation-front" "Clónalo en $SGA/adr-sgaReclamation-front"

echo "Configuración (solo se revisa si existen; nunca se muestran valores)"
[ -x "$PY" ] && ok "Entorno de Python (.venv)" \
  || falla "No hay entorno de Python" "Corre scripts/setup.sh"
[ -f "$DATA_API/.env" ] && ok ".env de data-access-api existe" \
  || falla "Falta $DATA_API/.env" "cp .env.example .env y pide al líder el KEYCLOAK_CLIENT_SECRET."
[ -f "$SGA/adr-sgaReclamation-bff/.env" ] && ok ".env del BFF existe" \
  || aviso "Falta el .env del BFF" "Solo para el modo con BFF: cp .env.example .env en el repo del BFF."
if [ -n "${SGA_MI_CORREO:-}" ]; then
  ok "config.local con tu correo definido"
else
  aviso "No definiste tu correo" "cp config.local.example config.local y pon tu correo de Keycloak; si no, tu bandeja Asignadas saldrá vacía."
fi

echo "Sesión de AWS (solo para bff.sh y smoke.sh)"
if command -v aws >/dev/null; then
  if env -u AWS_ENDPOINT_URL -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY AWS_PROFILE="${PERFIL_REAL:-ADRES-TEST-Medicalaudit1}" \
       aws sts get-caller-identity >/dev/null 2>&1; then
    ok "Sesión de AWS vigente (perfil ${PERFIL_REAL:-ADRES-TEST-Medicalaudit1})"
  else
    aviso "Sin sesión de AWS vigente" "aws sso login --profile ${PERFIL_REAL:-ADRES-TEST-Medicalaudit1}"
  fi
fi

echo "Puertos (libres = ✓; ocupados no siempre es un problema)"
for par in "Floci:$FLOCI_PUERTO" "data-access-api:$DATA_API_PUERTO" "BFF:${BFF_PUERTO:-8002}" "proxy:${PROXY_PUERTO:-8010}" "front:5173"; do
  nombre="${par%%:*}"; puerto="${par##*:}"
  if ss -ltn 2>/dev/null | grep -q ":$puerto "; then
    aviso "Puerto $puerto ($nombre) en uso" "Si es de este entorno, está bien. Si no: scripts/estado.sh, o cambia el puerto con una variable."
  else
    ok "Puerto $puerto ($nombre) libre"
  fi
done

echo
if [ "$FALLAS" -eq 0 ]; then
  echo "Todo lo imprescindible está listo ($AVISOS aviso(s))."
else
  echo "Faltan $FALLAS cosa(s) imprescindible(s). Arregla las marcadas con ✗."
  exit 1
fi
