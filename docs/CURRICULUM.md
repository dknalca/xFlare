# El Gym — currículo de xFlare

> Como se convierte una libreria de patrones en un plan de entrenamiento.
> Datos: `data/curriculum/levels.json` y `data/curriculum/exercises.json`.

## 1. Filosofia

No es un juego de puntuacion, es un **gimnasio**. Tres principios:

1. **Tempo antes que dificultad.** Siempre se empieza lento. Un 2-click flare a 60 BPM
   limpio vale mas que uno a 95 BPM sucio. La escalera de BPM es el peso de la barra.
2. **Series y repeticiones.** 3 series de 4 compases con descanso, no 10 minutos
   seguidos. El scratch es memoria muscular y la fatiga arruina el patron.
3. **Diagnostico, no nota.** El valor no es "78%", es *"tu segundo click va 35 ms tarde
   de forma sistematica en el trazo de vuelta"*. Eso es lo que hace un profesor.

## 2. Niveles

| Nivel | Nombre | Objetivo | Contenido |
|---|---|---|---|
| **L1** | Fundamentos | Mano a tiempo, sin pensar en el fader | Baby, Forward Cut, Stab, Drag |
| **L2** | Control de mano | Partir el movimiento, sostener velocidades | Baby 1/16, Reverse Cut, Tear, Scribble, Transformer x2 |
| **L3** | Fader basico | Mano y fader independientes | Transformer x3, Chirp, Tear de 3, 1-Click Flare |
| **L4** | Flares | Colocar el click dentro del trazo | Lo/Hi-1C, 2-Click Flare, 1-Click Orbit, Tear Flare, Transformer x4, Hydroplane |
| **L5** | Intermedio | Multiplicar clicks sin perder pulso | 3-Click Flare, 2-Click Orbit, Twiddle |
| **L6** | Velocidad | Los mismos patrones, al doble | Crab, 2-Click Flare a 1/16 |

Desbloqueo: hay que superar el umbral de precision del nivel **en N compases seguidos**,
no de media. La media perdona los fallos; el streak no.

## 3. Bucle de sesion

```
Calentamiento (2 min)     baby scratch libre, sin puntuar, para calibrar mano y fader
      ↓
Repaso (3 min)            1 ejercicio ya superado, elegido por repeticion espaciada
      ↓
Bloque principal (10 min) 3 series x 4 compases del ejercicio actual
                          si fallas 2 series seguidas → baja un escalon de BPM
                          si superas 3 seguidas      → sube un escalon
      ↓
Boss (2 min)              el patron al BPM objetivo, una sola toma, sin red
      ↓
Enfriamiento              scratch libre grabado, se guarda en la libreria personal
```

## 4. Modos

- `ghost` — el patron objetivo se mueve por la pantalla y tu lo persigues. Modo por defecto.
- `listen` — solo suena el patron, tu no tocas. Para interiorizar antes de intentar.
- `metronome` — sin fantasma visual, solo claqueta. El examen de verdad.
- `free` — sin evaluacion, se graba todo y se analiza al final.

## 4.5 Variantes, puntos y estrellas

Cada ejercicio tiene hasta **10 variantes** generadas por transformacion
(`docs/VARIANTS.md`) y se puntua sobre un maximo conocido de antemano, con tres
estrellas que miden cosas distintas (`docs/SCORING.md`). El calentamiento adaptativo
esta disenado en `docs/WARMUP.md` y queda para despues de la v1.

## 5. Scoring

Por cada compas se calcula:

| Metrica | Como | Peso |
|---|---|---|
| Timing de clicks | desfase con signo vs objetivo, ventanas ±20/40/70/110 ms | 40% |
| Contorno de tono | distancia DTW normalizada de la curva del disco | 35% |
| Regularidad | desviacion tipica del desfase (penaliza la inconsistencia) | 15% |
| Amplitud | que el recorrido del disco sea el pedido (ni corto ni pasado) | 10% |

## 6. Deteccion de debilidades

El coach agrupa los desfases y busca patrones. Mensajes que debe saber dar:

- *"Tus clicks de ida van bien; los de vuelta van 40 ms tarde de media."* → el dedo
  no recupera; trabajar el rebote.
- *"El primer click es perfecto, el segundo se te junta."* → estas colapsando el
  patron; bajar 10 BPM.
- *"Vas consistentemente 25 ms tarde, pero muy regular."* → solo hay que adelantar
  la entrada; es el fallo mas facil de arreglar y hay que decirlo asi.
- *"Tu recorrido de disco se acorta a partir del compas 3."* → fatiga o tension.

## 7. Progreso a largo plazo

- **Repeticion espaciada** sobre ejercicios superados (1 dia, 3, 7, 21).
- **Mapa de la matriz**: rejilla visual de todos los scratches, se van iluminando.
  Es la zanahoria y ademas ensena la logica composicional de un vistazo.
- **Racha diaria** con un minimo honesto (10 min), no gamificacion agresiva.
- **Historico de BPM** por patron: la grafica que demuestra que estas mejorando
  aunque hoy no lo sientas.
