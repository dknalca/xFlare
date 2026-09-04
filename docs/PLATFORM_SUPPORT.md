# Plataformas, toolchain y compatibilidad

> Estado: v0.4. Decidido en ADR-022, 023 y 024. **Leer antes de escribir una linea
> de Swift**, porque la mitad de los ejemplos que hay por internet no compilan aqui.

## 1. Resumen

| | |
|---|---|
| **Minimo soportado** | macOS **11.0 Big Sur** |
| **Arquitecturas** | Universal: `x86_64` (Intel) + `arm64` (Apple Silicon) |
| **Toolchain fijada** | **Xcode 14.2 / Swift 5.7.2** |
| **Maquina unica** | MacBook Pro 13" Early 2015, Intel, **macOS 12 Monterey** |
| **Se desarrolla y se prueba** | En la misma maquina |

## 2. La noticia buena

**Tu MacBook Pro 13" Early 2015 soporta macOS 12 Monterey.** Monterey es su tope;
Ventura ya exige un Mac de 2017 o posterior.

Actualizarlo es la decision mas rentable de todo este documento, y es gratis.
Mantener Catalina cuesta esto:

| | Catalina 10.15 | Monterey 12 |
|---|---|---|
| Xcode maximo | **12.4** | **14.2** |
| Swift maximo | **5.3.2** | **5.7.2** |
| `swift-tools-version` | 5.3 | 5.7 |
| `async/await`, actores | no | si |
| SwiftUI: `@main App`, `WindowGroup` | **no** (macOS 11+) | si |
| SwiftUI: `@StateObject`, `LazyVGrid` | **no** (macOS 11+) | si |
| CoreMIDI moderno (`MIDIEventList`) | **no** (macOS 11+) | si |
| Audio workgroups para hilos RT | **no** (macOS 11+) | si |

Con 10.15 como minimo, la UI habria que escribirla practicamente entera en AppKit,
porque el ciclo de vida `@main struct App: App` no existe hasta Big Sur. Son semanas
de trabajo extra por dar soporte a un sistema que tu propia maquina puede dejar
atras en una tarde.

**Decision: minimo macOS 11.0** (ADR-022). Si aun asi quieres 10.15, hace falta un
ADR nuevo que asuma el coste por escrito.

## 3. Toolchain fijada: Xcode 14.2 / Swift 5.7.2

Es el Xcode mas alto que corre en Monterey y por tanto **el techo real del proyecto**
mientras tus maquinas sean estas. Consecuencias practicas:

- `// swift-tools-version: 5.7` en `Package.swift`. Ni 5.9 ni 6.0.
- Tests con **XCTest**. `swift-testing` necesita Xcode 16.
- Sin macros de Swift ni *parameter packs* (ambos 5.9).
- Sin `@Observable` ni Observation (macOS 14). Se usa `ObservableObject` +
  `@Published` + `@StateObject`.
- Sin modo estricto de concurrencia de Swift 6. Se puede marcar `Sendable` a mano
  para no acumular deuda.

Xcode 14.2 compila sin problema con destino 11.0: el deployment target puede estar
muy por debajo del sistema de la maquina que compila.

### `swift test` en Monterey con Xcode 14.2 (ADR-029, RESUELTO 2026-08-31)

**Historico del bug.** Xcode 14.2 recien instalado, sin completar su primer
arranque, **compilaba pero no ejecutaba** bundles de test Swift:
`libXCTestSwiftSupport.dylib` entraba en recursion infinita contra el runtime
Swift del sistema y crasheaba con signal 11. Un `swift package init` vacio fallaba
igual → nunca fue el codigo del proyecto. Cambiar a una toolchain de swift.org
(5.7.3 / 5.8.1) no lo arreglaba: en macOS XCTest siempre viene de Xcode.

**Arreglo.** Completar la instalacion de componentes de Xcode 14.2 — se abrio
Xcode.app una vez y dejo que instalara el soporte de XCTest de la plataforma
macOS (`libXCTestBundleInject.dylib` + `libXCTestSwiftSupport.dylib` en
`MacOSX.platform/Developer/usr/lib/`). Equivale a `sudo xcodebuild
-runFirstLaunch`. Tras eso `swift test` ejecuta verde con Xcode 14.2 / Swift
5.7.2. No hizo falta Xcode 14.1. Detalle en `DECISIONS.md` ADR-029.

