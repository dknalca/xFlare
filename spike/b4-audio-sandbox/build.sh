#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Compila el spike B4. Prototipo desechable: no entra en Package.swift.
# Swift (ventana/trackpad/HUD) + C (callback de audio), en un solo binario.
# `swiftc` no compila .c: primero el objeto con clang, luego se enlaza.
set -e
cd "$(dirname "$0")"

clang -c -O2 -Wall -std=c11 sandbox_audio.c -o sandbox_audio.o

swiftc -O \
  -import-objc-header sandbox_audio.h \
  sandbox.swift sandbox_audio.o \
  -o sandbox \
  -framework AppKit -framework AudioToolbox -framework AudioUnit \
  -framework CoreAudio -framework CoreFoundation

rm -f sandbox_audio.o
echo "  ok -> ./sandbox"
echo "  ejecuta desde la raiz del repo:  spike/b4-audio-sandbox/sandbox"
echo "  (o pasale las rutas de los dos mp3 como argumentos)"
