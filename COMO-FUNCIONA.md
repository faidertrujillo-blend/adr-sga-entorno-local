# Cómo funciona el entorno local con Floci

Este documento explica **todo lo que hay en esta carpeta y por qué funciona así**.
Para saber solo qué comandos correr, mira el `README.md`. Aquí está el "por qué".

Está escrito para alguien que está aprendiendo: cada término técnico se explica la
primera vez que aparece.

---

## 1. La idea en una frase

Queremos ver el front del SGA con datos de prueba **sin depender del ambiente de
desarrollo (dev)**, porque dev:

- lo comparte todo el equipo (si pruebas algo, lo ven los demás);
- falla al azar el 10 % de las veces a propósito (*chaos testing*: errores
  inyectados para probar la resiliencia);
- no tiene cargados los escenarios de prueba de "Respuesta a glosa" (cruces,
  turnos, devueltas...) ni el catálogo de códigos de glosa.

Para eso montamos **una copia local del backend**, con datos controlados.

---

## 2. Vocabulario básico

| Término | Qué es |
|---|---|
| **AWS** | La nube de Amazon. El SGA guarda sus datos en dos servicios suyos. |
| **S3** | Almacén de archivos de AWS. Funciona como carpetas con archivos (por ejemplo, el catálogo de códigos). |
| **DynamoDB** | Base de datos de AWS. Guarda filas (llamadas *ítems*) en *tablas*. |
| **Índice secundario global (GSI)** | Un "atajo" para buscar en una tabla por otro campo distinto del identificador. Ejemplo: buscar reclamaciones por estado y fecha. |
| **Emulador de AWS** | Un programa que **imita** a S3 y DynamoDB en tu computador, sin conectarse a Amazon. |
| **Floci** | El emulador que usamos. Corre dentro de un contenedor de Docker. |
| **Docker / contenedor** | Una caja que trae un programa con todo lo que necesita. Se prende y se apaga sin ensuciar tu sistema. |
| **API** | Un programa que responde peticiones por internet (HTTP). |
| **BFF** | "Backend for Frontend": la API que el front llama. Hace de intermediario con la API de datos. |
| **JWT / token** | Un "carné digital" que prueba quién eres. Lo emite Keycloak al iniciar sesión. |
| **Keycloak** | El sistema de ADRES que maneja usuarios y contraseñas. |
| **CORS** | Regla del navegador: una página solo puede llamar a otro servidor si este lo permite expresamente. |
| **Proxy** | Un intermediario: recibe la petición y la reenvía a otro lado. |
| **Escenario** | Un conjunto de reclamaciones de prueba hechas a propósito para mostrar un caso (por ejemplo, "devuelta" o "cruce en error"). |

---

## 3. Las piezas y cómo se conectan

```
 Navegador
     │  http://localhost:5173
     ▼
  Front (React + Vite, puerto 5173)
     │  llama a  VITE_API_BASE_URL = http://localhost:8010
     ▼
  Proxy local (:8010)   ← proxy/proxy.py
     │
     ├── rutas que el BFF YA tiene ──────────► BFF local (:8002) ──┐
     │                                                              │
     └── rutas que el BFF AÚN NO tiene ──────────────────────────┐  │
                                                                  ▼  ▼
                                               data-access-api local (:8081)
                                                         │
                                                         ▼
                                               Floci (:4567)  =  S3 + DynamoDB falsos
                                               (datos en floci-data/)

 Aparte, en la nube real (no local):
   Keycloak ........ valida quién eres (login y firma de los tokens)
   AWS real ........ el BFF lee secretos y archivos de soporte (perfil ADRES-TEST-Medicalaudit1)
```

### Qué hace cada pieza

| Pieza | Puerto | Quién la arranca | Qué hace |
|---|---|---|---|
| **Floci** | 4567 | `up.sh` | S3 y DynamoDB de mentira. Guarda los datos en `floci-data/`. |
| **data-access-api** | 8081 | `api.sh` | La API de datos real (repo `adr-sgaPipeline-datasync`), pero leyendo de Floci. Aquí vive la lógica: cruces, turnos, glosas, asignaciones. |
| **BFF** | 8002 | `bff.sh` | Tu BFF (`adr-sgaReclamation-bff`), pero apuntando a la API local. |
| **Proxy** | 8010 | `proxy.sh` | Completa lo que el BFF todavía no tiene. |
| **Front** | 5173 | tú, con `npm run dev` | La aplicación que ves en el navegador. |

