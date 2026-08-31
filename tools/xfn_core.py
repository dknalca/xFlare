"""
xfn_core.py - Nucleo de la notacion xFlare (XFN).

Modelo: un scratch NO se almacena como dibujo, sino como la composicion de
  (patron de mano) x (patron de fader) x (subdivision) x (repeticiones)
Esa es la logica de la Periodic Matrix of Skratches: los ejes se multiplican.

Todo el tiempo se mide en ticks. PPQ = 480 ticks por negra (como MIDI).
Licencia: GPL-3.0-only (mismo que el resto de xFlare).
"""

PPQ = 480

# --- curvas de velocidad dentro de una fase -------------------------------
def _lin(u):  return u
def _bell(u): return u * u * (3.0 - 2.0 * u)      # lento-rapido-lento (mano natural)
def _acc(u):  return u * u                        # acelera (pitch sube)
def _dec(u):  return 1.0 - (1.0 - u) ** 2         # frena (pitch baja)
def _hold(u): return 0.0                          # disco parado

CURVES = {"lin": _lin, "bell": _bell, "acc": _acc, "dec": _dec, "hold": _hold}

# --- patrones de MANO ------------------------------------------------------
# phases: units = duracion relativa, dist = recorrido del disco (+ adelante,
# - atras). La suma de dist debe ser 0 para que el patron cierre en bucle.
HAND_PATTERNS = {
    "baby": {
        "name": "Baby", "level": 1,
        "desc": "Adelante y atras simetrico, sin parar. La base de todo.",
        "phases": [
            {"dir": "fwd", "units": 1.0, "dist":  1.0, "curve": "bell"},
            {"dir": "rev", "units": 1.0, "dist": -1.0, "curve": "bell"},
        ],
    },
    "stab": {
        "name": "Stab", "level": 1,
        "desc": "Empujon corto y rapido hacia delante, retorno lento.",
        "phases": [
            {"dir": "fwd", "units": 0.5, "dist":  1.2, "curve": "acc"},
            {"dir": "rev", "units": 1.5, "dist": -1.2, "curve": "dec"},
        ],
    },
    "drag": {
        "name": "Drag", "level": 1,
        "desc": "Movimiento lento y controlado. Base del transformer.",
        "phases": [
            {"dir": "fwd", "units": 2.0, "dist":  1.0, "curve": "lin"},
            {"dir": "rev", "units": 2.0, "dist": -1.0, "curve": "lin"},
        ],
    },
    "tear2": {
        "name": "Tear (2 partes)", "level": 2,
        "desc": "Adelante entero, vuelta partida en dos con una parada.",
        "phases": [
            {"dir": "fwd",  "units": 2.0, "dist":  2.0, "curve": "bell"},
            {"dir": "rev",  "units": 0.75, "dist": -1.0, "curve": "lin"},
            {"dir": "hold", "units": 0.5, "dist":  0.0, "curve": "hold"},
            {"dir": "rev",  "units": 0.75, "dist": -1.0, "curve": "lin"},
        ],
    },
    "tear3": {
        "name": "Tear (3 partes)", "level": 3,
        "desc": "Vuelta partida en tres tramos. Control de muneca fino.",
        "phases": [
            {"dir": "fwd",  "units": 1.8, "dist":  3.0, "curve": "bell"},
            {"dir": "rev",  "units": 0.6, "dist": -1.0, "curve": "lin"},
            {"dir": "hold", "units": 0.3, "dist":  0.0, "curve": "hold"},
            {"dir": "rev",  "units": 0.6, "dist": -1.0, "curve": "lin"},
            {"dir": "hold", "units": 0.3, "dist":  0.0, "curve": "hold"},
            {"dir": "rev",  "units": 0.6, "dist": -1.0, "curve": "lin"},
        ],
    },
    "scribble": {
        "name": "Scribble", "level": 2,
        "desc": "Vibracion rapida y corta con tension de antebrazo.",
        "phases": [
            {"dir": "fwd", "units": 0.5, "dist":  0.35, "curve": "lin"},
            {"dir": "rev", "units": 0.5, "dist": -0.35, "curve": "lin"},
        ],
    },
    "chirp_hand": {
        "name": "Chirp (mano)", "level": 3,
        "desc": "Como el baby pero con ataque y frenada marcados.",
        "phases": [
            {"dir": "fwd", "units": 1.0, "dist":  1.0, "curve": "dec"},
            {"dir": "rev", "units": 1.0, "dist": -1.0, "curve": "dec"},
        ],
    },
    "hydroplane": {
        "name": "Hydroplane", "level": 4,
        "desc": "Dedo apoyado en el disco: friccion que genera temblor.",
        "phases": [
            {"dir": "fwd", "units": 0.25, "dist":  0.18, "curve": "lin"},
            {"dir": "rev", "units": 0.25, "dist": -0.18, "curve": "lin"},
        ],
    },
}

