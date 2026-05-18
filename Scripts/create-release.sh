#!/usr/bin/env bash
# GitHub Release için MacLLM.app zip + DMG (Uygulamalar'a sürükle) üretir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' MacLLM/Info.plist)}"
TAG="v${VERSION}"
ZIP_NAME="MacLLM-${VERSION}-macOS-arm64.zip"
DMG_NAME="MacLLM-${VERSION}-macOS-arm64.dmg"
DIST="$ROOT/dist"

echo "Sürüm: $VERSION ($TAG)"

if [[ ! -d Vendor/build-apple/llama.xcframework ]]; then
  ./Scripts/build-llama-xcframework.sh
fi

./Scripts/build-app.sh

mkdir -p "$DIST"
rm -f "$DIST/$ZIP_NAME" "$DIST/$DMG_NAME" "$DIST/SHA256SUMS.txt"

ditto -c -k --sequesterRsrc --keepParent build/MacLLM.app "$DIST/$ZIP_NAME"

# DMG: MacLLM.app + Applications kısayolu (sürükle-bırak kurulum, terminal gerekmez)
STAGING="$DIST/.dmg-staging-$$"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R build/MacLLM.app "$STAGING/"
ln -sf /Applications "$STAGING/Applications"
hdiutil create -volname "MacLLM" -srcfolder "$STAGING" -ov -format UDZO "$DIST/$DMG_NAME" >/dev/null
rm -rf "$STAGING"

{
  shasum -a 256 "$DIST/$ZIP_NAME"
  shasum -a 256 "$DIST/$DMG_NAME"
} | tee "$DIST/SHA256SUMS.txt"

echo "Paketler:"
echo "  ZIP: $DIST/$ZIP_NAME ($(du -h "$DIST/$ZIP_NAME" | awk '{print $1}'))"
echo "  DMG: $DIST/$DMG_NAME ($(du -h "$DIST/$DMG_NAME" | awk '{print $1}'))"

if [[ "${SKIP_GITHUB:-}" == "1" ]]; then
  echo "SKIP_GITHUB=1 — yükleme atlandı."
  echo "GitHub: git push origin main && git push origin $TAG --force"
  exit 0
fi

if ! gh auth status -h github.com &>/dev/null; then
  echo "Hata: gh oturumu yok. Çalıştırın: gh auth login -h github.com"
  exit 1
fi

git push origin main
git tag -f "$TAG"
git push origin "$TAG" --force

gh release view "$TAG" 2>/dev/null && gh release delete "$TAG" --yes || true

gh release create "$TAG" \
  "$DIST/$DMG_NAME" \
  "$DIST/$ZIP_NAME" \
  --title "MacLLM $VERSION" \
  --notes "$(cat <<EOF
## MacLLM $VERSION — macOS Apple Silicon

### Install (no Terminal)

1. Download **$DMG_NAME** (recommended) or the zip
2. Open the DMG — drag **MacLLM** to **Applications**
3. First launch: **right-click MacLLM → Open** (unsigned build)
4. In the app: **Model Add → Recommended** or **Online** to download a GGUF model

### Downloads

| File | Description |
|------|-------------|
| **$DMG_NAME** | Drag-to-Applications installer |
| **$ZIP_NAME** | Zip archive (manual copy to Applications) |

**SHA-256:** see \`SHA256SUMS.txt\` in release assets.

### Highlights (1.2.0)

- Model download progress: speed, size, ETA
- Pause, resume, and cancel downloads
- Hardware-aware model recommendations
- DMG installer for easy setup

### Requirements

- macOS 14+, Apple Silicon (arm64)

### Docs

- [README (English)](https://github.com/kuarezma/MacLLM/blob/main/README.md)
- [README (Türkçe)](https://github.com/kuarezma/MacLLM/blob/main/README.tr.md)
EOF
)"

echo "Release: https://github.com/kuarezma/MacLLM/releases/tag/$TAG"
