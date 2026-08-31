# Trabajo previo

Lo que ya existe, que se aprende de ello y donde esta el hueco que ocupa xFlare.

## Visual Scratch — Jesse Kriss

Visualizacion en tiempo real de scratch, montada sobre **Ms. Pinky** (vinilo de
control con SDK), **Processing** para el dibujo y **Max/MSP** con MaxLink de pegamento.

Lo que valida: **ver tu propio scratch dibujado mientras lo haces ya ensena por si
solo.** El bucle ojo-mano es inmediato y revela cosas que el oido no separa —
sobre todo la asimetria entre ida y vuelta.

Lo que le falta y es exactamente nuestro hueco:

| Visual Scratch | xFlare |
|---|---|
| Visualiza lo que haces | Visualiza **y compara contra un objetivo** |
| No puntua ni diagnostica | Diagnostico accionable en ms con signo |
| No hay progresion ni curriculo | Gimnasio con niveles y escalera de BPM |
| Instalacion de tres piezas (Ms. Pinky + Processing + Max/MSP) | Una app, un DMG |
| Proyecto artistico/exploratorio | Producto de aprendizaje |

Ideas concretas que merece la pena robar: el dibujo continuo del recorrido como
estela (no solo la curva del compas actual), y la lectura del gesto como forma
reconocible antes que como serie de eventos.

## TTM — Turntablist Transcription Methodology (2000)

De **John Carluccio, Ethan Imboden y Ray "DJ Raedawn" Pirtle**. Eje vertical para
la posicion del sample, rejilla horizontal para tiempo y compas, marcas para los
cortes de crossfader. Es el estandar de facto y la base de nuestra notacion XFN.

## Periodic Matrix of Skratches — DJ Raedawn / TTM Academy

El diccionario: mas de 900 tecnicas organizadas por ejes que se multiplican. De ahi
sale la decision de que nuestra libreria sea **generativa** (ADR-015). Ver
`docs/MATRIX_MAPPING.md` para las reglas legales.

## S-notation — Sonnenfeld

Alternativa academica centrada en la "Theory of Motion" y en representar gestos
musicales concurrentes. Interesante si algun dia hacemos notacion de dos platos
(FUT F.1), porque ese es justo el problema que ataca.

## Ms. Pinky y xwax

Ms. Pinky fue de los primeros vinilos de control con SDK abierto para terceros.
Nosotros usamos **xwax** (GPL-3.0-only), que resuelve lo mismo con codigo libre y
mantenido. Ver ADR de vendorizacion.

## Serato, Traktor, Rekordbox

Son instrumentos, no profesores. Ninguno te dice que tu segundo click va tarde.
No competimos con ellos: xFlare se pone **al lado** del DVS, no en su lugar.

## Melodics

El competidor conceptual mas cercano: leccion guiada con hardware real, evaluacion
por tiempo, progresion. Cubre teclado, pads y controladores de DJ.
**Pendiente de verificar** si a dia de hoy cubre scratch con timecode; hasta donde
llega mi informacion, no. Si lo hiciera, seria la referencia a estudiar en detalle
antes de seguir. **Tarea: comprobarlo antes de cerrar el diseno del gimnasio.**

## Conclusion

El hueco es real y estrecho: **nadie junta captura de timecode + notacion tipo TTM +
evaluacion con diagnostico + curriculo**. Visual Scratch hizo la primera pieza hace
anos y se quedo ahi. Melodics hizo las otras tres para otros instrumentos.
