#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="S8Notch.app"

echo ">> Building S8Notch (${CONFIG})"
swift build -c "${CONFIG}"

BIN=".build/${CONFIG}/S8Notch"
echo ">> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/S8Notch"
cp Info.plist "${APP}/Contents/Info.plist"

# Ad-hoc code signature so login-item registration works.
codesign --force --sign - "${APP}" >/dev/null 2>&1 || true

echo "OK: built $(pwd)/${APP}"
echo "    Run:  open ${APP}     (or run the binary directly for logs)"
