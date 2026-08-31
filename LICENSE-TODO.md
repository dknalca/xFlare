# LICENSE — estado

**Hecho (B0.3 + ADR-030, 2026-08-31):**

- [x] `LICENSE` contiene el texto oficial e íntegro de la **GNU GPL v3**,
      descargado de la fuente canónica:
      `curl -o LICENSE https://www.gnu.org/licenses/gpl-3.0.txt`
      Empieza por "GNU GENERAL PUBLIC LICENSE / Version 3, 29 June 2007" (674 líneas).
- [x] El proyecto es **GPL-3.0-only** porque xwax pasó a GPL-3.0 en su v1.8 y
      vendorizamos la 1.10 (ADR-030). ADR-003 corregido en consecuencia.
- [x] Cabecera de licencia en cada fichero fuente propio: línea
      `SPDX-License-Identifier: GPL-3.0-only` en todos los `.swift`, `.c` y `.h`
      de `Sources/` y `Tests/`, en `Package.swift` y en `tools/*.py`.
- [x] Los ficheros de xwax en `Sources/CXFTimecode/vendor/xwax/` están **intactos**,
      con sus avisos de copyright (c) Mark Hills y de licencia GPLv3 originales.
      No llevan la línea `SPDX` propia de xFlare. Ver `docs/TIMECODE.md`.
- [x] El README cita xwax en «## Atribuciones» y «## Licencia» como GPL-3.0-only.

**Nada pendiente.**
