# 17 — Yol Haritası

Tam sürüm (v1.0) sekiz fazda inşa edilir. Her faz kullanılabilir bir sürüm üretir. Kodlayan ajan her oturumda bu dosyayı okur, **mevcut fazdaki ilk işaretlenmemiş görevi** alır, "tamamlandı" tanımına (`15` §7) göre bitirir, kutuyu işaretler ve alttaki **İlerleme günlüğü**ne bir satır ekler.

**Kurallar:**
- Görevler sırayla yapılır. Bir görev bir sonrakine engel değilse ve açık bir fayda varsa sıra değişebilir; değişiklik günlüğe yazılır.
- 👤 işaretli adımlar kullanıcının yapması gereken işlerdir (hesap, anahtar, sistem ayarı, onay). Ajan bu adımlarda durur, `19-setup.md`'deki ilgili bölümü gösterir ve bekler.
- Her fazın sonunda **faz dalı** `main`'e birleştirilir. Önce kabul kriterleri kontrol edilir ve kısa bir faz raporu yazılır.
- **Önerilen kullanım kapısı:** Faz 1 ve 2'den sonra en az 1–2 hafta günlük kullanım yapılır. Geri bildirimler `docs/feedback.md` dosyasına yazılır. Kodlama sonraki fazda sürebilir; geri bildirimler öncelikli ele alınır.

---

## Faz 0 — Temel kurulum
Dal: `faz-0`

- [x] **F0-01** Git deposu:
  - `git init`, dal `faz-0`
  - `.gitignore`: Flutter/Dart/Deno/Python, `env/`, `supabase/functions/.env`, `content/{sources,work,build}/`, `evals/asr/audio/`, `*.jks`, `key.properties`
  - `.editorconfig`, README kontrolü
- [x] **F0-02** Araç doğrulama: `flutter doctor -v`, `docker info`, `supabase --version`, `deno --version`, `uv --version`, `node --version`. Eksik varsa 👤 `19-setup.md` §2.
- [x] **F0-03** `packages/engine` iskeleti:
  - Dart 3.13 SDK kısıtı; `fsrs ^2.0.1`, `freezed` 4, `json_serializable`, `meta`
  - `very_good_analysis`, klasör yapısı (`12` §2)
  - Sentetik dil paketi üreteci (`test/fixtures/zz`)
  - İlk test: FSRS adaptörü (önekli içe aktarma, UTC)
- [x] **F0-04** `app` iskeleti:
  - `flutter create --org com.dilbaz --project-name dilbaz_app --platforms android,windows,web app`
  - Bağımlılıklar (`12` §4)
  - `l10n.yaml` + `app_tr.arb`
  - Material 3 tema ve renk token'ları (`09` §3)
  - go_router (4 sekme + "Söyleyemedim" butonu), boş ekranlar
  - Yasak kelime testi (`15` §2, I-12)
- [x] **F0-05** drift şema v1: kullanıcı tabloları, outbox, sync_state, boş içerik tabloları (`13` §8). drift_flutter kurulumu, migrasyon testi.
- [x] **F0-06** Supabase yerel:
  - `supabase init`
  - `config.toml`: e-posta OTP açık, kayıt izin listesi
  - İlk migrasyon: `sync_seq`, `profiles`, `courses`, `teams`, `team_members` + RLS
  - pgTAP testleri; `supabase start && supabase test db` geçer
- [x] **F0-07** Edge Functions iskeleti:
  - `_shared/`: auth, budget, `llm_config.ts`, `speech_config.ts`, yapılandırılmış log
  - `tutor` fonksiyonunda `health` rotası
  - `deno test`
