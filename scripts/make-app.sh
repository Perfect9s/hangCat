#!/usr/bin/env bash
# Builds hangCat.app from the SPM target and produces a distributable zip.
#
#   ./scripts/make-app.sh               # default version 0.1.0
#   ./scripts/make-app.sh 0.2.0         # custom version
#
# Output:
#   build/hangCat.app
#   build/hangCat.app.zip   (this is the file to attach to a GitHub release)

set -euo pipefail

VERSION="${1:-0.1.0}"
BUNDLE_ID="com.hangcat.app"
APP_NAME="hangCat"
PRODUCT="hangCat"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Cleaning build/"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> swift build -c release (universal: arm64 + x86_64)"
swift build -c release \
    --arch arm64 \
    --arch x86_64

# SPM puts release artefacts under .build/apple/Products/Release
RELEASE_DIR="$ROOT/.build/apple/Products/Release"
if [[ ! -f "$RELEASE_DIR/$PRODUCT" ]]; then
    # Fallback for single-arch builds
    RELEASE_DIR="$(swift build -c release --show-bin-path)"
fi

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$RELEASE_DIR/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"

# SPM's resource bundle (Bundle.module) — must live in Contents/Resources/
# so the generated `resource_bundle_accessor.swift` finds it via
# `Bundle.main.resourceURL`.
RES_BUNDLE="${PRODUCT}_${PRODUCT}.bundle"
if [[ -d "$RELEASE_DIR/$RES_BUNDLE" ]]; then
    cp -R "$RELEASE_DIR/$RES_BUNDLE" "$APP/Contents/Resources/$RES_BUNDLE"
else
    echo "WARNING: $RES_BUNDLE not found in $RELEASE_DIR — cat sprites may be missing"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>           <string>en</string>
    <key>CFBundleExecutable</key>                  <string>$PRODUCT</string>
    <key>CFBundleIdentifier</key>                  <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>       <string>6.0</string>
    <key>CFBundleName</key>                        <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>                 <string>APPL</string>
    <key>CFBundleShortVersionString</key>          <string>$VERSION</string>
    <key>CFBundleVersion</key>                     <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>              <string>14.0</string>
    <key>LSUIElement</key>                         <true/>
    <key>NSHighResolutionCapable</key>             <true/>
    <key>NSPrincipalClass</key>                    <string>NSApplication</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>hangCat 需要读取窗口位置，让小猫贴在窗口标题栏上。</string>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -5 || true

echo "==> Zipping for distribution"
( cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.app.zip" )

ls -lh "$BUILD_DIR"
echo
echo "Done."
echo "  $APP"
echo "  $BUILD_DIR/$APP_NAME.app.zip   ← attach this to your GitHub release"
