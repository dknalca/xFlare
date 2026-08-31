#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Valida perfiles de dispositivo .conf de xFlare.

  python3 tools/xf_profile.py --check profiles/rane-seventy-two.conf
  python3 tools/xf_profile.py --all
  python3 tools/xf_profile.py --show profiles/pioneer-djm-s9.conf   (resuelve extends)
"""
import configparser, glob, os, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROFILES = os.path.join(HERE, "profiles")

REQUIRED = {"profile": ["id", "name", "vendor", "schema", "revision", "verified"]}
BOOLS = ["profile.verified", "crossfader.midi.invert", "crossfader.reverse_default"]
METHODS = ["midi", "audio_return", "hid", "none"]
NEEDED_BY_METHOD = {
    "midi": ["midi.channel", "midi.cc", "midi.min", "midi.max"],
    "audio_return": ["pilot.frequency", "pilot.level_db"],
    "hid": [], "none": [],
}

def load(path):
    cp = configparser.ConfigParser()
    cp.optionxform = str
    with open(path, encoding="utf-8") as f:
        cp.read_file(f)
    return cp

def check(path):
    errs, warns = [], []
    try:
        raw = load(path)
    except Exception as e:
        return ["no se puede parsear: %s" % e], []

    # Un perfil con `extends` hereda secciones enteras del padre: hay que validar
    # el resultado resuelto, no el fichero en crudo.
    ext_raw = raw.get("profile", "extends", fallback=None)
    if ext_raw and not os.path.exists(os.path.join(PROFILES, ext_raw + ".conf")):
        return ["extends apunta a un perfil que no existe: %s" % ext_raw], []
    try:
        cp = resolve(path) if ext_raw else raw
    except ValueError as e:
        return [str(e)], []

    for sec, keys in REQUIRED.items():
        if not cp.has_section(sec):
            errs.append("falta la seccion [%s]" % sec); continue
        for k in keys:
            if not cp.has_option(sec, k):
                errs.append("falta %s.%s" % (sec, k))

    if cp.has_option("profile", "id"):
        pid = cp.get("profile", "id")
        base = os.path.splitext(os.path.basename(path))[0]
        if base not in (pid, pid + ".conf") and not path.endswith(".example"):
            warns.append("el id '%s' no coincide con el nombre del fichero '%s'" % (pid, base))
        if pid != pid.lower() or " " in pid:
            errs.append("el id debe ir en minusculas y sin espacios")

    for dotted in BOOLS:
        sec, key = dotted.split(".", 1)
        if cp.has_option(sec, key) and cp.get(sec, key) not in ("true", "false"):
            errs.append("%s debe ser true o false" % dotted)

    if cp.has_section("crossfader"):
        m = cp.get("crossfader", "method", fallback=None)
        if m not in METHODS:
            errs.append("crossfader.method invalido: %r (usa %s)" % (m, "/".join(METHODS)))
        else:
            for k in NEEDED_BY_METHOD[m]:
                if not cp.has_option("crossfader", k):
                    errs.append("con method=%s hace falta crossfader.%s" % (m, k))
        for k in ("cut_in.left", "cut_in.right", "hysteresis"):
            if cp.has_option("crossfader", k):
                try:
                    v = float(cp.get("crossfader", k))
                    if v < 0.0 or v > 1.0:
                        errs.append("crossfader.%s fuera de 0..1" % k)
                except ValueError:
                    errs.append("crossfader.%s no es numero" % k)
        L = cp.get("crossfader", "cut_in.left", fallback=None)
        Rr = cp.get("crossfader", "cut_in.right", fallback=None)
        if L and Rr and float(L) >= float(Rr):
            errs.append("cut_in.left debe ser menor que cut_in.right")
    elif not path.endswith(".example"):
        errs.append("falta la seccion [crossfader]")

    if raw.get("profile", "verified", fallback="false") == "false":
        warns.append("perfil SIN VERIFICAR contra hardware real")
    return errs, warns

def resolve(path, seen=None):
    seen = seen or []
    cp = load(path)
    ext = cp.get("profile", "extends", fallback=None)
    if not ext:
        return cp
    if ext in seen:
        raise ValueError("herencia circular: %s" % " -> ".join(seen + [ext]))
    base = resolve(os.path.join(PROFILES, ext + ".conf"), seen + [ext])
    for s in cp.sections():
        if not base.has_section(s):
            base.add_section(s)
        for k, v in cp.items(s):
            base.set(s, k, v)
    return base

def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__); return 0
    if args[0] == "--show":
        cp = resolve(args[1])
        for s in cp.sections():
            print("[%s]" % s)
            for k, v in cp.items(s):
                print("  %-22s = %s" % (k, v))
        return 0
    paths = sorted(glob.glob(os.path.join(PROFILES, "*.conf")) +
                   glob.glob(os.path.join(PROFILES, "*.example"))) \
            if args[0] == "--all" else args[1:]
    bad = 0
    for p in paths:
        errs, warns = check(p)
        name = os.path.basename(p)
        if errs:
            bad += 1
            print("  FALLO  %s" % name)
            for e in errs: print("           - %s" % e)
        else:
            print("  OK     %s" % name)
        for w in warns:
            print("           ! %s" % w)
    print()
    print("  %d perfiles, %d con errores" % (len(paths), bad))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
