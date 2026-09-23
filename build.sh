#!/bin/zsh
# Builds build/NetSpeed.app, then installs it into /Applications and restarts it.
#
#   ./build.sh               build and install
#   ./build.sh --no-install  build only

set -e
cd "$(dirname "$0")"

VERSION=1.0.0
BUNDLE_ID=io.github.yashchavda96.netspeed
MIN_MACOS=13.0

APP=build/NetSpeed.app
DEST=/Applications/NetSpeed.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# AppIcon.icon (an Icon Composer document) compiles to Assets.car, with Default, Dark,
# Clear and Tinted variants, plus AppIcon.icns for older macOS. Needs full Xcode.
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target "$MIN_MACOS" --app-icon AppIcon \
    --output-partial-info-plist build/icon-info.plist >/dev/null
else
  echo "warning: actool not found (it comes with Xcode), so the app will have no icon" >&2
fi

# Universal binary, so it runs on both Apple Silicon and Intel Macs.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" Sources/*.swift -o "build/NetSpeed-$arch"
done
lipo -create build/NetSpeed-arm64 build/NetSpeed-x86_64 -output "$APP/Contents/MacOS/NetSpeed"
rm build/NetSpeed-arm64 build/NetSpeed-x86_64

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NetSpeed</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>NetSpeed</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

# Ad-hoc signature: enough to run locally, but not notarized.
codesign --force --sign - "$APP"

if [[ "$1" == "--no-install" ]]; then
  echo "Built $APP"
  exit 0
fi

pkill -x NetSpeed && sleep 1 || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
