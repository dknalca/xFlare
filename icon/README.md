# Icono de xFlare

Motivo: el **cap de un crossfader visto en 2D** (planta), apoyado sobre la ranura
del fader. El cap vivo va en el acento del sistema de diseño (`#34E1C4`, "tu
fader" en `docs/UI_DESIGN.md` §2); detrás, translúcido, el cap **fantasma** = el
objetivo. Los grises y el fondo salen de los mismos tokens.

## Ficheros

| Fichero | Qué es | ¿Se versiona? |
|---|---|---|
| `xflare.svg` | **Fuente.** Editar aquí. 1024×1024, formas geométricas puras. | sí |
| `build-icns.sh` | Genera `.icns` + PNG master. Sin dependencias (usa `qlmanage` + `iconutil` del sistema). | sí |
| `xflare.icns` | Salida para el bundle de la app. | sí (pequeño, evita regenerar) |
| `xflare-1024.png` | Master rasterizado, para previews y la ficha de Homebrew/README. | sí |
| `xflare.iconset/` | Intermedio de `iconutil`. | no (`.gitignore`) |

## Regenerar

```sh
./icon/build-icns.sh
```

Rasteriza el SVG con QuickLook a 1024 px y arma el `.icns` reduciendo ese master
a los 10 tamaños del *iconset* de macOS con `sips`. También deja una copia en
`preview/xflare-icon.png`.

## Dónde se usa

`make app` copia `xflare.icns` a `xFlare.app/Contents/Resources/` y pone
`CFBundleIconFile` en el `Info.plist`. Si el `.icns` no existe, `make app` llama
a `build-icns.sh` solo.

Cuando exista el proyecto Xcode de verdad (cáscara que empaqueta `XFApp`, B11+),
el icono irá como `AppIcon.appiconset`; el SVG sigue siendo la fuente.

## Ajustes rápidos sobre el SVG

- **Quitar el cap fantasma:** borrar el `<path>` con `fill="#7A8794"`.
- **Menos cintura en el cap:** acercar los puntos de control de las curvas `Q`
  laterales (`674`→`684` en el lado derecho, `510`→`500` en el izquierdo).
- **Otro encuadre de la placa:** el `<rect>` de fondo (`x/y/width/height/rx`).
