# Variantes

> **⚠️ EN PAUSA (2026-09-02).** `data/curriculum/variants.json` se redujo a solo
> `base` a peticion del autor ("simplifica y elimina variantes; ya las
> introduciremos en el futuro"). El **codigo esta dormido, no borrado**:
> `Composer` (transforms), `VariantInfo.Transform`, `VariantAssembler` y
> `VariantPickerView` siguen ahi y probados. Este documento describe el diseno
> que se reactivara. Ver `docs/DECISIONS.md` ADR-050.
>
> Un patron base, muchos ejercicios. Las variantes son **transformaciones**
> generadas, no patrones escritos a mano (ADR-026).
> Datos: `data/curriculum/variants.json`. Referencia: `tools/xfn_core.py`.
> Vista comparada: `preview/variantes.png`.

## 1. La idea

Igual que la libreria es generativa (ADR-015), las variantes tambien. Un
2-Click Flare no es un ejercicio: es **diez**, porque el mismo gesto entrado por la
mitad, con la mitad de recorrido o con swing suena a otra cosa y se toca distinto.

Identificador: `ejercicio@variante` → `flare-2c@off50`, `crab@div16`.

**Estan cableadas a la practica (ADR-043):** `AppModel.scratch(exerciseId:variantId:)`
aplica el transform sobre el patron base antes de practicarlo. `sub-1-2/4/8` son
la **escalera de subdivision del gym**: el truco arranca ocupando 1 compas
(`sub-1-2`, un ciclo por compas) y se va a 2 y 4 ciclos por compas — corcheas es
el tope de momento. `dropout` (blind) no transforma el patron: es logica de sesion.

## 2. Catalogo

| id | Nombre | Transformacion | Dificultad | Se desbloquea con |
|---|---|---|---|---|
| `base` | Base | identidad | 1.00 | — |
| `sub-1-2` | 1 por compas | `subdivision(1/2)` | 0.70 | — (entrada del gym) |
| `sub-1-4` | 2 por compas | `subdivision(1/4)` | 0.85 | 2★ en sub-1-2 |
| `sub-1-8` | 4 por compas | `subdivision(1/8)` | 1.00 | 2★ en sub-1-4 |
| `off25` | Entrada a 1/4 | `offset(0.25)` | 1.15 | 2★ en base |
| `off50` | Entrada a la mitad | `offset(0.50)` | 1.25 | 2★ en base |
| `off75` | Entrada a 3/4 | `offset(0.75)` | 1.30 | 2★ en off50 |
| `amp50` | Recorrido corto | `amplitude(0.5)` | 1.20 | 2★ en base |
| `amp150` | Recorrido largo | `amplitude(1.5)` | 1.20 | 2★ en base |
| `mirror` | Empezando hacia atras | `mirror` | 1.25 | 3★ en base |
| `div16` | Doble tiempo | `subdivision(1/16)` | 1.40 | 3★ en base |
| `swing` | Con swing | `swing(0.62)` | 1.35 | 2★ en div16 |
| `blind` | A ciegas | `dropout([1,1,0,0])` | 1.50 | 3★ en base |

El BPM es un eje aparte, no una variante: cada variante tiene su propia escalera.

## 3. Como funciona cada transformacion

### `offset(fraction)` — entrar desplazado
La que mas cambia la sonoridad y la que mas cuesta. Se genera el patron con un
ciclo de mas y se **recorta** la ventana desplazada. Como el corte puede caer en
mitad de un movimiento, las fases guardan un tramo parcial de su curva (`u0`, `u1`)
en vez de partirse en trozos rectos. Asi el gesto sigue siendo exacto.

Musicalmente: un flare entrado por la vuelta empieza con el disco cayendo. El
primer sonido es descendente en vez de ascendente y el oido lo lee como otro
scratch, aunque la mano haga lo mismo.

### `amplitude(scale)` — recorrido
Escala el recorrido del disco sin tocar el tiempo. Medio recorrido = el mismo gesto
mas agudo y con la mitad de margen de error. Recorrido y medio = mas grave y obliga
a mover mas rapido. Es trabajo puro de control de tono.

### `mirror` — empezar hacia atras
Invierte el sentido del gesto: lo que iba adelante va atras. **No** es el modo
hamster: el hamster invierte el crossfader y es una opcion del perfil de mesa
(`reverse_default`), no del patron. Aqui lo que cambia es la mano. Sirve para
descubrir la asimetria que casi todo el mundo tiene entre ida y vuelta.

### `subdivision(div)` — doble tiempo
Recompone el patron con otra rejilla. No es "el mismo ejercicio mas rapido": tiene
el doble de clicks y por tanto el doble de puntos posibles.

### `swing(ratio)` — groove
Deforma la rejilla de corcheas. `0.5` es recto, `0.62` es un swing marcado, `0.66`
es tresillo. Los clicks se desplazan con la rejilla, no contra ella.

### `dropout(pattern)` — a ciegas
No transforma el patron: apaga la guia visual en algunos compases. Dos con guia,
dos sin ella, y **solo puntuan los ciegos**. Es la mejor prueba de si de verdad lo
has interiorizado o solo estabas siguiendo una linea por la pantalla.

## 4. Ideas para mas adelante

Cosas que encajan en el mismo motor y no cuestan casi nada una vez estan las de arriba:

- **Encadenado**: dos patrones alternando por compas (`baby | flare-2c`). Es como se
  construyen las rutinas de verdad.
- **Densidad creciente**: 1 click, 2, 3, 4 en compases consecutivos sobre el mismo
  gesto de mano. Prueba brutal de independencia mano/fader.
- **Rampa de tempo**: acelerando dentro de la toma.
- **Un solo lado**: puntuar solo la ida o solo la vuelta, para corregir la asimetria
  que descubra `mirror`.
- **Cambio de sample a mitad**: mismo patron, otro sonido, para romper el automatismo.

## 5. Nota honesta sobre el recorte

Al recortar por un punto arbitrario, una variante `offset` puede quedarse con un
control de tono de mas o de menos en los bordes, asi que su maximo de puntos puede
diferir en 100 respecto a la base. Es correcto (hay literalmente un evento mas), pero
conviene saberlo antes de comparar puntuaciones brutas entre variantes. **Comparad
siempre porcentajes.**
