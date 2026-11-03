#!/usr/bin/env bash
# Prueba de humo de data-access-api local (solo lecturas GET).
#
# Uso: scripts/smoke.sh
#
# Token: usa $SGA_TOKEN si existe. Si no, inicia sesión en la API local con el
# usuario de prueba guardado en Secrets Manager (perfil AWS real, solo para leer
# el secreto; nunca se imprime). Requiere `aws sso login` vigente en ese caso.
set -euo pipefail
source "$(dirname "$0")/env.sh"
API="http://127.0.0.1:$DATA_API_PUERTO"
PERFIL_REAL="${PERFIL_REAL:-ADRES-TEST-Medicalaudit1}"
SECRETO="adr-devs-sga-adres-api-auth-credentials"

if [ -z "${SGA_TOKEN:-}" ]; then
  # Subshell sin el endpoint de Floci ni las credenciales falsas.
  CUERPO=$(env -u AWS_ENDPOINT_URL -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY \
    AWS_PROFILE="$PERFIL_REAL" aws secretsmanager get-secret-value \
    --secret-id "$SECRETO" --query SecretString --output text 2>/dev/null \
    | "$PY" -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps({"email":d["user"],"password":d["password"]}))') \
    || { echo "No pude leer el secreto. ¿Corriste: aws sso login --profile $PERFIL_REAL?" >&2; exit 1; }
  SGA_TOKEN=$(curl -s -X POST "$API/auth/login" -H 'Content-Type: application/json' -d "$CUERPO" \
    | "$PY" -c 'import sys,json;d=json.load(sys.stdin);print(d.get("access_token") or d.get("token") or "")')
  unset CUERPO
  [ -n "$SGA_TOKEN" ] || { echo "El login local no devolvió token." >&2; exit 1; }
fi
export SGA_TOKEN API

"$PY" - <<'EOF'
import json, os, urllib.error, urllib.request

API, TOKEN = os.environ["API"], os.environ["SGA_TOKEN"]

def get(ruta):
    req = urllib.request.Request(API + ruta, headers={"Authorization": "Bearer " + TOKEN})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]

def caso(nombre, ruta, revisar):
    estado, cuerpo = get(ruta)
    try:
        detalle = revisar(cuerpo) if estado == 200 else cuerpo
        ok = estado == 200 and bool(detalle)
    except Exception as e:  # noqa: BLE001
        ok, detalle = False, f"respuesta inesperada: {e}"
    print(f"{'OK ' if ok else 'FALLA'} {estado} {nombre}: {detalle}")
    return ok

def cruces(c):
    return [(x["tipo"], x["estadoConsulta"], x["hayHallazgo"]) for x in c["cruces"] if x["hayHallazgo"] or x["estadoConsulta"] == "ERROR"]

resultados = [
    caso("health", "/health", lambda c: c.get("status") == "OK" and f"v{c['version']} errorRate={c['errorRate']}"),
    caso("auditores", "/api/v1/auditores?page=1&limit=100", lambda c: c["paginacion"] and [a["componente"] for a in c["datos"]]),
    caso("catálogo jurídico", "/api/v1/catalogos/codigos-glosa?componente=JURIDICO&limit=3", lambda c: [x["codigo"] for x in c["datos"]]),
    caso("bandeja RG", "/api/v1/reclamaciones/respuesta-glosa?fechaInicio=2000-01-01&fechaFin=3000-12-31&page=1&limit=5", lambda c: f"{c['paginacion']}"),
    caso("cruces RNEC con hallazgo (2026205001)", "/api/v1/reclamaciones/2026205001/cruces", cruces),
    caso("cruce siniestros en ERROR (2026211001)", "/api/v1/reclamaciones/2026211001/cruces", cruces),
    caso("historial (2026210003)", "/api/v1/reclamaciones/2026210003/historial", lambda c: f"{len(c.get('datos', c))} eventos"),
]
print(f"\n{sum(resultados)}/{len(resultados)} pruebas OK")
raise SystemExit(0 if all(resultados) else 1)
EOF
