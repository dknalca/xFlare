# Mapeo con la Periodic Matrix of Skratches

## 1. Aviso legal y de atribucion — leer antes de codificar

La **Periodic Matrix of Skratches™** y **TTM™** son obra de TTM Academy — la metodologia TTM la crearon John Carluccio, Ethan Imboden y Ray "DJ Raedawn" Pirtle (2000), y la matriz es de DJ Raedawn —
con copyright y marca registrada. xFlare es GPL-3.0-only y se distribuye publicamente,
asi que las reglas son estrictas:

- ❌ **No** incluir el poster, ni recortes, ni celdas escaneadas en el repositorio.
- ❌ **No** copiar el arte, la tipografia ni la maquetacion de la matriz.
- ❌ **No** usar "TTM" ni "Periodic Matrix" en el nombre del producto ni en la UI
  de forma que sugiera afiliacion.
- ✅ **Si** se pueden usar los **nombres de las tecnicas** (baby, flare, orbit, crab,
  chirp, tear...): son terminologia comun de la comunidad turntablista, anterior e
  independiente del poster.
- ✅ **Si** se puede adoptar la **gramatica visual** de TTM (tiempo en X, posicion en Y,
  marcas de fader): es un metodo de notacion, y los metodos no se protegen por copyright.
- ✅ Incluir atribucion en `README.md` y en la pantalla de creditos:
  *"La notacion de xFlare esta inspirada en el trabajo de TTM Academy y la Periodic
  Matrix of Skratches de DJ Raedawn. xFlare no esta afiliado ni respaldado por ellos."*

Si en algun momento se quiere ir mas alla (reproducir la matriz, usar la marca,
distribuir el poster dentro de la app) → **hay que pedir licencia por escrito**.

## 2. Los ejes de la matriz

La matriz esta construida sobre exactamente la misma logica que XFN:

| Eje de la matriz | Equivalente en XFN |
|---|---|
| Columna izquierda: tecnicas de fader puro (cuts, stabs, drags) | `fader_patterns` con mano simple |
| Cuerpo central: familias (Flare, Orbit, Chirp, Crab, Tear, Transformer, Tazer…) | producto `hand × fader` |
| Cabecera superior: divisiones de tiempo y RPM | parametro `div` + `bpmReference` |
| Panel derecho: notas, silencios, subdivisiones | rejilla de la rejilla XFN |

## 3. Diccionario de prefijos — con nivel de confianza

Esto es lo que se ha podido inferir de la imagen. **Se marca honestamente lo que no
esta verificado**: antes de dar por buena una definicion, contrastar con la fuente.

| Termino | Interpretacion asumida | Confianza |
|---|---|---|
| `nC` (1C, 2C, 3C, 4C) | Numero de clicks de fader por trazo | **Alta** |
| `Flare` | Fader abierto, interrumpido por clicks | **Alta** |
| `Orbit` | Flare ejecutado en circulo continuo, click tambien en la vuelta | **Alta** |
| `Chirp` | Abre al arrancar, cierra al frenar | **Alta** |
| `Tear` | Movimiento del disco partido con paradas | **Alta** |
| `Crab` | Clicks con 4 dedos contra el pulgar | **Alta** |
| `Twiddle` | Clicks alternando 2 dedos | **Alta** |
| `Transformer` | Fader trocea un movimiento lento y continuo | **Alta** |
| `Lo-` | El/los click(s) caen en la primera mitad del trazo | **Media** |
| `Hi-` | El/los click(s) caen en la segunda mitad del trazo | **Media** |
| `STC` | ¿Split Tear Click? | **POR VERIFICAR** |
| `HC` | ¿Half Click? ¿Hi Click? | **POR VERIFICAR** |
| `OC` | ¿Open Click? | **POR VERIFICAR** |
| `DC` | ¿Double Click? | **POR VERIFICAR** |
| `Tazer` / `Laser` | Familia de tono ascendente/descendente rapido | **Baja** |
| `Phantom` | — | **POR VERIFICAR** |
| `Uzi` | Transformer muy rapido, tipo rafaga | **Media** |
| `Hydroplane` | Friccion del dedo sobre el disco (textura) | **Alta** |
| `Squat`, `Phasor`, `Needle Skiz` | — | **POR VERIFICAR** |

## 3b. Manual TTM oficial (leido 2026-09-01)

Fuente: `TTM_Castellano.pdf` (15 pag., traduccion "daggah" del manual de
Carluccio/Imboden/Pirtle), guardado en `_local-reference/` (gitignored). Solo se
extraen **hechos del metodo**, no su prosa. Confirma o corrige lo de arriba:

- **Ejes (CONFIRMA `NOTATION.md`):** X = tiempo, Y = rotacion del disco. Disco
  adelante (horario) → la linea **sube**; atras → **baja**; parado → **horizontal**;
  una linea **vertical no significa nada** (movimiento en tiempo cero). Mas lento =
  menos pendiente (mas cuadros). Dos scratches no se solapan en el tiempo.
