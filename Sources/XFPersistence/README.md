# XFPersistence

**Capa 1 · depende de XFNotation y GRDB 6.x · SEALED 2026-09-01 · `apiVersion = 1`**

La base de datos local de xFlare: un fichero SQLite que el usuario puede copiar
(soberanía del usuario, `CLAUDE.md` §3). Guarda el histórico de tomas, el
progreso agregado, el estado de dominado, los desbloqueos, la repetición
espaciada y la calibración por dispositivo. **Sin UI, sin hardware, sin red.**

Puerta única: **`XFDatabase`**. Los *records* son públicos como forma de los
datos; las consultas y comandos son métodos sobre `XFDatabase`. Ver **ADR-035**.

## Abrir la base

```swift
public struct XFDatabase {
    public init(url: URL) throws                    // abre/crea y migra
    public static func inMemory() throws -> XFDatabase   // para tests
    public let writer: DatabaseWriter              // GRDB, para lecturas/escrituras extra
    public func isUpToDate() throws -> Bool
}
```

El esquema y sus migraciones son internos: `XFDatabase` los aplica al abrir. Una
migración publicada no se toca; los cambios entran como `v2`, `v3`…

## Histórico de tomas (`XFDatabase+Attempts`)

```swift
func saveSession(_ session: PracticeSession) throws
func session(id: String) throws -> PracticeSession?

func saveAttempt(_ attempt: Attempt, events: [AttemptEvent] = []) throws  // intento + eventScores, en 1 tx
func attempt(id: String) throws -> Attempt?
func events(ofAttempt attemptId: String) throws -> [AttemptEvent]         // ordenados por `t`
func attempts(exerciseId: String, variantId: String, limit: Int? = nil) throws -> [Attempt]
func attempts(exerciseId: String, limit: Int? = nil) throws -> [Attempt]  // del más reciente al más antiguo
```

`Attempt` tiene todos los campos de `data/schema/attempt.schema.json`, incluido
`sessionFile` (ruta al `.xfsession` crudo) y `countsForStars` (ADR-027, `false` en
calentamiento). `AttemptEvent` es el desglose `eventScores` (fila hija, borrado en
cascada).

## Progreso agregado (`XFDatabase+Progress`, `docs/SCORING.md` §3)

```swift
@discardableResult
func recomputeProgress(exerciseId: String, variantId: String) throws -> ExerciseProgress
func progress(exerciseId: String, variantId: String) throws -> ExerciseProgress?
func progressSummary(exerciseId: String, variantId: String) throws -> ProgressSummary?
```

`recomputeProgress` recalcula desde `attempt` (solo `countsForStars == true`,
salvo `totalPracticeMs`): intentos, mejor + fecha, última + fecha, estrellas (máx,
no baja), mejor BPM con 3★, sesgo medio. `ProgressSummary` añade la media de los
últimos 5 y la línea de los últimos 20.

## Dominado y desbloqueos (`XFDatabase+Mastery`, `XFDatabase+Unlocks`)

```swift
static let masteryBaseStars = 3
static let masteryVariantStars = 2
static let masteryVariantCount = 3

@discardableResult
func refreshMastery(exerciseId: String, baseVariantId: String = "base", at: Date) throws -> ExerciseMastery
func mastery(exerciseId: String) throws -> ExerciseMastery?
func isMastered(exerciseId: String) throws -> Bool
func masteredExercises() throws -> [String]
func setOxidized(exerciseId: String, at date: Date?) throws     // ADR-027 / WARMUP §5

func markVariantUnlocked(exerciseId: String, variantId: String, at: Date) throws
func isVariantUnlocked(exerciseId: String, variantId: String) throws -> Bool
func unlockedVariants(exerciseId: String) throws -> Set<String>

@discardableResult
func evaluateUnlocks(exerciseId: String, rules: [VariantUnlockRule], at: Date) throws -> [String]
```

**Dominado** = 3★ en la base y 2★ en ≥3 variantes. `masteredAt` se fija una vez y
no se borra. Las `VariantUnlockRule` (`variantId`, `requiresVariant`,
`requiresStars`) las construye el llamante desde `data/curriculum/variants.json`;
XFPersistence no lee el catálogo.

## Repetición espaciada (`XFDatabase+Review`, `docs/CURRICULUM.md` §7)

```swift
static let intervalDays = [1, 3, 7, 21]   // en ReviewItem

func scheduleReview(exerciseId: String, variantId: String, masteredAt: Date) throws
@discardableResult
func recordReviewOutcome(exerciseId: String, variantId: String, passed: Bool, at: Date) throws -> ReviewItem
func reviewItem(exerciseId: String, variantId: String) throws -> ReviewItem?
func dueReviews(asOf date: Date) throws -> [ReviewItem]
```

Aprobar un repaso sube un escalón (tope 21 días); fallarlo vuelve al escalón 0.
"Día" = 86 400 s exactos (determinista, sin zona horaria).

## Calibración por dispositivo (`XFDatabase+Calibration`)

```swift
func saveCalibration(_ calibration: DeviceCalibration) throws   // upsert por deviceKey
func calibration(deviceKey: String) throws -> DeviceCalibration?
func allCalibrations() throws -> [DeviceCalibration]
func deleteCalibration(deviceKey: String) throws
```

`deviceKey` = UID del dispositivo de audio o nombre del puerto MIDI. `profileId`
es el perfil de `XFProfiles`. **`v2` (2026-09-05, F.72, ADR-077):**
`faderMidiChannel`/`faderMidiCC`/`faderMidiRawMin`/`faderMidiRawMax`
(`Int?`, los cuatro `nil` si no se ha aprendido) — el CC MIDI del crossfader
que el asistente de calibración APRENDE observando el tráfico real (F.67),
en vez de fiarse de lo que declare el perfil `.conf`.

## Ejemplo de uso

```swift
import XFPersistence

let db = try XFDatabase(url: appSupport.appendingPathComponent("xflare.sqlite"))

// Al terminar una toma:
let attempt = Attempt(id: UUID().uuidString, exerciseId: "ex-l1-baby", variantId: "base",
                      mode: .ghost, bpm: 70, startedAt: startDate, durationMs: 12_000,
                      score: 3210, maxScore: 3600, accuracy: 0.89, stars: 2,
                      sigmaMs: 11, biasMs: -6, zeroEvents: 0,
                      sessionFile: "sessions/2026-09-01T10-00.xfsession")
try db.saveAttempt(attempt, events: eventScores)
try db.recomputeProgress(exerciseId: "ex-l1-baby", variantId: "base")
try db.refreshMastery(exerciseId: "ex-l1-baby", at: Date())

// Pantalla de progreso:
if let s = try db.progressSummary(exerciseId: "ex-l1-baby", variantId: "base") {
    // s.progress.stars, s.averageOfLast5, s.recentScores, ...
}
```

## Qué NO hace (a propósito)

- No lee ficheros del bundle (`data/curriculum/`): las reglas que dependen del
  catálogo entran como parámetros.
- No decide cuándo recalcular: el llamante llama a `recomputeProgress` /
  `refreshMastery` / `evaluateUnlocks` tras guardar.
- No hace repetición espaciada con días de calendario (usa 86 400 s).
- No arranca hilos ni observa cambios (nada de GRDB `ValueObservation` en el
  contrato; se puede añadir sin romperlo).

## Decisiones

- **ADR-027** — el calentamiento registra pero no cuenta para estrellas
  (`countsForStars`).
- **ADR-035** — esquema completo en `v1`, `XFDatabase` como puerta única, reglas
  de producto dentro y catálogo fuera, "día" = 86 400 s.
