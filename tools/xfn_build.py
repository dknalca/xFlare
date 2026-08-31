#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Regenera data/*.json a partir de las primitivas y el catalogo.
Uso:  python3 tools/xfn_build.py
El catalogo vive en tools/catalog.json para que anadir un scratch sea
anadir una linea, no tocar codigo."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import xfn_core as X

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cat = json.load(open(os.path.join(HERE, "tools", "catalog.json"), encoding="utf-8"))
out = {"schemaVersion": "0.1.0", "generatedBy": "tools/xfn_build.py",
       "notation": "XFN (xFlare Notation)", "ppq": X.PPQ, "scratches": []}
for e in cat:
    out["scratches"].append(X.compose(
        e["hand"], e["fader"], div=e["div"], cycles=e["cycles"],
        scratch_id=e["id"], name=e["name"], level=e["level"],
        family=e["family"], notes=e.get("notes", "")))
dst = os.path.join(HERE, "data", "scratches", "library-v0.1.json")
json.dump(out, open(dst, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print("OK ->", dst, len(out["scratches"]), "scratches")
