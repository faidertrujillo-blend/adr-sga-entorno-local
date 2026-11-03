# Mocks del proxy

Cada archivo `.json` de esta carpeta es una respuesta simulada. Se usan cuando el
proxy corre en modo `mock-primero` o `solo-mock` (ver `../mocks_engine.py` y
`COMO-FUNCIONA.md`).

- `*.json` aquí: escritos a mano. Tienen prioridad.
- `grabados/`: respuestas reales grabadas con `scripts/grabar.sh`.
- `_ejemplos/`: ejemplos inactivos (las carpetas que empiezan por `_` se ignoran).
  Cópialos aquí para activarlos.