---

## 4. Por qué Floci y qué hace exactamente

**Floci** es un emulador de AWS gratuito y de código abierto. Habla el mismo
"idioma" que AWS, así que el código del proyecto (que usa la librería `boto3`) no
se entera de que no es Amazon.

### Cómo se le dice al código que use Floci
La librería `boto3` lee una variable de entorno llamada `AWS_ENDPOINT_URL`. Si
existe, en vez de hablar con Amazon habla con esa dirección:

```
AWS_ENDPOINT_URL=http://127.0.0.1:4567
```

Eso es todo el truco. El código del proyecto no se modificó.

### Cómo corre (`compose.yaml`)
```yaml
image: floci/floci:2.3.0              # versión fija, para que no cambie sola
ports: "127.0.0.1:4567:4566"          # puerto 4567 de tu PC → 4566 dentro del contenedor
environment:
  FLOCI_STORAGE_MODE: hybrid          # guarda en disco cada ~5 segundos
  FLOCI_STORAGE_PERSISTENT_PATH: /data
volumes: ./floci-data:/data           # esa carpeta es donde quedan los datos
```

- **Puerto 4567 y no 4566:** el 4566 ya lo usa otro proyecto tuyo.
- **`127.0.0.1`:** solo tu computador puede hablarle. Nadie en la red.
- **Modo `hybrid`:** los datos viven en memoria (rápido) pero se copian a
  `floci-data/` cada pocos segundos. Si apagas y prendes, **siguen ahí**.
  (El modo `memory` los perdería al apagar.)
- **Sin `docker.sock`:** el log de Floci avisa que no encuentra el socket de
  Docker. Es normal: solo lo necesitan servicios que no usamos (EC2, Lambda...).
  S3 y DynamoDB corren dentro del propio contenedor.

### Qué se probó de Floci (para no desconfiar sin motivo)
- Crear tablas con índices secundarios (GSI), incluidos los de proyección
  `KEYS_ONLY` (que solo devuelven las claves).
- Consultar por índice con rangos de fecha, orden ascendente y descendente, y
  paginación.
- Actualizaciones condicionales (`ConditionExpression`): falla igual que en AWS
  cuando la condición no se cumple.
- Leer y escribir archivos en S3.

Si alguna vez ves un error de DynamoDB que **no** pasa en dev, sospecha de Floci y
avisa: es un emulador, no AWS.

---

## 5. De dónde salen los datos (el sembrado)

Los datos de prueba viven en el repo `adr-sgaPipeline-datasync`, carpeta
`mockdata/`. **Sembrar** es cargarlos en Floci. Lo hace `scripts/seed.sh` en tres
pasos:

1. **`moto_setup.py`** crea las tablas y los buckets (carpetas raíz de S3):

   | Tabla | Clave | Índices |
   |---|---|---|
   | `adr-devs-sga-reclamaciones` | `id_reclamacion` | por estado+fecha, por NIT+fecha |
   | `adr-devs-sga-items` | `item_id` | por reclamación |
   | `adr-devs-sga-glosas` | `item_id` + `glosa_id` | por reclamación |

   Buckets: `adr-devs-sga-data` y `adr-devs-sga-bff-files-...`.
   (El nombre del script dice "moto" porque se hizo para otro emulador; sirve
   igual con Floci.)

2. **`upload_dynamo.py ... --clean --no-soportes`** carga los datos:
   - 489 reclamaciones, 13.240 ítems y 34.654 glosas en DynamoDB;
   - en S3: certificados, el **catálogo de códigos de glosa**
     (`catalogos/codigos-glosa.json`, 123 códigos) y la **configuración**
     (`config/auditores.json`, `config/simulacion.json`).
   - `--clean` **borra todo antes** de cargar (estado limpio).
   - `--no-soportes` omite los documentos PDF de soporte (por eso la sección
     Soportes no abre archivos).

3. **`asignar_auditor.py`** asigna tu usuario real (ver sección 8).

### Por qué `--clean` es seguro aquí
`--clean` borra tablas completas; contra dev sería un desastre. Lo evita
`scripts/env.sh` (sección 6): **no deja correr nada si el endpoint no es local**.

### Los escenarios
Cada escenario es un grupo de reclamaciones preparadas para mostrar un caso. Los
define `mockdata/build_scenarios.py` y los describe `mockdata/README.md`. Los que
más usamos:

