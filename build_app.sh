#!/bin/zsh
set -e
cd "$(dirname "$0")"

APP_NAME="CycleCore"
OUT_DIR="final app"
APP="$OUT_DIR/$APP_NAME.app"
BUILD="build_tmp"

rm -rf "$APP" "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"

echo "→ Kompiliere…"
SOURCES=(main.swift assets/**/*.swift(N))
swiftc -O "${SOURCES[@]}" -o "$APP/Contents/MacOS/$APP_NAME" \
  -framework AppKit -framework IOKit -framework UserNotifications -framework ServiceManagement

echo "→ Erzeuge Icon…"
if [ -f icon.png ]; then
  cp icon.png "$BUILD/icon_1024.png"
else
  swift make_icon.swift "$BUILD/icon_1024.png"
fi
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp -R assets/Sprachen/*.lproj "$APP/Contents/Resources/"

echo "→ Schreibe Info.plist…"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>         <string>local.cyclecore.app</string>
  <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>           <string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key>  <string>en</string>
  <key>CFBundleLocalizations</key>      <array><string>de</string><string>en</string></array>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundleVersion</key>            <string>1</string>
  <key>LSMinimumSystemVersion</key>     <string>13.0</string>
  <key>NSHighResolutionCapable</key>    <true/>
  <key>NSRequiresAquaSystemAppearance</key> <true/>
</dict>
</plist>
EOF

echo "→ Signiere (ad-hoc)…"
codesign --force --deep --sign - -r='designated => identifier "local.cyclecore.app"' "$APP"

rm -rf "$BUILD"

touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
echo "✓ Fertig: $APP"
