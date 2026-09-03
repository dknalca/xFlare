# Diseno de interfaz de xFlare

> Moderna, oscura y amable. Estado: v0.2. Se implementa en `XFDesign` (tokens y
> componentes) y `XFApp` (pantallas). El dibujo de la autopista va en `XFRender`.

> **Restriccion de plataforma:** minimo macOS 11.0, Swift 5.7, Xcode 14.2.
> Antes de usar cualquier API de SwiftUI, comprueba la lista de prohibidas en
> `docs/PLATFORM_SUPPORT.md` seccion 4. `NavigationStack`, `.searchable`, `Table`
> y `@Observable` **no existen aqui**.

## 1. Principios

1. **El instrumento manda.** Estas mirando la pantalla con las dos manos ocupadas.
   Nada critico se hace con el raton durante una toma.
2. **Oscura por defecto.** Los DJs practican de noche y tocan en cabinas. Negro
   suave (nunca `#000000`, que vibra en OLED y cansa), acentos saturados.
3. **Un numero grande, nunca cinco.** En pantalla solo lo que se lee de reojo.
   El detalle llega despues de la toma.
4. **Diagnostico en cristiano.** "Tu segundo click va 35 ms tarde", no "sigma=0.34".
5. **Amable = perdona.** Nada de pantallas de error. Sin mesa conectada, te ofrece
   el modo teclado y sigues adelante.

## 2. Tokens de diseno (`XFDesign`)

### Color

| Token | Hex | Uso |
|---|---|---|
| `bg` | `#0B0D10` | Fondo de ventana |
| `surface` | `#14181D` | Tarjetas, paneles |
| `surfaceRaised` | `#1E242B` | Modales, menus |
| `stroke` | `#2A323B` | Bordes de 1 px |
| `text` | `#F2F5F7` | Texto principal |
| `textMuted` | `#9AA5B1` | Secundario |
| `accent` | `#34E1C4` | **Tu**: tu curva, tu fader, foco |
| `ghost` | `#7A8794` al 35% | El patron objetivo |
| `grid` | `#232A32` | Rejilla de compas |
| `gridBeat` | `#3A444F` | Linea de negra |

Escala de acierto (**nunca solo color**: cada nivel lleva forma e icono distintos,
por daltonismo):

| Nivel | Hex | Ventana | Forma |
|---|---|---|---|
| Perfecto | `#34E1C4` | ±20 ms | circulo lleno |
| Muy bien | `#8ED44A` | ±40 ms | circulo |
| Bien | `#F5C542` | ±70 ms | rombo |
| Tarde/pronto | `#FF7A45` | ±110 ms | triangulo |
| Fallo | `#FF4D5E` | fuera | cruz |

### Tipografia

- Titulos: **SF Pro Display** Semibold. Amable sin ser infantil.
- Texto: **SF Pro Text** Regular/Medium.
- Numeros (BPM, ms, precision): **SF Mono** Medium con cifras tabulares, para que
  no bailen al actualizarse 60 veces por segundo.

### Espaciado y forma

Escala 4 / 8 / 12 / 16 / 24 / 32 / 48. Radios: 10 en controles, 16 en tarjetas,
24 en modales. Sombras muy suaves; en su lugar, separar por color de superficie.
Materiales translucidos de macOS solo en barras laterales, nunca detras de la
autopista (mata el rendimiento y ensucia la lectura).

### Movimiento

- Todo lo que va a tiempo se anima con **el reloj de audio**, nunca con el frame.
- Escena sincronizada al refresco real: **60 fps garantizados en Intel**, 120 donde
  haya ProMotion. El renderizador se adapta, nunca asume.
- Transiciones de UI: 180 ms, curva `easeOut`. Nada rebota.
- Celebraciones sobrias: un pulso del borde y un contador que sube. Sin confeti.

## 3. Pantallas

### 3.1 Calibracion (primer arranque, y accesible siempre)

Asistente de cuatro pasos. Es la pantalla mas importante del producto: si esto
sale mal, todo lo demas miente.

1. **Audio** — elegir interfaz y salida. Muestra el buffer y la latencia estimada.
2. **Prueba de latencia** — mide round-trip real por loopback. Semaforo:
   verde ≤10 ms, ambar ≤15, rojo por encima con explicacion de que ajustar.
3. **Timecode** — "gira el plato despacio". Scope circular en vivo, indicador de
   calidad de senal y deteccion automatica de direccion y hamster.
4. **Fader** — "haz diez cortes". Detecta el punto de corte, dibuja la curva
   medida y deja ajustarla a mano. Guarda el perfil por dispositivo.

### 3.2 Home — el mapa

