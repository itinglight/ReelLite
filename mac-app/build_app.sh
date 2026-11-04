#!/bin/bash
# 构建 轻片.app（ReelLite）（输出到 build/）
set -e
cd "$(dirname "$0")"

APP_NAME="轻片"
BIN_NAME="ReelLite"
APP="build/${APP_NAME}.app"
VERSION="${VERSION:-0.0.2}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/${BIN_NAME}"
[ -f Resources/AppIcon.icns ] || ./scripts/make_icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.itinglight.reellite</string>
  <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Video</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.movie</string><string>org.webmproject.webm</string></array>
    </dict>
  </array>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "✅ 已生成: $(pwd)/$APP"
