# Entorno local del SGA con Floci

Corre en tu computador la **data-access-api** con una AWS falsa (Floci: S3 y
DynamoDB) cargada con los escenarios de prueba de `mockdata`. Opcionalmente, el
**BFF** apunta a esa API local.

Sirve para probar el front sin depender de dev: dev comparte datos con el
equipo, falla el 10 % de las veces a propósito (chaos testing) y no trae los
escenarios de Respuesta a glosa.

> Para entender **cómo y por qué** funciona cada pieza, lee `COMO-FUNCIONA.md`.

```
Front (:5173) ──► BFF (:8000) ──► data-access-api (:8081) ──► Floci (:4567)
                   │                    │                       S3 + DynamoDB
                   │                    └─► Keycloak real (valida los JWT)
                   └─► AWS real (Secrets Manager, soportes, SQS)
```

## Primer día (nuevo en el equipo)

Esta carpeta es una herramienta de apoyo, no parte del producto. Necesita que los
repos del SGA estén clonados **uno junto al otro** en la misma carpeta:

```
SGA/
├── adr-sgaPipeline-datasync/     data-access-api y mockdata
├── adr-sgaReclamation-bff/       el BFF
├── adr-sgaReclamation-front/     el front
└── entorno-local-floci/          esta carpeta
```

1. **Instala** Docker, `uv` (`curl -LsSf https://astral.sh/uv/install.sh | sh`),
   la AWS CLI y Node.
2. **Prepara el entorno:** `scripts/setup.sh` crea el Python 3.12 con sus librerías
   y te crea `config.local`.
3. **Pon tu correo** en `config.local` (`SGA_MI_CORREO`): debe ser exactamente el
   campo `email` de tu token de Keycloak. Sirve para que tu bandeja "Asignadas"
   tenga reclamaciones.
4. **Consigue los `.env`** de `data-access-api` y del BFF (`cp .env.example .env`).
   El de la API pide `KEYCLOAK_CLIENT_SECRET`: se solicita al líder del equipo.
   No va en este repo ni en ningún chat.
5. **Inicia sesión en AWS:** `aws sso login --profile ADRES-TEST-Medicalaudit1`
   (solo hace falta para el BFF y `smoke.sh`).
6. **Revisa qué falta:** `scripts/doctor.sh`. Solo lee; te dice qué arreglar y cómo.
7. **Levanta todo:** `scripts/visual.sh`, y lanza el front en el puerto 5173 con el
   comando que te imprime.

Luego lee `COMO-FUNCIONA.md` para entender qué hace cada pieza.

## Requisitos

- Docker.
- `uv` (crea el Python 3.12 del entorno en `.venv/`; lo hace `scripts/setup.sh`).
- Sesión de AWS solo para `smoke.sh` y `bff.sh`: `aws sso login --profile ADRES-TEST-Medicalaudit1`.

Si borras `.venv/`, se recrea con `scripts/setup.sh`.

## Uso diario

```bash
cd entorno-local-floci   # la carpeta de esta herramienta, junto a los repos del SGA

scripts/up.sh            # arranca Floci; la primera vez carga los datos
scripts/api.sh --fondo   # data-access-api local en :8081
scripts/smoke.sh         # 7 pruebas de lectura; deben salir 7/7 OK
scripts/estado.sh        # qué corre y hacia dónde apunta

scripts/down.sh          # apaga la API local y Floci (los datos se guardan)
```