**Si reaparece** (Xcode reinstalado, maquina nueva): abrir Xcode.app una vez y
dejar que instale componentes, o `sudo xcodebuild -runFirstLaunch`.

`make verify` sigue lanzando `swift test` en modo *advisory* (avisa, no corta)
por si otra maquina de dev entra sin los componentes. La toolchain swift.org
**5.8.1** queda instalada en `~/Library/Developer/Toolchains/` porque compila el
proyecto entero (GRDB incluido) mas rapido de perfilar; el `Makefile` la usa via
`TOOLCHAINS=swift` si esta presente.

## 4. APIs prohibidas (lista para Claude Code)

Son las que mas se cuelan, porque salen en todos los tutoriales recientes:

| API | Disponible desde | Alternativa en 11.0 |
|---|---|---|
| `NavigationStack`, `NavigationSplitView` | macOS 13 | `NavigationView` |
| `@Observable` / Observation | macOS 14 | `ObservableObject` + `@Published` |
| `.searchable` | macOS 12 | Campo de busqueda propio |
| `Table` | macOS 12 | `List` con filas propias |
| `AsyncImage` | macOS 12 | Carga manual |
| `.scrollContentBackground` | macOS 13 | Trucos de AppKit |
| `ShareLink`, `PhotosPicker` | macOS 13 | `NSSharingServicePicker` |
| `SwiftData` | macOS 14 | GRDB 6.x |
| `Duration` / `ContinuousClock` | macOS 13 | `mach_absolute_time`, `DispatchTime` |
| `swift-testing` | Xcode 16 | XCTest |
| `Form` + `ForEach` en un `Section` | (bug Big Sur) | `ScrollView { VStack { XFCard } }` a mano (ADR-058) |

**Regla:** si una API tiene `@available` posterior a macOS 11.0, no se usa. Si de
verdad hace falta, se aisla con `if #available` y se escribe la ruta alternativa.
El minimo no sube sin ADR.

## 5. Dependencias

- **GRDB**: pinnear a la serie **6.x** (`"6.0.0" ..< "7.0.0"`). GRDB 7 pide Swift 6
  y Xcode 16. *Verificar el minimo de despliegue exacto de la version que se fije.*
- **xwax**: C plano. **Comprobar** que `timecoder.c` y `lut.c` no traigan intrinsecos
  SSE ni flags `-msse`; si los traen, condicionarlos por arquitectura para que
  compile el slice `arm64`. Es la sorpresa clasica al hacer universal codigo C
  pensado para PC.
- Apache-2.0 **ahora es compatible** (el proyecto es GPL-3.0-only, ADR-030). MIT y
  BSD siguen bien. Cualquier dependencia nueva necesita ADR igualmente.

## 6. Realidades del hardware Intel de 2015

El MacBook Pro 13" Early 2015 es un Broadwell de dos nucleos, con Iris 6100 y
pantalla de **60 Hz**. Eso obliga a cambiar dos cosas del diseno:

- **Los 120 fps no existen ahi.** El objetivo pasa a ser sincronizar con el refresco
  real: 60 fps garantizados en Intel, 120 donde haya ProMotion.
- **Los 10 ms de latencia estan en riesgo real** en esa maquina: dos nucleos,
  estrangulamiento termico y SpriteKit compitiendo por CPU. El presupuesto pasa a
  ser por maquina y el buffer debe poder subir a 128 frames solo.

Ademas: 8 GB de RAM tipicos y Xcode 14 encima. Desarrolla en la maquina de Monterey
mas potente y usa la de 2015 solo para probar.

## 7. Presupuesto de latencia por maquina

El objetivo de 10 ms deja de ser un numero unico y pasa a ser una tabla que se
rellena midiendo (bloque B1). **El numero es la suma de las latencias de
entrada y salida que declara CoreAudio** (`AudioDeviceLatency`, F.48/F.63),
no un round-trip por loopback — ver ADR-074 y `docs/TIMECODE.md` §4.2: la Rane
72 no tiene un Master Out USB para loopback, y el camino real de xFlare no es
un bucle (una pierna de entrada + una de salida independiente, sin volver a
entrar al ordenador), asi que el retorno USB interno de la mesa sobreestima.

