# MacLLM Iteration 1 Smoke Checklist

Bu checklist stabilite ve sifir hata hedefi icin kritik kullanici akislari icindir.

## 1) Acilis ve temel durum

- [ ] Uygulama acilisinda crash olmadan ana ekran goruluyor.
- [ ] Durum cubugunda beklenmeyen bir hata mesaji gorulmuyor.
- [ ] Model secili degilken sohbet gonderimi kullaniciya anlasilir yonlendirme veriyor.

## 2) Model secimi ve yukleme

- [ ] Sidebar uzerinden model secimi basarili.
- [ ] Model yuklenirken tekrar secim denemeleri UI kilitlenmesi olusturmuyor.
- [ ] Yukleme hatasi olursa hata mesaji neden + cozum onerisi ile gorunuyor.

## 3) Sohbet akisi

- [ ] Yeni sohbet olusturma ve mevcut sohbet secimi tutarli calisiyor.
- [ ] Mesaj gonderimi, streaming ve yaniti durdur aksiyonlari sorunsuz.
- [ ] Uretim hatalarinda sohbet bozulmadan kalici hata geri bildirimi veriliyor.

## 4) Indirme ve dosya islemleri

- [ ] Hub uzerinden model indirme baslatilabiliyor.
- [ ] Indirme iptal/yeniden deneme akisinda UI tutarli.
- [ ] Indirme/ice aktarma hatalarinda kullaniciya acik hata mesaji veriliyor.

## 5) Proje ve oturum yonetimi

- [ ] Proje olusturma, guncelleme ve silme akislarinda tutarlilik var.
- [ ] Sohbet silme ve projeye tasima aksiyonlari dogru calisiyor.
- [ ] Hata durumlarinda sessizce basarisiz olma yok.

## 6) Kalite kapisi

- [ ] `Scripts/run-unit-tests.sh` basarili.
- [ ] Manuel smoke sonunda kritik akislarda beklenmeyen hata/log yok.
- [ ] Aciklanan tum regresyonlar kapatildi veya issue olarak kayda alindi.
