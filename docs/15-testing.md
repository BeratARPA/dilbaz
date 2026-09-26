# 15 — Test ve Kalite

Kalite burada iki anlama gelir:
1. **Yazılım doğru çalışıyor.**
2. **Pedagojik kurallar çiğnenmiyor.** Değişmez kuralların (I-01 … I-18) çoğu otomatik testle korunur.

## 1. Test katmanları

| Katman | Araç | Kapsam hedefi | Ne zaman |
|---|---|---|---|
| Motor birim + özellik testleri | `dart test` (packages/engine) | Satır kapsamı ≥ %90 | Her commit (CI) |
| Uygulama birim/controller testleri | `flutter test` | ≥ %70 (application katmanı) | Her commit |
| Widget ve golden testler | `flutter test` | Ana akışlar (kart, merdiven, bugün, ilerleme) | Her commit |
| Entegrasyon testleri | `integration_test` (Android emülatör) | Uçtan uca çekirdek akış, sahte (mock) servislerle | Faz sonu + haftalık |
| Veritabanı testleri | pgTAP (`supabase test db`) | Her tablo için RLS, RPC'ler, tetikleyiciler | Her commit (CI'da Docker ile) |
| Edge Function testleri | `deno test` | Rota mantığı, şema doğrulama, sızıntı kontrolü, bütçe | Her commit |
| İçerik hattı testleri | `pytest` | Doğrulayıcılar, kapsama hesabı, derleme | Her commit (content/ değişirse) |
| LLM değerlendirme (eval) | `evals/run.ts` | `07` §8 eşikleri | Prompt/model değişikliğinde **zorunlu** (ücretli, CI'da elle tetiklenir) |
| ASR karşılaştırma testi | `evals/asr/` | `08` §3.2 | Faz 2, sağlayıcı değişikliğinde |

## 2. Değişmez kural → test eşlemesi

| Kural | Test(ler) |
|---|---|
| I-01 Önce deneme | Widget testi: kart akışında cevap alanı boşken H4/doğru cevap görünmez. Controller testi: `reveal()` ilk denemeden önce reddedilir. |
| I-02 İpucu merdiveni | Controller testi: merdiven sırayla açılır. Sunucu testi: H1–H3 normalize edilmiş doğru cevabı içerirse reddedilir. Eval: sızıntı %0. |
| I-03 Her deneme loglanır | Repository testi: her akış sonunda `attempts` + outbox satırı var. DB testi: `attempts` üzerinde update/delete politikası yok. |
| I-04 Kanıta dayalı ilerleme | Motor testleri: kanıt düzeyleri yalnızca tanımlı koşullarla verilir. Widget testi: ilerleme ekranında "%" yalnızca izin verilen ölçümlerde. |
| I-05 Pratik = hedef | Planlayıcı testi: varsayılan kart modu `speak`, sessiz modda `type`. Model testi: `recognize_audio` üretim düzeyini etkilemez. |
| I-06 Anlaşılır girdi | Planlayıcı özellik testi: kapsama < %95 metin önerilmez; %95–98 ise ön öğretim eklidir. |
| I-07 Tekrar yükü | Planlayıcı özellik testi (`05` §8). |
| I-08 Aralığı FSRS belirler | Motor testi: vade tarihleri yalnızca FSRS çıktısından gelir. |
| I-09 Rehberlik azalır | Motor testi: iskele profili seviye tablosuyla eşleşir. |
| I-10 Karışık çalışma | Planlayıcı testi: karşıtlık çiftleri aynı gün tanıtılmaz, öğrenildikten sonra aynı blokta karışık gelir. |
| I-11 Yapay zekâ düşünmeyi devralmaz | Sunucu testleri: katalog dışı etiket reddi; cevapsız çağrı reddi. Eval eşikleri. |
| I-12 Suçluluk yok | **Metin taraması:** ARB dosyalarında yasak kelime yok (`09` §2 listesi). Widget testi: uzun aradan dönüşte nötr ekran. |
| I-13 Zaman bütçesi | Planlayıcı özellik testi. |
| I-14 Özerklik | Planlayıcı özellik testi: kalan süre ≥ 5 dk ise ≥ 2 seçenek. |
| I-15 Dilden bağımsız motor | Sentetik dil (`zz`) testleri; içe aktarma sınırı testi; dize sabiti taraması (`11` §7). |
| I-16 Doğrulanmış içerik | İçerik hattı testleri: kaynak/lisans alanı olmayan öğe derlemeyi durdurur. |
| I-17 Adil değerlendirme | Motor testi: normalizasyon + varyant eşleşmesi. Eval: doğru cevabı "yanlış" sayma ≤ %3. |
| I-18 Ses mahremiyeti | pgTAP: partner başkasının `recordings`/`attempts`/`gap_entries` satırlarını okuyamaz. Storage politikası testi. |

## 3. Motor test stratejisi

- **Sentetik dil paketi (`zz`):** Rastgele heceli kelimeler, sentetik lemma/biçim tabloları, sentetik gramer kodları. Motor testlerinin tamamı bununla çalışır (I-15).
- **Özellik tabanlı testler:** Rastgele öğrenci durumları, kart kümeleri ve içerik üreteçleri ile planlayıcı ve model değişmezleri denenir. Seed'li ve tekrarlanabilirdir.
- **FSRS entegrasyonu:** Bilinen bir tekrar dizisi için paketten beklenen durumlar karşılaştırılır. Tekrar oynatma (fuzz kapalı) determinizmi test edilir.
- **Simülasyon testi:** Sentetik bir öğrenci (hatırlama olasılığı FSRS'e göre örneklenir) 8 hafta çalıştırılır. Tekrar yükü tavanı aşmamalı, kol açıkları kapanmalı, yeni öğe akışı durmamalı.
- **Ölçümler:** `FluencyMetrics` ve `06` §3.3 formülleri elle hesaplanmış örneklerle doğrulanır.

## 4. Uçtan uca senaryolar (entegrasyon)

1. Karşılama → seviye testi (sahte) → ilk oturum: tanıtım + 5 kart (sahte ASR/LLM) → "Bugünlük yeter"
2. Kart: yanlış cevap → H1 → H2 → doğru → FSRS "Hard" → deneme + outbox kaydı
3. Söyleyemediklerim: yakalama → öneri (sahte) → karta ekle → ertesi günün tekrarında görünür
4. Konuşma görevi: kayıt (sahte ses) → işleme → 3 düzeltme akışı → kişisel öğeler oluşur
5. Çevrimdışı: kart (yazılı) → deneme outbox'ta → bağlantı gelince senkron → sunucuda satır var
6. İkili görev: iki sahte istemci → rol yükleri ayrı → cevap → sonuç
7. Aylık test: 5 görev → rapor ekranı → "önce/sonra" oynatma

## 5. CI (GitHub Actions)

`ci.yml` her push ve PR'da şunları çalıştırır:

1. `dart format --output=none --set-exit-if-changed .`
2. `dart analyze` / `flutter analyze` (uyarı = hata)
3. `dart test` (engine)
4. `flutter test` (app; golden testler dahil)
5. `supabase start` → `supabase test db` (pgTAP) → `supabase stop`
6. `deno test` (functions)
7. `uv run pytest` (content/tools, yalnızca `content/` değiştiyse)
8. `flutter build apk --debug` (artifact)
9. Gizli anahtar taraması

Eval ve ASR testleri ücretli olduğu için `workflow_dispatch` ile elle tetiklenir. Prompt dosyası değişen PR'da eval sonucu olmadan birleştirme yapılmaz (kural).

## 6. Lint ve stil

- **Dart:** `very_good_analysis` (ya da `flutter_lints` + katı kurallar). `prefer_const`, `always_declare_return_types`, `avoid_dynamic_calls` açık.
- **TypeScript (Deno):** `deno lint`, `deno fmt`.
- **Python:** `ruff` (lint + format), `mypy` (katı olmayan mod).
- **SQL:** `supabase db lint`.

## 7. "Tamamlandı" tanımı (her görev için)

Bir görev ancak şu koşullar sağlanınca tamamlanmış sayılır:

1. Kod yazıldı, analiz uyarısız, format temiz.
2. İlgili testler yazıldı ve geçiyor. İlgili değişmez kural testleri güncel.
3. Kullanıcıya görünen metinler ARB'de ve yasak kelime testinden geçiyor.
4. Doküman etkileniyorsa güncellendi (`docs/`). Karar değiştiyse ADR eklendi.
5. `docs/17-roadmap.md` içindeki görev kutusu işaretlendi, ilerleme günlüğüne satır eklendi.
6. Commit atıldı: konvansiyonel mesaj, İngilizce, atıf satırı.

## 8. Elle kullanım testi (dogfooding)

- Her faz sonunda iki kullanıcı en az birkaç gün gerçek kullanım yapar. Geri bildirimler `docs/feedback.md` dosyasına tarih ve maddeyle yazılır.
- Haftalık küçük inceleme: `llm_usage` maliyeti, `app_events` hataları, ret oranları, kullanıcı itirazları (`user_dispute`).
