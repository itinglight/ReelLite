#!/bin/bash
# 构建 轻片.app 并打包成 DMG 安装包（输出到 build/）
# 用法：VERSION=0.0.1 ./make_dmg.sh
set -e
cd "$(dirname "$0")"

export VERSION="${VERSION:-0.0.1}"
APP_NAME="轻片"
DMG="build/ReelLite-${VERSION}.dmg"

./build_app.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "build/${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "ReelLite ${VERSION}" -srcfolder "$STAGING" \
  -ov -format UDZO -fs HFS+ "$DMG" >/dev/null

echo "✅ 已生成: $(pwd)/$DMG"
