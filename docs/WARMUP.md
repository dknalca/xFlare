# Calentamiento (F.0)

> **Estado (2026-09-03):** la **logica y la pantalla estan hechas** (adelantado
> de futuribles a peticion del autor). `WarmupPlanner` escoge el plan,
> `WarmupOxidation` detecta la oxidacion, `AppModel.warmupPlan`/`settleWarmupTake`
> hacen el pegamento con la BD (ya lista desde la v1), y `WarmupView` + la nav
> "Calentar" lo enseñan. El calentamiento entero corre en **una sola sesion**:
> `AppModel.startWarmupSession()` monta `[WarmupStep]` del plan, abre la practica
> en el primero y `LivePracticeView` va encadenando el resto con
> `PracticeSession.reload(scratch:)` conforme se completan las frases de "repite
> conmigo". **Falta**: que la toma en modo calentamiento llame a
> `settleWarmupTake` (la practica tiene que saber que esta calentando) para que
> la oxidacion se detecte de verdad. Ver ADR-027 y `TODO.md` F.0.

## Que es

Cinco minutos al empezar la sesion repasando lo que **ya dominas**, con variantes
distintas cada dia. No es practica: es despertar la mano y detectar oxidacion.

## Como elige los ejercicios

Del conjunto de ejercicios **dominados** (3★ base + 2★ en tres variantes), escoge
entre 4 y 6 puntuando cada candidato por:

| Factor | Peso | Por que |
|---|---|---|
| Dias desde el ultimo repaso | alto | Repeticion espaciada: 1, 3, 7, 21 dias |
| Media reciente por debajo de tu techo | alto | Lo que se esta cayendo primero |
| Variedad de familia | medio | Que no salgan cuatro flares seguidos |
| Antiguedad del dominio | bajo | Lo aprendido hace mucho se oxida distinto |

**Sin historial** (nada dominado todavia): en vez de una pantalla vacia sale una
**rutina de arranque** fija — Forward Cut → Reverse Cut → Chirp → Transformer x2,
cada uno **8 frases de 2 compases** (16 compases). "Empezar calentamiento" abre
la practica ya en "repite conmigo" con frases de 2 compases y **encadena los
cuatro ejercicios sin salir**: al completar las 8 frases de uno, el patron cambia
en caliente al siguiente (la barra superior marca "Calentamiento i/N").

A cada uno le asigna una **variante al azar entre las desbloqueadas**, nunca la
misma que la vez anterior. Esa aleatoriedad es lo que impide que el calentamiento
se convierta en un automatismo mas.

## Reglas

- **No penaliza.** Las estrellas no bajan y no hay sensacion de examen.
- **Si registra.** Cada toma se guarda con `countsForStars: false`.
- Un solo pase por ejercicio, sin repetir, sin subir BPM.
- **Es una sola sesion**: no se vuelve a la lista entre ejercicios; el patron se
  cambia en caliente (`PracticeSession.reload`). El reloj musical no se reinicia
  (la rejilla sigue latiendo); solo se limpia la traza y el plato vuelve al inicio.
- Se puede saltar entero con un boton. Obligar a calentar es la mejor forma de que
  la gente deje de abrir la app.

## Lo que aporta de verdad: detectar oxidacion

Si un ejercicio dominado baja de 2★ en calentamiento, se marca **oxidado** y vuelve
a la rotacion de practica. El aviso es amable y concreto:

> *"El crab se te esta cayendo: hoy 78%, tu media era 94%. Lo meto de vuelta en la
> rotacion esta semana."*

Eso es lo que hace un profesor y no hace ninguna app de ritmo.
