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

## 4. TODO antes de la v0.2 de la libreria

- [ ] Verificar los terminos marcados POR VERIFICAR con material de TTM Academy
      o con la comunidad (r/turntablism, foros de DMC).
- [ ] Confirmar el convenio de marcadores: ¿circulo hueco = abrir y relleno = cerrar,
      o al reves? La leyenda del poster dice "Open Fader / Click Fader" — hay que
      mirarla a alta resolucion. **Nuestro convenio actual esta documentado en
      `NOTATION.md` §4 y es autoconsistente aunque no coincida.**
- [ ] Decidir si merece la pena contactar a TTM Academy para una colaboracion o
      licencia oficial. Seria un diferenciador enorme y evita cualquier zona gris.
- [ ] Ampliar `fader_patterns.json` con las familias de confianza Media/Baja una vez
      verificadas.
