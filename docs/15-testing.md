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
| Entegrasyon testleri | `integration_test` (Android telefon ya da emülatör; ekransız `flutter-tester`) | Uçtan uca çekirdek akış, sahte (mock) servislerle (§4) | Faz sonu + haftalık, elle |
| Veritabanı testleri | pgTAP (`supabase test db`) | Her tablo için RLS, RPC'ler, tetikleyiciler | Her commit (CI'da Docker ile) |
| Edge Function testleri | `deno test` | Rota mantığı, şema doğrulama, sızıntı kontrolü, sağlayıcı sırası ve kota | Her commit |
| İçerik hattı testleri | `pytest` | Doğrulayıcılar, kapsama hesabı, derleme | Her commit (content/ değişirse) |
| LLM değerlendirme (eval) | `evals/run.ts` | `07` §8 eşikleri | Sağlayıcı, model ya da prompt değişikliğinde **zorunlu** (ücretsiz kotaları tüketir; elle tetiklenir) |
| Deterministik değerlendirme | `dart test` (motor, `answer_check_golden_test.dart`) | `answer_check` altın seti; `07` §8 deterministik eşikleri | Her commit |
| ASR karşılaştırma testi | `evals/asr/` | `08` §3.2 | Faz 2, sağlayıcı değişikliğinde |
| Canlı kontrol | `app/test_live` (`flutter test`, elle) | Uygulamanın istemcileri + yerel yığın + gerçek sağlayıcılar: ses ve tutor rotaları (§4a) | Sağlayıcı ya da rota değişikliğinden ve sürümden önce (birkaç ücretsiz çağrı) |

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
| I-12 Suçluluk yok | **Metin taraması:** ARB dosyalarında yasak kelime yok (`09` §2 listesi; `app/test/l10n/forbidden_words_test.dart`, Türkçe eklere karşı kök eşleşmesi). Widget testi: uzun aradan dönüşte nötr ekran. Tema testi: hata rengi turuncu, kırmızı değil (`09` §3). |
| I-13 Zaman bütçesi | Planlayıcı özellik testi. |
| I-14 Özerklik | Planlayıcı özellik testi: kalan süre ≥ 5 dk ise ≥ 2 seçenek. |
| I-15 Dilden bağımsız motor | Sentetik dil (`zz`) testleri; içe aktarma sınırı testi; dize sabiti taraması (`11` §7). |
| I-16 Doğrulanmış içerik | İçerik hattı testleri: kaynak/lisans alanı olmayan öğe derlemeyi durdurur. |
| I-17 Adil değerlendirme | Motor testi: normalizasyon + varyant eşleşmesi. Eval: doğru cevabı "yanlış" sayma ≤ %3. |
| I-18 Ses mahremiyeti | pgTAP: partner başkasının `recordings`/`attempts`/`gap_entries` satırlarını okuyamaz. Storage politikası testi. |

## 3. Motor test stratejisi

- **Sentetik dil paketi (`zz`):** Rastgele heceli kelimeler (ASCII dışı harfler dahil), sentetik lemma/biçim tabloları (düzensiz ve eş yazımlı biçimler dahil), sentetik gramer kodları, ayarlanabilir kelime ayırıcı. Motor testlerinin tamamı bununla çalışır (I-15). Üreteç: `packages/engine/test/fixtures/zz/zz_pack.dart`.
- **Kapsam ölçümü:** `dart test --coverage-path=coverage/lcov.info` + `dart run tool/check_coverage.dart` (üretilmiş `*.g.dart`/`*.freezed.dart` hariç, eşik %90).
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

**Uygulama (F1-24):** `app/integration_test/core_flows_test.dart` senaryo 1, 2, 3 ve 5'i koşturur.
- **Gerçek olan:** ekranlar, denetleyiciler, depolar, motor ve cihazın SQLite'ı (bellekte). Paketler uygulamanın kendi içe aktarıcısıyla kurulur (sentetik dil `zz`).
- **Sahte olan:** giriş, sunucu (`sync_push`/`sync_pull` kurallarıyla bellekte; çevrimdışı anahtarı var), LLM, ASR, ses, sistem izinleri ve bildirimler. Telefonda sistem penceresi açılmaz, bildirim kurulmaz.
- **Saat senaryonun elindedir:** kart süresi ve "ertesi gün" böyle kurulur. Depolar satırları bu saatle damgalar.
- **Nasıl koşturulur:** telefonda `.local` kimliğiyle ve `--no-uninstall` ile (`19` §2, "Uçtan uca testler"). Telefonsuz: `flutter test integration_test -d flutter-tester`. CI'da koşmaz: emülatör dakikaları sıfır bütçeye sığmaz.
- **Plan/gerçek farkları:**
  - **Senaryo 1:** 15 dakikalık ilk günde planlayıcı 4 yeni öğe verir, 5 değil. Neden: yeni kartların tekrar yükü tavanın %80'inde kalır (I-07). Kart başına en çok 3 dk sayıldığı için oturum 12 dk tutar; kalan 3 dk kısa gündür ve sırada kart yoktur. "Bugünlük yeter", öğrenci bugünkü süresini 5 dk seçince gelir.
    - Not: Hiçbir bütçede tek bir ilk kart oturumu bütçeyi tek başına doldurmaz (yeni öğe sınırı × 3 dk < bütçe). İlk gün kalan süre seçeneklerle (konuşma görevi vb.) dolar ya da "Şu an sırada kart yok" görünür.
  - **Senaryo 3:** Ertesi gün ilk iki kart, kişisel cümle ve kalıbıdır. İkisinin sırası belirsizdir: öncelikleri aynıdır ve kimlikleri aynı milisaniyede üretilmiş UUIDv7'dir. Test hangisi önce gelirse onu cevaplar.
  - **Senaryo 4, 6 ve 7** uçtan uca test olarak henüz yok. Parçaları widget testlerinde: konuşma görevi, aylık test ve önce/sonra oynatma. İkili görev Faz 2'de gelir.