- **Rejilla de la matriz** como elemento central: cada celda es un scratch, agrupadas
  por nivel. Apagadas las bloqueadas, con brillo las dominadas. Ensena de un vistazo
  la logica composicional y da sensacion de coleccion.
- Cada celda lleva una **miniatura TTM**: la curva del disco (sube = adelante, baja
  = atras) de un ciclo del gesto. Trazo **lleno** donde suena (fader abierto), **a
  rayas** donde se corta (fader cerrado). Sin puntos ni marcas: la propia curva y
  su estilo cuentan el gesto.
- Recuadro **"Como leer el grafico"** a la derecha: curva de ejemplo + la clave
  lleno/rayas. Para el que llega nuevo a la notacion.
- Tarjeta grande **"Continuar"** con el ejercicio en curso y su BPM actual.
- Racha, minutos de hoy, y la grafica de BPM del ultimo patron trabajado.
- Nada de anuncios de novedades ni ruido.

### 3.3 Practica — la autopista (pantalla heroe)

```
┌──────────────────────────────────────────────────────────────┐
│  ← 2-Click Flare        Serie 2/3       ‹ 80 BPM ›     94%   │  barra fina
├────────┬─────────────────────────────────────────────────────┤
│        │                        ▎                            │
│ scope  │        curva fantasma (gris)                        │
│circular│        curva tuya (verde)          ◀── se desplaza  │
│        │                        ▎                            │
├────────┼─────────────────────────────────────────────────────┤
│ fader  │  ███  ███  ███  ███   carril de fader, mismo scroll │
├────────┴─────────────────────────────────────────────────────┤
│  ●●●○○  ultimos clicks        −18 ms  vas un pelin tarde      │
└──────────────────────────────────────────────────────────────┘
```

- **Cabeza de lectura fija al 30% del ancho**; la partitura se desplaza hacia la
  izquierda. Ves lo que viene con tiempo de reaccion.
- Curva fantasma gris detras, tu curva en acento delante. Donde te sales de
  tolerancia, el trazo se tine del color del nivel de error.
- El **scope circular** de la izquierda es el espejo del plato: posicion de la aguja
  y velocidad. Sirve para saber donde estas sin mirar el vinilo.
- **Cuenta atras de dos compases** con claqueta antes de puntuar.
- Barra inferior: los ultimos clicks como puntos, y **una sola frase** de feedback
  en vivo. Nunca mas de una.
- `Esc` sale siempre, sin dialogos de confirmacion.

### 3.4 Resultados — el diagnostico

**Cabecera:** las tres estrellas con animacion de entrada escalonada (180 ms cada
una), y debajo la puntuacion en grande: `3.840 / 4.800` con el porcentaje al lado.
Las estrellas no conseguidas se ven en gris con **su condicion escrita**:
*"★★★ Solido — te falta bajar de 15 ms de irregularidad"*. Una estrella apagada que
no dice como se consigue es una oportunidad desperdiciada.

Si es tu mejor marca, un `Record` discreto al lado. Sin fuegos artificiales.

**Cuerpo:**

No es una pantalla de nota, es la consulta del fisio.

- Titulo con el veredicto en lenguaje normal: *"Casi. El problema esta en la vuelta."*
- **Grafico de desfases**: un punto por click, eje Y en ms con el cero marcado.
  De un vistazo se ve si hay sesgo (todos abajo) o dispersion (nube).
- **Hasta tres diagnosticos**, priorizados, cada uno con su ejercicio correctivo
  y un boton "practicar esto 2 minutos".
- Reproductor de tu toma con la curva sincronizada. Poder oirse es la mitad del
  aprendizaje.
- **Barra de progreso del ejercicio**: intentos totales, mejor marca, media de los
  ultimos 5, y una linea con las ultimas 20 puntuaciones. Pequena, en el pie.
- Botones: repetir · subir BPM · **probar una variante** · volver al mapa.

### 3.4b Progreso de un ejercicio

Se llega desde resultados o desde la libreria. Una tarjeta por variante:

```
  2-Click Flare
  ┌──────────────────────────────────────────────────┐
  │ Base            ★★★   3.480/3.600  97%   41 int. │
  │ Entrada 1/4     ★★     2.900/3.500  83%   12 int. │
  │ Entrada mitad   ★      2.310/3.500  66%    5 int. │
  │ Recorrido corto  —      bloqueada: 2★ en base     │
  └──────────────────────────────────────────────────┘
       linea de las ultimas 20 puntuaciones
       mejor BPM con 3★: 92    ·    sesgo medio: +12 ms
```

El sesgo medio con signo es el dato mas util de la pantalla y casi nadie lo muestra:
te dice si vas tarde o pronto **de forma sistematica**, que se corrige en un dia.

### 3.5 Libre

