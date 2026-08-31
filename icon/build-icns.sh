#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Genera icon/xflare.icns y icon/xflare-1024.png a partir de icon/xflare.svg.
#
# Sin dependencias externas: rasteriza el SVG con QuickLook (`qlmanage`, que ya
# viene en macOS) y arma el .icns con `iconutil`. Los tamanos pequenos se sacan
# reduciendo el master de 1024 con `sips` (mas nitido que pedirle 16 px a
# QuickLook).
set -e
cd "$(dirname "$0")"

SVG="xflare.svg"
ICONSET="xflare.iconset"
MASTER="xflare-1024.png"

[ -f "$SVG" ] || { echo "  falta $SVG"; exit 1; }

echo "  rasterizando $SVG a 1024 px..."
rm -f "$MASTER" ./*.svg.png
qlmanage -t -s 1024 -o . "$SVG" >/dev/null 2>&1
mv "$SVG.png" "$MASTER"

# Comprobar que salio a 1024 y con alfa (QuickLook a veces se queda corto).
W=$(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/{print $2}')
[ "$W" = "1024" ] || { echo "  AVISO: el master salio a ${W}px, no 1024"; }

echo "  construyendo $ICONSET..."
rm -rf "$ICONSET"
mkdir "$ICONSET"
# nombre_de_fichero : lado_en_px  (spec de iconutil para macOS)
for pair in \
  "icon_16x16.png:16"        "icon_16x16@2x.png:32" \
  "icon_32x32.png:32"        "icon_32x32@2x.png:64" \
  "icon_128x128.png:128"     "icon_128x128@2x.png:256" \
  "icon_256x256.png:256"     "icon_256x256@2x.png:512" \
  "icon_512x512.png:512"     "icon_512x512@2x.png:1024"
do
  name=${pair%:*}; px=${pair#*:}
  sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o xflare.icns
echo "  ok -> icon/xflare.icns  ($(du -h xflare.icns | awk '{print $1}'))"
echo "  ok -> icon/$MASTER"

# Copia de cortesia para el visor de previews del repo.
if [ -d ../preview ]; then
  cp "$MASTER" ../preview/xflare-icon.png
  echo "  ok -> preview/xflare-icon.png"
fi