| Escenario | Ids | Qué muestra |
|---|---|---|
| Jurídico por cruce, cero glosas | `2026205001`, `2026205002` | Cruce RNEC con hallazgo (víctima fallecida) |
| Cruce en error | `2026211001` | El cruce de siniestros no se pudo consultar |
| Financiero en turno | `2026204001`, `2026204002` | Glosas resueltas y pendientes |
| En validación del supervisor | `2026206001`, `2026206002` | Todo completado |
| Devuelta | `2026208001`, `2026208002` | Devuelta por el supervisor, con glosa resaltada |
| RG2 con glosa nueva | `2026209001` | Segunda ronda |
| Auditada y liquidada | `2026210001`..`003` | Con valores levantado y ratificado |
| Médico en turno | `2026203002` | Lo prepara `asignar_auditor.py` |

---

## 6. Las protecciones: `scripts/env.sh`

Todos los scripts empiezan cargando este archivo. Hace tres cosas importantes:

```bash
export AWS_ENDPOINT_URL="http://127.0.0.1:4567"   # habla con Floci
export AWS_ACCESS_KEY_ID=test                      # credenciales falsas
export AWS_SECRET_ACCESS_KEY=test
unset AWS_PROFILE AWS_SESSION_TOKEN               # olvida tu perfil real de AWS
```

Y define la función `exigir_floci`, que **corta el script** si:
- el endpoint no empieza por `http://127.0.0.1` o `http://localhost`, o
- Floci no responde.

Resultado: con estas protecciones, aunque te equivoques, el script no puede llegar
a tu AWS real. Para llegar a dev tendrías que querer hacerlo.

**Excepción consciente:** `bff.sh` y `smoke.sh` sí usan tu perfil real de AWS,
pero solo para **leer secretos** (las credenciales del login de prueba y las del
BFF). Nunca escriben en AWS real.

---

## 7. La API de datos local: `api.sh` y `run_api.py`

### Qué hace `api.sh`
Arranca `data-access-api` con estas variables:

| Variable | Valor | Por qué |
|---|---|---|
| `AWS_ENDPOINT_URL` | Floci | Lee y escribe en Floci |
| `AUDITORES_FUENTE` | `directorio` | La lista de auditores sale de `config/auditores.json` en vez de Keycloak (que devuelve 403 para ese servicio) |
| `ERROR_RATE` | `0` | Sin fallos aleatorios |

Además se niega a arrancar si el puerto 8081 ya está ocupado. (Antes pasó algo
engañoso: tu API de dev ocupaba el 8080 y su `/health` parecía ser el mío.)

### La trampa que descubrimos: `load_dotenv(override=True)`
El archivo `app/main.py` de la API tiene esta línea:

```python
load_dotenv(override=True)
```

`override=True` significa que **el archivo `.env` del repo gana sobre las
variables que tú pones en la terminal**. Por eso, aunque exportábamos
`AUDITORES_FUENTE=directorio`, la API leía `keycloak` del `.env` y respondía
"auditor no encontrado".

**Solución sin tocar el repo:** `scripts/run_api.py` desactiva esa carga antes de
importar la app:

```python
import dotenv
dotenv.load_dotenv = lambda *args, **kwargs: False   # anula la función
import uvicorn
uvicorn.run("app.main:app", ...)
```

- Un detalle de Python: al ejecutar un script por ruta, la carpeta actual no
  entra en el buscador de módulos. Por eso `run_api.py` agrega la carpeta de la
  API con `sys.path.insert(0, os.getcwd())`.
- **Consecuencia:** no hay recarga automática (`--reload`). Si cambias código del
  repo de la API, reinicia con `scripts/api.sh`.
- **Lo que sí sigue saliendo del `.env`:** los datos de Keycloak y los nombres de
  tablas (tienen menor prioridad, pero se leen si no hay otra cosa).

### Caché de 5 minutos
La API guarda en memoria los archivos de referencia (como el directorio de
auditores) durante 300 segundos (`REFERENCIA_CACHE_TTL`). Por eso, si cambias
`config/auditores.json` en Floci, **hay que reiniciar la API** para que lo vea.
`asignar_auditor.sh` ya lo hace solo.

### El login
El front pide un token a Keycloak. La API local valida esos tokens contra el
Keycloak real (descarga sus claves públicas). Por eso **entras con tu usuario de
siempre**: nada de usuarios falsos.

---

## 8. Tu usuario (en los ejemplos, `auditor.dop`)

