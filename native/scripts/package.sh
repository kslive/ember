#!/usr/bin/env bash
# Ember release packaging — builds the native app and produces ALL release assets:
#   • Ember-<v>.zip + .sha256   → feed for the in-app updater (1.3 → 1.4+)
#   • Ember.app.tar.gz + latest.json → ONE-TIME bridge so Tauri 1.2.x auto-updates to native 1.3
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
TAURI_KEY="$HOME/.ember-updater-private.key" # minisign key baked into 1.2 (id 768B8FDF9AF51758)

VERSION="${1:-$(grep -m1 'MARKETING_VERSION' Project.swift | sed -E 's/.*"([0-9.]+)".*/\1/')}"
echo "▶︎ Packaging $APP_NAME $VERSION"

export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

# 1) Generate + Release build
tuist install --path "$ROOT" >/dev/null
tuist generate --path "$ROOT" --no-open >/dev/null
xcodebuild -workspace "$ROOT/Ember.xcworkspace" -scheme Ember -configuration Release \
  -derivedDataPath "$DERIVED" build >/dev/null
SRC_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"

# 2) Stage into dist/
rm -rf "$DIST"; mkdir -p "$DIST"
cp -R "$SRC_APP" "$DIST/$APP_NAME.app"
APP="$DIST/$APP_NAME.app"

# 3) MLX metallib fix (mlx-swift loads mlx.metallib; bundle ships default.metallib) — BEFORE signing
MLIB="$APP/Contents/Frameworks/Cmlx.framework/Versions/A/Resources"
if [ -f "$MLIB/default.metallib" ]; then cp -f "$MLIB/default.metallib" "$MLIB/mlx.metallib"; echo "🔧 mlx.metallib created"; fi

# 4) Ad-hoc sign (no Apple cert / notarization) + clear xattrs
codesign --force --deep --sign - "$APP"
xattr -cr "$APP"

# 5) Native-updater feed: zip + sha256 (asset names MUST end in .zip / .zip.sha256)
( cd "$DIST" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION.zip" )
shasum -a 256 "$DIST/$APP_NAME-$VERSION.zip" | awk '{print $1}' > "$DIST/$APP_NAME-$VERSION.zip.sha256"
SHA="$(cat "$DIST/$APP_NAME-$VERSION.zip.sha256")"
echo "📦 $APP_NAME-$VERSION.zip  sha256=$SHA"

# 6) 1.2 → 1.3 BRIDGE (Tauri updater): tar.gz + minisign signature + latest.json
TARBALL="$DIST/$APP_NAME.app.tar.gz"
( cd "$DIST" && tar czf "$APP_NAME.app.tar.gz" "$APP_NAME.app" )
SIG=""
if command -v tauri >/dev/null 2>&1; then
  # tauri writes "<tarball>.sig"; its contents is the value for latest.json.signature
  tauri signer sign --private-key-path "$TAURI_KEY" "$TARBALL"
  [ -f "$TARBALL.sig" ] && SIG="$(cat "$TARBALL.sig")"
fi
if [ -z "$SIG" ]; then
  # NEVER write a latest.json with an empty signature — every 1.2.x client would reject
  # it, stranding the whole existing user base. Fail hard instead.
  echo "❌  Tarball signing failed (need the Tauri CLI + key password)."
  echo "    Run:  tauri signer sign --private-key-path $TAURI_KEY $TARBALL"
  echo "    Then re-run this script. NOT writing latest.json (would break the 1.2→1.3 bridge)."
  exit 1
fi
REL_BASE="https://github.com/kslive/ember/releases/download/v$VERSION"
cat > "$DIST/latest.json" <<JSON
{
  "version": "$VERSION",
  "notes": "Ember $VERSION — native macOS rewrite.",
  "platforms": {
    "darwin-aarch64": {
      "url": "$REL_BASE/$APP_NAME.app.tar.gz",
      "signature": "$SIG"
    }
  }
}
JSON
echo "🌉 latest.json + $APP_NAME.app.tar.gz (Tauri 1.2 bridge)"

# 7) DMG (manual install)
DMG="$DIST/${APP_NAME}_${VERSION}_aarch64.dmg"
STAGE="$(mktemp -d)"; cp -R "$APP" "$STAGE/$APP_NAME.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "💿 $(basename "$DMG")"

cat <<DONE

✅ Assets in $DIST:
   $APP_NAME-$VERSION.zip (+ .sha256)   ← in-app updater feed (1.3→1.4+)
   $APP_NAME.app.tar.gz + latest.json   ← 1.2→1.3 Tauri bridge
   $(basename "$DMG")                    ← manual install

To publish (review first!):
   gh release create v$VERSION -R kslive/ember -t "Ember $VERSION" \\
     "$DIST/$APP_NAME-$VERSION.zip" "$DIST/$APP_NAME-$VERSION.zip.sha256" \\
     "$DIST/$APP_NAME.app.tar.gz" "$DIST/latest.json" "$DMG" \\
     -n "Ember $VERSION. SHA256: $SHA"
DONE
