#!/usr/bin/env bash
# MacLLM dağıtım paketleri: zip, dmg, pkg (+ Homebrew cask şablonu)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' MacLLM/Info.plist)}"
DIST="${DIST:-$ROOT/dist}"
APP_PATH="${APP_PATH:-$ROOT/build/MacLLM.app}"

ZIP_NAME="MacLLM-${VERSION}-macOS-arm64.zip"
DMG_NAME="MacLLM-${VERSION}-macOS-arm64.dmg"
PKG_NAME="MacLLM-${VERSION}-macOS-arm64.pkg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Hata: $APP_PATH bulunamadı. Önce ./Scripts/build-app.sh çalıştırın."
  exit 1
fi

mkdir -p "$DIST"
rm -f "$DIST/$ZIP_NAME" "$DIST/$DMG_NAME" "$DIST/$PKG_NAME"

echo "ZIP oluşturuluyor..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST/$ZIP_NAME"

echo "DMG oluşturuluyor..."
DMG_STAGING="$DIST/.dmg-staging-$$"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -sf /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "MacLLM" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DIST/$DMG_NAME" >/dev/null
rm -rf "$DMG_STAGING"

echo "PKG oluşturuluyor..."
PKG_STAGING="$DIST/.pkg-staging-$$"
rm -rf "$PKG_STAGING"
mkdir -p "$PKG_STAGING/Applications"
cp -R "$APP_PATH" "$PKG_STAGING/Applications/"
pkgbuild \
  --root "$PKG_STAGING" \
  --install-location / \
  --identifier com.macllm.pkg \
  --version "$VERSION" \
  "$DIST/$PKG_NAME"
rm -rf "$PKG_STAGING"

DMG_SHA="$(shasum -a 256 "$DIST/$DMG_NAME" | awk '{print $1}')"
ZIP_SHA="$(shasum -a 256 "$DIST/$ZIP_NAME" | awk '{print $1}')"
PKG_SHA="$(shasum -a 256 "$DIST/$PKG_NAME" | awk '{print $1}')"

{
  shasum -a 256 "$DIST/$ZIP_NAME"
  shasum -a 256 "$DIST/$DMG_NAME"
  shasum -a 256 "$DIST/$PKG_NAME"
} > "$DIST/SHA256SUMS.txt"

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