- [x] **F0-08** İçerik araçları iskeleti: `content/tools` (uv, typer CLI `dilbaz-content --help`, pytest, ruff).
- [x] **F0-09** CI: `.github/workflows/ci.yml` (`15` §5) + gizli anahtar taraması. İlk koşu yeşil.
- [x] **F0-10** 👤 Hesaplar ve anahtarlar (`19-setup.md` §1): *(ücretli anahtarlar sıfır bütçe nedeniyle F1-00'a ertelendi)*
  - Supabase projesi (Frankfurt)
  - Anthropic, Deepgram, Azure Speech anahtarları
  - `supabase link` ve `supabase secrets set` (kullanıcı çalıştırır)
  - `env/prod.json`
- [x] **F0-11** Android'de uçtan uca iskelet: debug APK telefonda açılır, e-posta kodu ile giriş, boş Bugün ekranı. Migrasyonlar üretime 👤 onayla `supabase db push`.

**Kabul:** CI yeşil; Android'de giriş çalışıyor; yerel pgTAP testleri geçiyor; anahtarlar yalnızca secrets'ta.

---

## Faz 1 — Çekirdek döngü (v0.1)
Dal: `faz-1`

### Ön koşul
- [x] **F1-00** ADR-0009 — sıfır bütçe (`18` §0): Claude API ve Azure olmadan çalışma yolları. 👤 Karar (2026-09-26): her bileşende ücretsiz olan en iyisi. LLM: Gemini + Groq ücretsiz katmanları, deterministik yedek. Ses: Deepgram kredisi, cihaz üstü, Kokoro. İçerik: Claude Code oturumları. Etkilenen görevler aşağıda güncellendi.

### İçerik
- [x] **F1-01** Hat S0–S1:
  - Kaynakları indir: NGSL, NGSL-S, CEFR-J, Octanove, wordfreq, CMUdict, Tatoeba EN–TR, Wiktextract alt kümesi
  - `lexicon.en.jsonl` üret, testleri yaz
- [x] **F1-02** S2 seçim (A0–A2):
  - Kelime anlamları
  - 120 kalıplık sohbet çantası (NGSL-Spoken + LLM önerisi + 👤 hızlı gözden geçirme)
  - 40 gramer kodu
- [ ] **F1-03** S3–S4 cümle üretimi ve doğrulama:
  - Tatoeba adayları + Claude Code oturumlarında üretim (ADR-0009)
  - Üretenden ayrı oturumda doğrulama geçişi (`10` §5.2)
  - QA raporu; 👤 20 örneklik inceleme
- [ ] **F1-04** S5 tr-en:
  - Karşılıklar, açıklamalar, karşıtlık notları
  - Geniş varyant listeleri ve H3 kural notları (LLM'siz değerlendirmenin temeli, ADR-0009 §2)
  - ~30 etiketlik hata kataloğu (`10` §6)
- [ ] **F1-05** Paketin tamamlanması:
  - S6 ses: Kokoro, çevrimdışı (≥ 2 ses + yavaş); 👤 kısa dinleme karşılaştırması (Kokoro / Gemini Flash TTS)
  - S8 X_Lex bankası
  - S9 derleme: `en@1.sqlite`, `tr-en@1.sqlite`
  - S10 rapor
  - 👤 onayla `upload`

### Motor
- [ ] **F1-06** FSRS adaptörü + otomatik puan (`03` §0.3) + `card_state_after`.
- [ ] **F1-07** `LanguageServices` (normalize/tokenize/lemma) + deterministik değerlendirme (`03` §0.5: eşleşme, hizalama, şablonlu merdiven) + varyantlar. Sentetik dil testleri.
- [ ] **F1-08** Öğrenci modeli v1:
  - L1 kart hafızası; L2 düzeyleri (new/learning/recallable/durable)
  - X_Lex puanlama, bant olasılıkları, kişisel kapsama (`06` §2)
- [ ] **F1-09** Planlayıcı v1:
  - Tekrar bloğu, yeni öğe sınırı, minimum gün, bütçe
  - Basit seçenekler
  - `05` §8 testleri 1, 2, 6, 7, 9
- [ ] **F1-10** Müfredat sıralaması (`02` §4.3) + taşıyıcı cümle seçimi (i+1).

### Uygulama ve sunucu
- [ ] **F1-11** Paket indirme, doğrulama, atomik içe aktarma (`11` §5) + içerik DAO'ları.
- [ ] **F1-12** Karşılama akışı (`09` §5.1): ekip oluşturma/katılma, ses onayı ve yapay zekâ veri onayı (ADR-0009, kullanıcı başına) dahil.
- [ ] **F1-13** Seviye testi (A24: X_Lex + gramer + dikte) + başlangıç kaydı.
- [ ] **F1-14** Ses altyapısı:
  - Kayıt ve kodlayıcı seçimi (`08` §4)
  - `speech/transcribe` fonksiyonu: Deepgram adaptörü (İngilizce); Türkçe cihaz üstü (`speech_to_text`), sunucu yedeği Groq/Gemini
  - 👤 Deepgram anahtarı (`19` §1)
  - `speech_usage` kaydı
- [ ] **F1-15** `tutor/answer_check` (`07` §4.1):
  - Sağlayıcı yönlendiricisi + Gemini ve Groq adaptörleri (SDK context7 ile doğrulanır; ADR-0009)
  - zod şeması, sabit sistem promptu, merdiven sızıntı kontrolü, kota ve adil paylaşım, `llm_usage`
  - deno testleri
  - Eval seti v1 (≥ 200 vaka), ücretsiz kotalarda eval; sonuçlara göre rota sırası (`07` §2)
  - 👤 Gemini ve Groq anahtarları (`19` §1)
- [ ] **F1-16** Kart oturumu (A00, A01, A02): merdiven, "yanlış duyuldu", sessiz mod, otomatik puan, deneme + outbox.
- [ ] **F1-17** Söyleyemediklerim (A19): yakalama butonu, yazılı ve sesli (Türkçe) yakalama, `tutor/gap_suggest` (Gemini Flash; kota dolunca bekleyen öneri), karta ekleme, Android paylaş menüsü hedefi.
- [ ] **F1-18** Bugün ekranı v1 + "Bugünlük yeter" + "bugün ne kadar vaktin var?".
- [ ] **F1-19** Konuşma görevi v1 (A11) + `tutor/speaking_annotate` (Gemini Flash; kota yoksa sonradan) + akıcılık ölçümleri (motor) + aylık test v1 (A23: tek işaretleme).
- [ ] **F1-20** İlerleme v1: kanıt sayıları, önce/sonra ses dinleme, basit eğilimler.
- [ ] **F1-21** Senkron v1: outbox, `sync_push`/`sync_pull` RPC'leri, Faz 1 tabloları, pgTAP RLS testleri.
- [ ] **F1-22** Bildirim: çıpa saatinde tek davet, sessiz saatler, bugün çalışıldıysa gönderilmez.
- [ ] **F1-23** Ayarlar v1: bütçe, çıpa, sessiz mod, yapay zekâ veri onayı, dışa aktar (JSON), tüm verimi sil.
- [ ] **F1-24** Teslim:
  - Entegrasyon testleri (`15` §4: 1, 2, 3, 5)
  - İmzalı sürüm APK (yerel keystore, 👤 parola)
  - İki telefona kurulum rehberi

**Kabul:**
- İki kullanıcı Android'de şunları kullanıyor: seviye testi, kart döngüsü, Söyleyemediklerim, konuşma görevi, aylık test.
- Denemeler senkronlanıyor.
- I-01…I-08, I-12…I-15 ve I-17 testleri yeşil.
- answer_check eval eşikleri seçilen sağlayıcıyla sağlandı; deterministik değerlendirme altın set eşiklerini geçiyor (`07` §8).
- Kullanım ve kota `llm_usage` ve `speech_usage` tablolarında görünüyor.

---

## Faz 2 — Konuşma, ses ve birlikte (v0.2)
Dal: `faz-2`

- [ ] **F2-01** ASR karşılaştırma testi (`08` §3.2):
  - Kayıt aracı ve 👤 veri seti kaydı
  - Ücretsiz adayların adaptörleri: Gemini Transcribe, Groq `whisper-large-v3`, cihaz üstü (Android, `sherpa-onnx`), ücretsiz kredisi varsa AssemblyAI (`08` §3.2)
  - Sonuçlar; ADR-0006 güncellemesi; gerekirse varsayılan sağlayıcıyı değiştir
- [ ] **F2-02** Konuşma görevi tam (A11):
  - İskeleler, yeniden yapma
  - Düzeltmelerin kişisel öğe olması
  - Aktarım tespiti → `transferred` düzeyi
- [ ] **F2-03** 4/3/2 (A12).
- [ ] **F2-04** Dikte (A05): hizalama, WER, `perc.*` etiketleri.
- [ ] **F2-05** Gölgeleme (A07): telaffuz sağlayıcısı kararı (ADR-0009: ücretsiz seçenek, Faz 2 başında), `speech/assess` (WAV 16 kHz), `pron.*` eşlemesi.
- [ ] **F2-06** Dinle-anla (A03) + bağlamda boşluk (A04).
- [ ] **F2-07** Birlikte: sohbet kartları (A14), partner varlığı (presence), "birlikte yapalım mı?" daveti.
- [ ] **F2-08** Bilgi boşluğu (A15):
  - `pair` fonksiyonu, `pair_sessions`/`pair_roles`, Realtime özel kanal
  - bas-konuş, cevap anahtarı, kişisel geri bildirim
  - 10 görev (A1–A2)
- [ ] **F2-09** Ortak haftalık hedef, tebrik gönder, `partner_week_summary` + pgTAP (I-18).
- [ ] **F2-10** Android hızlı ayar kutucuğu + ana ekran widget'ı.
- [ ] **F2-11** Haftalık özet ekranı.

**Kabul:**
- ASR seçimi veriyle yapıldı ve belgelendi; hata koruma ≥ %90.
- İkili görev iki telefonda çalışıyor.
- I-18 testleri yeşil.

---

## Faz 3 — Tam öğrenme motoru ve Windows (v0.3)
Dal: `faz-3`

- [ ] **F3-01** Planlayıcı tam (`05`):
  - Kol hedefleri ve açık hesabı, seçenek puanlama, davetler
  - Uzun ara davranışı, zorluk ayarı
  - `05` §8'deki tüm testler
- [ ] **F3-02** Öğrenci modeli tam (`04`):
  - Can-do kanıtı
  - Hata profili (EWMA, durumlar), haftalık odak
  - Seviye tahmini + güven, dış kalibrasyon girişi
- [ ] **F3-03** Karşıtlık (A08), yapılandırılmış girdi (A09), kelime taşları (A10) + iskele matrisi (`02` §3).
- [ ] **F3-04** Hata odağı (A22).
- [ ] **F3-05** Aylık test tam: çift işaretleme + uyum kontrolü + tüm CAF ölçümleri (`06` §3) + rapor ekranı.
- [ ] **F3-06** İlerleme tam (`09` §5.11).
- [ ] **F3-07** Senkron sağlamlaştırma: çakışma kuralları, çok cihaz testi, tam yeniden oynatma aracı, `attempt_amendments`.
- [ ] **F3-08** Saklama ve yedek:
  - `ops/retention_cleanup`, `ops/backup_export`, pg_cron işleri
  - Haftalık döküm iş akışı (👤 DB parolasını GitHub secret olarak ekler)
  - Geri yükleme provası
- [ ] **F3-09** Windows masaüstü: 👤 Geliştirici Modu ve VS C++; kayıt/oynatma/bildirim doğrulaması.
- [ ] **F3-10** İskele ayarları ekranı + "Neden böyle?" açıklamaları.

**Kabul:**
- Planlayıcı ve model testleri tam.
- Windows'ta çekirdek akış çalışıyor.
- Yedekten geri yükleme denendi.

---

## Faz 4 — Girdi: dinleme, okuma, telaffuz, medya (v0.4)
Dal: `faz-4`

- [ ] **F4-01** İçerik `en@2`:
  - 60 okuma metni (A1–B1)
  - 30 diyalog
  - Minimal çift bankası (15 × 20 × 4 ses)
  - Dikte cümleleri
- [ ] **F4-02** Seviyeli okuma (A16):
  - Okuyucu, dokun-anlamını-gör
  - `comprehension_check`, "3 cümleyle anlat"
  - Arama → kart önerisi
  - I-06 testleri
- [ ] **F4-03** Seviyeli dinleme (A17).
- [ ] **F4-04** Ses ayırt etme / HVPT (A06) + karşıtlık ilerlemesi.
- [ ] **F4-05** Medya günlüğü + altyazı içe aktarma, kapsama, bölüm hazırlığı, replik madenciliği (A18).
- [ ] **F4-06** Planlayıcıya girdi seçenekleri; medya dakikalarının kola 0,5 ağırlıkla sayılması.

**Kabul:** Okuma/dinleme önerileri kapsama kuralına uyuyor; altyazı akışı uçtan uca çalışıyor.

---

## Faz 5 — B1 ölçeği ve yapay zekâ etkileşimi (v0.5)
Dal: `faz-5`

- [ ] **F5-01** İçerik hattının üretimleştirilmesi: yeniden çalıştırılabilirlik, LLM önbelleği, maliyet raporu, ret oranı uyarıları.
- [ ] **F5-02** `en@3` + `tr-en@2` (B1):
  - +800 kelime anlamı, +800 cümle
  - 35 gramer noktası, karşıtlık setleri
  - 30 görev, rol senaryoları, yazma görevleri
- [ ] **F5-03** Rol oyunu (A13): `roleplay_turn`, `roleplay_debrief`, "nasıl derim?", eval seti ve eşikleri.
- [ ] **F5-04** Yazma (A20) + `writing_feedback` + satır içi düzeltme + aylık yazma örneği.
- [ ] **F5-05** Öğrenme bilimi notu (A25).
- [ ] **F5-06** Deney altyapısı (`16`): atama, onay, analiz araçları; E1 ve E2'nin başlatılması (önce `docs/experiments/` dosyaları).

**Kabul:** B1 içeriği kullanımda; rol oyunu eval eşiklerini geçiyor; E1/E2 çalışıyor.

---

## Faz 6 — B2, aracılık, web, kişisel FSRS (v0.6)
Dal: `faz-6`

- [ ] **F6-01** `en@4` (B2) + eşdizimler + aracılık metinleri.
- [ ] **F6-02** Aracılık (A21) + `mediation_check`.
- [ ] **F6-03** Kişisel FSRS: dışa aktarma → `tools/fsrs/optimize.py` → parametre yükleme; E5.
- [ ] **F6-04** E3 ve E4 deneyleri.
- [ ] **F6-05** Web:
  - drift wasm + worker; COOP/COEP başlıkları
  - 👤 Vercel projesi; yayın
  - Web'de kayıt/oynatma doğrulaması
- [ ] **F6-06** Dinleme mini testi + kelime yeniden testi otomasyonu (`06` §4).

**Kabul:** Web sürümü çalışıyor; kişisel parametreler etkin; B2 içeriği yayında.

---

## Faz 7 — C1–C2, kendi kendini yönetme, v1.0
Dal: `faz-7`

- [ ] **F7-01** `en@5`:
  - Otantik içerik iş akışları (makale/podcast bağlantısı + kişisel içe aktarma)
  - Deyim ve eşdizim setleri
  - Türe özgü yazma
- [ ] **F7-02** Kişisel korpus: içe aktarılan metinlerden sıklık çıkarımı ve bilinmeyen öğe çıkarımı.
- [ ] **F7-03** "Kendi planım" modu (C seviyeleri): planlayıcı koçluk yapar, kullanıcı hedef ve odak seçer.
- [ ] **F7-04** Dilden bağımsızlık kanıtı: `de@0` + `tr-de@0`, uçtan uca test (`11` §7).
- [ ] **F7-05** E6 deneyi; tüm deney raporları.
- [ ] **F7-06** Cilalama:
  - Erişilebilirlik denetimi
  - Performans ölçümü (`12` §11)
  - Dokümanların güncellenmesi, v1.0 sürüm notu

**Kabul (v1.0):** Tüm faz kabul kriterleri sağlandı; değişmez kural testleri yeşil; dokümanlar kodla tutarlı.

---

## İlerleme günlüğü

| Tarih | Faz | Görev | Not |
|---|---|---|---|
| 2026-09-26 | — | Plan | Tüm plan dokümanları, ADR'ler, CLAUDE.md ve başlangıç promptları yazıldı. |
| 2026-09-26 | 0 | F0-01 | Depo `main` üzerinde plan commit'iyle başlatıldı, iş `faz-0` dalında. `.gitignore` (gizli dosyalar, ses verisi, içerik çıktıları, üretilmiş `*.g.dart`/`*.freezed.dart`), `.gitattributes` (LF), `.editorconfig`. Sıra değişikliği: araç kontrolü (F0-02) eksik araçları erken kurmak için önce yapıldı. |
| 2026-09-26 | 0 | F0-03 | `dilbaz_engine`: `SrsScheduler` FSRS adaptörü (önekli içe aktarma, UTC zorunlu, `CardMemory` JSON = `card_state_after`), müfredat/sözlük tipleri, `zz` sentetik paket üreteci, I-15 mimari testleri (içe aktarma sınırı, fsrs öneki, dize sabiti taraması), kapsam aracı. 40 test, `lib` kapsamı %100. Not: Dart 3.13 + very_good_analysis 11 yeni yapıcı sözdizimini (`new(...)`, `factory ({...})`) zorunlu kılıyor; freezed 4.0.2 ile uyumlu. build_runner 2.16'da `-d` kaldırılmış, CLAUDE.md komutları güncellendi. |
| 2026-09-26 | 0 | F0-04 | `app` (dilbaz_app): `12` §4 bağımlılıkları, `l10n.yaml` + `app_tr.arb` (üretilen `lib/l10n/gen` git dışı), Material 3 tema (mavi-yeşil, hata rolü yumuşak turuncu, `FeedbackColors`), go_router 4 sekme + her sekmede "Söyleyemedim" butonu, boş ekranlar. Testler: yasak kelime taraması (I-12), gezinme, tema renk kuralları (14 test). Debug APK tüm eklentilerle derleniyor. Sapma: AGP 9.4.1 + Gradle 9.6.0 + `compileSdk 37` (`permission_handler_android` 14.1), `just_audio_media_kit` F3-09'a ertelendi (`12` §4). |
| 2026-09-26 | 0 | F0-05 | drift şema v1: 13 senkron kullanıcı tablosu (sunucu aynası + `pending_push`), `outbox`, `sync_state`, 7 içerik tablosu. `driftDatabase` sağlayıcısı, ISO metin UTC zamanlar, JSON dönüştürücüler. Testler: tablo kümesi, senkron sütunları, UTC gidiş-dönüş, benzersizlik, JSON, outbox sırası, v1 anlık görüntü doğrulaması (26 uygulama testi). Kararlar `13` §8'de: yerelde FK/CHECK yok, outbox yalnızca satırı adlandırır. Düzeltmeler: `recordings.audio_path` saklama sonrası null olabildiği için nullable yapıldı. Üretilmiş kod artık analizden hariç tutulmuyor, derleme hataları görünür. |
| 2026-09-26 | 0 | F0-07 | Edge Functions: `_shared/` (`llm_config.ts`: model, rota effort/max_tokens, refusal fallback, fiyatlar; `speech_config.ts`; `auth.ts`: `@supabase/server` JWKS doğrulaması; `budget.ts`: maliyet + günlük tavan; `log.ts`: kapalı alan kümeli JSON log; `http.ts`), `tutor` yol tabanlı yönlendirici + `health`. 23 deno testi (model adı yalnızca `llm_config.ts`'te, log'a metin sızmaz). Sıra değişikliği: F0-06 Docker'a (WSL yeniden başlatması) bağlı olduğu için F0-07 önce yapıldı. `config.toml`'da `verify_jwt = false` F0-06'da eklenecek. `07` §3 tablosuna eksik `max_tokens` değerleri eklendi. |
| 2026-09-26 | 0 | F0-08 | `content/tools` (uv, `uv_build`): typer CLI `dilbaz-content` (`version`, `check-manifest`), pydantic manifest şeması (`11` §3; kaynak lisansı/atıfı zorunlu, I-16). pytest (14), ruff lint+format, mypy temiz. |
| 2026-09-26 | 0 | F0-02 | Araçlar doğrulandı: Flutter 3.47.5 / Dart 3.13.4 (Android toolchain ✓; Visual Studio Faz 3), Docker 29.8.0 (WSL 2), Supabase CLI 2.118.0 (kök `package.json`'da sabit), Deno 2.9.7, uv 0.12.19, Node 24.19, Python 3.14.7, JDK 21. Kullanıcı: Geliştirici Modu, `wsl --install`, yeniden başlatma. Ajan: winget ile Deno/uv/gitleaks/Docker Desktop/Android Studio, Android SDK (platform 36+37, build-tools 36, NDK 28.2, emulator; SDK lisansları kurulumla kabul edildi). `19-setup` §2 gerçek adımlarla güncellendi. |
| 2026-09-26 | 0 | F0-06 | Yerel Supabase (CLI 2.118, Postgres 17): `config.toml` e-posta OTP (6 hane, onay açık, iki şablonda `{{ .Token }}`), kayıt izin listesi = before-user-created hook + `private.signup_allowlist` (Data API'ye kapalı; `app_config` yerine, e-postalar gizli kalsın diye; `14` §2). İlk migrasyon: `sync_seq` + `server_seq` tetikleyicisi, `profiles`, `courses`, `teams`, `team_members`, RLS (varsayılan-red, anon yetkisiz, üyelik `private.is_team_member`, paylaşım anahtarlarına sütun düzeyi UPDATE). pgTAP 40/40. Uçtan uca curl: kod e-postası, doğrulama, izinsiz e-posta 403, oturumla `tutor/health` 200. Veri modeli düzeltmeleri: `interests` ve `created_at` alanları not null (yerel aynayla uyum). |
| 2026-09-26 | 0 | F0-09 (kısmi) | `.github/workflows/ci.yml`: gizli anahtar taraması (gitleaks, tüm geçmiş), motor, uygulama, debug APK (artifact), pgTAP (`supabase db start` + `test db`), Deno, içerik araçları. Sürümler sabit (Flutter 3.47.5, Deno 2.9.7, Supabase CLI `package.json`'dan). Dependabot (Actions), yerel pre-commit gitleaks kancası (`.githooks`, `core.hooksPath`). Sapma: içerik araçları testi her koşuda çalışır (hızlı). **Açık:** ilk yeşil koşu GitHub deposu gerektiriyor (👤, `19` §1 #1). |
| 2026-09-26 | 0 | F0-11 (kısmi) | Sıra değişikliği: F0-10 bir 👤 adımı olduğu için F0-11'in kod kısmı önce yapıldı. E-posta koduyla giriş: `AuthRepository` + Supabase uygulaması (GoTrue hata eşlemesi yerel sunucuda ölçülen yanıtlarla), `SignInController` (freezed durumlar), `SignInScreen`, oturum durumuna göre go_router yönlendirmesi, Ayarlar'da çıkış, `AppEnv` + `Supabase.initialize` (publishable key). 52 uygulama testi. Web + yerel Supabase ile uçtan uca denendi: izinsiz e-posta notu, Mailpit'ten kod, giriş → Bugün, çıkış → giriş sayfası. **Açık:** üretim projesi ve `db push` (👤 F0-10), telefonda debug APK ile deneme. |
| 2026-09-26 | 0 | F0-06 (ek) | Açık Data API yetkileri: Supabase varsayılanı `authenticated`'a TRUNCATE/DELETE dahil her şeyi veriyordu. Yeni migrasyon varsayılan yetkileri kaldırır, tablo başına yalnızca gereken yetkileri verir. pgTAP 52/52 (+ yetki testleri, yeni tablo varsayılan kapalı). GitHub deposu `BeratARPA/dilbaz` açıldı; `main` ve `faz-0` gönderildi. |
| 2026-09-26 | 0 | F0-10 / F0-11 (üretim) | Kullanıcı: Supabase projesi `dilbaz` (eu-central-1), `supabase login`, `gh auth login`. Ajan: `app/env/prod.json` (URL + publishable key, git dışı), `supabase link` (parolasız, geçici giriş rolü), onayla `db push` (3 migrasyon). Üretimde "expose new tables" kapalı olduğu için `service_role` yetkisi de verilmiyordu; ortamları eşitleyen migrasyon eklendi (pgTAP 53/53). Üretim salt okunur SQL ile doğrulandı: RLS her tabloda açık, `anon` yetkisiz, `authenticated` yalnızca gereken yetkiler, `service_role` tam yetki. `test db --linked` pgtap'i erişilemeyen bir şemaya kurduğu için doğrulama sorguyla yapıldı. CI: `setup-uv` kayan `v10` etiketi yayınlamıyor, tam sürüme sabitlendi. |
| 2026-09-26 | 0 | F0-10 (kapsam) | **Sıfır bütçe** (kullanıcı): Anthropic ve Azure adımları askıya alındı, Faz 1 öncesi ADR-0009 ile karar verilecek (`18` §0). Üretim girişi için Brevo SMTP eklendi: Supabase'in yerleşik e-postası yalnızca ekip üyelerine gönderiyor, şablonları ücretsiz planda kilitli (kod yerine bağlantı gidiyor), saatte 2 e-posta. |
| 2026-09-26 | 0 | F0-09 | İlk tam yeşil CI koşusu (7/7 iş; `faz-0`, 322a967). Süreler: APK ~11,5 dk, uygulama ~3 dk, pgTAP ~3 dk, motor ~2 dk, diğerleri < 1 dk. Ücretsiz dakikaları korumak için yalnızca doküman değişikliklerinde CI atlanır. |
| 2026-09-26 | 0 | F0-10 | Supabase projesi ve bağlantı, `env/prod.json`, üretim auth yapılandırması (`config push`: 6 haneli kod şablonları, izin listesi hook'u, MFA kapalı), Brevo SMTP (kullanıcı), izin listesi: tek adres. Ücretli anahtarlar (Anthropic, Azure) sıfır bütçe ve kart olmaması nedeniyle F1-00'a ertelendi; Deepgram da F1-00 kararıyla birlikte. |
| 2026-09-26 | 0 | F0-11 | Debug APK (üretim yapılandırmasıyla) Samsung Galaxy A55'e (Android 16) kuruldu. Kullanıcı e-posta koduyla giriş yaptı, boş Bugün ekranı açıldı. |
| 2026-09-26 | 0 | **Faz 0 raporu** | **Kabul:** CI yeşil (7/7 iş) ✓ · Android'de giriş ✓ · yerel pgTAP 53/53 ✓ · gizli anahtar yalnızca sağlayıcı panellerinde; depo geçmişi temiz (gitleaks) ✓. **Testler:** motor 40 (lib %100), uygulama 52, Deno 23, pytest 14, pgTAP 53. **Maliyet:** $0 (LLM/ses kullanımı yok). **Değişmez kurallar:** I-08 (FSRS yalnızca adaptörde, test), I-12 (yasak kelime taraması), I-15 (içe aktarma sınırı, dize taraması, `zz`), I-18 (partner verisine erişim yok, pgTAP). **Bilinen sorunlar:** (1) sıfır bütçe → F1-00 kararı; (2) sohbette paylaşılan DB parolası ve Brevo anahtarları değiştirilmeli (👤); (3) `home_widget`/`share_handler_android` Kotlin Gradle eklentisi uyarısı; (4) `supabase test db --linked` barındırılan projede pgtap'i kullanamıyor, üretim SQL ile doğrulandı; (5) ücretsiz Supabase projesi 1 hafta hareketsizlikte duraklar; (6) Brevo gönderen adresini `brevosend.com` olarak değiştiriyor, e-posta Gereksiz klasörüne düşebilir; (7) Windows derlemesi için VS C++ (Faz 3). **Kullanım kapısı:** Faz 0'da öğrenme özelliği yok; kapı Faz 1 sonunda (1–2 hafta günlük kullanım). |
| 2026-09-26 | 1 | F1-00 (taslak) | `faz-0` → `main` birleştirildi (`--no-ff`), `faz-1` dalı açıldı. ADR-0009 taslağı yazıldı (`adr/0009-zero-budget.md`): bileşen bazında seçenekler, 4 karar noktası (K1 LLM, K2 İngilizce ASR, K3 paket sesleri, K4 içerik) ve öneriler, Faz 1 görev ve kabul etkileri. Kullanıcı kararı bekleniyor; Faz 1 görevleri karardan sonra başlar. |
| 2026-09-26 | 1 | F1-00 | **ADR-0009 kabul edildi.** Kullanıcı kararı: her bileşende ücretsiz olan en iyisi; Gemini'nin veriyi ürün geliştirmede kullanması sorun değil. Kotalar doğrulandı: Gemini Flash ~20, Flash-Lite ~500 istek/gün; Groq `gpt-oss-120b` 1.000 istek ve 200K token/gün. Rota planı: kart kontrolü Flash-Lite → Groq → deterministik; öneri ve konuşma işaretleme Flash. Partner için kullanıcı başına veri onayı (F1-12). Ses: Deepgram kredisi, Türkçe ve dinamik TTS cihaz üstü, paket sesleri Kokoro; telaffuz kararı Faz 2 başında (F2-05 Azure'a bağlıydı). İçerik Claude Code oturumlarında. Güncellenen dokümanlar: CLAUDE.md, `00`, `03` (§0.3, §0.5), `07`, `08`, `10`, `11`, `12`, `13` (`llm_usage.provider`), `14`, `15`, `17`, `18`, `19`; ADR-0005/0006/0008 durum notları. `llm_config.ts`/`speech_config.ts` F1-14/F1-15'te yeniden yazılacak. |
| 2026-09-26 | 1 | F1-01 | S0 `ingest`: `content/sources.yaml` kayıt defteri (8 kaynak, lisans ve atıf). 7 sabit dosya sha256 ile sabitlendi. Tatoeba ve Wiktextract haftalık döküm olarak tarih klasörüne iniyor. Her klasörde `SNAPSHOT.json` var. S1 `lexicon`: `work/lexicon.en.jsonl`, 8.679 girdi, ~30 sn. Kurallar `10` §4.1: çekim başlıklarının lemmaya katılması, Wiktionary biçimleri, ABD IPA'sı CMUdict'ten. pytest 91, ruff/mypy temiz. Sapmalar: CEFR-J v1.6 yalnızca istekle veriliyor, aynı koşullu v1.5 kullanıldı. NGSL lemmatize listeleri belirteç parçaları içerdiği için kullanılmadı. NGSL-Spoken'da bozuk "true" satırı var. Çok kelimeli girdilerin sırası yok. |
| 2026-09-27 | 1 | F1-02 (taslak) | S2 `select`: kelime anlamları kural + küratörlükle seçiliyor. Sıra: gündelik `include` listesi, NGSL-Spoken, diğerleri; haber ağırlıklı wordfreq sırası konuşma hedefine uymuyordu. 546 lemma ve 600 anlam (A0 167, A1 299, A2 134); açıklamaların hepsi kendi sözlerimizle, çünkü Wiktionary'nin ilk anlamı sık sık yanlış. 120 kalıplık sohbet çantası (17 işlev) ve 40 gramer noktası (A0 8, A1 16, A2 16). Kaynaklar `content/curation/en/`, çıktılar `content/packs/en/items/`. pytest 109. 👤 Sohbet çantasının gözden geçirilmesi bekleniyor. |
| 2026-09-27 | 1 | F1-03 (taslak) | S3 `carriers` + S4 `sentences`: 600 anlamın hepsine Tatoeba'dan 3 aday bulundu; 344 otomatik seçim elle değiştirildi (320 başka Tatoeba cümlesi, 24 kendi cümle). 587 cümle (A0 44, A1 408, A2 135), engelleyici sorun yok; anlamlar `carriers` alanıyla cümlelerine bağlı. Gramer seviyeleri CEFR-J/Core Inventory/EGP ile karşılaştırıldı: nesne zamirleri, and/but/because, sıklık zarfları ve olumlu Past Simple A1'e alındı (`02` §5). Etiketleyici paket dışı yapıları (edilgen, used to, yan cümle…) tanıyor; aynı lemmanın iki anlamı (right, too, free, letter) yalnızca küratörlükle seçiliyor. pytest 186. Sırada: ayrı oturumda doğrulama geçişi, QA raporu, 👤 20 örneklik inceleme. |
| 2026-09-27 | 1 | F1-02 | 👤 Sohbet çantası onaylandı: 120 kalıp, değişiklik yok. Gramer noktaları CEFR-J Grammar Profile (Core Inventory ve EGP sütunlarıyla) karşılaştırılarak yeniden seviyelendi: A0 8, A1 22, A2 10 (`02` §5). `check` isminin açıklaması A1'deki gündelik kullanımına (restoran hesabı) çevrildi. Kelime anlamları S4'ten sonra taşıyıcılarını (`carriers`) taşıyor. |
| 2026-09-27 | 1 | F1-01 (düzeltme) | S1 İngiltere IPA'sı: Wiktextract ses notları alt kümede tutuluyor (`SLIM_VERSION` 5). Niteleyici etiketli ya da notlu söyleyişler (spelling pronunciation, in fast speech, weak form…) son çare; ses değişimi notları olağan biçim sayılıyor. Sözlükte 31 İngiltere değeri değişti (işlev sözcüklerinde güçlü biçim, 9 yeni değer), 600 anlamda 2 (breakfast, there). "breakfast"ın yazılışa göre söylenişi dökümde işaretsiz olduğundan S2 küratörlüğüne `ipa_uk`/`ipa_us` alanları eklendi. Cümleler değişmedi, S4 sorunsuz. pytest 189. |
