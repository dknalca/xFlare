#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Compila el spike B1.4 (deteccion de crossfader por tono piloto).
# Prototipo desechable: no entra en Package.swift.
set -e
cd "$(dirname "$0")"

clang -std=c11 -O2 -g -Wall -Wextra \
  -arch x86_64 -arch arm64 \
  -mmacosx-version-min=11.0 \
  -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreFoundation \
  -o pilot_fader pilot_fader.c

echo "  ok -> ./pilot_fader   (prueba: ./pilot_fader --list)"
