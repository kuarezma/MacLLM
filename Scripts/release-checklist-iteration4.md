# MacLLM Iteration 4 Release Checklist

Urunlesme ve dagitim kalitesi icin yayin oncesi kontrol listesi.

## Onboarding ve UX

- [ ] Ilk acilista model secimi adimi net metinlerle anlasilir.
- [ ] Model indirme, secme ve ilk mesaj gonderme akisi uctan uca test edildi.
- [ ] Hata mesajlari kullaniciya cozum onerisi ile gorunuyor.

## Stabilite ve kalite

- [ ] `Scripts/run-unit-tests.sh` basarili.
- [ ] Kritik smoke akislari (`Scripts/smoke-checklist-iteration1.md`) tekrarlandi.
- [ ] Performans kontrolu (`Scripts/perf-checklist-iteration3.md`) guncel sonucla tamamlandi.

## Dagitim

- [ ] Paketleme scriptleri dry-run ile dogrulandi (`build-packages.sh`).
- [ ] Notlar/changelog ilgili surum icin guncellendi.
- [ ] DMG/PKG/ZIP/Homebrew artefact isimlendirmesi ve surum tutarliligi dogrulandi.
