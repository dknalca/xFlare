# `xFlare` — ejecutable (cascarón de andamiaje)

Abre una ventana y pinta la **pantalla de inicio maquetada** con los tokens de
diseño reales de `docs/UI_DESIGN.md` §2. **Nada responde**: no hay lógica, no hay
audio, no hay navegación. Es solo para poder *abrir algo* y ver la forma.

## Ejecutar

```
make run
# o
swift run xFlare
```

`swift run` es CLI puro (compila + ejecuta un binario normal); **no** usa XCTest.
La ventana sale.

Desde Xcode: abre `Package.swift`, elige el esquema **xFlare**, Run.

## Qué hay aquí

| Fichero | Qué es |
|---|---|
| `xFlareApp.swift` | `@main` SwiftUI App + `AppDelegate` que fuerza la política de activación (un ejecutable SPM no trae bundle; sin esto la ventana sale sin Dock ni foco). Importa `XFApp` solo para enlazar el grafo entero y servir de prueba de humo. |
| `HomeScaffoldView.swift` | La maqueta: barra lateral con las secciones (Calibración, Practicar, Libre, Librería, Progreso, Mi mesa, Ajustes) + Home con tarjeta "Continuar", stats y mapa de la matriz. Tokens de color inline. |

## Qué NO es

- **No es** el módulo `XFApp`. `XFApp` sigue siendo un stub vacío hasta el bloque
  **B11**, donde se implementan las pantallas de verdad.
- Cuando llegue B11, este `@main` pasará a montar la vista raíz real de `XFApp` y
  `HomeScaffoldView.swift` se borra.
- Los tokens de color se moverán a `XFDesign` en **B7.1**.

Restricciones de plataforma vigentes: macOS 11, Swift 5.7, sin `NavigationStack`
ni `@Observable` (`docs/PLATFORM_SUPPORT.md` §4). Esta maqueta ya las respeta
(`NavigationView`, `SidebarListStyle()`, `LazyVGrid`).
