#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Compila el spike B5.5 (sonda de timecode). Prototipo desechable: no entra en
# Package.swift. Enlaza el wrapper xf_timecode + el xwax vendorizado INTACTO,
# directamente desde Sources/CXFTimecode (sin tocarlos).
# Universal (x86_64 + arm64) como todo en xFlare desde B0.6 (ADR-028).
set -e
cd "$(dirname "$0")"

TC=../../Sources/CXFTimecode
XWAX=$TC/vendor/xwax

# -Wall -Wextra pero SIN -Werror: timecoder.c del upstream tiene un par de
# -Wshorten-64-to-32 conocidos (docs/TIMECODE.md 2) y no se toca.
clang -std=c11 -O2 -g -Wall -Wextra \
  -arch x86_64 -arch arm64 \
  -mmacosx-version-min=11.0 \
  -I "$TC/include" -I "$XWAX" \
  -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreFoundation \
  -lm \
  -o tcprobe \
  tcprobe.c "$TC/xf_timecode.c" "$XWAX/timecoder.c" "$XWAX/lut.c"

echo "  ok -> ./tcprobe   (prueba: ./tcprobe --list)"
