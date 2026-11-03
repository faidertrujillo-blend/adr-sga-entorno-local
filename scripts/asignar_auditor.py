"""Asigna tu usuario real de Keycloak como auditor Médico en las reclamaciones de Floci.

Los datos de mockdata asignan a auditores ficticios (aud.medico.dop@...). Este
script cambia, en Floci, el auditor del componente MEDICO por el tuyo para que
lo veas en "Asignadas". También lo agrega al directorio de auditores, que es de
donde la API local saca la lista (AUDITORES_FUENTE=directorio).

Es idempotente: puedes correrlo varias veces. `scripts/seed.sh` lo vuelve a
correr después de recargar los datos, así que el reset no lo pierde.

Solo escribe en Floci: se niega a correr si AWS_ENDPOINT_URL no es local.

Uso (lo normal es `scripts/asignar_auditor.sh`):
    python asignar_auditor.py [--correo tu.usuario@adres.gov.co]   (por defecto SGA_MI_CORREO)
                              [--nombre "Tu nombre"]                (por defecto SGA_MI_NOMBRE)
                              [--en-turno ID ...]   ids a dejar con el Médico en turno
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import boto3

TABLA = "adr-devs-sga-reclamaciones"
BUCKET = "adr-devs-sga-data"
CLAVE_DIRECTORIO = "config/auditores.json"
FICTICIO_MEDICO = "aud.medico.dop@adres.gov.co"
# Reclamación donde el Médico queda con el turno (jurídico y financiero ya cerraron).
EN_TURNO_POR_DEFECTO = ["2026203002"]


def exigir_local() -> None:
    destino = os.environ.get("AWS_ENDPOINT_URL", "")
    if not destino.startswith(("http://127.0.0.1", "http://localhost")):
        sys.exit(f"ABORTADO: AWS_ENDPOINT_URL no es local ({destino!r}).")


def agregar_al_directorio(s3, correo: str, nombre: str) -> None:
    cuerpo = s3.get_object(Bucket=BUCKET, Key=CLAVE_DIRECTORIO)["Body"].read()
    directorio = json.loads(cuerpo)
    if any(str(a.get("correo", "")).lower() == correo for a in directorio):
        print(f"= {correo} ya está en el directorio")
        return
    directorio.append({"correo": correo, "nombre": nombre, "componente": "MEDICO", "activo": True})
    s3.put_object(
        Bucket=BUCKET, Key=CLAVE_DIRECTORIO,
        Body=json.dumps(directorio, ensure_ascii=False, indent=2).encode(),
        ContentType="application/json",
    )
    print(f"+ {correo} agregado al directorio (MEDICO)")


def reasignar_medico(tabla, correo: str, nombre: str) -> list[str]:
    """Cambia el auditor Médico ficticio por el real en todas las reclamaciones."""
    cambiadas: list[str] = []
    kwargs = {"ProjectionExpression": "id_reclamacion, respuesta_glosa"}
    while True:
        pagina = tabla.scan(**kwargs)
        for doc in pagina["Items"]:
            medico = ((doc.get("respuesta_glosa") or {}).get("componentes") or {}).get("medico") or {}
            auditor = medico.get("auditor")
            if not isinstance(auditor, dict):
                continue
            if str(auditor.get("auditorId", "")).lower() != FICTICIO_MEDICO:
                continue
            nuevo = {**auditor, "auditorId": correo, "correo": correo, "nombre": nombre}
            tabla.update_item(
                Key={"id_reclamacion": doc["id_reclamacion"]},
                UpdateExpression="SET respuesta_glosa.componentes.medico.auditor = :a",
                ExpressionAttributeValues={":a": nuevo},
            )
            cambiadas.append(doc["id_reclamacion"])
        if "LastEvaluatedKey" not in pagina:
            return sorted(cambiadas)
        kwargs["ExclusiveStartKey"] = pagina["LastEvaluatedKey"]


def dejar_en_turno(tabla, ids: list[str], correo: str) -> None:
    """Jurídico y financiero completados; el turno pasa al Médico."""
    for id_reclamacion in ids:
        fila = tabla.get_item(Key={"id_reclamacion": id_reclamacion}).get("Item")
        if not fila:
            print(f"! {id_reclamacion} no existe, se omite")
            continue
        rg = fila.get("respuesta_glosa") or {}
        comps = rg.get("componentes") or {}
        medico_auditor = (comps.get("medico") or {}).get("auditor") or {}
        if str(medico_auditor.get("auditorId", "")).lower() != correo:
            print(f"! {id_reclamacion}: el Médico no es {correo}, se omite")
            continue
        ahora = (comps.get("juridico") or {}).get("fecha_turno") or "2026-09-20T08:00:00Z"
        tabla.update_item(
            Key={"id_reclamacion": id_reclamacion},
            UpdateExpression=(
                "SET respuesta_glosa.componente_actual = :m, "
                "respuesta_glosa.componentes.juridico.completado = :t, "
                "respuesta_glosa.componentes.financiero.completado = :t, "
                "respuesta_glosa.componentes.medico.fecha_turno = :f"
            ),
            ExpressionAttributeValues={":m": "MEDICO", ":t": True, ":f": ahora},
        )
        print(f"+ {id_reclamacion}: Médico en turno")


def main() -> None:
    exigir_local()
    p = argparse.ArgumentParser()
    p.add_argument("--correo", default=os.environ.get("SGA_MI_CORREO", ""))
    p.add_argument("--nombre", default=os.environ.get("SGA_MI_NOMBRE", "Mi usuario"))
    p.add_argument("--en-turno", nargs="*", default=EN_TURNO_POR_DEFECTO)
    a = p.parse_args()
    correo = a.correo.strip().lower()
    if not correo:
        sys.exit("Falta tu correo: pásalo con --correo o define SGA_MI_CORREO en config.local "
                 "(el campo `email` de tu token de Keycloak).")

    agregar_al_directorio(boto3.client("s3"), correo, a.nombre)
    tabla = boto3.resource("dynamodb").Table(TABLA)
    cambiadas = reasignar_medico(tabla, correo, a.nombre)
    print(f"+ Médico reasignado a {correo} en {len(cambiadas)} reclamaciones: {', '.join(cambiadas) or '(ninguna)'}")
    dejar_en_turno(tabla, a.en_turno, correo)


if __name__ == "__main__":
    main()
