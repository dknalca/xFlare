# Calentamiento (futuribles, disenado)

> No entra en la v1, pero se diseña ahora para que la base de datos y el motor no
> tengan que rehacerse despues. Ver ADR-027.

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

A cada uno le asigna una **variante al azar entre las desbloqueadas**, nunca la
misma que la vez anterior. Esa aleatoriedad es lo que impide que el calentamiento
se convierta en un automatismo mas.

## Reglas

- **No penaliza.** Las estrellas no bajan y no hay sensacion de examen.
- **Si registra.** Cada toma se guarda con `countsForStars: false`.
- Un solo pase por ejercicio, sin repetir, sin subir BPM.
- Se puede saltar entero con un boton. Obligar a calentar es la mejor forma de que
  la gente deje de abrir la app.

## Lo que aporta de verdad: detectar oxidacion

Si un ejercicio dominado baja de 2★ en calentamiento, se marca **oxidado** y vuelve
a la rotacion de practica. El aviso es amable y concreto:

> *"El crab se te esta cayendo: hoy 78%, tu media era 94%. Lo meto de vuelta en la
> rotacion esta semana."*

Eso es lo que hace un profesor y no hace ninguna app de ritmo.