| Maquina | Buffer | Latencia declarada (in + out) | Estado |
|---|---|---|---|
| MacBook Pro 2015 (Monterey) | 64 frames | 10,00 + 4,35 = **14,35 ms** | **DENTRO** de ≤ 15 ms aceptable (ADR-024) |
| MacBook Pro 2015 (Monterey) | 128 frames | _(pendiente)_ | por medir |
| Maquina de referencia | 64 frames | _(pendiente — no hay segunda Mac todavia)_ | por medir |

Al ser la unica maquina hasta ahora, **este numero es EL numero del proyecto**.
Si sale 18 ms, esa es la realidad de xFlare hoy y hay que decidir con ese dato
en la mano, no esperar a un Mac mejor.

Si en el 2015 no se baja de 15 ms, se documenta como limitacion conocida y la app
lo dice en la calibracion, en vez de fingir que va fino.

## 8. Permisos y firma

- **Permiso de microfono obligatorio.** El timecode entra como entrada de audio y
  desde Catalina eso requiere consentimiento: `NSMicrophoneUsageDescription` en el
  Info.plist con un texto honesto ("xFlare necesita la entrada de audio para leer el
  vinilo de control"). Sin esto la app parece rota y nadie sabe por que.
- Hardened runtime con la excepcion de entrada de audio.
- Notarizacion con `notarytool` (Xcode 13+, disponible en Monterey).
- Universal: `ARCHS = x86_64 arm64`. Verificar con `lipo -archs`.

## 8.5 Una sola maquina: consecuencias

Se desarrolla y se prueba en el MacBook Pro de 2015 con Monterey. Eso tiene dos
caras y conviene tener las dos presentes:

**A favor, y no es poco:** desarrollas sobre **la maquina mas lenta que vas a
soportar**. Los problemas de rendimiento aparecen el mismo dia que los causas, no
seis meses despues cuando alguien con un portatil viejo se queja. Es la mejor
posicion posible para un proyecto de audio en tiempo real.

**En contra:**
- Compilar en un doble nucleo con 8 GB es lento. Aqui la arquitectura modular deja
  de ser solo higiene: **compilas un modulo, no el proyecto entero**. Ese es el
  segundo motivo por el que existe `Package.swift` con 13 targets.
- **El slice `arm64` no se puede probar en hardware aqui.** Se compila universal
  desde el primer dia (B0.6) y la **logica se verifica en CI** con runners de Apple
  Silicon, que son gratis en repos publicos. Lo que no queda cubierto es el audio en
  tiempo real y el timecode, que necesitan hardware. Ver `docs/ARCHITECTURES.md`.
- No hay segunda maquina para descartar si un fallo es del codigo o del equipo.
  Por eso los `.xfsession` grabados valen doble: reproducen el problema sin hardware.

## 9. Matriz de pruebas

Cada release pasa por las dos maquinas antes de salir:

| | Intel / Monterey (2015) | La otra (Monterey) |
|---|---|---|
| Arranca y calibra | obligatorio | obligatorio |
| Latencia medida y anotada | obligatorio | obligatorio |
| 5 min de scratch sin overloads | obligatorio | obligatorio |
| 60 fps estables en la autopista | obligatorio | — |
| Slice de arquitectura correcto (`lipo`) | obligatorio | obligatorio |

Si tu segunda maquina es Apple Silicon, mejor: cubres las dos arquitecturas de
verdad. Si tambien es Intel, **el slice `arm64` no lo prueba nadie** y hay que
decirlo en el README hasta que alguien lo haga.

## 10. Sobre los drivers de la mesa

**Por verificar antes del bloque B1:** que la Rane Seventy-Two (MK1) tenga driver de
audio USB para Monterey, o que sea class-compliant. Es otro punto a favor de
actualizar el 2015: el soporte de fabricante para Catalina va desapareciendo.

## 11. Portar a Linux y Windows

Sigue en FUTURIBLES. La capa 0 y la 1 son C y Swift sin UI, y xwax ya es
multiplataforma; lo caro seria `XFRender` y `XFApp`. No se hace nada hoy para
facilitarlo mas alla de no meter AppKit en las capas bajas, que ya es regla.
