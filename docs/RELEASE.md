# RELEASE.md — cómo se corta una release de xFlare

> **B12a** — DMG **sin notarizar** publicado en GitHub Releases (ADR-037). La
> notarización + Homebrew es B12b, pospuesto sin fecha.
>
> Este documento es la lista de comprobación + el texto de la nota de release
> (B12a.5). No hay tags todavía; la primera será `v0.1-preview`.

---

## 1. Pre-flight (no se sube nada si algo de esto falla)

- [ ] `make verify` en verde (build + lint + perfiles + tests).
- [ ] `make universal && make archs` → `lipo -archs` muestra `x86_64 arm64`.
      **ADR-028 no se relaja**: universal desde el primer día.
- [ ] Matriz de máquinas de `docs/PLATFORM_SUPPORT.md` §9 cubierta:
  - [ ] arranca y calibra en el MacBook Pro Intel 2015 **y** en la segunda máquina
  - [ ] latencia medida y anotada (`docs/TIMECODE.md` §4.2) en ambas
  - [ ] 5 min de scratch sin overloads en ambas
  - [ ] 60 fps estables en la autopista (Intel 2015)
  - [ ] `lipo` del slice correcto en ambas
- [ ] Si la segunda máquina también es Intel, **el slice `arm64` no lo ha
      probado nadie en hardware** → decirlo en la nota de release (ya está en el
      README, mantenerlo hasta que alguien lo pruebe).
- [ ] Bloque B1 cerrado (B1.3): la latencia entra en la puerta o hay un ADR con
      el plan B/C.

## 2. Construir el artefacto

```sh
make verify                 # gate
make universal              # release, x86_64 + arm64, con Xcode 14.2 (ADR-023)
make dmg REL=1              # empaqueta el binario de RELEASE en xFlare-<version>.dmg
```

`make dmg` sin `REL=1` empaqueta el binario **debug** de `make app` — sirve para
probar el flujo, **no** para publicar. El artefacto de Releases se compila con
`make universal`.

Comprobar el DMG antes de subirlo:

```sh
hdiutil attach -nobrowse -readonly xFlare-*.dmg
lipo -archs "/Volumes/xFlare/xFlare.app/Contents/MacOS/xFlare"   # -> x86_64 arm64
codesign -dv "/Volumes/xFlare/xFlare.app" 2>&1 | grep adhoc      # -> flags=0x2(adhoc)
hdiutil detach /Volumes/xFlare
```

## 3. Publicar

```sh
git tag -a v0.1-preview -m "xFlare v0.1-preview"
git push origin v0.1-preview
gh release create v0.1-preview xFlare-0.1-preview.dmg \
  --title "xFlare v0.1-preview" \
  --notes-file docs/release-notes/v0.1-preview.md
```

El `.dmg` **no** se versiona en git (`.gitignore`); vive solo como adjunto de la
Release.

---

## 4. Texto de la nota de release (plantilla)

Copiar a `docs/release-notes/v<x.y>.md` y rellenar. Va tal cual en la Release.

```markdown
# xFlare v0.1-preview

Preview técnica. **No es una release de usuario final**: falta la validación con
hardware (bloque B1) y la app aún no puntúa (necesita el callback de audio con
captura).

## Instalación

1. Descarga `xFlare-0.1-preview.dmg`, ábrelo y arrastra **xFlare.app** a
   *Aplicaciones*.
2. El `.app` **no está notarizado**. La primera vez, macOS dirá "de un
   desarrollador no identificado". Para abrirlo:
   - **clic derecho** sobre xFlare.app → **Abrir** → **Abrir**, o
   - `xattr -dr com.apple.quarantine /Applications/xFlare.app`
3. Al arrancar pedirá **permiso de micrófono**: xFlare lee el vinilo de control
   como entrada de audio. Sin permiso parece rota.

## Requisitos

- macOS **11.0 Big Sur** o superior.
- Binario **universal** (Intel `x86_64` + Apple Silicon `arm64`). El slice
  `arm64` está compilado nativo y verificado en CI; **el audio en tiempo real y
  el timecode aún no se han probado en hardware Apple Silicon**.

## Código fuente (GPL-3.0-only)

Esta build corresponde exactamente al tag
[`v0.1-preview`](https://github.com/dknalca/xFlare/tree/v0.1-preview). xFlare es
**GPL-3.0-only** (impuesto por xwax, ver `docs/DECISIONS.md` ADR-003/ADR-030):
tienes derecho al fuente completo de esta versión, y está ahí.

## Problemas conocidos

- Sin scoring real todavía (práctica "rudimentaria": mueve y escucha).
- Latencia sin medir en hardware; puede no cumplir la puerta de 10/15 ms.
- Captura del crossfader por tono piloto (ADR-021) sin validar.
```

---

## 5. Checklist de que NO se sube

- ❌ El `.dmg` al repo (solo como adjunto de la Release).
- ❌ `Audio/` (samples con copyright, CLAUDE.md §12) — `make app` ya lo omite si
     no está, y `.gitignore` lo excluye.
- ❌ Binarios de `spike/` (`.gitignore`).
- ❌ Ninguna dependencia de red en runtime (CLAUDE.md §4).
