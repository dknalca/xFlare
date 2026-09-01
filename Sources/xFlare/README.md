# `xFlare` — ejecutable de la app

Cáscara fina: monta `AppModel` y `AppRootView` de **XFApp** y ya. Toda la lógica
vive en los módulos SPM.

## Ejecutar

```
make run          # swift run xFlare (dev, lee data/ y profiles/ del repo)
make app          # empaqueta xFlare.app en la raiz, autocontenido y firmado ad-hoc
```

`swift run` es CLI puro (compila + ejecuta un binario normal); **no** usa XCTest.
Desde Xcode: abre `Package.swift`, elige el esquema **xFlare**, Run.

`make app` copia `data/` y `profiles/` a `Contents/Resources/` (los lee
`BundleContentLoader`) y firma ad-hoc (`codesign -s -`) para que arranque en
Apple Silicon. Sin notarizar: la 1a vez, clic derecho > Abrir. Es B12a; falta
solo el DMG (`hdiutil`) y el binario universal para publicar en Releases.

## Qué hace

- `AppModel.boot()` carga el catálogo (`data/scratches/library-v0.1.json`,
  `data/curriculum/*.json`) y los perfiles (`profiles/*.conf`), abre la base
  SQLite en *Application Support*, y crea el motor de audio (`EngineHandle`).
- `AppRootView` pinta la barra de navegación y la pantalla actual según
  `AppModel.screen`: Home (matriz + racha), Librería, Mi mesa, Ajustes,
  Calibración, Progreso, Resultados, Práctica, Modo libre.
- Si algo falla al arrancar, la ventana abre en `.error(...)` y lo dice.

## Límites conocidos (para B12 / hardware)

- **Contenido** (`data/`, `profiles/`): el `@main` elige el loader. Si el bundle
  trae el catálogo → `BundleContentLoader` (`Contents/Resources/`, lo pone
  `make app`). Si no (`swift run` en dev) → `RepoContentLoader` (repo, vía
  `#filePath`).
- **Práctica**: hay modo rudimentario jugable con trackpad/teclado (mueve el
  plato, suena el scratch + base instrumental, medidor de nivel, volúmenes por
  ejercicio). El **bucle de sesión + scoring en vivo** (series, cuenta atrás,
  `XFEngine`+`XFAnalysis`) sigue pendiente y necesita la captura de audio real.
- **Ajustes** se persisten en un plist local (`UserDefaults` de suite
  `app.xflare.settings`), no en la BD. Un accesor de la tabla `setting` de
  `XFPersistence` sigue pendiente (aditivo) para unificarlo.
- Para publicar en Releases falta: binario **universal** y el **DMG**
  (`hdiutil`). Notarización + Homebrew = B12b (ADR-037).
