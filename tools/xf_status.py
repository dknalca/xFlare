#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Imprime el estado del backlog. Uso: python3 tools/xf_status.py [--all]"""
import json, os, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bl = json.load(open(os.path.join(HERE, "data", "backlog.json"), encoding="utf-8"))
show_all = "--all" in sys.argv
MARK = {"todo": "[ ]", "wip": "[~]", "done": "[x]"}

done = wip = todo = 0
nxt = []
for b in bl["blocks"]:
    for t in b["tasks"]:
        s = t.get("status", "todo")
        if s == "done": done += 1
        elif s == "wip": wip += 1
        else:
            todo += 1
            if b["phase"] != "future" and len(nxt) < 5:
                nxt.append((b["id"], t))

total = done + wip + todo
pct = (100.0 * done / total) if total else 0.0
bar = "#" * int(pct / 4) + "." * (25 - int(pct / 4))
print()
print("  xFlare  [%s] %.0f%%   %d hechas / %d en curso / %d pendientes"
      % (bar, pct, done, wip, todo))
print()

if wip:
    print("  EN CURSO")
    for b in bl["blocks"]:
        for t in b["tasks"]:
            if t.get("status") == "wip":
                print("    %s %-8s %s" % (MARK["wip"], t["id"], t["title"]))
    print()

print("  SIGUIENTES")
for bid, t in nxt:
    print("    [ ] %-8s %s" % (t["id"], t["title"]))
    if t.get("acceptance", "-") != "-":
        print("             -> %s" % t["acceptance"])
print()

if show_all:
    for b in bl["blocks"]:
        print("  %s  %s  (%s)" % (b["id"], b["name"], b["phase"]))
        for t in b["tasks"]:
            print("    %s %-8s %s" % (MARK.get(t.get("status", "todo")), t["id"], t["title"]))
        print()