Los datos de prueba asignan trabajo a auditores ficticios (`aud.medico.dop@...`).
Tú inicias sesión con tu propio correo (en los ejemplos de este documento,
`auditor.dop@adres.gov.co`), así que tu bandeja saldría vacía. `scripts/asignar_auditor.sh` lo arregla:

1. Agrega a `auditor.dop` al directorio (`config/auditores.json` en Floci).
2. En todas las reclamaciones donde el **Médico** era `aud.medico.dop`, pone a
   `auditor.dop`. Son 13 (el campo es
   `respuesta_glosa.componentes.medico.auditor`).
3. Deja a `auditor.dop` **en turno** en `2026203002`: cierra Jurídico y
   Financiero y pone `componente_actual = MEDICO`.
4. Reinicia la API para que vea el directorio nuevo.

Es **idempotente**: puedes correrlo varias veces sin duplicar nada. Y `seed.sh` lo
vuelve a correr, así que un `reset.sh` no te quita la asignación.

**Por qué `2026205001` no aparece en tu bandeja:** en esa reclamación el Médico no
aplica (no tiene auditor Médico), así que no hay nada que reasignar. Su gemela
`2026205002` sí aparece.

**El correo debe coincidir exactamente** con el campo `email` del token de
Keycloak. Si no coincide, la bandeja sale vacía.

Tu correo y nombre se leen de `config.local` (`SGA_MI_CORREO`, `SGA_MI_NOMBRE`; el
archivo se crea con `scripts/setup.sh` y no se sube al repo). Para otro puntual:
`scripts/asignar_auditor.sh --correo otro@adres.gov.co --nombre "Nombre"`.

---

## 9. El BFF local: `bff.sh`

Levanta tu BFF (carpeta `adr-sgaReclamation-bff`) en el puerto 8002, con una sola
diferencia: `RECLAMATIONS_API_URL=http://localhost:8081`, o sea, que le pregunta a
la API local y no a dev.

**Cómo se cambia sin editar su `.env`:** el BFF usa `pydantic-settings`, que da
prioridad a las variables de entorno sobre el archivo `.env`. Así que basta con
exportar la variable al lanzarlo. (El BFF sí respeta eso; la API de datos no, ver
sección 7.)

Lo demás (Keycloak, secretos, soportes) sigue saliendo de su `.env` y de tu AWS
real, por eso necesita `aws sso login`.

Corre en el 8002 y no en el 8000 porque tu BFF de dev suele ocupar el 8000.

---

## 10. El proxy: `proxy/proxy.py`

### Por qué existe
El swagger (la lista de rutas) del BFF describe **56 rutas**, pero el BFF
desplegado tiene **38**. Faltan, entre otras: `/cruces`, `/siguiente-paso`,
`/historial`, `/devolver`, `/marcar-auditadas` y las acciones de
`glosas-reclamacion`. Además, `levantar-parcial` y "crear glosa" existen pero con
un cuerpo viejo que la API ya no acepta.

El front de esas tareas ya espera las rutas completas. Para poder verlo, el proxy
las manda **directo a la API de datos**, que sí las tiene.

### Cómo decide a dónde va cada petición
Al inicio del archivo hay una lista de pares (método, ruta). Cada petición se
compara con la lista:

```python
RUTAS_DATA_API = [
  ("GET",  r"^/api/v1/reclamaciones/[^/]+/cruces$"),
  ("POST", r"^/api/v1/reclamaciones/[^/]+/siguiente-paso$"),
  ...
]
```

- Si coincide → va a la **API de datos** (`:8081`).
- Si no → va al **BFF** (`:8002`).

(`[^/]+` significa "cualquier texto sin barras", o sea, el id de la reclamación.)

Cada respuesta trae la cabecera `X-Proxy-Destino: bff` o `data-api`, y
`logs/proxy.log` muestra una línea por petición.

### Lo que hace el proxy "por el BFF" en las rutas directas
El BFF real hace dos cosas que la API de datos no hace sola. El proxy las imita:

1. **Agrega el `action`.** Las acciones (levantar, ratificar...) necesitan saber
   *quién* las hace: `{id, usuario, correo, rol, timestamp}`. El BFF lo arma desde
   el token. El proxy hace lo mismo: decodifica el cuerpo del token (sin
   verificarlo, porque la API lo verifica después) y arma el `action`. El rol sale
   del claim `groups`: `SGA-Auditores` → `AUDITOR`, `SGA-Supervisores*` →
   `SUPERVISOR`, `SGA-Financieros` → `DIRECTOR`.
