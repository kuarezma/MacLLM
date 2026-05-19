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

### Bu sürümde (1.14.19)

- Gözlemlenebilirlik: model yükleme, üretim yaşam döngüsü, durdurma akışı ve indirme süreçlerine süre/durum bazlı yapılandırılmış tanı logları eklendi
- Tanı sinyalleri: generation stalled/empty retry denemeleri ile terminal üretim hataları ayrıştırıldı; fallback/cancel akışları loglandı
- Destek hızı: kalıcı kullanıcı hatalarına kısa “Hata Kodu” eklendi ve aynı kimlik uygulama loglarıyla eşleştirildi
- Yayın hazırlığı: paket artefact akışı 1.14.19 sürümüne hizalandı (DMG/PKG/ZIP + Homebrew cask checksum güncellemesi)

### Önceki (1.14.18)

- Stabilite: AppModel genelinde kullanıcı hataları tek formatta ve çözüm önerisiyle gösteriliyor
- UI/UX: Ayarlar, sohbet ve Model Hub için premium buton stilleri ve daha tutarlı etkileşim geri bildirimi
- Performans: Streaming sırasında otomatik scroll yoğunluğu azaltıldı; uzun yanıtlarda daha akıcı deneyim
- Kalite kapısı: UserErrorFormatter birim testleri eklendi, release/smoke/perf checklist runbook ile birleştirildi

### Önceki (1.14.16)

- Qwopus: redacted_im_end stop/sanitize; üretim zaman aşımı; boş yanıt hatası

### Önceki (1.14.14)

- Token-tabanlı KV prompt cache: Compute error ve bozuk çok turlu sohbet düzeltmesi
- decodeFailed otomatik retry + flash attention fallback (uyumsuz modeller)
- maxTokens limiti düzeltmesi (n_decode)
- Açılışta model yükleme sorusu (Sor / Otomatik / Yükleme)
- İçe aktarılan GGUF modellerde flash attention varsayılan kapalı

### Önceki (1.14.13)

- KV prompt cache düzeltmesi: önbellek artık gerçek prefill + üretim metni ile hizalanır; token pozisyonu doğrulanır
- Yarım ChatML kontrol token'ları (ör. im_start) ekranda gösterilmez
- Önbellek uyuşmazlığında otomatik tam prefill'e düşülür

### Önceki (1.14.12)

- **Inference performansı:** chunked prefill, flash attention, ayarlanabilir batch size
- **KV prompt cache:** çok turlu sohbette yalnızca yeni mesaj prefill (TTFT düşer)
- **Hot-apply ayarlar:** maxTokens ve sampling model reload gerektirmeden güncellenir
- **Donanım profili:** RAM/çekirdeğe göre Hız / Denge / Kalite preset ve tier varsayılanları
- **Streaming UI:** izole buffer — sidebar ve bağlam halkası stream sırasında donmaz
- **I/O:** debounced session save, detached disk yazımı, context token fingerprint cache

### Önceki (1.14.11)

- Silinen sohbetlerin geri gelmesi düzeltildi: aktif sohbet silinince artık yeniden kaydedilmez
- Streaming sonrası arka plan kaydı silme ile yarışmayacak şekilde korundu

### Önceki (1.14.10)

- Model-adaptive runtime profile: model yüklendiğinde GGUF + mtmd + heuristics birleşir
- UI ve inference tek kaynaktan: şablon, stop dizileri, vision, bağlam üst sınırı
- Composer/header/bağlam halkası/ayarlar modele göre şekillenir (global num_ctx değişmez)
- Vision ekleri profil tutarsızsa engellenir; mmproj/base model uyarıları profile taşındı

### Önceki (1.14.9)

- phi-2 Instruct prompt formatı; echo sorunu ve yanlış chatml/phi3 şablonu düzeltildi
- Base model uyarı bandı (phi-2 base için composer rehberi)
- Streaming performans: üretim sırasında bağlam sayımı durduruldu, akıcı metin akışı
- Header ayarlar butonu: openSettings bridge, görsel ve hit-target iyileştirmesi

### Önceki (1.14.8)

- Ayarlar butonu düzeltmesi: sidebar, header ve composer menüsünden açılır
- Sohbet silme: onay penceresi sidebar üzerinde, swipe ile silme desteği
- Model silme onay penceresi macOS uyumlu hale getirildi

### Önceki (1.14.7)

- Composer buton düzeltmesi: + ekle, gönder, durdur, bağlam halkası tıklama alanı
- İndirme toolbar bildirimi: aç/kapa toggle, badge tıklamayı engellemez
- Model Hub quant satırı: info popover doğru konumda açılır

### Önceki (1.14.6)

- Modern arayüz: cam efektler, gradient accent, spring animasyonlar
- Yenilenen sidebar, composer, hızlı promptlar ve durum çubuğu
- Gradient kullanıcı baloncukları ve bağlam halkası

### Önceki (1.14.5)

- Vision model rehberi: composer uyarısı, Hub üzerinden otomatik mmproj indirme
- mmproj dosyası otomatik bulma ve modele bağlama
- Görüntü gönderimi için net yönlendirme (Qwen2-VL, LLaVA, Moondream)

### Önceki (1.14.4)

- Model Hub arama listesi: yayıncı avatarları, sabit satır düzeni
- Quant uygunluk kartı ve Mac RAM rehberi (Q4_K_M vb.)

### Önceki (1.14.3)

- LM Studio tarzı Model Hub: split arama + detay paneli, metadata, quant seçici
- Paralel indirme ilerleme düzeltmesi (0% takılması giderildi)
- PDF ekleri: metin çıkarımı, taranmış PDF sayfa görüntüleri, hata banner

### Önceki (1.14.2)

- Jan tarzı Ayarlar; Hub parametre boyutu gösterimi

### Önceki (1.14)

- Jan.ai tarzı sohbet arayüzü, projeler, bağlam halkası

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
