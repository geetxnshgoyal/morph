#!/bin/sh
# Builds Morph.app (menu bar app + bundled `morph` CLI) into ./dist.
# `scripts/bundle.sh --install` also copies it to /Applications and launches it.
# `scripts/bundle.sh --dmg` also makes dist/Morph-<version>.dmg for sharing.
# Builds universal (Apple Silicon + Intel).
#
# Signing: uses the keychain's "Developer ID Application" certificate when there is one (hardened runtime +
# secure timestamp), otherwise ad-hoc (runs here; other Macs need "Open Anyway"). MORPH_SIGN_ID overrides it.
# With a Developer ID, --dmg also notarizes and staples the DMG using the notarytool keychain profile "morph"
# (or MORPH_NOTARY_PROFILE). Create the profile once with
#   xcrun notarytool store-credentials morph --apple-id you@example.com --team-id TEAMID
set -e
cd "$(dirname "$0")/.."
ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS --product MorphMac
swift build -c release $ARCHS --product morph
BIN=$(swift build -c release $ARCHS --show-bin-path)
VERSION=1.0.0
DMG="dist/Morph-$VERSION.dmg"
SIGN_ID="${MORPH_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
SIGN_ID="${SIGN_ID:--}"
NOTARY_PROFILE="${MORPH_NOTARY_PROFILE:-morph}"
sign() {
    if [ "$SIGN_ID" = "-" ]; then codesign --force --sign - "$1"
    else codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$1"; fi
}
APP=dist/Morph.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM's universal build records macOS 14 as the SDK, which runs the app in compatibility mode: no Liquid
# Glass and the old look. Record the SDK it was really built with, as Xcode does (signing comes later).
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Morph" "$BIN/MorphMac" 2>/dev/null
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/Resources/morph" "$BIN/morph" 2>/dev/null
ICONSET=$(mktemp -d)/AppIcon.iconset
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -r "$(dirname "$ICONSET")"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.morph.Morph</string>
  <key>CFBundleName</key><string>Morph</string>
  <key>CFBundleExecutable</key><string>Morph</string>
  <key>CFBundleDisplayName</key><string>Morph</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Free file converter and toolbox</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Any file</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.item</string></array>
  </dict></array>
  <key>NSServices</key><array><dict>
    <key>NSMenuItem</key><dict><key>default</key><string>Open in Morph</string></dict>
    <key>NSMessage</key><string>openFiles</string>
    <key>NSPortName</key><string>Morph</string>
    <key>NSRequiredContext</key><dict/>
    <key>NSSendFileTypes</key><array><string>public.item</string></array>
  </dict></array>
</dict></plist>
PLIST
# Inside out: the bundled CLI first, then the app that seals it.
sign "$APP/Contents/Resources/morph"
sign "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed: $SIGN_ID)"

if [ "$1" = "--dmg" ]; then
    # Styled drag-to-install window (background, icon layout, volume icon) via dmgbuild.
    [ -x .build/dmg-venv/bin/dmgbuild ] || { python3 -m venv .build/dmg-venv && .build/dmg-venv/bin/pip install -q dmgbuild; }
    ART=$(mktemp -d)
    swift scripts/make-dmg-background.swift "$ART"
    rm -f dist/Morph*.dmg
    .build/dmg-venv/bin/dmgbuild -s scripts/dmg-settings.py \
        -D app="$APP" -D volume_icon="$APP/Contents/Resources/AppIcon.icns" -D background="$ART/background.png" \
        "Morph $VERSION" "$DMG" >/dev/null
    rm -r "$ART"
    if [ "$SIGN_ID" = "-" ]; then codesign --force --sign - "$DMG"
    else codesign --force --timestamp --sign "$SIGN_ID" "$DMG"; fi
    if [ "$SIGN_ID" != "-" ]; then
        if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
            xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
            xcrun stapler staple "$DMG"
            spctl --assess --type open --context context:primary-signature -v "$DMG"
        else
            echo "Not notarized: no notarytool profile \"$NOTARY_PROFILE\" (see the top of this script)"
        fi
    fi
    echo "Built $DMG"
fi

if [ "$1" = "--install" ]; then
    osascript -e 'quit app "Morph"' 2>/dev/null || true
    pkill -x Morph 2>/dev/null || true
    rm -rf /Applications/Morph.app
    ditto "$APP" /Applications/Morph.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Morph.app
    /System/Library/CoreServices/pbs -update 2>/dev/null || true
    open /Applications/Morph.app
    echo "Installed /Applications/Morph.app"
fi