2. **Traduce los errores.** La API de datos responde `{codigo, mensaje}`; el BFF
   responde `{error: {code, httpStatus, message, ...}, detail}`. El front solo
   entiende el segundo (por ejemplo, para mostrar "No es su turno" en un 409). El
   proxy convierte uno en el otro.

### CORS
El navegador bloquea llamadas a otro servidor salvo que este lo permita. El proxy
responde con `Access-Control-Allow-Origin` para `localhost` en los puertos 5173,
5174 y 5175. También acepta las cabeceras raras que el front agrega a sus
peticiones.

### `PROXY_ACTUAR_COMO`
Variable opcional. Si la defines con un correo de auditor, las acciones que van a
la API de datos se firman como ese auditor (rol `AUDITOR`), sin importar con qué
usuario entraste. **Solo afecta al API**: los botones del front siguen
dependiendo de tus permisos reales.

### Limitación importante
**El proxy imita al BFF, no es el BFF.** Cuando el BFF implemente una ruta, hay
que **borrarla de la lista** del proxy y volver a probar contra el BFF real: podría
transformar respuestas o usar otros códigos de error.

---

## 10b. Mocks: responder sin BFF ni capa de datos

Hasta aquí el proxy **reenvía**. Pero también puede **responder él mismo** con
archivos JSON (mocks). Está en `proxy/mocks_engine.py` y se activa con la variable
`PROXY_MODO` (o con `scripts/mock.sh`).

### Los tres modos

| Modo | Orden de decisión |
|---|---|
| `normal` | Ignora los mocks. Lista fija → capa de datos; el resto → BFF. |
| `mock-primero` | 1) ¿Hay un mock para esta petición? Lo uso. 2) Si no, como `normal`. |
| `solo-mock` | 1) ¿Hay un mock? Lo uso. 2) Si no, respondo **501** y no llamo a nadie. |

En `solo-mock` el proxy hizo **0 llamadas salientes** al probarlo: no necesita
BFF, ni API de datos, ni Floci. Solo el login sigue necesitando internet, porque
va directo a Keycloak desde el navegador y no pasa por el proxy.

### Qué es un mock
Un archivo `.json` en `proxy/mocks/` que dice "cuando pidan ESTO, responde AQUELLO":

```json
{
  "metodo": "GET",
  "ruta": "/api/v1/reclamaciones/{id}/cruces",
  "cuando": { "id": "2026205001" },
  "estado": 200,
  "demora_ms": 800,
  "cuerpo": { "idReclamacion": "{id}", "cruces": [] }
}
```

| Campo | Para qué |
|---|---|
| `ruta` | La ruta. `{id}` o cualquier `{nombre}` significa "cualquier valor". |
| `cuando` | Opcional. Limita a valores concretos de esas variables (solo el id `2026205001`). |
| `consulta` | Opcional. Exige un query string exacto (`page=1&limit=10`). |
| `estado` | Código HTTP. Con `409` o `500` simulas errores. |
| `demora_ms` | Espera antes de responder: sirve para ver los cargadores y esqueletos. |
| `cuerpo` | Lo que se responde. Cualquier `{id}` dentro del texto se reemplaza por el valor real de la ruta. |

**Cuál gana si varios coinciden:** primero los escritos a mano, luego los más
específicos (con `cuando` o `consulta`), luego los genéricos.

### De dónde salen los mocks
1. **Grabados.** Con `scripts/grabar.sh`, cada GET exitoso que pasa por el proxy
   se guarda en `proxy/mocks/grabados/`. Navegas una vez por el front con todo
   encendido y después lo reproduces sin nada. Seguridad: solo graba si el BFF y la
   API son locales (nunca guarda datos de dev), y no graba `/presign`, `/auth` ni
   `/embed-url`.
2. **A mano.** Copia un ejemplo de `proxy/mocks/_ejemplos/`. Las carpetas que
   empiezan por `_` se ignoran, por eso los ejemplos están inactivos.

Los archivos se **recargan solos** al cambiarlos; no hay que reiniciar el proxy.

### Límites a tener en cuenta
- **Un mock grabado sin query responde a cualquier query.** Si grabaste
  `/cruces` sin parámetros y luego el front pide `/cruces?otra=2`, recibe la
  respuesta grabada. Útil como respaldo; confuso en listas con paginación.