# --- patrones de FADER -----------------------------------------------------
# per_phase: reglas por direccion de fase. Cada regla es (fraccion, estado)
# donde fraccion va de 0..1 DENTRO de esa fase.
FADER_PATTERNS = {
    "open": {
        "name": "Abierto", "level": 1, "technique": "ninguna",
        "desc": "El fader no se toca. Se oye todo el movimiento del disco.",
        "initial": "open", "per_phase": {},
    },
    "forward_cut": {
        "name": "Forward Cut", "level": 1, "technique": "indice",
        "desc": "Solo suena la ida. La vuelta se corta.",
        "initial": "closed",
        "per_phase": {"fwd": [(0.0, "open"), (0.96, "closed")], "rev": [(0.0, "closed")]},
    },
    "reverse_cut": {
        "name": "Reverse Cut", "level": 2, "technique": "indice",
        "desc": "Solo suena la vuelta. La ida se corta.",
        "initial": "closed",
        "per_phase": {"fwd": [(0.0, "closed")], "rev": [(0.0, "open"), (0.96, "closed")]},
    },
    "chirp": {
        "name": "Chirp", "level": 3, "technique": "indice + pulgar",
        "desc": "Abre al arrancar y cierra al frenar, en las dos direcciones.",
        "initial": "closed",
        "per_phase": {"any": [(0.05, "open"), (0.80, "closed")]},
    },
    "transformer_2": {
        "name": "Transformer x2", "level": 2, "technique": "indice (tap)",
        "desc": "Dos pulsos de apertura por trazo sobre un movimiento lento.",
        "initial": "closed",
        "per_phase": {"any": [(0.10, "open"), (0.35, "closed"), (0.55, "open"), (0.80, "closed")]},
    },
    "transformer_3": {
        "name": "Transformer x3", "level": 3, "technique": "indice (tap)",
        "desc": "Tres pulsos por trazo.",
        "initial": "closed",
        "per_phase": {"any": [(0.06, "open"), (0.24, "closed"), (0.38, "open"),
                              (0.56, "closed"), (0.70, "open"), (0.88, "closed")]},
    },
    "transformer_4": {
        "name": "Transformer x4", "level": 4, "technique": "indice + corazon",
        "desc": "Cuatro pulsos por trazo. Antesala del uzi.",
        "initial": "closed",
        "per_phase": {"any": [(0.04, "open"), (0.17, "closed"), (0.29, "open"), (0.42, "closed"),
                              (0.54, "open"), (0.67, "closed"), (0.79, "open"), (0.92, "closed")]},
    },
    "flare_1c": {
        "name": "Flare 1 click", "level": 3, "technique": "indice (rebote)",
        "desc": "Fader abierto con un click (cierre breve) en mitad de cada trazo.",
        "initial": "open",
        "per_phase": {"any": [(0.45, "closed"), (0.55, "open")], "hold": []},
    },
    "flare_1c_lo": {
        "name": "Lo-1C Flare", "level": 3, "technique": "indice (rebote)",
        "desc": "Un click adelantado, en la primera mitad del trazo.",
        "initial": "open",
        "per_phase": {"any": [(0.25, "closed"), (0.35, "open")], "hold": []},
    },
    "flare_1c_hi": {
        "name": "Hi-1C Flare", "level": 3, "technique": "indice (rebote)",
        "desc": "Un click retrasado, en la segunda mitad del trazo.",
        "initial": "open",
        "per_phase": {"any": [(0.65, "closed"), (0.75, "open")], "hold": []},
    },
    "flare_2c": {
        "name": "Flare 2 clicks", "level": 4, "technique": "indice (rebote doble)",
        "desc": "Dos clicks por trazo. El escalon clasico tras el 1-click.",
        "initial": "open",
        "per_phase": {"any": [(0.28, "closed"), (0.36, "open"),
                              (0.62, "closed"), (0.70, "open")], "hold": []},
    },
    "flare_3c": {
        "name": "Flare 3 clicks", "level": 5, "technique": "indice + corazon",
        "desc": "Tres clicks por trazo.",
        "initial": "open",
        "per_phase": {"any": [(0.20, "closed"), (0.27, "open"),
                              (0.45, "closed"), (0.52, "open"),
                              (0.70, "closed"), (0.77, "open")], "hold": []},
    },
    "orbit_1c": {
        "name": "Orbit 1 click", "level": 4, "technique": "indice (ida y vuelta)",
        "desc": "Flare de 1 click con el click de vuelta dado con el reverso del dedo.",
        "initial": "open",
        "per_phase": {"fwd": [(0.45, "closed"), (0.55, "open")],
                      "rev": [(0.45, "closed"), (0.55, "open")], "hold": []},
    },
    "orbit_2c": {
        "name": "Orbit 2 clicks", "level": 5, "technique": "indice (ida y vuelta)",
        "desc": "Orbit doble: cuatro clicks por ciclo, movimiento circular continuo.",
        "initial": "open",
        "per_phase": {"any": [(0.28, "closed"), (0.36, "open"),
                              (0.62, "closed"), (0.70, "open")], "hold": []},
    },
    "twiddle_2c": {
        "name": "Twiddle", "level": 5, "technique": "indice + corazon alternos",
        "desc": "Mismo dibujo que el flare de 2 clicks, pero alternando dos dedos.",
        "initial": "open",
        "per_phase": {"any": [(0.28, "closed"), (0.36, "open"),
                              (0.62, "closed"), (0.70, "open")], "hold": []},
    },
    "crab_4c": {
        "name": "Crab", "level": 6, "technique": "4 dedos contra pulgar",
        "desc": "Cuatro clicks por trazo disparando dedo a dedo contra el pulgar.",
        "initial": "open",
        "per_phase": {"any": [(0.14, "closed"), (0.20, "open"),
                              (0.34, "closed"), (0.40, "open"),
                              (0.54, "closed"), (0.60, "open"),
                              (0.74, "closed"), (0.80, "open")], "hold": []},
    },
}

