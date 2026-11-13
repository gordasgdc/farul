#!/bin/bash
# Construiește candidatul Farul, reproductibil: compilare release (ieșire pe
# extern, STORAGE_POLICY), asamblare .app, semnare Developer ID + hardened
# runtime, pachet .pkg (pkgbuild + productbuild cu licență + productsign),
# manifest de actualizare local, verificări. Notarizarea e un pas SEPARAT și
# explicit (--notarize): trimite pachetul la Apple.
#
#   scripts/build_app.sh [--notarize] [--unsigned]
#
# Rezultat: $OUT/candidate-<versiune>/{Farul.app, Farul-<versiune>.pkg, update/update.json, SHA256SUMS}
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="/Volumes/CristiGordas/TESTE"
NOTARIZE=0; UNSIGNED=0
for a in "$@"; do case "$a" in --notarize) NOTARIZE=1;; --unsigned) UNSIGNED=1;; *) echo "argument necunoscut: $a"; exit 2;; esac; done

# Poarta de stocare (Regula 52): fără volum extern real și scriibil, STOP.
if [ ! -d "$EXT" ] || [ ! -w "$EXT" ] || ! mount | grep -q " on /Volumes/CristiGordas "; then
  echo "EXTERNAL TEST STORAGE NOT AVAILABLE"; exit 3
fi
PROJ="$EXT/GDC_PROJECTS/Farul"; BUILDS="$PROJ/builds"
mkdir -p "$BUILDS/clang" "$BUILDS/cache" "$BUILDS/scratch"
[ -x /Users/gordasgdc/Developer/_gdc-tools/gdc-disk-guard.sh ] && /Users/gordasgdc/Developer/_gdc-tools/gdc-disk-guard.sh 2 || true

PKG_DIR="$ROOT/macOS/Farul"
PLIST="$PKG_DIR/Resources/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD_NO=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")

# Regula 14: versiunea e sincronă în toate punctele care o poartă.
MANIFEST_V=$(python3 -c "import json;print(json.load(open('$ROOT/gdc-manifest.json'))['version'])")
CHANGELOG_V=$(grep -m1 -oE '^## v[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CHANGELOG.md" | sed 's/## v//')
[ "$VERSION" = "$MANIFEST_V" ] && [ "$VERSION" = "$CHANGELOG_V" ] || { echo "Versiuni nesincrone: plist=$VERSION manifest=$MANIFEST_V changelog=$CHANGELOG_V"; exit 1; }

CAND="$BUILDS/candidate-$VERSION"
APP="$CAND/Farul.app"
rm -rf "$CAND"; mkdir -p "$CAND"

echo "→ Compilare release (ieșire: $BUILDS/scratch)"
( cd "$PKG_DIR" && CLANG_MODULE_CACHE_PATH="$BUILDS/clang" swift build -c release --scratch-path "$BUILDS/scratch" --cache-path "$BUILDS/cache" )
BIN="$BUILDS/scratch/release/Farul"
"$ROOT/scripts/check-l10n.sh" "$BIN"

echo "→ Asamblare Farul.app $VERSION (build $BUILD_NO)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/GDC"
cp "$BIN" "$APP/Contents/MacOS/Farul"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$PKG_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/gdc-manifest.json" "$APP/Contents/Resources/GDC/"

find_identity() { security find-identity -v | grep "$1" | grep "8AR6XP8MG7" | head -1 | awk '{print $2}'; }
if [ "$UNSIGNED" = 1 ]; then
  codesign --force -s - "$APP"; SIGNED="ad-hoc"
else
  APP_ID=$(find_identity "Developer ID Application")
  [ -n "$APP_ID" ] || { echo "Lipsește identitatea Developer ID Application (Team 8AR6XP8MG7) în Keychain."; exit 4; }
  codesign --force --timestamp --options runtime --sign "$APP_ID" "$APP"
  SIGNED="developer-id"
fi
codesign --verify --strict --deep --verbose=1 "$APP"
SIGNED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$SIGNED_VERSION" = "$VERSION" ] || { echo "Versiunea din bundle ($SIGNED_VERSION) ≠ $VERSION"; exit 1; }   # Regula 0

echo "→ Pachet .pkg"
STAGE="$CAND/_stage"; mkdir -p "$STAGE/root/Applications" "$STAGE/res"
ditto "$APP" "$STAGE/root/Applications/Farul.app"
# Componentă ne-relocabilă: altfel installer-ul ar „actualiza” orice copie de Farul.app găsită în altă parte.
pkgbuild --analyze --root "$STAGE/root" "$STAGE/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$STAGE/component.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$STAGE/component.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :0:BundleIsRelocatable' "$STAGE/component.plist")" = "false" ] || { echo "BundleIsRelocatable nu e false"; exit 1; }
pkgbuild --root "$STAGE/root" --component-plist "$STAGE/component.plist" --identifier dev.gordas.Farul.pkg \
  --version "$VERSION" --install-location / "$STAGE/Farul-component.pkg" >/dev/null
sed "s/@VERSION@/$VERSION/" "$ROOT/installer/Distribution.xml.in" > "$STAGE/Distribution.xml"
cp "$ROOT/installer/license.txt" "$STAGE/res/license.txt"
PKG="$CAND/Farul-$VERSION.pkg"          # Regula 17: versiunea în NUMELE fișierului
if [ "$UNSIGNED" = 1 ]; then
  productbuild --distribution "$STAGE/Distribution.xml" --resources "$STAGE/res" --package-path "$STAGE" "$PKG" >/dev/null
else
  INST_ID=$(find_identity "Developer ID Installer")
  [ -n "$INST_ID" ] || { echo "Lipsește identitatea Developer ID Installer."; exit 4; }
  productbuild --distribution "$STAGE/Distribution.xml" --resources "$STAGE/res" --package-path "$STAGE" \
    --sign "$INST_ID" --timestamp "$PKG" >/dev/null
fi
rm -rf "$STAGE"
pkgutil --check-signature "$PKG" | sed -n 1,6p || true

if [ "$NOTARIZE" = 1 ]; then
  echo "→ Notarizare (trimite la Apple, profil gdc-notary)"
  xcrun notarytool submit "$PKG" --keychain-profile gdc-notary --wait
  xcrun stapler staple "$PKG"
  xcrun stapler validate "$PKG"
fi

SHA=$(shasum -a 256 "$PKG" | awk '{print $1}')   # DUPĂ staple: stapling schimbă octeții pachetului
echo "$SHA  Farul-$VERSION.pkg" > "$CAND/SHA256SUMS"

echo "→ Manifest de actualizare local (canal 127.0.0.1)"
mkdir -p "$CAND/update"
PORT="${FARUL_UPDATE_PORT:-8765}"
python3 - "$CAND/update/update.json" "$VERSION" "$SHA" "$PORT" <<'PY'
import json, sys
path, version, sha, port = sys.argv[1:5]
json.dump({
  "version": version, "app_version": version,
  "changes": "Candidat local: somn/trezire, diagnostic exportabil, dezinstalare, actualizare verificată.",
  "download_url": {"mac": f"http://127.0.0.1:{port}/Farul-{version}.pkg"},
  "sha256": {"mac": sha},
  "mandatory": False
}, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
cp "$PKG" "$CAND/update/"

echo
echo "✅ Candidat: $CAND"
echo "   App:  $APP  (semnare: $SIGNED, notarizat: $([ "$NOTARIZE" = 1 ] && echo da || echo NU))"
echo "   Pkg:  $PKG"
echo "   sha256: $SHA"
