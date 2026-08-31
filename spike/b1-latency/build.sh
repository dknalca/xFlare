#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Compila el spike B1.1. Prototipo desechable: no entra en Package.swift.
# Universal (x86_64 + arm64) porque en xFlare todo lo es desde B0.6 (ADR-028),
# aunque este binario no se distribuye.
set -e
cd "$(dirname "$0")"

clang -std=c11 -O2 -g -Wall -Wextra \
  -arch x86_64 -arch arm64 \
  -mmacosx-version-min=11.0 \
  -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreFoundation \
  -o passthrough passthrough.c

echo "  ok -> ./passthrough    (prueba: ./passthrough --list)"
