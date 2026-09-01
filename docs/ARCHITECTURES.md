# Intel y Apple Silicon

> Respuesta corta: **si, un Mac con M1/M2/M3... puede ejecutar xFlare**, y hacerlo
> compatible con ambos cuesta muy poco **si se hace desde el primer dia**.
> Estado: v0.6. Decidido en ADR-028.

## 1. Las tres opciones, y por que solo una vale

| Opcion | Funciona en M | Coste | Veredicto |
|---|---|---|---|
| Solo `x86_64` + Rosetta 2 | si, traducido | cero | **No.** Ver seccion 2 |
| **Binario universal** (`x86_64` + `arm64`) | si, nativo | muy bajo | **Esto** |
| Solo `arm64` | si | — | No: tu MacBook es Intel |

## 2. Por que Rosetta no es un plan

Rosetta 2 traduce aplicaciones Intel y funciona sorprendentemente bien. Un M1
ejecutando xFlare bajo Rosetta probablemente iria **mas rapido que tu MacBook de
2015 nativo**, porque la diferencia bruta de potencia se come el peaje de la
traduccion.

Pero:

- **Apple lo esta retirando.** Rosetta 2 se mantiene con soporte amplio hasta
  **macOS 27 (otono de 2026)**; en **macOS 28 (otono de 2027)** desaparece el
  soporte general para apps solo-Intel, quedando una capa limitada unicamente para
  ciertos juegos antiguos. Desde macOS 26.4 el sistema ya avisa al abrir apps Intel.
- **Rosetta no traduce drivers.** Si la mesa necesita un driver de audio USB, ese
  driver tiene que ser nativo arm64 si o si. Rosetta no te salva ahi.
- Una app de audio en tiempo real que arranca con un aviso del sistema diciendo
  "esto es software Intel antiguo" no inspira ninguna confianza.

Conclusion: Rosetta sirve como **red de seguridad temporal**, no como estrategia.

## 3. El binario universal: lo que de verdad cuesta

Para el codigo Swift, **nada**. Se compila dos veces y se pegan los dos resultados.
El trabajo real esta en cuatro puntos concretos, y todos estan en el backlog:

### 3.1 El C de xwax y los intrinsecos SSE  (`B0.7`)
`timecoder.c` y `lut.c` vienen del mundo PC. Si traen intrinsecos SSE o flags
`-msse`, el slice `arm64` **no compila**. Hay que detectarlo y condicionarlo por
arquitectura sin tocar la logica. Es la sorpresa clasica y es mejor descubrirla el
primer dia que en el mes seis.

### 3.2 Los golden tests con coma flotante  (`B0.8`)
**Esto era un fallo del diseno anterior.** `docs/TESTING.md` decia comparar los
goldens "byte a byte". Las operaciones en coma flotante pueden dar resultados que
difieren en los ultimos bits entre `x86_64` y `arm64` (orden de operaciones,
contraccion a FMA, tratamiento de denormales). Un golden byte a byte **fallara en
arm64 aunque el codigo sea correcto**.

Regla corregida: los goldens numericos se serializan **redondeados a 4 decimales**,
y las comparaciones de valores usan tolerancia `1e-9`. Los goldens de SVG se
comparan por estructura y valores redondeados, no como texto crudo.

### 3.3 La prioridad del hilo de audio  (`B4.2`)
Aqui Apple Silicon **no es Intel mas rapido, es otra cosa**: tiene nucleos de
rendimiento y nucleos de eficiencia. Si el hilo de audio cae en un nucleo de
eficiencia, hay cortes aunque sobre CPU de media.

Hay que hacer **las dos cosas**:
- `thread_policy_set` con `THREAD_TIME_CONSTRAINT_POLICY` — funciona en ambas.
- Unirse al **workgroup del dispositivo de audio**
  (`kAudioDevicePropertyIOThreadOSWorkgroup`, macOS 11+) — esencial en Apple Silicon
  para que el planificador mantenga el hilo en un nucleo de rendimiento.

### 3.4 Los drivers de la mesa  (`perfiles`)
Un kext Intel no carga en Apple Silicon. Una mesa puede funcionar en tu MacBook y
no en un M sin culpa de xFlare. Por eso los perfiles ganan una clave de rarezas:

```ini
[quirks]
arm64_driver_unknown = true
text = Driver USB no verificado en Apple Silicon.
```

