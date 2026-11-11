#!/bin/bash
# Build Choxieshoot into a self-contained macOS .app bundle.
# Usage: ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Choxieshoot"
BUNDLE="build/${APP_NAME}.app"
CONTENTS="${BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

rm -rf "${BUNDLE}" "build/${APP_NAME} "*.app
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Compiling Objective-C sources…"
clang \
  -fobjc-arc \
  -fblocks \
  -O2 \
  -Wall \
  -Wno-deprecated-declarations \
  -mmacosx-version-min=11.0 \
  -framework Cocoa \
  -framework QuartzCore \
  -framework Carbon \
  -framework CoreGraphics \
  -framework CoreImage \
  -framework Vision \
  -framework AVFoundation \
  -framework AVKit \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework UniformTypeIdentifiers \
  -o "${MACOS_DIR}/${APP_NAME}" \
  Choxieshoot/*.m \
  -I Choxieshoot

echo "==> Packaging app bundle…"
cp Choxieshoot/Info.plist "${CONTENTS}/Info.plist"
if [ -f Choxieshoot/AppIcon.icns ]; then
  cp Choxieshoot/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> Signing (ad-hoc)…"
codesign --force --deep --sign - "${BUNDLE}" >/dev/null 2>&1 || {
  echo "warning: ad-hoc codesign failed; app may still run locally"
}

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
for DEST_DIR in "${HOME}/Applications" "/Applications"; do
  if [ -d "${DEST_DIR}" ] && [ -w "${DEST_DIR}" ]; then
    echo "==> Syncing ${DEST_DIR}/${APP_NAME}.app…"
    rm -rf "${DEST_DIR}/${APP_NAME}.app"
    ditto "${BUNDLE}" "${DEST_DIR}/${APP_NAME}.app"
    if [ -x "${LSREGISTER}" ]; then
      "${LSREGISTER}" -f "${DEST_DIR}/${APP_NAME}.app" >/dev/null 2>&1 || true
    fi
  fi
done
if [ -x "${LSREGISTER}" ]; then
  "${LSREGISTER}" -f "$(pwd)/${BUNDLE}" >/dev/null 2>&1 || true
fi
ditto -c -k --sequesterRsrc --keepParent "${BUNDLE}" "build/${APP_NAME}-1.7.zip"
cp -f "build/${APP_NAME}-1.7.zip" "build/${APP_NAME}-1.6.zip"

echo "==> Built ${BUNDLE}"
echo "    Open it with: open \"${BUNDLE}\""
echo "    Self-test:    \"${MACOS_DIR}/${APP_NAME}\" --selftest"
