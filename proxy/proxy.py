"""Proxy local entre el front y el BFF.

Las rutas que el BFF real todavía no tiene (o tiene con un cuerpo viejo) se
mandan directo a la data-access-api local, que ya cumple el contrato. Todo lo
demás va al BFF. Así el front se ve completo sin cambiar el BFF ni el front.

Para las rutas que van directo a la data-access-api, el proxy hace lo que haría
el BFF:
- agrega `action` (quién hace la acción) a partir del JWT del usuario;
- traduce el error de la API (`{codigo, mensaje}`) al sobre de error del BFF
  (`{error: {code, httpStatus, message, ...}, detail}`) para que el front lo lea.

Solo para uso local. Configuración por variables de entorno:
- PROXY_BFF_URL       (por defecto http://127.0.0.1:8002)
- PROXY_DATA_API_URL  (por defecto http://127.0.0.1:8081)
- PROXY_ORIGENES      (por defecto localhost y 127.0.0.1 en 5173, 5174 y 5175)
- PROXY_ACTUAR_COMO   (opcional) correo de un auditor; las acciones que van a la
                      data-access-api se firman como ese auditor (rol AUDITOR).
- PROXY_MODO          normal (por defecto) | mock-primero | solo-mock
                        normal:       ignora los mocks; BFF y data-access-api.
                        mock-primero: si hay un mock para la ruta lo usa; si no, como `normal`.
                        solo-mock:    solo responde con mocks; no llama a nadie. Lo que no
                                      tenga mock responde 501. No necesita BFF, API ni Floci.
- PROXY_GRABAR        1 = guarda como mock cada GET exitoso que pasa por el proxy
                      (en proxy/mocks/grabados/). Solo si BFF y API son locales.
- PROXY_MOCKS_DIR     carpeta de mocks (por defecto proxy/mocks). Ver mocks_engine.py.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

import asyncio

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware

import mocks_engine

BFF_URL = os.getenv("PROXY_BFF_URL", "http://127.0.0.1:8002").rstrip("/")
DATA_API_URL = os.getenv("PROXY_DATA_API_URL", "http://127.0.0.1:8081").rstrip("/")
ORIGENES = os.getenv("PROXY_ORIGENES", "http://localhost:5173,http://localhost:5174,http://localhost:5175,http://127.0.0.1:5173,http://127.0.0.1:5174,http://127.0.0.1:5175").split(",")
ACTUAR_COMO = os.getenv("PROXY_ACTUAR_COMO", "").strip()
MODO = os.getenv("PROXY_MODO", "normal").strip().lower()
if MODO not in {"normal", "mock-primero", "solo-mock"}:
    raise SystemExit(f"PROXY_MODO inválido: {MODO!r}. Usa normal, mock-primero o solo-mock.")


def _es_local(url: str) -> bool:
    return url.startswith(("http://127.0.0.1", "http://localhost"))


# Grabar solo si todo es local: así nunca se guardan datos de dev en disco.
GRABAR = os.getenv("PROXY_GRABAR", "") == "1" and _es_local(BFF_URL) and _es_local(DATA_API_URL)
if os.getenv("PROXY_GRABAR", "") == "1" and not GRABAR:
    raise SystemExit("PROXY_GRABAR=1 exige que PROXY_BFF_URL y PROXY_DATA_API_URL sean locales.")
mocks = mocks_engine.Repositorio()

# Igual que app/api/security/roles.py del BFF.
GRUPO_A_ROL = {
    "SGA-Auditores": "AUDITOR",
    "SGA-Supervisores": "SUPERVISOR",
    "SGA-Supervisores-Autorizadores": "SUPERVISOR",
    "SGA-Supervisores-Calidad": "SUPERVISOR",
    "SGA-Financieros": "DIRECTOR",
}

_ID = r"[^/]+"
# (método, ruta) que el BFF desplegado no tiene o tiene desactualizadas.
RUTAS_DATA_API: list[tuple[str, re.Pattern[str]]] = [
    (m, re.compile(p))
    for m, p in [
        ("GET", rf"^/api/v1/reclamaciones/{_ID}/cruces$"),
        ("GET", rf"^/api/v1/reclamaciones/{_ID}/historial$"),
        ("GET", rf"^/api/v1/reclamaciones/{_ID}/devoluciones$"),
        ("POST", rf"^/api/v1/reclamaciones/{_ID}/siguiente-paso$"),
        ("POST", rf"^/api/v1/reclamaciones/{_ID}/marcar-notificada$"),
        ("GET", rf"^/api/v1/reclamaciones/{_ID}/glosas-reclamacion/{_ID}/respuesta-ips$"),
        ("POST", rf"^/api/v1/reclamaciones/{_ID}/glosas-reclamacion/{_ID}/(levantar|confirmar)$"),
        ("DELETE", rf"^/api/v1/reclamaciones/{_ID}/glosas-reclamacion/{_ID}$"),
        # El BFF solo acepta valorAprobado (falta BFF T-36).
        ("POST", rf"^/api/v1/items/{_ID}/glosas/{_ID}/levantar-parcial$"),
        # El BFF exige tipoGlosa y no acepta cantidad.
        ("POST", rf"^/api/v1/items/{_ID}/glosas$"),
        ("DELETE", rf"^/api/v1/items/{_ID}/glosas/{_ID}$"),
        ("POST", r"^/api/v1/respuesta-glosa/(devolver|marcar-auditadas)$"),
        ("GET", r"^/api/v1/respuesta-glosa/ips$"),
    ]
]

# Cabeceras que no se copian de una petición/respuesta a otra.
SALTO = {"host", "content-length", "connection", "keep-alive", "transfer-encoding",
         "content-encoding", "upgrade", "te", "trailer", "proxy-authorization"}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [proxy] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("proxy")

app = FastAPI(title="Proxy local SGA", docs_url=None, redoc_url=None)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ORIGENES,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Proxy-Destino"],
)
cliente = httpx.AsyncClient(timeout=120.0)


def va_a_data_api(metodo: str, ruta: str) -> bool:
    return any(m == metodo and p.match(ruta) for m, p in RUTAS_DATA_API)


def payload_jwt(autorizacion: str | None) -> dict[str, Any]:
    """Lee el cuerpo del JWT sin verificarlo (la data-access-api sí lo verifica)."""
    if not autorizacion or not autorizacion.lower().startswith("bearer "):
        return {}
    partes = autorizacion.split(" ", 1)[1].split(".")
    if len(partes) < 2:
        return {}
    relleno = "=" * (-len(partes[1]) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(partes[1] + relleno))
    except ValueError:
        return {}


def construir_action(jwt: dict[str, Any]) -> dict[str, Any]:
    """Mismo `action` que arma el BFF (`_build_action`)."""
    correo = jwt.get("email") or ""
    usuario = jwt.get("name") or correo
    rol = next((GRUPO_A_ROL[g] for g in jwt.get("groups", []) if g in GRUPO_A_ROL), "SUPERVISOR")
    if ACTUAR_COMO:
        correo, usuario, rol = ACTUAR_COMO, ACTUAR_COMO, "AUDITOR"
    return {
        "id": quote(correo, safe=""),
        "usuario": usuario,
        "correo": correo,
        "rol": rol,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def sobre_de_error(estado: int, cuerpo: bytes) -> bytes:
    """Convierte el error de la data-access-api al sobre de error del BFF."""
    try:
        datos = json.loads(cuerpo)
    except ValueError:
        return cuerpo
    if isinstance(datos, dict) and "codigo" in datos:
        codigo, mensaje = str(datos["codigo"]), str(datos.get("mensaje") or "")
    elif isinstance(datos, dict) and isinstance(datos.get("detail"), list):
        codigo = "VALIDACION"
        mensaje = "; ".join(
            f"{'.'.join(str(x) for x in e.get('loc', []))}: {e.get('msg')}" for e in datos["detail"]
        )
    else:
        return cuerpo
    return json.dumps({
        "error": {
            "code": codigo,
            "httpStatus": estado,
            "message": mensaje,
            "step": "proxy_local",
            "operation": None,
            "requestId": None,
            "traceId": None,
        },
        "detail": mensaje,
    }).encode()


@app.get("/_proxy/estado")
async def estado() -> dict[str, Any]:
    """Diagnóstico: modo actual y cuántos mocks hay cargados."""
    return {
        "modo": MODO,
        "grabando": GRABAR,
        "mocks": mocks.total(),
        "bff": BFF_URL,
        "dataApi": DATA_API_URL,
    }


async def responder_con_mock(metodo: str, ruta: str, consulta: str) -> Response | None:
    """Respuesta del mock que coincide con la petición, o None si no hay."""
    encontrado = mocks.buscar(metodo, ruta, consulta)
    if encontrado is None:
        return None
    mock, variables = encontrado
    if mock.demora_ms:
        await asyncio.sleep(mock.demora_ms / 1000)
    log.info("%-6s %s -> mock (%s) [%s]", metodo, ruta, mock.archivo, mock.estado)
    cuerpo = json.dumps(mocks_engine.rellenar(mock.cuerpo, variables)).encode() if mock.cuerpo is not None else b""
    cabeceras = {"content-type": "application/json", **mock.cabeceras, "X-Proxy-Destino": "mock"}
    return Response(content=cuerpo, status_code=mock.estado, headers=cabeceras)


@app.api_route("/{ruta:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def reenviar(ruta: str, request: Request) -> Response:
    ruta = "/" + ruta
    metodo = request.method
    consulta = request.url.query

    if MODO != "normal":
        respuesta_mock = await responder_con_mock(metodo, ruta, consulta)
        if respuesta_mock is not None:
            return respuesta_mock
        if MODO == "solo-mock":
            mensaje = f"No hay un mock para {metodo} {ruta}. Agrégalo en proxy/mocks/ o grábalo con PROXY_GRABAR=1."
            log.info("%-6s %s -> SIN MOCK [501]", metodo, ruta)
            return Response(
                content=json.dumps({
                    "error": {"code": "PROXY-MOCK-SIN-RESPUESTA", "httpStatus": 501, "message": mensaje,
                              "step": "proxy_local", "operation": None, "requestId": None, "traceId": None},
                    "detail": mensaje,
                }).encode(),
                status_code=501,
                headers={"content-type": "application/json", "X-Proxy-Destino": "sin-mock"},
            )

    directo = va_a_data_api(metodo, ruta)
    base = DATA_API_URL if directo else BFF_URL

    cabeceras = {k: v for k, v in request.headers.items() if k.lower() not in SALTO}
    cuerpo = await request.body()

    if directo and metodo in ("POST", "PUT", "PATCH", "DELETE"):
        try:
            datos = json.loads(cuerpo) if cuerpo else {}
        except ValueError:
            datos = None
        if isinstance(datos, dict) and "action" not in datos:
            datos["action"] = construir_action(payload_jwt(request.headers.get("authorization")))
            cuerpo = json.dumps(datos).encode()
            cabeceras["content-type"] = "application/json"

    respuesta = await cliente.request(
        metodo, base + ruta, params=request.query_params, headers=cabeceras, content=cuerpo
    )

    contenido = respuesta.content
    if directo and respuesta.status_code >= 400:
        contenido = sobre_de_error(respuesta.status_code, contenido)

    destino = "data-api" if directo else "bff"
    log.info("%-6s %s -> %s [%s]", metodo, ruta, destino, respuesta.status_code)

    if GRABAR and metodo == "GET" and "json" in respuesta.headers.get("content-type", ""):
        try:
            grabado = mocks_engine.grabar(metodo, ruta, consulta, respuesta.status_code, json.loads(contenido))
            if grabado:
                log.info("grabado: %s", grabado.name)
        except ValueError:
            pass

    salida = {
        k: v for k, v in respuesta.headers.items()
        if k.lower() not in SALTO and not k.lower().startswith("access-control-")
    }
    salida["X-Proxy-Destino"] = destino
    return Response(content=contenido, status_code=respuesta.status_code, headers=salida)
