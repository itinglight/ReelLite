#!/bin/bash
# 由 make_icon.swift 渲染 1024px 原图，再生成 Resources/AppIcon.icns
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift scripts/make_icon.swift "$TMP/icon_1024.png"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon_1024.png" Resources/icon_1024.png
rm -rf "$TMP"
echo "✅ 已生成 Resources/AppIcon.icns"
