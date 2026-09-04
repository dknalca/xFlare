#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Mide la latencia round-trip (plato -> altavoz) por loopback analogico.

Es la herramienta de la tarea B1.2 / B1.5 del plan. Reproduce un chirp corto por
la SALIDA y graba a la vez la ENTRADA; la salida hay que puentearla fisicamente a
la entrada (un cable, o el retorno USB del master de la mesa). Por correlacion
cruzada saca el desfase en muestras -> milisegundos. Ese numero incluye TODO:
buffer de salida + DAC + cable + ADC + buffer de entrada + host.

Uso:
    python3 tools/measure_latency.py --list
    python3 tools/measure_latency.py --device "Rane" --frames 64 --reps 20
    python3 tools/measure_latency.py --device "Rane" --out-ch 3 --in-ch 5

Sin --out-ch/--in-ch usa el canal 1 de cada lado (el primero del dispositivo),
que en una interfaz multicanal (p. ej. la Rane 72, 14 in / 10 out) casi nunca
es el que lleva el loopback real -- especifica el par exacto en vez de
adivinar (docs/HW_BRINGUP.md paso 3).

Al terminar imprime una linea lista para pegar en docs/TIMECODE.md seccion 4.2.

Dependencias: numpy + sounddevice (ver tools/requirements.txt). Si faltan, el
script lo dice y explica como instalarlas.
"""
import argparse
import statistics
import sys

try:
    import numpy as np
    import sounddevice as sd
except ImportError as e:
    sys.exit(
        "  falta una dependencia (%s).\n"
        "  instala el entorno de tools/:\n"
        "    cd tools && python3 -m venv .venv && source .venv/bin/activate\n"
        "    pip install -r requirements.txt" % e.name
    )


def list_devices():
    print(sd.query_devices())
    print("\n  para el loopback necesitas un dispositivo con entrada Y salida.")
    print("  puentea una salida a una entrada (cable) o usa el retorno USB del master.")


def make_stimulus(fs, chirp_ms=4.0, window_ms=250.0):
    """Chirp lineal 1.5-12 kHz con ventana de Hann, seguido de silencio.

    El chirp es corto y de banda ancha: da un pico de correlacion estrecho y
    robusto frente al ruido, sin excitar demasiado los graves del sistema.
    """
    n_chirp = int(fs * chirp_ms / 1000.0)
    n_window = int(fs * window_ms / 1000.0)
    t = np.arange(n_chirp) / fs
    dur = n_chirp / fs
    f0, f1 = 1500.0, 12000.0
    phase = 2 * np.pi * (f0 * t + (f1 - f0) / (2 * dur) * t * t)
    chirp = np.sin(phase) * np.hanning(n_chirp) * 0.5
    stim = np.zeros(n_window, dtype="float32")
    stim[:n_chirp] = chirp.astype("float32")
    return stim


def xcorr_lag(rec, ref):
    """Desfase (en muestras) de 'rec' respecto a 'ref' por correlacion via FFT.

    argmax de la correlacion cruzada = cuantas muestras tarda en aparecer en la
    grabacion lo que se mando reproducir. Solo numpy, sin scipy.
    """
    n = 1 << int(np.ceil(np.log2(len(rec) + len(ref))))
    R = np.fft.rfft(rec, n)
    S = np.fft.rfft(ref, n)
    cc = np.fft.irfft(R * np.conj(S), n)
    # el desfase real cae en la primera mitad; nunca va a ser negativo aqui
    search = cc[: len(rec)]
    return int(np.argmax(search)), search


def main():
    ap = argparse.ArgumentParser(description="Latencia round-trip por loopback (B1.2).")
    ap.add_argument("--list", action="store_true", help="enumera dispositivos y sale")
    ap.add_argument("--device", help="nombre (subcadena) o indice del dispositivo de loopback")
    ap.add_argument("--fs", type=int, default=48000, help="sample rate (por defecto 48000)")
    ap.add_argument("--frames", type=int, default=64, help="tamano de buffer objetivo (por defecto 64)")
    ap.add_argument("--reps", type=int, default=20, help="numero de medidas (por defecto 20)")
    ap.add_argument("--out-ch", type=int, default=1,
                     help="canal de SALIDA a usar, 1-based (por defecto 1: el primero del dispositivo)")
    ap.add_argument("--in-ch", type=int, default=1,
                     help="canal de ENTRADA a usar, 1-based (por defecto 1: el primero del dispositivo)")
    args = ap.parse_args()

    if args.list:
        list_devices()
        return 0

    dev = args.device
    if dev is not None and dev.isdigit():
        dev = int(dev)
    if dev is not None:
        sd.default.device = (dev, dev)  # mismo dispositivo para entrada y salida

    sd.default.samplerate = args.fs
    sd.default.dtype = "float32"
    try:
        sd.default.blocksize = args.frames
        sd.default.latency = "low"
    except Exception:
        pass

    try:
        info_in = sd.query_devices(sd.default.device[0])
        info_out = sd.query_devices(sd.default.device[1])
    except Exception as e:
        sys.exit("  no se pudo abrir el dispositivo: %s\n  prueba --list" % e)

    max_out = info_out["max_output_channels"]
    max_in = info_in["max_input_channels"]
    if not (1 <= args.out_ch <= max_out):
        sys.exit("  --out-ch %d fuera de rango: el dispositivo tiene %d canales de salida"
                  % (args.out_ch, max_out))
    if not (1 <= args.in_ch <= max_in):
        sys.exit("  --in-ch %d fuera de rango: el dispositivo tiene %d canales de entrada"
                  % (args.in_ch, max_in))

    print("  entrada : %s  (canal %d de %d)" % (info_in["name"], args.in_ch, max_in))
    print("  salida  : %s  (canal %d de %d)" % (info_out["name"], args.out_ch, max_out))
    print("  fs=%d Hz  buffer objetivo=%d frames  reps=%d" % (args.fs, args.frames, args.reps))
    print("  latencia declarada por el driver: in=%.2f ms  out=%.2f ms\n"
          % (info_in["default_low_input_latency"] * 1000,
             info_out["default_low_output_latency"] * 1000))

    # El chirp mono se coloca en la columna --out-ch (0-based) de un buffer
    # que abarca TODOS los canales de salida del dispositivo (el resto va a
    # cero); para grabar se piden TODOS los canales de entrada y luego se
    # recorta la columna --in-ch. Es la unica forma de elegir canal concreto
    # con sounddevice/PortAudio -- sin esto, "channels=1" coge siempre el
    # primer canal del dispositivo, casi nunca el que lleva el loopback real
    # en una interfaz multicanal.
    stim_mono = make_stimulus(args.fs)
    stim = np.zeros((len(stim_mono), max_out), dtype="float32")
    stim[:, args.out_ch - 1] = stim_mono

    lags_ms = []
    for i in range(args.reps):
        rec = sd.playrec(stim, samplerate=args.fs, channels=max_in, blocksize=args.frames)
        sd.wait()
        rec = rec[:, args.in_ch - 1].astype("float64")

        rms = float(np.sqrt(np.mean(rec ** 2)))
        if rms < 1e-4:
            sys.exit("  la grabacion esta en silencio (rms=%.2e).\n"
                     "  ¿has puenteado la salida a la entrada? ¿sube el volumen del loopback?" % rms)

        lag, cc = xcorr_lag(rec, stim_mono.astype("float64"))
        # calidad del pico: cuanto sobresale del resto
        peak = cc[lag]
        med = np.median(np.abs(cc))
        sharp = peak / med if med > 0 else 0.0
        ms = 1000.0 * lag / args.fs
        flag = "" if (3.0 < ms < 60.0 and sharp > 8) else "  <- dudosa (pico sharp=%.1f)" % sharp
        lags_ms.append(ms)
        print("  rep %2d/%2d:  %6.2f ms  (%d muestras)%s" % (i + 1, args.reps, ms, lag, flag))

    lo = min(lags_ms)
    hi = max(lags_ms)
    med = statistics.median(lags_ms)
    mean = statistics.fmean(lags_ms)
    sd_ms = statistics.pstdev(lags_ms)

    print("\n  ---------------- RESUMEN B1.2 ----------------")
    print("  round-trip:  min %.2f  |  mediana %.2f  |  media %.2f  |  max %.2f  ms" % (lo, med, mean, hi))
    print("  jitter (desv. tipica): %.2f ms" % sd_ms)
    print("  buffer:      %d frames @ %d Hz  (%.3f ms/callback teorico)"
          % (args.frames, args.fs, 1000.0 * args.frames / args.fs))
    gate = 10.0
    verdict = "DENTRO de la puerta (<= %.0f ms)" % gate if med <= gate else \
              "FUERA de la puerta (> %.0f ms) -> ADR con plan B (B1.3)" % gate
    print("  veredicto:   %s" % verdict)
    print("  ---------------------------------------------")
    print("\n  linea para docs/TIMECODE.md seccion 4.2:")
    print("  | %s | %d frames @ %d Hz | %.2f ms (mediana, jitter %.2f) | %s |"
          % (info_out["name"], args.frames, args.fs, med, sd_ms,
             "OK" if med <= gate else "REVISAR"))
    return 0 if med <= gate else 1


if __name__ == "__main__":
    raise SystemExit(main())
