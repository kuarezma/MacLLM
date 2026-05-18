#!/usr/bin/env bash
# GitHub Release: zip + dmg + pkg + Homebrew cask
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' MacLLM/Info.plist)}"
TAG="v${VERSION}"
DIST="$ROOT/dist"

echo "Sürüm: $VERSION ($TAG)"

if [[ ! -d Vendor/build-apple/llama.xcframework ]]; then
  ./Scripts/build-llama-xcframework.sh
fi

./Scripts/build-app.sh
./Scripts/build-packages.sh "$VERSION"

if [[ "${SKIP_GITHUB:-}" == "1" ]]; then
  echo "SKIP_GITHUB=1 — GitHub yükleme atlandı."
  echo "Yayın: git push origin main && git push origin $TAG --force"
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
  "$DIST/MacLLM-${VERSION}-macOS-arm64.dmg" \
  "$DIST/MacLLM-${VERSION}-macOS-arm64.pkg" \
  "$DIST/MacLLM-${VERSION}-macOS-arm64.zip" \
  "$DIST/SHA256SUMS.txt" \
  --title "MacLLM $VERSION" \
  --notes "$(cat <<EOF
## MacLLM $VERSION — macOS Apple Silicon

### Bu sürümde (1.10+)

- Markdown başlıklar (`#`–`###`) ve madde işaretli / numaralı listeler
- Kenar çubuğunda sohbet arama (başlık + mesaj metni)
- Aktif sohbette mesaj arama (⌘F) ve eşleşmeler arasında gezinme

### Önceki (1.9)

- Canlı Markdown akışı; video API; GGUF içe aktarma UX

### Önceki (1.8)

- Oturum başına sohbet dosyası; asistan Markdown; GGUF üzerine yazma onayı

### Kurulum (Terminal gerekmez)

| Yöntem | Dosya |
|--------|--------|
| **Sürükle-bırak (önerilen)** | \`MacLLM-${VERSION}-macOS-arm64.dmg\` — DMG aç, **MacLLM** → **Uygulamalar** |
| **Kurulum sihirbazı** | \`MacLLM-${VERSION}-macOS-arm64.pkg\` — çift tıkla, adımları izle |
| **Elle kopya** | \`MacLLM-${VERSION}-macOS-arm64.zip\` — aç, Uygulamalar’a taşı |

İlk açılış: **sağ tık → Aç** (imzasız build).

### Homebrew

\`\`\`bash
brew install --cask https://raw.githubusercontent.com/kuarezma/MacLLM/main/packaging/homebrew/macllm.rb
\`\`\`

### SHA-256

\`SHA256SUMS.txt\` dosyasına bakın.

### Gereksinimler

- macOS 14+, Apple Silicon (arm64)

- [README (EN)](https://github.com/kuarezma/MacLLM/blob/main/README.md) · [README (TR)](https://github.com/kuarezma/MacLLM/blob/main/README.tr.md)
EOF
)"

echo "Release: https://github.com/kuarezma/MacLLM/releases/tag/$TAG"
