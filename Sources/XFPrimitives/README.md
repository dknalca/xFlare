# XFPrimitives

**Capa 0 (fondo del grafo) · sin dependencias · SEALED 2026-09-01 · `apiVersion = 1`**

El vocabulario compartido de muestras de entrada. Dos `struct` `Sendable` puros,
sin lógica. Existen para que `XFCapture` (que las produce) y `XFAnalysis` (que las
consume dentro de `Take`) no tengan que importarse entre sí — rompería la regla de
capas de `docs/ARCHITECTURE.md` §2. Ver **ADR-033**.

"Capa 0" es posición en el grafo, no código de tiempo real: esto es Swift y nunca
entra en el callback de audio (ese es C, `CXFAudioCore`).

## API pública

```swift
public enum XFPrimitives { public static let apiVersion = 1 }

public struct MotionSample: Equatable, Sendable {
    let hostTime: UInt64     // mach_absolute_time; mismo dominio que CoreAudio/CoreMIDI
    let position: Double     // vueltas acumuladas, signo = sentido, no se envuelve
    let velocity: Double     // 1.0 = 33⅓ rpm nominal, 0 = parado, <0 = atrás
    let confidence: Float    // 0..1, calidad de la lectura
    init(hostTime:position:velocity:confidence:)
}

public struct FaderSample: Equatable, Sendable {
    let hostTime: UInt64
    let value: Float         // 0..1 crudo (para análisis posterior)
    let isOpen: Bool         // binarizado con cut-in + histéresis (ADR-017)
    init(hostTime:value:isOpen:)
}
```

Campos según `docs/ARCHITECTURE.md` §3. Un cambio incompatible necesita ADR nuevo,
subir `apiVersion` y re-sellar.