- **Solo se graban lecturas (GET).** Las acciones que escriben (levantar,
  ratificar...) no se graban: en `solo-mock` necesitan un mock escrito a mano, o
  responden 501. Tampoco cambian nada: un mock no guarda estado.
- **Un mock no recuerda lo que hiciste.** Si "levantas" una glosa y recargas, el
  mock devuelve lo mismo que antes. Para estado real hay que usar Floci.
- **Una grabación envejece.** Si cambia el dato o el contrato, vuelve a grabar.
- **Las grabaciones pueden tener datos de prueba personales** (nombres, documentos
  ficticios de los escenarios). `proxy/mocks/grabados/` no se sube a ningún repo
  porque esta carpeta no es un repositorio; no la copies a uno.

### Cuándo usar cada modo
| Quiero... | Modo |
|---|---|
| Ver todo con datos reales de prueba | `normal` |
| Probar un error 409 o una respuesta lenta en una pantalla | `mock-primero` con un mock a mano |
| Trabajar en el front sin levantar nada más (tren, sin AWS, CI) | `solo-mock` con grabaciones |
| Una pantalla cuyo backend aún no existe | `mock-primero`/`solo-mock` con un mock a mano |

`GET http://127.0.0.1:8010/_proxy/estado` muestra el modo actual y cuántos mocks
hay cargados.

---

## 11. El front y el puerto 5173

El front lee la dirección del backend de `VITE_API_BASE_URL`. Para este entorno:

```bash
VITE_API_BASE_URL=http://localhost:8010 npm run dev -- --port 5173 --strictPort
```

- **La variable va en la misma línea**, antes de `npm`. Si la pones aparte sin
  `export`, `npm` no la ve y el front usa la del archivo `.env` (el BFF de dev).
  Esto nos pasó.
- **Vite da prioridad a las variables de la terminal** sobre el `.env`. No hay que
  editar nada.
- **Tiene que ser el puerto 5173.** El Keycloak de dev solo acepta
  `http://localhost:5173/*` como dirección de retorno del login (probado: 5174,
  5175 y `127.0.0.1:5173` dan "Parámetro no válido: redirect_uri"). Si usas otro
  puerto, Keycloak te manda al sitio desplegado y verás datos de dev sin darte
  cuenta.
- **`--strictPort`** hace que Vite falle si el 5173 está ocupado, en lugar de
  saltarse al siguiente puerto sin avisar.
- Usa **`localhost`**, no `127.0.0.1`.

**Cómo comprobar a qué backend apunta tu front:**
```bash
curl -s http://127.0.0.1:5173/app/keys/index.ts | grep -o '"VITE_API_BASE_URL": "[^"]*"'
```
Debe decir `http://localhost:8010`. Si dice `https://visor.dev...`, estás mirando
dev.

---

## 12. Recorrido de una petición real

**Caso: abres la bandeja "Asignadas" como `auditor.dop`.**

1. El front pide `GET /api/v1/auditores/auditor.dop@adres.gov.co/reclamaciones` a
   `http://localhost:8010`, con tu token en la cabecera.
2. El proxy ve que esa ruta no está en su lista → la manda al **BFF** (`:8002`).
3. El BFF valida tu token contra Keycloak y reenvía la pregunta a la **API de
   datos** (`:8081`).
4. La API de datos comprueba que `auditor.dop` existe (en el directorio de
   Floci), busca en DynamoDB las reclamaciones donde su componente tiene
   `auditorId = auditor.dop@adres.gov.co`, calcula para cada una el "estado de
   trabajo" (en turno / en espera / completada) y responde.
5. La respuesta vuelve por el mismo camino hasta tu pantalla.

**Caso: abres el detalle de `2026205002` (cruces).**

1. El front pide `GET /api/v1/reclamaciones/2026205002/cruces`.
2. El proxy la reconoce en su lista → va **directo a la API de datos**.
3. La API lee el campo `cruces` del documento en DynamoDB, lo convierte de
   `snake_case` a `camelCase` y responde `{idReclamacion, cruces: [...]}`.
4. El proxy agrega `X-Proxy-Destino: data-api`. El componente `CruceHallazgos`
   (tarea T-23) pinta la tabla.

---

## 13. Los scripts, uno por uno

