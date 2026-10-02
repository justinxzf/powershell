#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PowerShell"
BUNDLE_ID="com.powershell.app"
VERSION="1.0.0"
BUILD_NUM="1" 
DIST_DIR="${PROJECT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
RESOURCE_BUNDLE="${PROJECT_DIR}/.build/release/${APP_NAME}_${APP_NAME}.bundle"

echo "==> Building ${APP_NAME} (Release)..."
swift build -c release --package-path "${PROJECT_DIR}"

echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${PROJECT_DIR}/.build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "${PROJECT_DIR}/Sources/PowerShell/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"

cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>PowerShell</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.powershell.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PowerShell</string>
    <key>CFBundleDisplayName</key>
    <string>PowerShell</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo "==> Signing app bundle (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Verifying app bundle signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Creating DMG..."
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
rm -f "${DMG_PATH}"

DMG_STAGING="$(mktemp -d)"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_STAGING}"

DMG_SIZE=$(du -h "${DMG_PATH}" | cut -f1)
echo ""
echo "==> Done! DMG created: ${DMG_PATH} (${DMG_SIZE})"
echo "    App bundle: ${APP_BUNDLE}"
echo ""
echo "    Note: The app bundle is ad-hoc signed and verified locally before DMG packaging."
echo "    This addresses the previous unsigned-bundle integrity issue behind the damaged-app problem, but does not guarantee every cross-machine Gatekeeper outcome."
echo "    On another Mac, first launch may still require allowing an unidentified developer app."