## 4. Como se compila

Desde terminal, con SPM:

```
swift build -c release --arch arm64 --arch x86_64
lipo -archs .build/apple/Products/Release/xFlare
# -> x86_64 arm64
```

En Xcode: `ARCHS = $(ARCHS_STANDARD)` y **`ONLY_ACTIVE_ARCH = NO` en Release**.
Ese ajuste es el que se olvida todo el mundo y por eso el DMG sale solo-Intel.

**Puedes generar el slice `arm64` desde tu MacBook Intel sin problema.** La
compilacion cruzada funciona. Lo que no puedes es *ejecutarlo*.

`make universal` y `make archs` lo dejan hecho y comprobado.

## 5. Como probar arm64 sin tener un Mac con M

Esta es la parte buena: **GitHub Actions ofrece runners de Apple Silicon
(`macos-14`, `macos-15`) gratis e ilimitados para repositorios publicos**. xFlare es
GPL y es publico, asi que sale a coste cero.

**El target real —MacBook Pro Intel de 2015 con macOS 12.7— NO tiene runner en
GitHub** (no hay imagenes de macOS 12). Ese target se cubre en **local**: la
maquina de referencia corre `make verify` en cada tarea. La CI aporta lo que esa
maquina no puede dar: arm64 nativo.

`.github/workflows/ci.yml` monta dos trabajos, ambos en `macos-14`:

| Trabajo | Que cubre |
|---|---|
| `test-arm64` | **Que la logica pasa en arm64 de verdad** + `swift test` + validador de perfiles + guard de `data/` |
| `universal` | Que el binario de release sale con los dos slices (`make universal`) |

> Se probo un job `macos-13` (Intel/Ventura) y se retiro: no es el OS objetivo y
> GitHub le da tan poca capacidad —imagen en fin de vida— que se quedaba
> encolado sin runner. El x86_64 lo valida la maquina de referencia, que ES Intel.

Lo que **si** queda cubierto en arm64: `XFClock`, `XFNotation`, `XFProfiles`,
`XFPrimitives`, `XFAnalysis`, `XFCapture` (lo puro), `XFDesign` y la parte de
`CXFAudioCore` sin hardware. Es decir, la mayoria de las puertas de sellado.

Lo que **no**: nada que necesite tarjeta de sonido o mesa. Los runners no tienen
audio real.

Dos avisos honestos:

- Los runners `macos-14`+ traen **Xcode 15 o superior**, no el 14.2 que tienes
  fijado. No hay paridad exacta de toolchain: ese trabajo vale como **comprobacion
  de arquitectura**, no como validacion de la toolchain de release. La build que se
  distribuye se hace en tu maquina con 14.2.
- *Verificar* que version de Xcode trae cada imagen antes de fijarla en el YAML;
  cambian con el tiempo.

## 6. Detectar Rosetta en tiempo de ejecucion

Si por lo que sea alguien acaba ejecutando el slice Intel bajo Rosetta, la app debe
decirlo en vez de fingir que va fino:

```c
int translated = 0; size_t size = sizeof(translated);
sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0);
```

Si devuelve 1, aviso en la pantalla de calibracion: *"Estas ejecutando la version
Intel mediante Rosetta. La latencia sera peor de lo necesario. Descarga la version
universal."* Coherente con no mentirle nunca al usuario sobre la latencia.

## 7. Que decir en el README mientras tanto

Hasta que alguien con un Mac M lo pruebe con hardware real:

> Apple Silicon: compilado nativo y **logica verificada en CI**. El audio en tiempo
> real y el timecode **no se han probado todavia en hardware Apple Silicon**.
> Si tienes un Mac M y una mesa, tu informe vale oro.

Es mas preciso que "no verificado" y mas honesto que callarse.

## 8. Resumen para el que tiene prisa

1. Compilar universal **desde el primer dia** (`B0.6`). Dejarlo para el final es
   como se descubre en la semana 20 que medio proyecto no cruza-compila.
2. Arreglar los goldens de coma flotante **antes** de escribir el primero (`B0.8`).
3. Workgroup de audio ademas de la politica de hilo (`B4.2`).
4. CI en `macos-14` gratis para cubrir arm64 sin comprar nada.
5. Rosetta como red, nunca como plan: se acaba en macOS 28.
