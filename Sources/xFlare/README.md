# `xFlare` — ejecutable de la app

Cáscara fina: monta `AppModel` y `AppRootView` de **XFApp** y ya. Toda la lógica
vive en los módulos SPM.

## Ejecutar

```
make run
# o
swift run xFlare
```

`swift run` es CLI puro (compila + ejecuta un binario normal); **no** usa XCTest.
Desde Xcode: abre `Package.swift`, elige el esquema **xFlare**, Run.

## Qué hace

- `AppModel.boot()` carga el catálogo (`data/scratches/library-v0.1.json`,
  `data/curriculum/*.json`) y los perfiles (`profiles/*.conf`), abre la base
  SQLite en *Application Support*, y crea el motor de audio (`EngineHandle`).
- `AppRootView` pinta la barra de navegación y la pantalla actual según
  `AppModel.screen`: Home (matriz + racha), Librería, Mi mesa, Ajustes,
  Calibración, Progreso, Resultados, Práctica, Modo libre.
- Si algo falla al arrancar, la ventana abre en `.error(...)` y lo dice.

## Límites conocidos (para B12 / hardware)

- **En dev** el contenido se lee del **repo** (`RepoContentLoader`, vía
  `#filePath`). Empaquetar `data/` y `profiles/` como recursos del bundle es
  tarea del bloque de distribución (B12); ahí se cambia a `DirectoryContentLoader`.
- La pantalla de práctica dibuja la autopista sincronizada al reloj del motor,
  pero el **bucle de sesión + scoring en vivo** necesita el callback de audio
  corriendo → se verifica en la máquina.
- Persistir "ajustes" y "continuar" necesita un accesor de la tabla `setting`
  en `XFPersistence` (aditivo, pendiente).