| Script | Qué hace | Cuándo usarlo |
|---|---|---|
| `env.sh` | Variables comunes y protecciones. No se ejecuta; lo cargan los demás. | Nunca directo |
| `up.sh` | Arranca Floci (`docker compose up`). Si no hay datos, llama a `seed.sh`. | Al empezar |
| `seed.sh` | Crea tablas y recarga **todo desde cero** (`--sin-clean` solo agrega). | Datos dañados o primera vez |
| `reset.sh` | Lo mismo que `seed.sh`. | Tras probar acciones que escriben |
| `asignar_auditor.sh` / `.py` | Asigna tu usuario (de `config.local`) como Médico y reinicia la API. | Si cambias de usuario |
| `setup.sh` | Primer día: crea `.venv`, instala dependencias y `config.local`. | Una vez |
| `doctor.sh` | Revisa qué falta en tu máquina. Solo lee. | Si algo no arranca |
| `api.sh` | Arranca la API de datos (con `--fondo` queda en segundo plano). | Al empezar |
| `run_api.py` | Lanzador que anula `load_dotenv(override=True)`. | Lo usa `api.sh` |
| `bff.sh` | Arranca el BFF apuntando a la API local. | Al empezar |
| `proxy.sh` | Arranca el proxy. | Al empezar |
| `mock.sh` | Reinicia el proxy en `solo-mock`, `mock-primero` o `normal`. | Para usar mocks (sección 10b) |
| `grabar.sh` | Reinicia el proxy grabando cada GET exitoso como mock. | Para crear mocks (sección 10b) |
| `visual.sh` | Hace `up` + `api` + `bff` + `proxy` de una vez. | **Lo normal** |
| `smoke.sh` | 7 pruebas GET para comprobar que todo responde. | Tras arrancar |
| `estado.sh` | Muestra qué corre y hacia dónde apunta. | Para diagnosticar |
| `down.sh` | Detiene proxy, BFF, API y Floci. Los datos se conservan. | Al terminar |

Los procesos en segundo plano guardan su número de proceso (PID) en
`logs/*.pid` y su salida en `logs/*.log`. `down.sh` usa esos PID para apagarlos.

### `smoke.sh`: qué comprueba
1. `health` de la API (versión y `errorRate`).
2. `auditores`: lista los tres componentes.
3. `catálogo jurídico`: devuelve códigos.
4. `bandeja RG`: devuelve reclamaciones.
5. `cruces` de `2026205001`: RNEC con hallazgo.
6. `cruces` de `2026211001`: siniestros en ERROR.
7. `historial` de `2026210003`.

Obtiene un token iniciando sesión en la API local con el usuario de prueba que
está en AWS Secrets Manager. **Nunca imprime** usuario, clave ni token.

---

## 14. Estructura de la carpeta

```
entorno-local-floci/
├── README.md          Guía rápida de uso
├── COMO-FUNCIONA.md   Este documento
├── compose.yaml       Define el contenedor de Floci
├── config.local.example  Plantilla de tu configuración personal
├── config.local       Tu configuración (no se sube)
├── .gitignore         Ignora .venv/, floci-data/, logs/, config.local y grabados
├── scripts/           Todo lo que se ejecuta (sección 13)
├── proxy/
│   ├── proxy.py       El proxy
│   ├── mocks_engine.py   Motor de mocks
│   └── mocks/         Mocks (*.json), grabados/ y _ejemplos/
├── .venv/             Python 3.12 propio, con las librerías (no se sube)
├── floci-data/        Los datos de Floci (no se sube)
└── logs/              Logs y PID de lo que corre en segundo plano
```

**Por qué esta carpeta está fuera de los repos del equipo:** es una herramienta
tuya. Así no ensucia `adr-sgaReclamation-front`, el BFF ni `datasync`, y no se
sube por accidente. No es un repositorio git.

**Por qué un `.venv` propio con Python 3.12:** tu Python del sistema es 3.14, muy
nuevo para algunas librerías. `uv` (una herramienta que instala Pythons) creó un
entorno virtual aislado. Un entorno virtual es una carpeta con su propio Python y
sus propias librerías, para no mezclarlas con las del sistema.

---

## 15. Qué es real y qué es de mentira

| Componente | ¿Real o local? |
|---|---|
| Datos (reclamaciones, ítems, glosas) | **Local** (Floci) |
| Catálogo de códigos, directorio de auditores | **Local** (Floci) |
| Lógica de negocio (cruces, turnos, glosas) | **Real** (el mismo código de dev, versión 1.31.0) |
| Login y tokens | **Real** (Keycloak de dev) |
| Soportes (PDF) | **No hay** (se cargaron con `--no-soportes`) |
| Secretos y archivos del BFF | **Reales** (tu AWS, solo lectura) |
| Cruces (RNEC, pólizas, siniestros) | **Simulados**: la API devuelve los que están guardados en el dato |
| Asignador automático, liquidación | **Simulados** por la API a partir de datos y de `config/simulacion.json` |

