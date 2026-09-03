# xFlare · Scratch Pack v0.1

> **Documento histórico.** Este era el inventario del pack inicial que se copió
> a la raíz del repo al arrancar el proyecto. Ya está todo integrado; se
> conserva como referencia de procedencia.

Contenido generado para alimentar a Claude Code. **Copiar el contenido de este
paquete a la raiz del repo `xFlare/`**, fusionando con lo que ya existe
(`CLAUDE.md`, `PLAN.md`, `docs/DECISIONS.md`).

```
docs/NOTATION.md              Especificacion de la notacion XFN
docs/MATRIX_MAPPING.md        Mapeo con la Periodic Matrix + AVISO LEGAL
docs/CURRICULUM.md            El gym: niveles, sesiones, scoring
docs/DECISIONS.md             ADR-014+ (ya fusionados; en su dia iban aparte)

data/primitives/*.json        10 patrones de mano + 16 de fader
data/scratches/library-v0.1.json   25 scratches compilados
data/curriculum/*.json        6 niveles + 18 ejercicios
data/schema/*.json            JSON Schema de scratch y ejercicio

tools/xfn_core.py             Motor: primitivas, compositor, renderizador
tools/xfn_build.py            Regenera la libreria desde tools/catalog.json
tools/xfn_render.py           CLI: renderiza un scratch a SVG
tools/catalog.json            El catalogo editable (anadir scratch = anadir linea)

preview/xfn_preview.png       Vista de 6 scratches en notacion XFN
preview/svg/*.svg             Los 25 scratches renderizados
```

## Como usarlo

Las herramientas en `tools/` son **Python de andamiaje**, no forman parte de la app.
Sirven para disenar y validar la libreria en el escritorio. La app macOS lee
directamente los JSON de `data/` y reimplementa el renderizado en SpriteKit
siguiendo `docs/NOTATION.md` §4.

Anadir un scratch nuevo:

1. Anadir una linea a `tools/catalog.json`.
2. Si necesita un gesto nuevo, anadir el patron a `xfn_core.py`.
3. `python3 tools/xfn_build.py`
4. `python3 tools/xfn_render.py mi-scratch preview/svg/mi-scratch.svg`

## Prompt sugerido para arrancar con Claude Code

> Lee `CLAUDE.md`, `PLAN.md`, `TODO.md`, `docs/DECISIONS.md`, `docs/NOTATION.md` y
> `docs/CURRICULUM.md`. No escribas codigo todavia. Dime que has entendido del
> proyecto en 10 lineas, senala las contradicciones que encuentres entre documentos
> y proponme la primera tarea del bloque B0 con su criterio de aceptacion.

Licencia: GPL-3.0-only, igual que el resto de xFlare.