| Script | Qué hace |
|---|---|
| `setup.sh` | Primer día: crea `.venv`, instala dependencias y `config.local`. Seguro de repetir. |
| `doctor.sh` | Revisa qué falta (herramientas, repos, `.env`, sesión de AWS, puertos). Solo lee. |
| `up.sh` | Arranca Floci y siembra los datos si está vacío. |
| `seed.sh` | Crea tablas e índices y recarga **todo** desde cero (`--sin-clean` solo agrega). |
| `reset.sh` | Igual que `seed.sh`: vuelve al estado inicial después de probar acciones. |
| `asignar_auditor.sh` | Asigna tu usuario (el de `config.local`) como auditor Médico y lo agrega al directorio. |
| `api.sh` | data-access-api contra Floci (`--fondo` en segundo plano; sin `--reload`: reinícialo tras cambiar código). |
| `smoke.sh` | Pruebas GET: health, auditores, catálogo, bandeja RG, cruces e historial. |
| `bff.sh` | BFF (:8002) apuntando a la API local, sin editar su `.env` (`--fondo`). |
| `proxy.sh` | Proxy (:8010) que completa las rutas que el BFF aún no tiene (`--fondo`). |
| `mock.sh` | Reinicia el proxy en `solo-mock`, `mock-primero` o `normal`. |
| `grabar.sh` | Reinicia el proxy grabando cada GET exitoso como mock. |
| `visual.sh` | Levanta todo lo anterior de una vez para ver el front. |
| `estado.sh` | Muestra Floci, la API local y qué hay en los puertos 8000 y 8080. |
| `down.sh` | Detiene proxy, BFF y API local lanzados en segundo plano, y Floci. |

## Seguridad: por qué no toca dev

- `scripts/env.sh` fija `AWS_ENDPOINT_URL=http://127.0.0.1:4567`, credenciales
  falsas (`test`) y **borra `AWS_PROFILE`**. Si el endpoint no es local o Floci no
  responde, el script se corta antes de hacer nada.
- Por eso `seed.sh` puede usar `upload_dynamo.py --clean` sin riesgo: solo
  trunca las tablas de Floci. **Nunca corras `--clean` fuera de estos scripts.**
- Los puertos solo se publican en `127.0.0.1`.
- `bff.sh` es la excepción: el BFF sí necesita AWS real (secretos, soportes), así
  que usa el perfil real; solo cambia `RECLAMATIONS_API_URL`.

## Puertos

| Puerto | Qué | Nota |
|---|---|---|
| 4567 | Floci de este entorno (`sga-floci`) | El 4566 lo usa otro proyecto (`paca-local-floci-1`). |
| 8081 | data-access-api local | El 8080 suele tenerlo tu data-access-api apuntando a dev. |
| 8002 | BFF de este entorno | El 8000 suele tenerlo tu BFF apuntando a dev. |
| 8010 | Proxy para el front | `VITE_API_BASE_URL=http://localhost:8010`. |

Todos se cambian con variables: `FLOCI_PUERTO`, `DATA_API_PUERTO`, `BFF_PUERTO`, `PROXY_PUERTO`.
Si cambias `FLOCI_PUERTO`, cambia también el puerto en `compose.yaml`.

## Ver el front con todo (modo visual)

```
Front (:5173) ──► proxy (:8010) ──┬─► rutas que el BFF ya tiene     ──► BFF (:8002) ──► data-api (:8081)
                                  └─► rutas que el BFF aún no tiene ─────────────────► data-api (:8081)
```

```bash
scripts/visual.sh                       # Floci + data-api + BFF (:8002) + proxy (:8010)

# en el repo del front, en la rama central de la pantalla:
git checkout feat/p2-detalle-reclamacion-rg
VITE_API_BASE_URL=http://localhost:8010 npm run dev
```

Vite da prioridad a las variables de la terminal sobre el `.env`, así que no hay
que editar el `.env` del front. Tu BFF de dev en `:8000` no se toca.

**El front debe correr en el puerto 5173.** El Keycloak de dev solo acepta
`http://localhost:5173/*` como dirección de retorno del cliente
`ars-devs-AIGestorAuditorias` (probado: 5174, 5175, `127.0.0.1:5173` y otros dan
"Parámetro no válido: redirect_uri"). Si ya tienes un `npm run dev` en el 5173
apuntando a dev, detenlo (Ctrl+C) antes de lanzar este. Abre siempre
`http://localhost:5173` (no `127.0.0.1`). Si el login te deja en
`visor.dev.adr.ia.blend360.com`, estás en el sitio desplegado, no en tu front.