def div_to_ticks(div, ppq=PPQ):
    """'1/8' -> ticks de una unidad. 1/4 = una negra."""
    num, den = div.split("/")
    return int(round(ppq * 4 * (float(num) / float(den))))

def compose(hand_id, fader_id, div="1/8", cycles=4, bpm=90, ppq=PPQ,
            scratch_id=None, name=None, level=None, family=None, notes=None):
    hand = HAND_PATTERNS[hand_id]
    fad = FADER_PATTERNS[fader_id]
    unit = div_to_ticks(div, ppq)

    closure = round(sum(p["dist"] for p in hand["phases"]), 6)
    if closure != 0.0:
        raise ValueError("El patron de mano %s no cierra el bucle (dist=%s)" % (hand_id, closure))

    record, fader = [], [{"t": 0, "state": fad["initial"]}]
    t, pos = 0, 0.0
    for _ in range(cycles):
        for ph in hand["phases"]:
            dur = int(round(ph["units"] * unit))
            record.append({"t": t, "dur": dur, "dir": ph["dir"], "dist": ph["dist"],
                           "curve": ph["curve"], "from": round(pos, 4),
                           "to": round(pos + ph["dist"], 4)})
            rules = fad["per_phase"].get(ph["dir"], fad["per_phase"].get("any", []))
            for frac, state in rules:
                fader.append({"t": t + int(round(frac * dur)), "state": state})
            pos += ph["dist"]
            t += dur

    fader.sort(key=lambda e: e["t"])
    clean, last = [], None
    for e in fader:
        if e["state"] != last:
            clean.append(e)
            last = e["state"]
    clicks = sum(1 for e in clean if e["state"] == "closed")

    return {
        "id": scratch_id or ("%s__%s__%s" % (hand_id, fader_id, div.replace("/", "-"))),
        "name": name or ("%s %s" % (hand["name"], fad["name"])),
        "family": family or fader_id.split("_")[0],
        "level": level if level is not None else max(hand["level"], fad["level"]),
        "hand": hand_id, "fader": fader_id, "div": div, "cycles": cycles,
        "technique": fad["technique"],
        "ppq": ppq, "bpmReference": bpm,
        "lengthTicks": t, "clickCount": clicks,
        "record": record, "faderEvents": clean,
        "notes": notes or "",
    }

