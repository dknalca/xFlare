#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Renderiza un scratch de la libreria a SVG/PNG con la notacion XFN.
Uso:  python3 tools/xfn_render.py flare-2c salida.svg"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import xfn_core as X

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lib = json.load(open(os.path.join(HERE, "data", "scratches", "library-v0.1.json"), encoding="utf-8"))
sid = sys.argv[1] if len(sys.argv) > 1 else "flare-2c"
out = sys.argv[2] if len(sys.argv) > 2 else sid + ".svg"
sc = next(s for s in lib["scratches"] if s["id"] == sid)
fig, (a, b) = plt.subplots(2, 1, figsize=(9, 2.6),
                           gridspec_kw={"height_ratios": [3, 1], "hspace": 0.15}, sharex=True)
X.render(sc, a, b)
fig.savefig(out, bbox_inches="tight", facecolor="white")
print("OK ->", out)