El proxy (`proxy/proxy.py`) manda directo a la data-api las rutas que el BFF no
tiene o tiene con un cuerpo viejo, y para ellas hace lo que haría el BFF:

- agrega `action` (usuario, correo, rol, fecha) tomado de tu JWT;
- traduce los errores de la API al sobre de error del BFF, para que el front
  muestre los mensajes de conflicto (409) y de validación.

Rutas que van directo a la data-api: `cruces`, `historial`, `devoluciones`,
`siguiente-paso`, `marcar-notificada`, `glosas-reclamacion/{glosaId}/levantar|confirmar|respuesta-ips`
y su `DELETE`, `items/{id}/glosas/{glosaId}/levantar-parcial`, crear y eliminar glosa
de ítem, y `respuesta-glosa/devolver|marcar-auditadas|ips`. La lista está al
inicio de `proxy/proxy.py`; cuando el BFF agregue una ruta, bórrala de ahí.

Cada respuesta trae la cabecera `X-Proxy-Destino: bff | data-api`, y el log
`logs/proxy.log` muestra a dónde fue cada llamada.

**Actuar como auditor.** No tienes usuarios auditores. Con
`PROXY_ACTUAR_COMO=aud.juridico.dop@adres.gov.co scripts/proxy.sh --fondo` las
acciones que van a la data-api se firman como ese auditor (rol AUDITOR). Solo
afecta al API: los botones del front siguen dependiendo de los permisos de tu
usuario real. Auditores del directorio: `aud.juridico.dop`, `aud.financiero.dop`
y `aud.medico.dop` (`@adres.gov.co`).

## Respuestas simuladas (mocks): usar el front sin BFF ni API

El proxy puede responder por su cuenta, con archivos JSON que tú controlas
(`proxy/mocks/`). Tiene tres modos:

| Modo | Qué hace | Necesita BFF/API/Floci |
|---|---|---|
| `normal` (por defecto) | Ignora los mocks; BFF y capa de datos como siempre. | Sí |
| `mock-primero` | Si hay mock para la ruta lo usa; si no, va al backend real. | Solo para lo que no tenga mock |
| `solo-mock` | Solo responde con mocks; **no llama a nadie**. Lo que no tenga mock da 501. | **No** |

```bash
scripts/mock.sh                  # solo-mock
scripts/mock.sh mock-primero
scripts/mock.sh normal           # volver a lo de siempre
curl http://127.0.0.1:8010/_proxy/estado   # modo actual y mocks cargados
```

Dos formas de tener mocks:

1. **Grabarlos** (lo más cómodo): `scripts/grabar.sh`, navegas por el front con todo
   encendido y cada lectura (GET) exitosa queda en `proxy/mocks/grabados/`. Luego
   `scripts/mock.sh` y el front funciona sin backend. `scripts/grabar.sh --parar`
   deja de grabar.
2. **Escribirlos a mano**: copia un ejemplo de `proxy/mocks/_ejemplos/` a
   `proxy/mocks/` y edítalo. Sirve para casos que el dato no tiene: un error 409,
   una lista vacía o una respuesta lenta (`demora_ms`) para ver los cargadores.

Formato, reglas de prioridad y límites: `proxy/mocks_engine.py` y `COMO-FUNCIONA.md`
(sección 11). En solo-mock el login sigue necesitando internet (Keycloak real).

## Ver reclamaciones como tu usuario

Los datos de prueba asignan trabajo a auditores ficticios (`aud.medico.dop@...`).
Para que **tu** usuario real vea trabajo en **Asignadas**, `scripts/asignar_auditor.sh`:

- cambia el auditor del componente **Médico** por tu correo (`SGA_MI_CORREO`, de
  `config.local`) en las reclamaciones de Floci donde el Médico estaba asignado;
