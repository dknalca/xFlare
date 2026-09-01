# Puntuacion, estrellas y progreso

> Como se convierte una toma en un numero, tres estrellas y una linea de progreso.
> Datos: `data/curriculum/scoring.json`. Modulo: `XFAnalysis` puntua, `XFPersistence` guarda.

## 1. Puntos: "3.840 de 4.800"

Cada patron tiene un numero fijo de **eventos evaluables**, y cada evento vale
**hasta 100 puntos**. El maximo del ejercicio es `eventos x 100`, se conoce **antes**
de empezar y se muestra siempre.

| Tipo de evento | Cuantos hay | Como se puntua |
|---|---|---|
| `click` | uno por cierre de fader del patron | desfase con signo contra la ventana |
| `pitch` | uno por **semicorchea** (`ppq/4` = 120 ticks) | distancia local de contorno (DTW) |
| `amplitude` | uno por trazo hacia delante | error relativo de recorrido |

Ventanas de click: **±20 ms → 100 · ±40 → 75 · ±70 → 50 · ±110 → 25 · fuera → 0**.

Formula exacta (la implementa `XFNotation.ScoreEvents`, criterio unificado
2026-09-01):
```
clicks    = nº de eventos `closed` del patron
pitch     = max(1, lengthTicks / (ppq/4))
amplitude = max(1, nº de fases `fwd` del carril de disco)
maxScore  = (clicks + pitch + amplitude) * 100
```

Ejemplo real, 2-Click Flare base (4 ciclos a 1/8, 1920 ticks = 1 compas):
16 clicks + 16 controles de tono + 4 de amplitud = 36 eventos = **3.600 puntos
posibles**. Su variante de doble tiempo `subdivision(1/16)` conserva la longitud
musical y pasa a 8 ciclos: 32 clicks + 16 tono + 8 amplitud = 56 eventos =
**5.600**.

Que el maximo dependa de la variante es intencionado: un patron con el doble de
clicks tiene el doble de oportunidades de acertar, y el porcentaje sigue siendo
comparable entre ambos.

## 2. Tres estrellas, tres cosas distintas

Las estrellas **no son tres umbrales del mismo numero**. Cada una mide algo
diferente, y por eso el numero de estrellas ya es un diagnostico:

| | Nombre | Condicion | Que significa |
|---|---|---|---|
| ★ | **Completado** | ≥70% y llegaste al final | Lo has hecho |
| ★★ | **Limpio** | ≥85% **y cero eventos a 0** | No se te ha caido ninguno |
| ★★★ | **Solido** | ≥95%, **σ ≤ 15 ms** y al BPM objetivo | Lo dominas |

Por que asi y no por porcentaje a secas:

- La segunda estrella castiga **el fallo suelto**. Puedes tener un 88% con un click
  perdido; eso no es limpio, y en una rutina se oye.
- La tercera exige **regularidad** (σ) y **tempo**. Impide sacar tres estrellas por
  suerte en una toma buena, que es justo lo que hace inutiles los sistemas de
  estrellas de la mayoria de juegos.

Las estrellas **no bajan nunca**: se guarda la mejor marca. Lo que si registra el
historial es si has empeorado, y de eso se encarga el calentamiento (seccion 5).

## 3. Progreso por ejercicio

Cada variante de cada ejercicio guarda:

| Dato | Para que |
|---|---|
| Numero de intentos | Cuanto has insistido |
| Mejor puntuacion y su fecha | Tu techo |
| Ultima puntuacion | Como estas hoy |
| Media de los ultimos 5 | Tu nivel real, sin el pico de suerte |
| Estrellas conseguidas | El estado |
| BPM mas alto con 3★ | La medida honesta de mejora |
| Sesgo medio (ms, con signo) | ¿vas tarde o pronto de forma sistematica? |
| Tiempo total practicado | — |

En pantalla, una **linea de puntuaciones** de los ultimos 20 intentos. Es la grafica
que te demuestra que estas mejorando los dias en que no lo sientes.

Cada intento guarda ademas el `.xfsession` crudo, asi que cualquier toma antigua se
puede volver a oir y a analizar con un scoring mejorado mas adelante.

## 4. Dominado

Un ejercicio esta **dominado** cuando tiene **3★ en la base y 2★ en al menos tres
variantes**. No basta con clavar el patron de memoria: hay que sostenerlo cuando
cambia la entrada, el recorrido o el tempo. Ese es el filtro que separa "me sale"
de "lo se hacer".

Solo los ejercicios dominados entran en el calentamiento.

## 5. Oxidacion

Si en calentamiento un ejercicio dominado baja de 2★, se marca **oxidado** y vuelve
a la rotacion de practica con un aviso amable. Es la funcion mas util de todo el
sistema de progreso: detecta lo que se te esta cayendo **antes** de que lo notes en
una actuacion.

## 6. Lo que NO se hace

- Nada de XP, monedas, ligas ni rachas agresivas. Un contador de dias honesto y ya.
- No se penaliza abandonar una toma: se guarda como incompleta y no cuenta.
- No hay clasificacion online. Compites contigo de la semana pasada.
