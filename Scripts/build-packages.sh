#!/usr/bin/env bash
# MacLLM dağıtım paketleri: zip, dmg, pkg (+ Homebrew cask şablonu)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' MacLLM/Info.plist)}"
DIST="${DIST:-$ROOT/dist}"
APP_PATH="${APP_PATH:-$ROOT/build/MacLLM.app}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"

ZIP_NAME="MacLLM-${VERSION}-macOS-arm64.zip"
DMG_NAME="MacLLM-${VERSION}-macOS-arm64.dmg"
PKG_NAME="MacLLM-${VERSION}-macOS-arm64.pkg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Hata: $APP_PATH bulunamadı. Önce ./Scripts/build-app.sh çalıştırın."
  exit 1
fi

if [[ "$REQUIRE_SIGNING" == "1" ]]; then
  if [[ -z "$APP_SIGN_IDENTITY" || -z "$PKG_SIGN_IDENTITY" || -z "$NOTARYTOOL_PROFILE" ]]; then
    echo "Hata: REQUIRE_SIGNING=1 için APP_SIGN_IDENTITY, PKG_SIGN_IDENTITY ve NOTARYTOOL_PROFILE zorunlu."
    exit 1
  fi
fi

echo "Uygulama imzalanıyor..."
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}" "$ROOT/Scripts/sign-app.sh" "$APP_PATH"

mkdir -p "$DIST"
rm -f "$DIST/$ZIP_NAME" "$DIST/$DMG_NAME" "$DIST/$PKG_NAME" "$DIST/SHA256SUMS.txt"

echo "ZIP oluşturuluyor..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST/$ZIP_NAME"

echo "DMG oluşturuluyor..."
DMG_STAGING="$DIST/.dmg-staging-$$"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -sf /Applications "$DMG_STAGING/Applications"
if [[ -f "$ROOT/packaging/dmg/KURULUM.txt" ]]; then
  cp "$ROOT/packaging/dmg/KURULUM.txt" "$DMG_STAGING/KURULUM.txt"
fi
if [[ -f "$ROOT/packaging/dmg/MacLLM-Kur.command" ]]; then
  cp "$ROOT/packaging/dmg/MacLLM-Kur.command" "$DMG_STAGING/MacLLM-Kur.command"
  chmod +x "$DMG_STAGING/MacLLM-Kur.command"
fi
hdiutil create \
  -volname "MacLLM" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DIST/$DMG_NAME" >/dev/null
rm -rf "$DMG_STAGING"

echo "DMG doğrulanıyor..."
hdiutil verify "$DIST/$DMG_NAME" >/dev/null
DMG_MOUNT="$DIST/.dmg-mount-$$"
rm -rf "$DMG_MOUNT"
mkdir -p "$DMG_MOUNT"
hdiutil attach "$DIST/$DMG_NAME" -nobrowse -readonly -mountpoint "$DMG_MOUNT" >/dev/null
if [[ ! -d "$DMG_MOUNT/MacLLM.app" ]]; then
  hdiutil detach "$DMG_MOUNT" -force >/dev/null || true
  rm -rf "$DMG_MOUNT"
  echo "Hata: DMG mount edildi ama MacLLM.app bulunamadı."
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$DMG_MOUNT/MacLLM.app"
hdiutil detach "$DMG_MOUNT" >/dev/null
rm -rf "$DMG_MOUNT"

echo "PKG oluşturuluyor..."
PKG_STAGING="$DIST/.pkg-staging-$$"
rm -rf "$PKG_STAGING"
mkdir -p "$PKG_STAGING/Applications"
cp -R "$APP_PATH" "$PKG_STAGING/Applications/"
PKG_SCRIPTS="$ROOT/packaging/pkg-scripts"
chmod +x "$PKG_SCRIPTS/postinstall" 2>/dev/null || true
pkgbuild \
  --root "$PKG_STAGING" \
  --install-location / \
  --identifier com.macllm.pkg \
  --version "$VERSION" \
  --scripts "$PKG_SCRIPTS" \
  "$DIST/$PKG_NAME"
rm -rf "$PKG_STAGING"

if [[ -n "$PKG_SIGN_IDENTITY" ]]; then
  echo "PKG imzalanıyor..."
  productsign --sign "$PKG_SIGN_IDENTITY" "$DIST/$PKG_NAME" "$DIST/$PKG_NAME.signed"
  mv -f "$DIST/$PKG_NAME.signed" "$DIST/$PKG_NAME"
  pkgutil --check-signature "$DIST/$PKG_NAME" >/dev/null
else
  echo "Uyarı: PKG_SIGN_IDENTITY yok; pkg unsigned kalacak."
fi

if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
  echo "DMG notarize ediliyor..."
  xcrun notarytool submit "$DIST/$DMG_NAME" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$DIST/$DMG_NAME"
  echo "PKG notarize ediliyor..."
  xcrun notarytool submit "$DIST/$PKG_NAME" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$DIST/$PKG_NAME"
else
  echo "Uyarı: NOTARYTOOL_PROFILE yok; notarization atlandı."
fi

DMG_SHA="$(shasum -a 256 "$DIST/$DMG_NAME" | awk '{print $1}')"
ZIP_SHA="$(shasum -a 256 "$DIST/$ZIP_NAME" | awk '{print $1}')"
PKG_SHA="$(shasum -a 256 "$DIST/$PKG_NAME" | awk '{print $1}')"

(
  cd "$DIST"
  shasum -a 256 "$ZIP_NAME" "$DMG_NAME" "$PKG_NAME"
) > "$DIST/SHA256SUMS.txt"

CASK_DIR="$ROOT/packaging/homebrew"
mkdir -p "$CASK_DIR"
cat > "$CASK_DIR/macllm.rb" <<RUBY
# Homebrew Cask — MacLLM ${VERSION}
# Kurulum: brew install --cask ./packaging/homebrew/macllm.rb

cask "macllm" do
  version "${VERSION}"
  sha256 "${DMG_SHA}"

  url "https://github.com/kuarezma/MacLLM/releases/download/v\#{version}/MacLLM-\#{version}-macOS-arm64.dmg"
  name "MacLLM"
  desc "Native local LLM chat for Apple Silicon (Metal, Hugging Face GGUF)"
  homepage "https://github.com/kuarezma/MacLLM"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "MacLLM.app"

  zap trash: [
    "~/Library/Application Support/MacLLM",
  ]
end
RUBY

echo ""
echo "Paketler ($VERSION):"
echo "  ZIP  $DIST/$ZIP_NAME"
echo "  DMG  $DIST/$DMG_NAME"
echo "  PKG  $DIST/$PKG_NAME"
echo "  Cask $CASK_DIR/macllm.rb"
echo ""
echo "SHA-256 (DMG): $DMG_SHA"
