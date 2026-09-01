# XFProfiles

**Capa 1 · sin dependencias · SEALED 2026-08-31 · `apiVersion = 1`**

Parsea y resuelve los `.conf` de mesa: parser INI propio (ADR-019, cero
dependencias), herencia `extends`, validación equivalente a `tools/xf_profile.py`,
y autodetección por nombre de puerto. Puro: sin hardware, sin UI.

El `.conf` describe **el modelo de mesa** (canales, método de captura, CC). La
calibración personal del usuario **nunca** va aquí — vive en `XFPersistence`
(docs/DEVICE_PROFILES.md §6).

## API pública

### INI

```swift
public struct INIDocument: Equatable, Sendable {
    struct Item { var key, value: String }
    init(text: String) throws                 // ParseError si algo no cuadra
    var sectionOrder: [String]
    func hasSection(_:) -> Bool
    func hasOption(_ section:_ key:) -> Bool
    func get(_ section:_ key:) -> String?      // última aparición gana
    func keys(in section:) -> [String]
    mutating func set(_ section:_ key:_ value:)   // para el resolvedor
}
```

Reglas: `[sección]`; `clave = valor` o `clave : valor` (se recorta el espacio);
líneas `#`/`;` son comentarios; claves **sensibles a mayúsculas**; sin comentarios
de fin de línea ni continuación.

### Perfil resuelto

```swift
public enum CrossfaderMethod: String { case midi, audioReturn = "audio_return", hid, none }

public struct DeviceProfile: Equatable, Sendable {
    let id, name, vendor: String
    let schema, revision: Int
    let author: String?; let verified: Bool; let notes: String?
    let ancestorID: String?                    // valor de `extends`, si lo había
    let match: Match                           // midiPort / audioDevice (globs)
    let audio: Audio                           // samplerate, buffer.frames, canales
    let crossfader: Crossfader                 // method + claves según el método
    let keyboard: Keyboard?                    // solo el perfil sin mesa
    let raw: INIDocument                       // para [quirks], [linefader.*], etc.
    static func parse(resolved: INIDocument) throws -> DeviceProfile
}
```

### Resolución, validación, autodetección

```swift
public enum ProfileResolver {
    static func resolve(id: String, in registry: [String: INIDocument]) throws -> INIDocument
    // ResolveError: unknownProfile | unknownAncestor | circularInheritance(chain:)
}

public enum ProfileValidator {
    struct Report { var errors, warnings: [String]; var isValid: Bool }
    static func validate(raw:registry:filenameStem:isExample:) -> Report   // == xf_profile.py
}

public enum GlobMatch { static func matches(pattern: String, _ text: String) -> Bool }  // solo `*`, sin caso

public struct ProfileStore {
    init(bundled: [(filename, text)], user: [(filename, text)] = [])   // el usuario pisa al bundle por id
    var entries: [String: Entry]                // Entry: id, origin(.bundled/.user), raw, profile?, problem?
    func profile(id:) -> DeviceProfile?
    var usableProfiles: [DeviceProfile]
    enum Autodetect { case unique(DeviceProfile), ambiguous([DeviceProfile]), none }
    func autodetect(midiPortNames: [String], audioDeviceNames: [String]) -> Autodetect
}
```

Si el `[match]` de varios perfiles casa con lo que hay enchufado, `autodetect`
devuelve `.ambiguous` — **no elige**, la UI pregunta (criterio B5b.4).

## Ejemplo

```swift
import XFProfiles

let files = try FileManager.default.contentsOfDirectory(atPath: profilesDir)
    .filter { $0.hasSuffix(".conf") }
    .map { ($0, try! String(contentsOfFile: profilesDir + "/" + $0)) }

let store = ProfileStore(bundled: files, user: userFiles)

switch store.autodetect(midiPortNames: midiPorts, audioDeviceNames: audioDevices) {
case .unique(let p):     use(p)
case .ambiguous(let ps): askUser(ps)
case .none:              offerKeyboardProfile()
}
```

## Verificación (B5b)

- **B5b.1** parser INI propio: carga los 6 perfiles de `profiles/` sin pérdida.
- **B5b.2** `extends` + herencia circular: `pioneer-djm-s9` resuelve heredando de
  la s11; un ciclo da `circularInheritance(chain:)`.
- **B5b.3** validación == `tools/xf_profile.py`: mismos OK/FALLO y mismos avisos
  sobre los mismos ficheros.
- **B5b.4** autodetección con comodines `*`; empate → `.ambiguous`.
- **B5b.5** carga bundle + carpeta de usuario con precedencia (usuario gana).

24 tests. `apiVersion = 1`.
