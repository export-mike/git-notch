#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="GitNotch.app"

echo ">> Building GitNotch (${CONFIG})"
swift build -c "${CONFIG}"

BIN=".build/${CONFIG}/GitNotch"
echo ">> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/GitNotch"
cp Info.plist "${APP}/Contents/Info.plist"
cp Resources/*.mp3 "${APP}/Contents/Resources/" 2>/dev/null || true

# Ad-hoc code signature so login-item registration works.
codesign --force --sign - "${APP}" >/dev/null 2>&1 || true

echo "OK: built $(pwd)/${APP}"
echo "    Run:  open ${APP}     (or run the binary directly for logs)"