Sin fantasma ni puntuacion. Metronomo opcional, grabacion siempre activa en
segundo plano con un "guardar los ultimos 30 segundos" — para cuando te sale algo
bueno por accidente, que es siempre cuando pasa.

### 3.6 Libreria

Buscador de la matriz. Cada scratch con su notacion XFN dibujada, su nivel, su
tecnica de dedos y un boton de escucha. Filtros por familia, nivel y numero de clicks.

### 3.7 Ajustes

Tres **pestañas**: **General** (perfil, audio/buffer, sesión/tolerancia,
accesibilidad, diagnóstico de FPS, vídeo), **MIDI** y **Debug**. Todo local:
**sin cuenta, sin nube, sin telemetria**.

- **Vídeo**: FPS (24/30/60) y resolución (Rápida/Estándar/Alta) de la exportación
  de tomas (F.4).
- Pestaña **Debug** — sliders para dejar fino el "tacto" del plato mientras no
  hay mesa: **glide** (suavizado de velocidad; menos = el audio sigue mejor al
  gesto), **puerta de velocidad** (por debajo enmudece), **fricción** (cómo frena
  al soltar) y **sensibilidad del trackpad**. Se guardan en `AppSettings` y se
  aplican al abrir la práctica. Botón "Restablecer valores".
- Pestaña **MIDI** — asigna una nota o un CC a cada comando de la practica (cue,
  reiniciar la base, congelar, grabar, BPM ±1, fader como momentaneo, metronomo,
  repite conmigo) — los mismos que el teclado. **MIDI Learn**: seleccionas el
  comando, pulsas "Aprender MIDI" y el siguiente control que muevas queda
  asignado (mientras Ajustes esta abierto se escucha CoreMIDI). Tambien se puede
  escribir a mano (`note:canal:nº` / `cc:canal:nº`); vacio = lo que traiga el
  perfil de mesa (seccion `[transport]` del `.conf`, ver `DEVICE_PROFILES.md` §3).
- Cada pestaña es `ScrollView` + tarjetas a mano, **sin `Form`** de SwiftUI: en
  macOS 11 se quedaba en blanco con listas dinamicas (ADR-058).

### 3.8 Mi mesa (dentro de Ajustes)

La pantalla que hace util el sistema de perfiles.

- **Lista de perfiles** agrupada por fabricante, con buscador. Cada uno con su
  insignia: verde `Verificado`, ambar `Sin verificar`, azul `Tuyo`.
- Al seleccionar, **prueba en vivo inmediata**: barras que se mueven al tocar los
  controles. Si el crossfader no responde, un aviso claro con el boton para pasar
  al metodo de retorno de audio, explicado en una frase.
- **Autodeteccion**: si al arrancar reconoce la mesa por nombre de puerto o
  dispositivo de audio, lo propone en un aviso discreto, no lo impone.
- Botones: `Duplicar y editar` (crea un perfil que hereda del oficial),
  `Crear desde cero`, `Importar .conf`, `Abrir carpeta de perfiles`.

### 3.9 Asistente de mapeo MIDI/HID

Modal a pantalla completa, un control cada vez. Nada de tablas de 40 filas.

- **Monitor en crudo** siempre visible en un lateral: todo lo que llega por MIDI y
  HID, con su canal y su numero. Solo con esto el usuario ya descubre si su
  crossfader emite algo, que es la primera pregunta que se hace todo el mundo.
- Instruccion grande y en lenguaje normal: *"Mueve el crossfader de un lado a otro,
  despacio"*. Barra de progreso mientras aprende el rango.
- Si en 5 segundos no llega nada: *"Tu mesa no parece enviar el crossfader por MIDI.
  Es normal en mesas de battle. Podemos detectarlo por el audio."* y ofrece cambiar
  de metodo sin salir del asistente.
- Solo el crossfader es obligatorio. El resto se pueden saltar con un boton claro.
- Al terminar: resumen de lo mapeado, guardar con nombre, y un boton
  **`Aportar este perfil`** que abre la carpeta con las instrucciones del pull
  request. Sin subida automatica ni telemetria.

## 4. Accesibilidad

- Dynamic Type en toda la UI que no sea la autopista.
- VoiceOver en navegacion y resultados; la autopista se anuncia como region en vivo
  con el resumen de compas.
- Modo alto contraste que sube `ghost` al 60% y engorda los trazos.
- Nunca informacion solo por color (ver tabla de formas arriba).
- Todo accionable con teclado. Atajos: espacio = empezar/parar, R = repetir,
  flechas = BPM.

## 5. Que NO va en la v1

Temas personalizables, modo claro, editor visual de scratches, red social,
tabla de clasificacion online. Todo eso es ruido antes de que el motor sea bueno.
