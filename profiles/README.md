# Perfiles de dispositivo

Un `.conf` por modelo de mesa o controlador. Especificacion en `docs/DEVICE_PROFILES.md`.

| Fichero | Aparato | Verificado |
|---|---|---|
| `keyboard.conf` | Modo sin mesa (teclado) | si |
| `generic-midi.conf` | Controlador MIDI con crossfader | no |
| `rane-seventy-two.conf` | Rane Seventy-Two (MK1) · hardware de referencia | **no** |
| `pioneer-djm-s11.conf` | Pioneer DJM-S11 | **no** |
| `pioneer-djm-s9.conf` | Pioneer DJM-S9 (hereda de la S11) | **no** |
| `user_custom.conf.example` | Plantilla | — |

**Ningun perfil de mesa esta verificado contra hardware real.** La estructura es
correcta; los numeros hay que confirmarlos con `Ajustes -> Mi mesa`. Si tienes el
aparato, aportar el perfil verificado es la contribucion mas util que puedes hacer.

Licencia de esta carpeta: CC0-1.0 (ver `LICENSE`), no GPL.
