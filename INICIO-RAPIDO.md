# Inicio rápido: instalar y correr el entorno local

Para quien **ya tiene los demás repos configurados** (front, BFF y datasync, con
sus `.env`) y va a instalar esta herramienta por primera vez.

## Comando para correr (cada vez que lo uses)

```bash
# Terminal 1: backend local
cd ~/Documentos/SGA/entorno-local-floci && scripts/visual.sh

# Terminal 2: front, siempre en el puerto 5173
cd ~/Documentos/SGA/adr-sgaReclamation-front
VITE_API_BASE_URL=http://localhost:8010 npm run dev -- --port 5173 --strictPort
```

Abre **http://localhost:5173** (con `localhost`, no `127.0.0.1`). La variable
`VITE_API_BASE_URL` va **en la misma línea** que `npm`: si la pones aparte, el
front usa su `.env` y habla con dev.

---

## Instalación (una sola vez)

### 1. Antes de empezar, ten instalado
| Herramienta | Para qué | Comprobar |
|---|---|---|
| Docker | Corre Floci (la AWS local) | `docker ps` sin `sudo` |
| `uv` | Crea el Python 3.12 del entorno | `uv --version` |
| AWS CLI | Leer secretos | `aws --version` |
| Node | Correr el front | `node --version` |

Instalar `uv` si falta: `curl -LsSf https://astral.sh/uv/install.sh | sh`

### 2. Clona esta herramienta junto a los demás repos
Debe quedar **en la misma carpeta** que los otros, con este nombre exacto:

```bash
cd ~/Documentos/SGA          # la carpeta donde ya están tus repos
git clone https://github.com/faidertrujillo-blend/adr-sga-entorno-local.git entorno-local-floci
```

El repositorio es público: no hace falta invitación. La carpeta debe quedar así:

```
SGA/
├── adr-sgaPipeline-datasync/
├── adr-sgaReclamation-bff/
├── adr-sgaReclamation-front/
└── entorno-local-floci/        ← este
```

### 3. Prepara el entorno
```bash
cd entorno-local-floci
scripts/setup.sh
```
Crea el Python 3.12 con sus librerías (dentro de esta carpeta) y el archivo
`config.local`. No instala Docker, `uv`, AWS CLI ni Node.

### 4. Pon tu correo y tu nombre
```bash
nano config.local
```
```bash
SGA_MI_CORREO="tu.correo@adres.gov.co"   # el email EXACTO de tu usuario de Keycloak
SGA_MI_NOMBRE="Tu Nombre"
```
Si el correo no coincide con el de tu token, la bandeja "Asignadas" sale vacía.
Este archivo es personal y no se sube al repositorio.

### 5. Inicia sesión en AWS
```bash
aws sso login --profile ADRES-TEST-Medicalaudit1
```
La necesita el BFF para leer secretos. Si tu perfil tiene otro nombre, usa
`PERFIL_REAL=tu-perfil` antes de los scripts.

### 6. Verifica que todo esté listo
```bash
scripts/doctor.sh
```
Solo revisa (no instala nada). Lo marcado con ✗ es imprescindible; arréglalo
según lo que indique y vuelve a correrlo.

### 7. Levanta todo
```bash
scripts/visual.sh
```
La primera vez carga los datos de prueba (unos 30 segundos). Después levanta
Floci, la API de datos (:8081), el BFF (:8002) y el proxy (:8010).

### 8. Comprueba que responde
```bash
scripts/smoke.sh
```
Debe terminar en `7/7 pruebas OK`.

### 9. Abre el front
Usa el comando de la sección "Comando para correr". Antes, **detén cualquier otro
`npm run dev`** que tengas en el 5173: el login de dev (Keycloak) solo acepta ese
puerto.

---

## Uso diario

| Quiero... | Comando (desde `entorno-local-floci`) |
|---|---|
| Levantar todo | `scripts/visual.sh` |
| Ver qué corre y hacia dónde apunta | `scripts/estado.sh` |
| Apagar todo (los datos se conservan) | `scripts/down.sh` |
| Volver a los datos iniciales | `scripts/reset.sh` |
| Ver a dónde va cada llamada | `tail -f logs/proxy.log` |

Lo que pruebes (crear glosas, ratificar...) **solo se guarda en tu Floci local**;
no toca dev.

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| Bandeja "Asignadas" vacía | Revisa que `SGA_MI_CORREO` sea el email exacto de tu Keycloak; luego `scripts/asignar_auditor.sh` |
| El front muestra datos de dev | Lo arrancaste sin `VITE_API_BASE_URL=http://localhost:8010` en la misma línea |
| "Parámetro no válido: redirect_uri" al iniciar sesión | Usa el puerto 5173 y `localhost` |
| El BFF o `smoke.sh` dan errores de AWS | Se venció la sesión: `aws sso login --profile ADRES-TEST-Medicalaudit1` |
| "puerto ocupado" | `scripts/estado.sh` muestra qué lo usa |
| Cualquier otra cosa | `scripts/doctor.sh` y los logs en `logs/` |

Más detalle de cómo funciona cada pieza: `COMO-FUNCIONA.md`. Referencia
completa de comandos: `README.md`.
