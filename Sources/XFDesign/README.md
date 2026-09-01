# XFDesign

**Capa 2 · sin dependencias · SEALED 2026-09-01 · `apiVersion = 1`**

Tokens de diseño y componentes SwiftUI reutilizables (`docs/UI_DESIGN.md` §2).
Sin lógica de negocio. Deployment target **macOS 11** — solo APIs de SwiftUI
disponibles ahí (`docs/PLATFORM_SUPPORT.md` §4).

## API pública

### Tokens

```swift
enum XFColor {                 // paleta oscura, un solo acento (UI_DESIGN §2)
    bg, surface, surfaceRaised, stroke, text, textMuted, accent,
    ghost /* #7A8794 al 35% */, grid, gridBeat            // -> Color
}
extension Color { init(hex: UInt32, opacity: Double = 1) }

enum XFSpacing { xxs=4, xs=8, sm=12, md=16, lg=24, xl=32, xxl=48 }   // CGFloat
enum XFRadius  { control=10, card=16, modal=24 }
enum XFStroke  { hairline=1 }

enum XFFont {
    title(_:)      // SF Pro Display Semibold
    body(_:) / bodyMedium(_:)
    mono(_:)       // design .monospaced -> dígitos a ancho fijo (no bailan)
}
extension Text { func xfNumber(_ size:) -> Text }

enum HitLevel { perfect, great, good, offbeat, miss }    // CaseIterable
    init(absOffsetMs: Double)          // clasifica por ventana (±20/40/70/110)
    var color: Color
    var shape: Shape                    // filledCircle/circle/diamond/triangle/cross
    var label: String                  // para VoiceOver
```

`HitLevel` **nunca informa solo por color**: cada nivel tiene forma distinta
(daltonismo). Las ventanas en ms coinciden con `docs/SCORING.md`.

### Componentes base (B7.2)

```swift
struct XFCard<Content: View> { init(raised: Bool = false, padding: CGFloat = 16, content:) }
struct XFButtonStyle: ButtonStyle { init(_ variant: .filled | .bordered) }
extension View { func xfButton(_ variant:) -> some View }
struct BPMStepper: View { init(bpm: Binding<Int>, range: 40...200, step: 5) }   // ‹ 80 BPM ›
struct HitBadge: View { init(_ level: HitLevel, offsetMs: Double? = nil, size: CGFloat = 12) }
struct HitShape: View { init(_ shape: HitLevel.Shape) }
```

## Pendiente

- **B7.2b–B7.6 (XFRender):** escena SpriteKit de la autopista, sincronizada al
  **reloj de audio**, 60 fps garantizados en Intel, scope Lissajous, golden tests
  SVG. Necesita el bucle de render y una pantalla.
- **B7.7:** sellar XFDesign + XFRender juntos.

## Notas de plataforma

- `Text.monospacedDigit()` es macOS 12 → se usa `Font` con `design: .monospaced`,
  que ya deja los dígitos a ancho fijo.
- Sin `NavigationStack`, `@Observable`, `.scrollContentBackground`, etc.