## 4a. Canlı kontrol (elle)

Uygulamanın kendi istemcileri (`SupabaseSpeechRepository`, `SupabaseTutorRepository`) yerel Supabase yığınına bağlanır; yığının fonksiyonları gerçek sağlayıcıları çağırır (Deepgram, Groq, Gemini).
- Kullanıcının hesabına dokunulmaz: yerel bir test öğrencisi kullanılır.
- Telefon ve insan sesi gerekmez: kayıtları Windows'un konuşma sentezi üretir.

- **Neyi sınar:**
  - İngilizce döküm kelimesi kelimesine yapılıyor mu (öğrencinin hatası kalmalı)?
  - `speaking_annotate` cümlecik, hata ve düzeltme çıkarıyor mu?
  - Türkçe döküm sunucu yolundan geliyor mu?
  - `gap_suggest` öneri veriyor mu?
  - Kullanım satırları (`llm_usage`, `speech_usage`) yazılıyor mu?
- **Maliyet:** Her çalıştırma 4–5 ücretsiz kota çağrısı harcar.
- **Nasıl:** Klasör depo dışında olmalı, çünkü `live.env` yerel anahtar ve parola taşır.
  1. `npx supabase start` ve arka planda `npx supabase functions serve --env-file supabase/functions/.env --no-verify-jwt`.
  2. `python -I app/test_live/make_live_user.py <depo> <klasör>/live.env`: yerel izinli listeye bir test öğrencisi, yapay zekâ onayıyla.
  3. `powershell -File app/test_live/make_live_audio.ps1 -OutDir <klasör>`: `live_en.wav` (Zira, hatalı bir İngilizce tanıtma) ve `live_tr.wav` (Tolga, Türkçe bir cümle). Betik BOM'lu UTF-8'dir; BOM'suz hâlde Windows PowerShell 5.1 Türkçe harfleri bozar.
  4. `cd app && flutter test test_live --dart-define=DILBAZ_LIVE=<klasör>`. Tanım yoksa testler atlanır.
- **2026-10-09 sonucu: 4/4.**
  - Deepgram Nova-3: 59 kelime; "i am work in a bank" olduğu gibi kaldı.
  - `speaking_annotate` (gemini-3.5-flash): 21 sn, 10 cümlecik, 5'i hatasız, 4 düzeltme. Ekranda en çok 3'ü gösterilir (I-02, `correction_choice`).
  - Türkçe (Groq whisper-large-v3): "Canım sıkıldı. Hadi dışarı çıkalım."
  - `gap_suggest`: birincil model (3.5 Flash) günlük kotada "quota" döndü, Flash-Lite 2 sn'de önerdi: "I'm bored. Let's go out."

- **Birlikte (F2-07):** `python -I app/test_live/make_live_pair.py <depo> <klasör>/pair.env` iki yerel partner ve bir ekip kurar; `flutter test test_live/together_live_test.dart --dart-define=DILBAZ_LIVE=<klasör>` uygulamanın `SupabaseTogetherRepository`'siyle ekibi, Realtime üzerinden gelen daveti, yetkisiz kabulün reddini, kabulü ve iki partnerin presence'ta birbirini görmesini sınar; ikinci test bilgi boşluğu oturumunu (başlat, katıl, iki cevap, Realtime ile `done`) sınar (F2-08); üçüncüsü ortak haftayı ve Realtime ile gelen tebriği (F2-09). `db reset`'ten sonraki ilk koşuda presence testi zaman aşımına uğrayabilir (Realtime'ın ısınması); ikinci koşu geçer. Ücretsiz kota harcamaz. **2026-10-17:** geçti (2 sn). Yığın özel kanalı ilk kez kullanırken `realtime.messages` yayınını kurar; o ilk koşu zaman aşımına uğrayabilir.

## 5. CI (GitHub Actions)

`ci.yml` her push ve PR'da şunları çalıştırır:

1. `dart format --output=none --set-exit-if-changed .`
2. `dart analyze` / `flutter analyze` (uyarı = hata)
3. `dart test` (engine)
4. `flutter test` (app; golden testler dahil)
5. `supabase start` → `supabase test db` (pgTAP) → `supabase stop`
6. `deno test` (functions; ayrıca `evals/`: altın setin biçimi ve puanlama, sağlayıcı çağrısı yok)
7. `uv run pytest` (content/tools, yalnızca `content/` değiştiyse)
8. `flutter build apk --debug` (artifact)
9. Gizli anahtar taraması

Eval ve ASR testleri ücretli olduğu için `workflow_dispatch` ile elle tetiklenir. Prompt dosyası değişen PR'da eval sonucu olmadan birleştirme yapılmaz (kural).

Uygulama: `.github/workflows/ci.yml` (işler: `secrets`, `engine`, `app`, `apk`, `database`, `functions`, `content`). Bir koşu ~24 ücretsiz Actions dakikası harcar (en uzunu APK işi, ~12 dk). Sıfır bütçe nedeniyle yalnızca doküman değişikliği (`docs/`, `prompts/`, `*.md`) içeren push'larda CI çalışmaz. Yerelde aynı tarama pre-commit kancasıyla yapılır: `git config core.hooksPath .githooks` (klon başına bir kez).

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
- Haftalık küçük inceleme: `llm_usage` kota tüketimi, `app_events` hataları, ret oranları, kullanıcı itirazları (`user_dispute`).
