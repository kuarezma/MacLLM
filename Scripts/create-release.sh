#!/usr/bin/env bash
# GitHub Release için MacLLM.app zip üretir ve gh release oluşturur.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' MacLLM/Info.plist)}"
TAG="v${VERSION}"
ZIP_NAME="MacLLM-${VERSION}-macOS-arm64.zip"
DIST="$ROOT/dist"

echo "Sürüm: $VERSION ($TAG)"

if [[ ! -d Vendor/build-apple/llama.xcframework ]]; then
  ./Scripts/build-llama-xcframework.sh
fi

./Scripts/build-app.sh

mkdir -p "$DIST"
rm -f "$DIST/$ZIP_NAME" "$DIST/SHA256SUMS.txt"
ditto -c -k --sequesterRsrc --keepParent build/MacLLM.app "$DIST/$ZIP_NAME"
shasum -a 256 "$DIST/$ZIP_NAME" | tee "$DIST/SHA256SUMS.txt"

echo "Paket: $DIST/$ZIP_NAME ($(du -h "$DIST/$ZIP_NAME" | awk '{print $1}'))"

if [[ "${SKIP_GITHUB:-}" == "1" ]]; then
  echo "SKIP_GITHUB=1 — yükleme atlandı."
  echo "GitHub'a yüklemek için: git push origin main && git push origin $TAG --force"
  echo "veya tag push ile CI: git tag -f $TAG && git push origin $TAG --force"
  exit 0
fi

if ! gh auth status -h github.com &>/dev/null; then
  echo "Hata: gh oturumu yok. Çalıştırın: gh auth login -h github.com"
  echo "Alternatif: SKIP_GITHUB=1 ile zip üretin, sonra tag push ile CI release kullanın."
  exit 1
fi

git tag -f "$TAG" 2>/dev/null || true
if ! git push origin "$TAG" --force; then
  echo "Uyarı: tag push başarısız (ağ?). CI için önce: git push origin main"
  exit 1
fi

gh release view "$TAG" 2>/dev/null && gh release delete "$TAG" --yes || true

gh release create "$TAG" \
  "$DIST/$ZIP_NAME" \
  --title "MacLLM $VERSION" \
  --notes "$(cat <<EOF
## MacLLM $VERSION — macOS Apple Silicon

Native local LLM chat: Metal inference, Hugging Face GGUF downloads, streaming UI.

### Download

| File | Platform |
|------|----------|
| **$ZIP_NAME** | macOS 14+, Apple Silicon (arm64) |

**SHA-256:** \`$(awk '{print $1}' "$DIST/SHA256SUMS.txt")\`

### Install

1. Download and unzip \`$ZIP_NAME\`
2. Drag **MacLLM.app** to Applications
3. First launch: **right-click → Open** (unsigned app) or System Settings → Privacy & Security → Open Anyway
4. Open **Online Model** to download a GGUF model from Hugging Face

### Requirements

- macOS 14+ (Sonoma or later)
- Apple Silicon Mac (M1/M2/M3/M4)
- 16 GB RAM recommended for 7B models

### Docs

- [README (English)](https://github.com/kuarezma/MacLLM/blob/main/README.md)
- [README (Türkçe)](https://github.com/kuarezma/MacLLM/blob/main/README.tr.md)

---

**Full changelog:** Initial public release.
EOF
)"

echo "Release: https://github.com/kuarezma/MacLLM/releases/tag/$TAG"
