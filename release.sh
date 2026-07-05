#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Build a release .app, wrap it in a drag-to-install DMG, tag the commit, and
# publish a GitHub release with the DMG attached.
#
# Usage:  ./release.sh [version]
#   version  Optional. Defaults to CFBundleShortVersionString in Info.plist.
#            When passed, Info.plist is updated to match before building.

APP="GitNotch.app"
VOL="Git Notch"

# --- version ---------------------------------------------------------------
plist_version() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist
}
VERSION="${1:-$(plist_version)}"
if [[ -z "${VERSION}" ]]; then
  echo "!! could not determine version" >&2; exit 1
fi
if [[ -n "${1:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" Info.plist
fi
TAG="v${VERSION}"
DMG="GitNotch-${VERSION}.dmg"

# --- auth / repo -----------------------------------------------------------
# Prefer an explicit env token, else the project token file (see repo memory).
if [[ -z "${GH_TOKEN:-}" && -f "${HOME}/.config/git-notch/token" ]]; then
  GH_TOKEN="$(cat "${HOME}/.config/git-notch/token")"
  export GH_TOKEN
fi
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

echo ">> Releasing ${TAG} to ${REPO}"

# --- build -----------------------------------------------------------------
./build.sh release

# --- package DMG -----------------------------------------------------------
echo ">> Packaging ${DMG}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"   # drag-to-install target

rm -f "${DMG}"
hdiutil create \
  -volname "${VOL}" \
  -srcfolder "${STAGE}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG}" >/dev/null

SHA="$(shasum -a 256 "${DMG}" | awk '{print $1}')"
echo "   ${DMG}  sha256=${SHA}"

# --- tag -------------------------------------------------------------------
if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  git tag -a "${TAG}" -m "Git Notch ${VERSION}"
  git push origin "${TAG}"
else
  echo ">> Tag ${TAG} already exists — reusing"
fi

# --- publish ---------------------------------------------------------------
NOTES="$(cat <<EOF
Git Notch ${VERSION}

**Install:** open the DMG and drag **Git Notch** onto the **Applications** folder.

On first launch, macOS may warn the app is from an unidentified developer
(it is ad-hoc signed). Right-click the app → **Open**, then confirm.

\`\`\`
sha256  ${SHA}
\`\`\`
EOF
)"

if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  echo ">> Release ${TAG} exists — updating asset"
  gh release upload "${TAG}" "${DMG}" --repo "${REPO}" --clobber
else
  gh release create "${TAG}" "${DMG}" \
    --repo "${REPO}" \
    --title "Git Notch ${VERSION}" \
    --notes "${NOTES}"
fi

echo "OK: published ${TAG} — https://github.com/${REPO}/releases/tag/${TAG}"