def position_at(scratch, tick):
    """Posicion del disco en un tick dado (unidades de recorrido)."""
    for ph in scratch["record"]:
        if ph["t"] <= tick <= ph["t"] + ph["dur"]:
            u = 0.0 if ph["dur"] == 0 else (tick - ph["t"]) / ph["dur"]
            return ph["from"] + (ph["to"] - ph["from"]) * CURVES[ph["curve"]](u)
    return scratch["record"][-1]["to"]

def fader_at(scratch, tick):
    state = "open"
    for e in scratch["faderEvents"]:
        if e["t"] <= tick:
            state = e["state"]
        else:
            break
    return state

def render(scratch, ax_top, ax_bot, samples=1400):
    """Dibuja el scratch en dos carriles al estilo TTM (matplotlib)."""
    ppq, total = scratch["ppq"], scratch["lengthTicks"]
    xs = [i * total / float(samples) for i in range(samples + 1)]
    beats = [x / ppq for x in xs]
    ys = [position_at(scratch, x) for x in xs]

    ax_top.plot(beats, ys, color="#111111", linewidth=2.0, solid_capstyle="round")
    for e in scratch["faderEvents"]:
        b, y = e["t"] / ppq, position_at(scratch, e["t"])
        if e["state"] == "open":
            ax_top.plot([b], [y], marker="o", ms=7, mfc="white", mec="#111111", mew=1.6, zorder=5)
        else:
            ax_top.plot([b], [y], marker="o", ms=7, mfc="#111111", mec="#111111", zorder=5)

    last_beat = total / ppq
    step = 0.25
    n = int(round(last_beat / step))
    for i in range(n + 1):
        b = i * step
        major = abs(b - round(b)) < 1e-9
        ax_top.axvline(b, color="#999999" if major else "#dddddd",
                       lw=1.0 if major else 0.6, zorder=0)
    ax_top.set_xlim(0, last_beat)
    ax_top.set_ylabel("disco", fontsize=8)
    ax_top.set_yticks([])
    ax_top.set_xticks(range(int(last_beat) + 1))
    ax_top.tick_params(labelsize=7)
    ax_top.set_title("%s   ·   %s clicks/ciclo   ·   nivel %s"
                     % (scratch["name"],
                        scratch["clickCount"] // max(scratch["cycles"], 1),
                        scratch["level"]),
                     fontsize=9, loc="left")
    for s in ("top", "right"):
        ax_top.spines[s].set_visible(False)

    prev_t, prev_state = 0, scratch["faderEvents"][0]["state"]
    spans = []
    for e in scratch["faderEvents"][1:]:
        spans.append((prev_t, e["t"], prev_state))
        prev_t, prev_state = e["t"], e["state"]
    spans.append((prev_t, total, prev_state))
    for a, b, st in spans:
        ax_bot.axvspan(a / ppq, b / ppq,
                       color="#111111" if st == "open" else "#f2f2f2",
                       lw=0)
    ax_bot.set_xlim(0, last_beat)
    ax_bot.set_ylim(0, 1)
    ax_bot.set_yticks([])
    ax_bot.set_ylabel("fader", fontsize=8)
    ax_bot.set_xlabel("tiempo (negras)", fontsize=8)
    ax_bot.tick_params(labelsize=7)
    for s in ("top", "right", "left"):
        ax_bot.spines[s].set_visible(False)


# ===========================================================================
# Extension v0.5: tramos parciales de curva, recorte y transformaciones de
# variante. Ver docs/VARIANTS.md.
# ===========================================================================

def normalize(sc):
    for ph in sc["record"]:
        ph.setdefault("pFrom", ph["from"]); ph.setdefault("pTo", ph["to"])
        ph.setdefault("u0", 0.0); ph.setdefault("u1", 1.0)
    return sc