- te agrega al directorio de auditores (la lista que usa la API local);
- te deja **en turno** en la reclamación `2026203002`;
- reinicia la API local para que vea el cambio (guarda el directorio en caché ~5 min).

Es idempotente y `seed.sh` / `reset.sh` lo vuelven a aplicar solos. Para otro
correo puntual: `scripts/asignar_auditor.sh --correo otro@adres.gov.co --nombre "Nombre"`.
El correo debe ser exactamente el `email` del token de Keycloak.

Con tu usuario deberías ver 13 reclamaciones:

| Estado de mi trabajo | Ids |
|---|---|
| En turno | `2026203002` |
| En espera | `2026203001`, `2026204001`, `2026204002`, `2026205002` |
| Completada | `2026206001`, `2026206002`, `2026208001` (devuelta), `2026208002` (devuelta), `2026210001`, `2026210002`, `2026210003`, `2026227001` |

`2026205001` no aparece en la bandeja porque en esa reclamación el Médico no
aplica; se abre por URL (`/reclamaciones/2026205001`). Su gemela `2026205002` sí.

En el front: `/gestion-reclamaciones/asignadas`.

## Usar solo el BFF contra este entorno

1. `scripts/up.sh` y `scripts/api.sh --fondo`.
2. `scripts/bff.sh` (puerto 8002; `BFF_PUERTO=8000` si detienes tu BFF de dev).
3. `VITE_API_BASE_URL=http://localhost:8002 npm run dev`.

Reclamaciones útiles (escenarios de `mockdata/README.md`):

| Escenario | Ids |
|---|---|
| Jurídico aplica solo por cruce RNEC con hallazgo | `2026205001`, `2026205002` |
| Cruce de siniestros en ERROR | `2026211001` |
| Financiero en turno, glosas resueltas y pendientes | `2026204001`, `2026204002` |
| En validación del supervisor | `2026206001`, `2026206002` |
| Devuelta por el supervisor | `2026208001`, `2026208002` |
| RG2 con glosa nueva notificada | `2026209001` |
| Auditada y liquidada | `2026210001`, `2026210002`, `2026210003` |

## Limitaciones conocidas

- **`app/main.py` hace `load_dotenv(override=True)`:** el `.env` del repo de la API
  pisa las variables de la terminal. Por eso `api.sh` usa `run_api.py`, que anula
  esa carga. No uses `uvicorn` directo en esa carpeta si quieres Floci.

- **El BFF aún no expone todo lo del contrato.** El BFF real tiene 38 rutas; el
  swagger de `Documentos/SGA/Swaggers` describe 56. El proxy tapa ese hueco en
  local; en dev esas pantallas seguirán fallando hasta que el BFF las agregue.
- **El proxy imita al BFF, no es el BFF.** Si el BFF transforma una respuesta o
  usa otros códigos de error cuando implemente la ruta, el front podría verse
  distinto. Vuelve a probar contra el BFF real cuando la ruta exista.
- **Permisos:** el usuario de servicio del secreto no tiene permisos de
  supervisor ni auditor en el BFF (responde 403). Para la UI usa tu usuario.
- **Soportes:** se cargan con `--no-soportes`; los documentos de soporte no estarán.
- **Acciones:** levantar, ratificar o crear glosas sí escriben, pero en Floci.
  Para deshacerlas: `scripts/reset.sh`.
- **Floci no es AWS:** probado OK con consultas por índice (GSI), orden,
  paginación y updates condicionales. Si ves un error raro de DynamoDB que no
  pasa en dev, sospecha de Floci y avisa.

## Probar la API local directo

`http://127.0.0.1:8081/docs` abre Swagger UI. Pulsa **Authorize** y pega un
token. Para obtenerlo:

```bash
curl -s -X POST http://127.0.0.1:8081/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"TU_USUARIO","password":"TU_CLAVE"}'
```

No guardes claves ni tokens en archivos de esta carpeta.