- **Rejilla por defecto = 1/16** (compas partido en 16). Cambio de escala con un
  **triangulo invertido**. → nuestra rejilla de negras/compas (ADR-038) es un
  subconjunto; la escala de subdivision del ejercicio es cosa aparte.
- **"Linea de sample"** a la izquierda: lineas horizontales que marcan zonas del
  sample (principio, final, silabas).
- **Fader abierto:** scratch que empieza **y termina** con el fader en on (baby,
  scribble, flare, orbit). Incluye el sonido del cambio de direccion.
- **Phantom click (CONFIRMA/define):** en el cambio de direccion el disco queda
  parado un instante → mini-silencio que corta el sonido **sin mover el fader**.
  Un flare de 2 clicks reales + 2 phantom suena a 4 cortes. → xFlare deberia
  marcarlos en la sombra/miniatura de los scratches de fader abierto.
- **Flare** (DJ Flare → Q-bert): fader abierto, ida y vuelta con **1 click a mitad
  de ida y a mitad de vuelta**. El cambio de direccion **se oye** (a diferencia de
  chirp/transformer). → el `Lo-`/`Hi-` del poster es una **extension de la matriz**,
  no del manual (el flare canonico es a mitad de trazo). Sigue en **Media**.
- **Crab** (Q-bert): pulgar contra los 4 dedos en secuencia menique→indice = 4
  clicks. **Twiddle** = alternar 2 dedos.
- **Chirp:** el sonido se corta al cambiar de direccion, un sonido por direccion;
  el pitch sube/baja con la velocidad. **Transformer:** ida y vuelta mientras el
  fader abre/cierra, varios cortes por ciclo en ambos sentidos.
- **Forward** = baby cortando la vuelta con fader/linea/interruptor. **Military** =
  forwards alternados con baby. **Stab** = rapido y agudo, la vuelta no se oye.
  **Scribble** = baby muy rapido en un trozo pequeno, vibracion de la yema.
- **Scratch sobre ritmo:** dos pentagramas (TT1/TT2) unidos por una **barra
  vertical** = simultaneidad. Debajo de cada pentagrama, la **"linea del mixer"**
  para anotaciones de fader/volumen. Si un plato se manipula poco, su pentagrama
  se **suprime** y se resume en la linea de mixer del otro. → asi es como el
  manual mete el ritmo: no como onda, como pentagrama alineado en el mismo eje X.
- **Delaying / Chasing:** dos copias desfasadas 1/8; el fader alterna canales al
  mismo intervalo (chasing = ademas para el disco entre golpes). Simbolos
  `|-1/8-/\/\-` (alternar) y `|------|` (continuacion).
- **Pitch/tono:** linea continua para el pitch, lineas cortadas para la duracion
  de nota, altura = pitch. Simbolo `P` + nº de plato, valor en % de rpm.

**Vocabulario del manual = pequeno.** El manual solo nombra: baby, forward,
military, scribble, stab, chirp, transformer, flare, crab, orbit. **Todo lo demas
del poster (~900 celdas: Tazer, Laser, Uzi, Phantom-como-familia, Squat, Phasor,
Needle Skiz, prefijos STC/HC/OC/DC…) es la expansion generativa propia de DJ
Raedawn.** Razon de mas para **no** copiar esos nombres de celda: xFlare hace su
**propia** expansion generativa desde estos ~10 movimientos canonicos + las
primitivas de fader, y solo usa nombres que son de verdad comunes en la comunidad.

## 4. TODO antes de la v0.2 de la libreria

- [x] Leido el manual TTM oficial (§3b): confirma ejes, define phantom click y
      fader abierto, y deja claro que el vocabulario canonico es de ~10 moves.
- [ ] Los terminos STC/HC/OC/DC/Tazer/Squat/Phasor **no salen en el manual** — son
      del poster. Si algun dia se quieren, verificar con la comunidad, no adivinar.
- [ ] Confirmar el convenio de marcadores: ¿circulo hueco = abrir y relleno = cerrar,
      o al reves? La leyenda del poster dice "Open Fader / Click Fader" — hay que
      mirarla a alta resolucion. **Nuestro convenio actual esta documentado en
      `NOTATION.md` §4 y es autoconsistente aunque no coincida.**
- [ ] Modelar el **phantom click** en la sombra/miniatura: marcar el cambio de
      direccion en los scratches de fader abierto (baby, flare, orbit).
- [ ] Decidir si merece la pena contactar a TTM Academy para una colaboracion o
      licencia oficial. Seria un diferenciador enorme y evita cualquier zona gris.
- [ ] Ampliar `fader_patterns.json` con las familias de confianza Media/Baja una vez
      verificadas.
