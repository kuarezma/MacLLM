# MacLLM Release-Ready Runbook

Bu runbook, yayin oncesi kalite kapisini tek bir akista tamamlamak icindir.

## 0) Scope ve branch hazirligi

- [ ] Branch temizligini kontrol et.
- [ ] Bu surume girecek degisiklik listesini netlestir.
- [ ] Acik bilinen riskleri not et (varsa).

## 1) Zorunlu kalite kapisi (otomatik)

Komut:

```bash
./Scripts/run-unit-tests.sh
```

Beklenen:

- Tum testler `OK` ve script sonu `unit tests basarili`.

## 2) Stabilite smoke (manuel)

Checklist:

- `Scripts/smoke-checklist-iteration1.md`

Odak:

- Acilis, model secimi/yukleme, sohbet, indirme/import, proje ve oturum akislari.
- Kullanici aksiyonlarinda bos/no-op davranis olmamasi.

## 3) Performans dogrulamasi (manuel)

Checklist:

- `Scripts/perf-checklist-iteration3.md`

Odak:

- TTFT, token hizi, model yukleme suresi, uzun streaming akiciligi.
- Ayni model/prompt ile baseline karsilastirmasi.

## 4) Urunlesme ve paketleme kontrolu

Checklist:

- `Scripts/release-checklist-iteration4.md`

Odak:

- Onboarding metinleri ve ilk kullanim akisi.
- Paketleme tutarliligi (DMG/PKG/ZIP/Homebrew).
- Changelog/release note uyumu.

## 5) Go / No-Go karari

Go kosullari:

- [ ] Otomatik testler gecti.
- [ ] Smoke checklist kritik maddeleri gecti.
- [ ] Performans baseline altina dusmedi.
- [ ] Release checklist tamamlandi.

No-Go kosullari:

- Kritik akis bozulmasi, veri kaybi riski, tekrarlanabilir crash, ya da yayin bloklayici performans gerilemesi.

## 6) Commit stratejisi (onerilen)

Iki secenekten biri:

1. **Tek commit**: Kucuk/orta degisikliklerde hizli yayin.
2. **Iterasyon bazli commitler**: Inceleme ve geri alma kolayligi icin.

Iterasyon bazli onerilen commit sirası:

- Iteration 1: Stabilite + hata yonetimi + test/checklist
- Iteration 2: Premium UI/UX iyilestirmeleri
- Iteration 3: Performans optimizasyonlari
- Iteration 4: Onboarding + release checklist/polish

## 7) Son onay notu

Yayin oncesi ekip notuna su ozet eklenir:

- Test sonucu
- Smoke sonucu
- Performans sonucu
- Bilinen sinirlar (varsa)
