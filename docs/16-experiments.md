# 16 — Uygulama İçi Deneyler

"Araştırmaya dayanan" bir sistem, araştırmadan esinlenmekle kalmaz; **kendi yöntemlerinin kendi öğrencilerinde işe yarayıp yaramadığını ölçer.** Bu doküman Dilbaz'ın deney altyapısını ve ilk deneyleri tanımlar.

## 1. İlkeler

1. **Önce kayıt:** Her deney başlamadan önce `docs/experiments/Exx.md` dosyası yazılır: hipotez, birim, kollar, birincil ölçüt, süre, durdurma kuralı. Sonradan ölçüt değiştirilmez.
2. **Öğrenci içi, birim düzeyi rastgeleleme:** İki kişilik bir sistemde kişiler arası karşılaştırma anlamsızdır. Bunun yerine her öğrencinin öğeleri, kartları ya da oturumları kollara rastgele atanır. Bellek araştırmasındaki klasik kişi içi tasarım budur.
3. **Deterministik atama:** `arm = hash(experiment_id, profile_id, unit_ref) mod k`. Atama `experiment_assignments` tablosuna ve her denemenin `experiment` alanına yazılır.
4. **Onay:** Ayarlar > Gizlilik > "Deneylere katıl" (varsayılan kapalı; karşılamada açıklanır). Katılmayan kullanıcı her zaman varsayılan kolu alır.
5. **Değişmez kurallar korunur:** Bir deney kolu bir kuralı yalnızca `01-pedagogy.md` §5'te "açık soru" olarak listelenmiş konularda ve açık onayla esnetebilir (ör. E2'nin doğrudan düzeltme kolu I-02'yi esnetir).
6. **Aynı anda en fazla 2 deney.** Aynı birim iki deneye birden atanmaz.
7. **Dürüst raporlama:** Küçük örneklemde sonuçlar kesinlik değil, **eğilim ve belirsizlik aralığı** olarak raporlanır.

## 2. Analiz

- **Araç:** `tools/analysis/` (Python, pandas + statsmodels ya da bambi/PyMC).
- **Model:** Birincil ölçüt ikili (hatırladı/hatırlamadı) ise karma etkili lojistik regresyon (öğe ve öğrenci rastgele etkileri) ya da Bayesçi eşdeğeri. Etki büyüklüğü ve %95 aralık raporlanır.
- **Güç notu:** İki öğrenci × kol başına ~300 öğe ile, hatırlamada ~10 puanlık farklar makul biçimde görülebilir. Daha küçük farklar için süre uzatılır ya da sonuç "belirsiz" raporlanır.
- **Durdurma:** Önceden belirlenen süre dolunca durdurulur. Bir kol açıkça zarar veriyorsa (ör. hatırlama farkı > 20 puan ve aralık sıfırı içermiyor) erken durdurulur.

## 3. Sonuçların kullanıcıya dönmesi

Deney sonuçları, haftalık öğrenme notu (A25) ile öğrencinin kendi verisi üzerinden anlatılır. Örnek: "Senin verinde sesli çalıştığın kalıplar 30 gün sonra yazılı çalıştıklarından %X daha iyi hatırlandı." Bu, "öğrenmeyi öğrenmek" hedefinin somut karşılığıdır (P20).

## 4. İlk deneyler

| Kod | Soru | Birim | Kollar | Birincil ölçüt | Faz |
|---|---|---|---|---|---|
| **E1** | Sesli mi, yazılı üretim mi daha kalıcı? | Öğe | `speak` / `type` (çalışma modu) | ≥ 21 gün sonraki **sesli** üretimde ipucusuz başarı (hedef beceri konuşma, P3) | 5 |
| **E2** | İpucu merdiveni mi, doğrudan düzeltme mi? | Öğe | Merdiven (H1→H4) / ilk hatada H4 | Sonraki tekrarda ipucusuz başarı; ikincil: öğe başına harcanan süre | 5 |
| **E3** | Karşıtlık setlerinde karışık mı, bloklu mu? | Karşıtlık seti | Karışık / bloklu | ≥ 7 gün sonra karışık testte doğruluk | 6 |
| **E4** | Dizi öncesi kelime ön öğretimi işe yarıyor mu? | Kelime (bölüm içinde) | Ön öğretildi / öğretilmedi | 7 gün sonra dinle-anla doğruluğu | 6 |
| **E5** | Kişisel FSRS parametreleri daha iyi mi? | Kart | Kişisel / varsayılan parametre | Tahmin kalibrasyonu (log-loss), günlük tekrar yükü | 6 |
| **E6** | 4/3/2 mi, tek turluk anlatım mı? | Konu | 4/3/2 / tek 3 dk anlatım | Sonraki haftanın sabit görevlerinde uzun duraklama/dk ve konuşma hızı | 7 |

## 5. Deney dosyası şablonu (`docs/experiments/Exx.md`)

```markdown
# Exx — <kısa başlık>
- Durum: draft | running | stopped | analyzed
- Hipotez:
- Kaynak/gerekçe: (01-pedagogy ilkesi, literatür)
- Birim ve atama:
- Kollar:
- Birincil ölçüt (tanımıyla):
- İkincil ölçütler:
- Esnetilen kural (varsa) ve onay:
- Başlangıç / planlanan bitiş:
- Durdurma kuralı:
- Sonuç (etki, %95 aralık, yorum):
- Karar (varsayılan değişiyor mu?):
```
