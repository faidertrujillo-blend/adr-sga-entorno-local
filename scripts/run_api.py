"""Lanza data-access-api respetando las variables de entorno de scripts/env.sh.

`app/main.py` hace `load_dotenv(override=True)`: el `.env` del repo pisa las
variables que exportamos (AUDITORES_FUENTE=directorio, etc.) y la API volvería a
consultar Keycloak. Este lanzador desactiva esa carga antes de importar la app,
sin modificar el repo. Pydantic sigue leyendo el `.env` para lo que NO está en el
entorno (KEYCLOAK_*, nombres de tablas...), con menor prioridad que el entorno.

Uso: python run_api.py PUERTO [--reload]   (desde la carpeta data-access-api)
"""

import os
import sys

# Al ejecutar un script por ruta, sys.path[0] es su carpeta y no la actual:
# se agrega la carpeta de data-access-api para poder importar `app`.
sys.path.insert(0, os.getcwd())

import dotenv

dotenv.load_dotenv = lambda *args, **kwargs: False  # noqa: E731

import uvicorn  # noqa: E402

puerto = int(sys.argv[1])
recargar = "--reload" in sys.argv[2:]
if recargar:
    # El proceso de recarga importa de nuevo la app y perdería el parche.
    sys.exit("--reload no es compatible con este lanzador; reinicia con scripts/api.sh.")
uvicorn.run("app.main:app", host="127.0.0.1", port=puerto)
