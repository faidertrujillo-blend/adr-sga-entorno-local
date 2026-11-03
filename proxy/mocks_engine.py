"""Motor de respuestas simuladas (mocks) del proxy.

Un mock es un archivo JSON que dice: "cuando el front pida ESTA ruta, responde
ESTO". Sirve para ver el front sin BFF ni capa de datos, para fijar casos que
el dato real no tiene (un error 409, una lista vacía, una respuesta lenta) o
para repetir una respuesta que se grabó antes.

Dónde viven (carpeta `mocks/` junto a este archivo):
- `mocks/*.json`             mocks escritos a mano. Tienen prioridad.
- `mocks/grabados/*.json`    respuestas grabadas del backend real (`PROXY_GRABAR=1`).
- Toda carpeta cuyo nombre empiece por `_` se ignora (ahí van los ejemplos).

Formato de un archivo (un objeto, o una lista de objetos):

    {
      "metodo": "GET",                                  # opcional, por defecto GET
      "ruta": "/api/v1/reclamaciones/{id}/cruces",      # {nombre} = cualquier id
      "cuando": {"id": "2026205001"},                   # opcional: valores de las {variables}
      "consulta": "page=1&limit=10",                    # opcional: query string exacta
      "estado": 200,                                    # opcional, por defecto 200
      "demora_ms": 0,                                   # opcional: simula lentitud
      "cabeceras": {},                                  # opcional
      "cuerpo": {"idReclamacion": "{id}", "cruces": []} # lo que se responde
    }

En cualquier texto de `cuerpo`, `{id}` (o la variable que uses) se reemplaza por
el valor que venía en la ruta.

Si varios mocks coinciden, gana el más específico: primero los escritos a mano,
luego los que tienen `cuando` o `consulta`, luego los demás.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

log = logging.getLogger("proxy.mocks")

CARPETA = Path(os.getenv("PROXY_MOCKS_DIR", str(Path(__file__).resolve().parent / "mocks")))
GRABADOS = CARPETA / "grabados"

_VARIABLE = re.compile(r"(\{\w+\})")


@dataclass
class Mock:
    metodo: str
    ruta: str
    patron: re.Pattern[str]
    cuando: dict[str, str]
    consulta: str | None
    estado: int
    demora_ms: int
    cabeceras: dict[str, str]
    cuerpo: Any
    archivo: str
    grabado: bool
    variables: dict[str, str] = field(default_factory=dict)

    @property
    def especificidad(self) -> tuple[int, int, int]:
        """Orden de preferencia (menor = gana): manual antes que grabado, más condiciones primero."""
        return (1 if self.grabado else 0, -len(self.cuando), 0 if self.consulta is not None else 1)


def _a_patron(ruta: str) -> re.Pattern[str]:
    """`/a/{id}/b` -> regex con un grupo con nombre por cada {variable}."""
    partes = _VARIABLE.split(ruta)
    regex = "".join(
        f"(?P<{p[1:-1]}>[^/]+)" if _VARIABLE.fullmatch(p) else re.escape(p) for p in partes
    )
    return re.compile(f"^{regex}$")


def _leer(archivo: Path, grabado: bool) -> list[Mock]:
    try:
        crudo = json.loads(archivo.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        log.warning("mock ignorado (%s): %s", archivo.name, e)
        return []
    mocks: list[Mock] = []
    for d in crudo if isinstance(crudo, list) else [crudo]:
        if not isinstance(d, dict) or "ruta" not in d:
            log.warning("mock ignorado (%s): falta 'ruta'", archivo.name)
            continue
        mocks.append(
            Mock(
                metodo=str(d.get("metodo", "GET")).upper(),
                ruta=d["ruta"],
                patron=_a_patron(d["ruta"]),
                cuando={k: str(v) for k, v in (d.get("cuando") or {}).items()},
                consulta=d.get("consulta"),
                estado=int(d.get("estado", 200)),
                demora_ms=int(d.get("demora_ms", 0)),
                cabeceras={k: str(v) for k, v in (d.get("cabeceras") or {}).items()},
                cuerpo=d.get("cuerpo"),
                archivo=archivo.name,
                grabado=grabado,
            )
        )
    return mocks


class Repositorio:
    """Carga los mocks y los recarga solos cuando cambia algún archivo."""

    def __init__(self) -> None:
        self._firma: tuple[tuple[str, float], ...] = ()
        self._mocks: list[Mock] = []

    def _archivos(self) -> list[tuple[Path, bool]]:
        if not CARPETA.exists():
            return []
        salida: list[tuple[Path, bool]] = []
        for raiz, carpetas, nombres in os.walk(CARPETA):
            carpetas[:] = [c for c in carpetas if not c.startswith("_")]
            for n in sorted(nombres):
                if n.endswith(".json"):
                    ruta = Path(raiz) / n
                    salida.append((ruta, GRABADOS in ruta.parents))
        return salida

    def _recargar_si_cambio(self) -> None:
        archivos = self._archivos()
        firma = tuple((str(p), p.stat().st_mtime) for p, _ in archivos)
        if firma == self._firma:
            return
        self._firma = firma
        self._mocks = sorted(
            (m for p, g in archivos for m in _leer(p, g)), key=lambda m: m.especificidad
        )
        log.info("mocks cargados: %d (en %d archivos)", len(self._mocks), len(archivos))

    def total(self) -> int:
        self._recargar_si_cambio()
        return len(self._mocks)

    def buscar(self, metodo: str, ruta: str, consulta: str) -> tuple[Mock, dict[str, str]] | None:
        self._recargar_si_cambio()
        for m in self._mocks:
            if m.metodo != metodo:
                continue
            coincide = m.patron.match(ruta)
            if not coincide:
                continue
            variables = coincide.groupdict()
            if any(variables.get(k) != v for k, v in m.cuando.items()):
                continue
            if m.consulta is not None and m.consulta != consulta:
                continue
            return m, variables
        return None


def rellenar(valor: Any, variables: dict[str, str]) -> Any:
    """Reemplaza {variable} en todos los textos del cuerpo."""
    if isinstance(valor, str):
        for k, v in variables.items():
            valor = valor.replace("{" + k + "}", v)
        return valor
    if isinstance(valor, list):
        return [rellenar(x, variables) for x in valor]
    if isinstance(valor, dict):
        return {k: rellenar(v, variables) for k, v in valor.items()}
    return valor


# ── Grabación ────────────────────────────────────────────────────────────────

# Rutas que nunca se graban: devuelven URLs firmadas o datos de sesión.
_NO_GRABAR = ("/presign", "/auth", "/embed-url")


def grabar(metodo: str, ruta: str, consulta: str, estado: int, cuerpo: Any) -> Path | None:
    """Guarda una respuesta real como mock (solo lecturas exitosas)."""
    if metodo != "GET" or not 200 <= estado < 300 or any(x in ruta for x in _NO_GRABAR):
        return None
    GRABADOS.mkdir(parents=True, exist_ok=True)
    base = re.sub(r"[^A-Za-z0-9]+", "_", ruta).strip("_")[:120]
    sufijo = f"__{hashlib.sha1(consulta.encode()).hexdigest()[:8]}" if consulta else ""
    archivo = GRABADOS / f"{metodo}_{base}{sufijo}.json"
    archivo.write_text(
        json.dumps(
            {"metodo": metodo, "ruta": ruta, "consulta": consulta or None, "estado": estado, "cuerpo": cuerpo},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return archivo
