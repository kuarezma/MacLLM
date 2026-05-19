# MacLLM Iteration 3 Performance Checklist

Performans optimizasyonlarindan sonra temel metrikleri ayni kosullarda olcun.

## Test ortami

- [ ] Ayni model, ayni prompt ve benzer sistem yukunde olcum yapildi.
- [ ] Uygulama yeniden baslatilip soguk baslangic ve sicak baslangic ayri olculdu.

## Hedef metrikler

- [ ] Model yukleme suresi (cold/warm)
- [ ] Ilk token suresi (TTFT)
- [ ] Ortalama token hizi (tokens/sn)
- [ ] Uzun streaming sirasinda UI akiciligi (gozlemlenen takilma/jank)

## Chat akisi kontrolu

- [ ] Streaming sirasinda otomatik scroll akici ve stabil.
- [ ] Uzun cevaplarda CPU zirve kullanimi onceki surume gore azalmis.
- [ ] Mesaj arama acikken gereksiz scroll tetiklenmiyor.

## Sonuc

- [ ] Baseline karsilastirmasi dokumante edildi.
- [ ] Kazanc saglamayan degisiklikler geri degerlendirildi.
