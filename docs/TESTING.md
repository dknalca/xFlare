# Estrategia de pruebas

El objetivo no es cobertura, es **que no se rompa lo que ya funcionaba**.

## Cuatro tipos, cuatro proposito

| Tipo | Que prueba | Donde | Velocidad |
|---|---|---|---|
| Unitarias | Logica pura: reloj, compositor, DTW, scoring | Todos los modulos | ms |
| Golden | Que el dibujo y la libreria compilada no cambien sin querer | XFNotation, XFRender | ms |
| De replay | Tomas reales grabadas → puntuacion esperada | XFAnalysis, XFEngine | s |
| De tiempo real | Latencia, ausencia de overloads, deriva | CXFAudioCore, CXFTimecode | min, manual |

## Golden tests

`XFNotation` compila la libreria a JSON y `XFRender` dibuja SVG. Ambos son
deterministas **dentro de una misma arquitectura**, asi que se congela la salida en
`Fixtures/golden/` y se compara contra ella.

> **Cuidado con la coma flotante entre arquitecturas.** Las operaciones en punto
> flotante pueden diferir en los ultimos bits entre `x86_64` y `arm64` (orden de
> operaciones, contraccion a FMA, denormales). Un golden comparado **byte a byte
> fallara en arm64 aunque el codigo sea correcto**. Regla: los goldens numericos se
> serializan **redondeados a 4 decimales** y las comparaciones de valores usan
> tolerancia `1e-9`. Los SVG se comparan por estructura y valores redondeados, no
> como texto crudo. Ver `docs/ARCHITECTURES.md` seccion 3.2. Para aceptar un cambio
intencionado: `make golden-update`, y el diff se revisa en el commit.

Esto es lo que impide que una "mejora" del compositor cambie en silencio 25 patrones.

## Tests de replay

Cada patron del nivel 1 al 4 necesita como minimo tres tomas grabadas:

- `flare-2c__good.xfsession` → debe puntuar ≥ 0.88
- `flare-2c__late.xfsession` → debe detectar sesgo positivo de ~35 ms
- `flare-2c__sloppy.xfsession` → debe puntuar ≤ 0.60 y senalar dispersion

Son los tests que de verdad protegen el producto: describen el comportamiento
deseado con datos reales, no con numeros inventados.

## Integracion continua

`.github/workflows/ci.yml` corre en cada push: `macos-13` (Intel, toolchain fijada),
`macos-14` (**Apple Silicon**, comprobacion de arquitectura) y un trabajo que
verifica que el binario sale universal. Los runners arm64 son gratis en repos
publicos y son la unica forma de cubrir Apple Silicon sin comprar hardware.
Detalle en `docs/ARCHITECTURES.md` seccion 5.

## Matriz de maquinas

Todo lo que toque audio o render se prueba en **las dos maquinas**: la de referencia
y el MacBook Pro Intel de 2015. Ver `docs/PLATFORM_SUPPORT.md` seccion 9. Un cambio
que va fino en la maquina buena y estrangula la de 2015 es un cambio roto.

## Presupuesto de tiempo real

Se comprueba a mano con Instruments (Audio System Trace) al cerrar cada bloque que
toque audio, y queda anotado en `docs/TIMECODE.md`:

- [ ] Round-trip ≤ 10 ms en el Mac de referencia; ≤ 15 ms en el Intel de 2015
- [ ] 0 overloads en 5 minutos de scratch continuo
- [ ] Sin deriva de sincronia tras 10 minutos
- [ ] Uso de CPU del hilo de audio por debajo del 25%

## make verify

```
make verify          # compila todo, tests de todos los modulos, goldens, lint
make test M=XFClock  # solo un modulo
make golden-update   # regenera goldens (revisar el diff SIEMPRE)
make seal M=XFClock  # comprueba las 5 condiciones de sellado
make status          # imprime el backlog: hecho, en curso, siguiente
```

`make verify` en verde es la condicion para cerrar cualquier tarea. Sin excepciones.