Lo que escribas (levantar, ratificar, crear glosa...) **solo se guarda en
Floci**. `scripts/reset.sh` lo deja como al principio.

---

## 16. Cosas que pueden salir mal

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El front muestra datos de dev | Lo arrancaste sin `VITE_API_BASE_URL` | Relanzar con la variable en la misma línea y comprobar con el `curl` de la sección 11 |
| Keycloak: "Parámetro no válido: redirect_uri" | Puerto distinto del 5173 | Usar el 5173 |
| Quedas en `visor.dev.adr...` | Entraste al sitio desplegado, no a tu front | Abrir `http://localhost:5173` |
| Bandeja Asignadas vacía | El correo del token no es `auditor.dop@adres.gov.co`, o la API local no se reinició | `scripts/asignar_auditor.sh` |
| "Auditor no encontrado" | La API tomó `AUDITORES_FUENTE=keycloak` del `.env` | Arrancarla con `api.sh` (usa `run_api.py`) |
| `ABORTADO: el puerto X ya está en uso` | Otro proceso ocupa el puerto | `scripts/estado.sh`; cambiar con `DATA_API_PUERTO`, `BFF_PUERTO`, `PROXY_PUERTO` |
| El BFF no arranca o da errores de AWS | Venció la sesión de AWS | `aws sso login --profile ADRES-TEST-Medicalaudit1` |
| 403 en una petición al BFF | A tu usuario le falta un permiso en el BFF | Ver `logs/proxy.log` y `logs/bff.log` |
| `smoke.sh` no puede leer el secreto | Sesión de AWS vencida | `aws sso login ...` |
| Floci no responde | El contenedor está apagado | `scripts/up.sh` |
| Quieres datos limpios | Probaste acciones que escriben | `scripts/reset.sh` |

**Dónde mirar:**
- `logs/proxy.log`: a dónde fue cada petición (`-> bff` o `-> data-api`) y el estado.
- `logs/bff.log` y `logs/data-api.log`: el detalle de cada servicio.
- `docker logs sga-floci`: el log del emulador.
- `scripts/estado.sh`: resumen rápido.

---

## 17. Cómo extenderlo

**Agregar una ruta nueva al proxy** (porque el BFF aún no la tiene): agrega una
línea a `RUTAS_DATA_API` en `proxy/proxy.py`, por ejemplo
`("GET", rf"^/api/v1/reclamaciones/{_ID}/mi-ruta$")`, y reinicia el proxy
(`kill $(cat logs/proxy.pid)` y `scripts/proxy.sh --fondo`).

**Quitar una ruta del proxy** (porque el BFF ya la implementó): bórrala de la
lista y vuelve a probar el flujo completo.

**Crear un escenario nuevo:** se define en `mockdata/build_scenarios.py` del repo
`datasync` (ese repo es del equipo; el cambio iría con su revisión). Luego
`scripts/seed.sh`.

**Probar con otro usuario:** `scripts/asignar_auditor.sh --correo ...`. Si el
usuario es de otro componente (Jurídico o Financiero), habría que extender
`asignar_auditor.py`, que hoy solo reasigna el componente Médico.

**Actuar como otro auditor solo en el API:**
`PROXY_ACTUAR_COMO=aud.juridico.dop@adres.gov.co scripts/proxy.sh --fondo`.

---

## 18. Limitaciones conocidas

- **El proxy no es el BFF.** Probar contra el BFF real cuando exista cada ruta.
- **Sin soportes:** los documentos no abren.
- **Sin `--reload` en la API de datos** (por `run_api.py`).
- **Tus permisos mandan en el front.** Con `auditor.dop` (rol Auditor, componente
  Médico) los botones que dependen de turno o componente pueden salir
  deshabilitados. Eso lo explicará T-26 cuando exista.
- **Contraseñas en el repo:** `mockdata/simulate_config.json` tiene contraseñas de
  usuarios de prueba en texto plano. No se usaron aquí. Conviene avisar al equipo.
- **Floci es un emulador**, no AWS; diferencias raras son posibles.
- **El Keycloak de dev solo acepta el puerto 5173** para el login.
- **Dependes de la sesión de AWS** para el BFF y `smoke.sh`.
