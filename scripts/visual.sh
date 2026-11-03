#!/usr/bin/env bash
# Levanta todo lo necesario para ver el front con datos de los escenarios:
# Floci -> data-access-api (:8081) -> BFF (:8002) -> proxy (:8010).
# Lo que ya esté corriendo se deja como está.
#
# Uso: scripts/visual.sh
#      PROXY_ACTUAR_COMO=aud.juridico.dop@adres.gov.co scripts/visual.sh
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/env.sh"
BFF_PUERTO="${BFF_PUERTO:-8002}"
PROXY_PUERTO="${PROXY_PUERTO:-8010}"

"$DIR/up.sh"
curl -s -m 2 "http://127.0.0.1:$DATA_API_PUERTO/health" >/dev/null || "$DIR/api.sh" --fondo
curl -s -m 2 -o /dev/null "http://127.0.0.1:$BFF_PUERTO/openapi.json" || BFF_PUERTO="$BFF_PUERTO" "$DIR/bff.sh" --fondo
ss -ltn | grep -q ":$PROXY_PUERTO " || BFF_PUERTO="$BFF_PUERTO" "$DIR/proxy.sh" --fondo

cat <<EOF

Todo arriba. Ahora, en el repo del front (rama feat/p2-detalle-reclamacion-rg).
Debe ser el puerto 5173: es el único que el Keycloak de dev acepta para el login.
Si ya tienes un npm run dev ahí apuntando a dev, deténlo primero (Ctrl+C).

  VITE_API_BASE_URL=http://localhost:$PROXY_PUERTO npm run dev -- --port 5173 --strictPort

Reclamaciones para mirar: 2026205001 (cruce RNEC), 2026211001 (cruce en ERROR),
2026204001 (financiero en turno), 2026208001 (devuelta), 2026210003 (auditada).
Para ver a dónde va cada llamada: tail -f $RAIZ/logs/proxy.log
Para apagar: scripts/down.sh
EOF
