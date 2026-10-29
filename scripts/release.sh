#!/usr/bin/env bash
# Builds a universal, ad-hoc signed Aura.app and packages it as dist/Aura-<version>.dmg.
# Requires: Xcode, xcodegen, create-dmg (brew install xcodegen create-dmg).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*: *"?([0-9.]+)"?/\1/')
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "› Generating project"
xcodegen generate --quiet

echo "› Building Aura $VERSION (arm64 + x86_64)"
xcodebuild -project Aura.xcodeproj -scheme Aura -configuration Release \
  -derivedDataPath "$WORK/dd" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet
APP="$WORK/dd/Build/Products/Release/Aura.app"
codesign --verify --deep --strict "$APP"
mkdir -p "$WORK/src" && cp -R "$APP" "$WORK/src/"

echo "› Preparing DMG art"
mkdir -p "$WORK/Aura.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s docs/art/icon-1024.png --out "$WORK/Aura.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) docs/art/icon-1024.png --out "$WORK/Aura.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/Aura.iconset" -o "$WORK/Aura.icns"
tiffutil -cathidpicheck docs/art/dmg-background.png docs/art/dmg-background@2x.png -out "$WORK/background.tiff" >/dev/null

echo "› Packaging"
mkdir -p dist
rm -f "dist/Aura-$VERSION.dmg"
create-dmg \
  --volname "Aura $VERSION" --volicon "$WORK/Aura.icns" \
  --background "$WORK/background.tiff" \
  --window-pos 200 140 --window-size 660 480 \
  --icon-size 128 --text-size 13 \
  --icon "Aura.app" 170 190 --hide-extension "Aura.app" \
  --app-drop-link 490 190 --no-internet-enable \
  "dist/Aura-$VERSION.dmg" "$WORK/src"

shasum -a 256 "dist/Aura-$VERSION.dmg"
