#!/bin/bash
# Builds TrainerHUD.app into ./build using only the Swift toolchain (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" 2>&1 | grep -vE "^\s*$" || true
BIN=".build/$CONFIG/TrainerHUD"
[ -x "$BIN" ] || { echo "build failed"; exit 1; }
APP="build/TrainerHUD.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TrainerHUD"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TrainerHUD</string>
  <key>CFBundleDisplayName</key><string>TrainerHUD</string>
  <key>CFBundleIdentifier</key><string>com.hugob.TrainerHUD</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleExecutable</key><string>TrainerHUD</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.hugob.TrainerHUD</string>
      <key>CFBundleURLSchemes</key><array><string>trainerhud</string></array>
    </dict>
  </array>
  <key>NSBluetoothAlwaysUsageDescription</key><string>TrainerHUD connects to your smart trainer, heart rate strap, power meter and Zwift Click shifters.</string>
  <key>NSBluetoothPeripheralUsageDescription</key><string>TrainerHUD connects to your smart trainer, heart rate strap, power meter and Zwift Click shifters.</string>
</dict>
</plist>
PLIST
echo -n "APPL????" > "$APP/Contents/PkgInfo"
# A stable identity keeps the macOS Bluetooth permission across rebuilds (ad-hoc signatures re-prompt every time).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "TrainerHUD Dev"; then
  codesign --force --sign "TrainerHUD Dev" --identifier com.hugob.TrainerHUD "$APP" 2>&1 | grep -v "replacing existing" || true
else
  codesign --force --sign - --identifier com.hugob.TrainerHUD "$APP" >/dev/null 2>&1 || echo "warning: codesign failed"
fi
echo "Built $APP"
