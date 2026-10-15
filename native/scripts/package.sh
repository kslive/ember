#!/usr/bin/env bash
# Ember release packaging — builds the native app and produces ALL release assets:
#   • Ember-<v>.zip + .sha256   → direct-download archive + checksum
#   • Ember_<v>_aarch64.dmg     → manual download / first install
#
# Does NOT touch /Applications and does NOT publish. Upload to the GitHub release
# manually (gh commands are printed at the end), then verify before announcing.
#
# Usage:  native/scripts/package.sh [version]   (version defaults to MARKETING_VERSION in Project.swift)
set -euo pipefail

cd "$(dirname "$0")/.."                      # → native/
ROOT="$(pwd)"
APP_NAME="Ember"
DERIVED="/tmp/ember-release-dd"
DIST="$ROOT/dist"

VERSION="${1:-$(grep -m1 'MARKETING_VERSION' Project.swift | sed -E 's/.*"([0-9.]+)".*/\1/')}"
echo "▶︎ Packaging $APP_NAME $VERSION"

export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

# 1) Generate + Release build
tuist install --path "$ROOT" >/dev/null
"$ROOT/scripts/patch-sherpa-onnx.sh"
tuist generate --path "$ROOT" --no-open >/dev/null
# The project signs with the App Store team; this local package is ad-hoc signed in step 4.
xcodebuild -workspace "$ROOT/Ember.xcworkspace" -scheme Ember -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" \
  build >/dev/null
SRC_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"

# 2) Stage into dist/
rm -rf "$DIST"; mkdir -p "$DIST"
cp -R "$SRC_APP" "$DIST/$APP_NAME.app"
APP="$DIST/$APP_NAME.app"

# 3) MLX metallib fix (mlx-swift loads mlx.metallib; bundle ships default.metallib) — BEFORE signing
MLIB="$APP/Contents/Frameworks/Cmlx.framework/Versions/A/Resources"
if [ -f "$MLIB/default.metallib" ]; then cp -f "$MLIB/default.metallib" "$MLIB/mlx.metallib"; echo "🔧 mlx.metallib created"; fi

# 4) Sign + clear xattrs. Prefer the persistent self-signed "Ember Signing"
# identity (login keychain): it gives a STABLE designated requirement
# (identifier + certificate leaf), so TCC grants (calendar/microphone) survive
# updates — ad-hoc DRs are per-build cdhashes and reset permissions on every
# update. No Apple account involved; Gatekeeper behavior is unchanged.
# Fallback to ad-hoc keeps the script usable on a machine without the key.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Ember Signing"; then
  codesign --force --deep --sign "Ember Signing" "$APP"
  echo "🔏 signed with Ember Signing (stable TCC identity)"
else
  codesign --force --deep --sign - "$APP"
  echo "⚠️  Ember Signing identity not found — ad-hoc signed (TCC grants will reset on update)"
fi
xattr -cr "$APP"

# 5) Direct-download archive: zip + sha256
( cd "$DIST" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION.zip" )
shasum -a 256 "$DIST/$APP_NAME-$VERSION.zip" | awk '{print $1}' > "$DIST/$APP_NAME-$VERSION.zip.sha256"
SHA="$(cat "$DIST/$APP_NAME-$VERSION.zip.sha256")"
echo "📦 $APP_NAME-$VERSION.zip  sha256=$SHA"

# 6) DMG (manual install)
DMG="$DIST/${APP_NAME}_${VERSION}_aarch64.dmg"
STAGE="$(mktemp -d)"; cp -R "$APP" "$STAGE/$APP_NAME.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "💿 $(basename "$DMG")"

cat <<DONE

✅ Assets in $DIST:
   $APP_NAME-$VERSION.zip (+ .sha256)   ← direct download
   $(basename "$DMG")                    ← manual install

To publish (review first!):
   gh release create v$VERSION -R kslive/ember -t "Ember $VERSION" \\
     "$DIST/$APP_NAME-$VERSION.zip" "$DIST/$APP_NAME-$VERSION.zip.sha256" "$DMG" \\
     -n "Ember $VERSION. SHA256: $SHA"
DONE