def position_at(scratch, tick):
    for ph in scratch["record"]:
        if ph["t"] <= tick <= ph["t"] + ph["dur"]:
            q = 0.0 if ph["dur"] == 0 else (tick - ph["t"]) / ph["dur"]
            u0 = ph.get("u0", 0.0); u1 = ph.get("u1", 1.0)
            u = u0 + q * (u1 - u0)
            pf = ph.get("pFrom", ph["from"]); pt = ph.get("pTo", ph["to"])
            return pf + (pt - pf) * CURVES[ph["curve"]](u)
    last = scratch["record"][-1]
    pf = last.get("pFrom", last["from"]); pt = last.get("pTo", last["to"])
    return pf + (pt - pf) * CURVES[last["curve"]](last.get("u1", 1.0))

def crop(sc, t0, t1):
    out = dict(sc); rec = []
    for ph in sc["record"]:
        a, b = ph["t"], ph["t"] + ph["dur"]
        if b <= t0 or a >= t1: continue
        na, nb = max(a, t0), min(b, t1)
        q0 = (na - a) / ph["dur"] if ph["dur"] else 0.0
        q1 = (nb - a) / ph["dur"] if ph["dur"] else 1.0
        u0, u1 = ph.get("u0", 0.0), ph.get("u1", 1.0)
        rec.append(dict(ph, t=na - t0, dur=nb - na,
                        u0=u0 + q0 * (u1 - u0), u1=u0 + q1 * (u1 - u0)))
    state = "open"
    for e in sc["faderEvents"]:
        if e["t"] <= t0: state = e["state"]
        else: break
    fad = [{"t": 0, "state": state}]
    for e in sc["faderEvents"]:
        if t0 < e["t"] < t1: fad.append({"t": e["t"] - t0, "state": e["state"]})
    clean, last = [], None
    for e in fad:
        if e["state"] != last: clean.append(e); last = e["state"]
    out["record"] = rec; out["faderEvents"] = clean; out["lengthTicks"] = t1 - t0
    out["clickCount"] = sum(1 for e in clean if e["state"] == "closed")
    return out

def v_offset(hand, fader, div, cycles, frac):
    ext = normalize(compose(hand, fader, div=div, cycles=cycles + 1))
    cyc = ext["lengthTicks"] // (cycles + 1)
    s = int(round(frac * cyc))
    return crop(ext, s, s + cyc * cycles)

def v_amplitude(sc, scale):
    out = dict(sc)
    out["record"] = [dict(p, pFrom=p["pFrom"] * scale, pTo=p["pTo"] * scale,
                          dist=p.get("dist", 0) * scale) for p in sc["record"]]
    return out

def v_mirror(sc):
    flip = {"fwd": "rev", "rev": "fwd", "hold": "hold"}
    out = dict(sc)
    out["record"] = [dict(p, pFrom=-p["pFrom"], pTo=-p["pTo"],
                          dist=-p.get("dist", 0), dir=flip[p["dir"]]) for p in sc["record"]]
    return out

def v_swing(sc, ratio, ppq=PPQ):
    unit = ppq // 2
    def warp(t):
        pair = unit * 2
        n, r = divmod(t, pair)
        nr = r * (2 * ratio) if r <= unit else pair * ratio + (r - unit) * 2 * (1 - ratio)
        return int(round(n * pair + nr))
    out = dict(sc)
    out["record"] = [dict(p, t=warp(p["t"]), dur=max(warp(p["t"] + p["dur"]) - warp(p["t"]), 1))
                     for p in sc["record"]]
    out["faderEvents"] = [dict(e, t=warp(e["t"])) for e in sc["faderEvents"]]
    return out

def score_events(sc, ppq=PPQ):
    """Puntos posibles de un patron: cada evento evaluable vale 100."""
    clicks = sum(1 for e in sc["faderEvents"] if e["state"] == "closed")
    pitch  = max(1, sc["lengthTicks"] // (ppq // 2))
    ampl   = max(1, len([p for p in sc["record"] if p["dir"] == "fwd"]))
    n = clicks + pitch + ampl
    return {"clicks": clicks, "pitch": pitch, "amplitude": ampl,
            "events": n, "maxScore": n * 100}
