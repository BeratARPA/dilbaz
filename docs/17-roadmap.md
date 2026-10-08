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
- [x] **F1-04** S5 tr-en:
  - Karşılıklar, açıklamalar, karşıtlık notları
  - Geniş varyant listeleri ve H3 kural notları (LLM'siz değerlendirmenin temeli, ADR-0009 §2)
  - ~30 etiketlik hata kataloğu (`10` §6)
- [x] **F1-05** Paketin tamamlanması:
  - S6 ses: Kokoro, çevrimdışı (≥ 2 ses + yavaş); 👤 kısa dinleme karşılaştırması (Kokoro / Gemini Flash TTS)
  - S8 X_Lex bankası
  - S9 derleme: `en@1.sqlite`, `tr-en@1.sqlite`
  - S10 rapor
  - 👤 onayla `upload`

### Motor
- [x] **F1-06** FSRS adaptörü + otomatik puan (`03` §0.3) + `card_state_after`.
- [x] **F1-07** `LanguageServices` (normalize/tokenize/lemma; `normalization.yaml`'ın `tests` örnekleri dahil) + deterministik değerlendirme (`03` §0.5: eşleşme, hizalama, şablonlu merdiven) + varyantlar ve alternatifler (hedefsiz doğru cevap → yeniden sorma, `03` §0.2–0.3). Sentetik dil testleri.
- [x] **F1-08** Öğrenci modeli v1:
  - L1 kart hafızası; L2 düzeyleri (new/learning/recallable/durable)
  - X_Lex puanlama, bant olasılıkları, kişisel kapsama (`06` §2)
- [x] **F1-09** Planlayıcı v1:
  - Tekrar bloğu, yeni öğe sınırı, minimum gün, bütçe
  - Basit seçenekler
  - `05` §8 testleri 1, 2, 6, 7, 9
- [x] **F1-10** Müfredat sıralaması (`02` §4.3) + taşıyıcı cümle seçimi (i+1).

### Uygulama ve sunucu
- [x] **F1-11** Paket indirme, doğrulama, atomik içe aktarma (`11` §5) + içerik DAO'ları.
- [x] **F1-12** Karşılama akışı (`09` §5.1): ekip oluşturma/katılma, ses onayı ve yapay zekâ veri onayı (ADR-0009, kullanıcı başına) dahil.
- [x] **F1-13** Seviye testi (A24: X_Lex + gramer + dikte). Başlangıç kaydı kayıt altyapısına (F1-14) ve sabit görevlere bağlı olduğu için F1-19'a taşındı.
- [ ] **F1-14** Ses altyapısı:
  - Kayıt ve kodlayıcı seçimi (`08` §4)
  - `speech/transcribe` fonksiyonu: Deepgram adaptörü (İngilizce). Türkçe cihaz üstü tanıma (`speech_to_text`) onu kullanan F1-17'ye, Türkçe sunucu yedeği Groq/Gemini adaptörleriyle F1-15'e taşındı.
  - 👤 Deepgram anahtarı (`19` §1)
  - `speech_usage` kaydı
- [ ] **F1-15** `tutor/answer_check` (`07` §4.1):
  - Sağlayıcı yönlendiricisi + Gemini ve Groq adaptörleri (SDK context7 ile doğrulanır; ADR-0009)
  - zod şeması, sabit sistem promptu, merdiven sızıntı kontrolü, kota ve adil paylaşım, `llm_usage`
  - deno testleri
  - Eval seti v1 (≥ 200 vaka), ücretsiz kotalarda eval; sonuçlara göre rota sırası (`07` §2)
  - 👤 Gemini ve Groq anahtarları (`19` §1)
- [x] **F1-16** Kart oturumu (A00, A01, A02): merdiven, "yanlış duyuldu", sessiz mod, otomatik puan, deneme + outbox. Cevap listeleri kart hedefine göre ayrılır (`07` §4.1); dilbilgisi kartları için paket cevap başına gramer kodu taşır (S9).
- [ ] **F1-17** Söyleyemediklerim (A19): yakalama butonu, yazılı ve sesli (Türkçe) yakalama, `tutor/gap_suggest` (Gemini Flash; kota dolunca bekleyen öneri), karta ekleme, Android paylaş menüsü hedefi.
- [ ] **F1-18** Bugün ekranı v1 + "Bugünlük yeter" + "bugün ne kadar vaktin var?".
- [ ] **F1-19** Konuşma görevi v1 (A11) + `tutor/speaking_annotate` (Gemini Flash; kota yoksa sonradan) + akıcılık ölçümleri (motor) + aylık test v1 (A23: tek işaretleme) + başlangıç kaydı (ANC-1, `06` §2 Bölüm 4; F1-13'ten).
- [ ] **F1-20** İlerleme v1: kanıt sayıları, önce/sonra ses dinleme, basit eğilimler.
- [ ] **F1-21** Senkron v1: outbox, `sync_push`/`sync_pull` RPC'leri, Faz 1 tabloları, pgTAP RLS testleri. F1-16'dan: bekleyen LLM kontrolleri (`llm_resolved`), kart itirazı (`user_dispute`), "Bu içerikte hata var" (`content_reports`).
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
| 2026-09-27 | 1 | F1-03 (doğrulama) | Bağımsız doğrulama (`10` §5.2): üretim gerekçelerini görmeyen ayrı ajan oturumları 587 cümleyi puanladı, 523'ü kabul edildi. Reddedilen 64'ün yerine gelenler 2. ve 3. turda doğrulandı (69'da 65 kabul). Paketteki 588 cümlenin hepsi doğrulanmış (`curation/en/sentences.validation.jsonl`); S4, kabul kaydı olmayan cümleyi raporluyor (I-16). `wish` ve `need` açıklamaları düzeltildi. 65 Tatoeba çevirisinin düzeltmesi S5'e kaldı. QA raporu: `content/reports/2026-09-27-en1-sentences-qa.md`. pytest 190. 👤 20 örneklik inceleme bekleniyor. |
| 2026-09-29 | 1 | F1-04 | S5 `pair`: 600 anlam, 120 kalıp, 40 gramer noktası ve 588 cümle istemi Türkçeleştirildi (istemler: 364 Tatoeba, 166 küratörlük, 58 doğrulama düzeltmesi). Varyantlar hedef kelimeyi içeriyor (cümlelerde 1.206, kalıplarda 153). Hedefsiz doğru cevaplar `alternatives` listesinde (274): 👤 kararıyla hata sayılmaz, hedef için yeniden sorulur (`01` I-17, `03` §0.2). 40 H3 notu, 34 karşıtlık notu, 45 hata etiketi var. Normalizasyon veri olarak tutuluyor (`packs/en/normalization.yaml`: kısaltma, yazım, sayı, para birimi, "he's got"). Kontroller: karşılık eksikliği, hedefsiz varyant, hedefli alternatif, aynı istemde ortak cevap, H3 sızıntısı ("go → went" dahil). Beş ayrı ajan oturumunun bağımsız incelemesi uygulandı. Yan düzeltmeler: ride taşıyıcısı "Can you ride a bike?" oldu (4. tur doğrulama); etiketleyici olumsuz emri ve zaman edatını doğru tanıyor; eşleştirici "Mondays"ı buluyor. QA raporu: `content/reports/2026-09-29-tr-en1-pair-qa.md`. pytest 238. |
| 2026-09-29 | 1 | F1-05 (S8) | X_Lex bankası (`placement`): 3 sürümün her birinde 5 sıklık bandından 20'şer gerçek kelime ve 20 uydurma kelime var (360 madde). Türkçe konuşanın İngilizce bilmeden tanıdığı 165 alıntı ve yanıltıcı benzerlik dışlandı. Dışlama yalnızca o kelimeyi değiştiriyor. Sürümlere dönüşümlü dağıtımla eşit zorluk sağlanıyor. Uydurma kelimeler wordfreq (İngilizce ve Türkçe), CMUdict, Wiktionary başlıkları, 1 harf uzaklık, sık kelimeyle başlama/bitme ve kaba parça kontrollerinden geçiyor. pytest 258. Sırada: S9 derleme, S6 ses (Kokoro indirme onayı). |
| 2026-09-30 | 1 | F1-06 | Motor: otomatik puan `scoring/` altında. `Verdict` + `Evaluation` → `AnswerEffect` (`03` §0.2 tablosu) → `CardReview` (3 deneme, her yanlışta bir üst ipucu, istekle ipucu/H4, hedefsiz doğru cevapta bir kez yeniden sorma, anlaşılmayan ses sayılmaz) → `ReviewOutcome.rating`. Easy için `LatencyProfile`: son 200 denemenin 25. yüzdeliği; 20 denemeden azsa Easy yok. FSRS tarafı: `CardMemory`'ye `reps`/`lapses` eklendi, JSON'u artık `cards` satırının FSRS sütunlarının tamamı. `SrsScheduler.replay` fuzz kapalı yeniden oynatma yapıyor; fuzz yalnızca `due`'yu değiştirdiği için canlı kartla S/D/durum/sayaçlar aynı çıkıyor (test). `SrsConfig.forCourse` mod grubunun ağırlıklarını okuyor, `CardMode`/`ModeGroup` eklendi. Belirsiz kalan bir durum için karar verildi, `03` §0.3'e not edildi: yeniden sorulduktan sonra "göster" denirse Hard, arada yanlış varsa Again. Seviyeye göre ipucu profili (I-09, `02` §3) F1-16'da `CardReview`'a eklenecek. 96 test, `lib` kapsamı %100. |
| 2026-09-30 | 1 | F1-05 (S6, S9, S10) | Paket sesleri Kokoro ile üretildi: 3.637 klip, 3.629 dosya (aynı metin ve ses tek dosyayı paylaşıyor), 78,4 dk, 23,5 MB. Ses başına: v1 af_heart 1.169, v2 am_michael 1.160, v3 bf_emma 654, v4 bm_george 654. A0–A1 için 0,8× yavaş klip sayısı 1.021. Üretim tek işçiyle ~80 dk sürdü. S9 derleme sorunsuz: `en@1.sqlite` 3,6 MB (10.180 öğe, 3.252 bağ, 19.394 biçim), `tr-en@1.sqlite` 0,5 MB (2.068 çift girdisi, 40 karşıtlık bağı). S10 raporunda sayılar artık Türkçe biçimde. Yükleme yerel Supabase'e karşı uçtan uca denendi: ilk çalıştırma 26 sn sürdü, ikincisi klipleri atladı, `--publish` durumu değiştirdi. Sırada 👤 adımları var: `db push` onayı ve üretime yükleme (`19` §1). |
| 2026-09-30 | 1 | F1-05 | 👤 Onayla `db push`: `packs_registry` migrasyonu üretimde. Salt okunur SQL ile doğrulandı: RLS açık, `anon` yetkisiz, `authenticated` yalnızca SELECT, iki kova özel. Yükleme: kullanıcı "CLI oturumuyla sen yap" dedi. Gizli anahtar `supabase projects api-keys --reveal` ile yalnızca komutun ortamına verildi, hiçbir çıktıya yazılmadı. `en@1` ve `tr-en@1` yayımlandı, sağlama toplamları derlemeyle aynı. `pack-audio` kovasında 3.629 dosya (23 MB, v1–v4), `packs` kovasında 4 dosya var. Bu yol `19` §1'e eklendi. |
| 2026-09-30 | 1 | F1-07 | Motor: `language/` altında `Normalizer` (`normalization.yaml`'ın 8 adımı, Python S5 uygulamasıyla aynı sırada; düzenli ifade yok), `PackLanguage` (`normalize`, `tokenize`, `lemmasOf`) ve `WordAlignment` (eksik, fazla, biçim, sıra, başka kelime). Motor `en` paketinin 28 normalizasyon örneğini geçiyor. `scoring/` altında `AnswerChecker`: `match` (adım 2) ve `checkWithoutLlm` (adım 4), şablonlu `HintLadder`. **Gerçek paketle deneme üç şeyi değiştirdi** (`03` §0.5'e işlendi): (1) Varyant ya da hedefsiz cevap kararı listeye göre değil kartın hedef kelimesine göre veriliyor, çünkü bir cümle birden çok öğe taşıyor. `en@1`'de 3.946 kart–varyant çiftinin 650'si o kartın hedefini içermiyor (ör. `get` kartında "I have homework to do"), 492 kart–alternatif çiftinin 203'ü içeriyor. (2) Küçük fark eşiği uzunluğa bağlı: 1 fark, 6+ kelimede 2 fark. Böylece 3 kelimelik cümlede yalnızca hedefi söylemek küçük hata sayılmıyor. (3) Şablonlu H3 yalnızca kartın kendi gramer noktası için var; kelime ve kalıp kartlarında cümlenin gramer notu hatayla ilgisiz çıkıyordu. Hata etiketi deterministik yoldan eklenmiyor (pakette tespit kuralı yok). Bilinen sınır: normalizasyon isimden sonraki `'s`'i açmadığı için 2 cümlede hedef bulunamıyor ("Now's a bad time.", "… the party's going to start."); bu kartlarda cevabın tamamı hedef sayılıyor. `coverage` F1-08/F1-10'a kaldı. 211 test, `lib` kapsamı %100. |
| 2026-09-30 | 1 | F1-08 | Motor `model/`: `CardRecord` + `ReviewRecord` → `ItemEvidence` (üretim düzeyi `new → learning → recallable → durable`, alıcı `recognized`, I-05 testli). `XlexResult.of`: puan (+50 / −250'nin genel biçimi), bant kabul oranları, yanlış alarm oranı, %25 üstünde "tahmine dayalı". `LemmaKnowledge`: kartla bilinen lemma 1, diğerleri bant olasılığı; kişisel kapsama bunların ortalaması. **Dokümana işlenen dört netleştirme:** (1) Düzey eşikleri son *kanıtlı* tekrardaki stabiliteyle karşılaştırılıyor; kanıtsız Hard'lar (LLM'siz `uncertain`, hedefsiz doğru cevap) zamanlamayı ilerletiyor ama düzey yükseltmiyor (`04` §3, I-04). (2) `durable` için 21 gün, önceki *başarılı* tekrardan değil hemen önceki tekrardan sayılıyor; unutup 10 dakika sonra yeniden öğrenmek aralıklı hatırlama sayılmasın. (3) Tanıtımın hemen ardındaki ilk tekrarda Easy verilmiyor (`03` §0.3): FSRS varsayılanlarıyla Easy kartı 16 günlük stabiliteye atıyor ve öğe hiç aralıklı hatırlanmadan "Hatırlıyor" oluyordu. (4) Bant olasılığı = bant kabul oranı − yanlış alarm oranı (`06` §2); toplamı X_Lex puanını veriyor. `transferred` düzeyi ve CEFR eşlemesi (Milton tablosu dile özgü, paketten gelmeli) sonraki görevlerde. 240 test, `lib` kapsamı %100. |
| 2026-09-30 | 1 | F1-09 | Motor `planner/`: `Planner.plan` → `TodayPlan`. Bütçe ve "Bugünlük yeter" (I-13), minimum gün (≤ 7 dk: yalnızca tekrar), tekrar bloğu (tavan: 10 dk ya da bütçenin %40'ı; öncelik = unutulma × mod ağırlığı + odak bonusu; 0,1'lik öncelik dilimi içinde seed ile karıştırma; karşıtlık çifti birlikte ve arada en az bir kartla), yeni öğe sayısı (I-07: `05` §3 satır 10–13, ayrıca kalan bütçe), basit seçenekler (kol açığına göre puan, en fazla 3, kol başına en fazla 2, tek seçenek sunulmaz; I-14). Yeni öğenin ilk kartı `speak`, sessiz modda `type` (I-05). Özellik testleri 300 rastgele öğrenci durumuyla `05` §8 madde 1, 2, 6, 7, 9'u doğruluyor; plan girdi listelerinin sırasından bağımsız. Platformlar arası aynı plan için karıştırma motorun kendi üretecini (`SeededRandom`, xorshift32) kullanıyor. Netleştirmeler `05` §1 ve §3'e işlendi: dilim R'ye değil önceliğe göre; dolu blokta çiftin diğer yarısı, çifti olmayan son kartın yerine giriyor. Sonraya kalanlar: davetler, etkinlik uygunluğu (§4), geçmişten süre tahmini, §8 madde 3–5, 8, 10. 266 test, `lib` kapsamı %100. |
| 2026-09-30 | 1 | F1-10 | Motor `curriculum/`: `Curriculum.next` (`02` §4.3 puanı; önkoşullar `recallable` olmadan aday değil; karşıtlık çiftleri ve aynı kelimenin iki anlamı aynı gün listede birlikte yer almıyor: `05` §8 madde 10) ve `CarrierPicker.pick` (hedef dışındaki lemmalardan bilinmeyenlerin beklenen sayısına göre sıralama; ≤ 0,5 ise i+1'e uygun). **Gerçek paketle deneme sonuçları:** (1) `contains` bağları lemma + sözcük türü düzeyinde; anlam doğruluğu yalnızca seçilmiş taşıyıcılarda (`carriers`) doğrulanmış. Taşıyıcı adayları bu yüzden seçilmiş cümlelerle sınırlandı (`02` §4.4). (2) Kalıpların sıklık sırası yok; hepsi aynı puanı alıp alfabetik tek blok hâlinde geliyordu. Çözüm paket tarafında: kalıplara sohbet çantasındaki sıralarına göre sıra verilecek (bir sonraki satır). (3) Belgelenen ağırlıklarla A1 öğrenciye A0 öğeleri (have, do, Hello…) tüm A1 ve A2 öğelerinden sonra geliyor ("seviyenin altı: 0,5"). Formüle uyuldu; ağırlıklar kullanıcıyla ve ilk kullanım verisiyle gözden geçirilmeli. 285 test, `lib` kapsamı %100. |
| 2026-09-30 | 1 | F1-10 (paket) | S9 derleme kalıplara sıra veriyor (`chunk_ranks`): her seviyenin kalıpları, sohbet çantasındaki sırayla, o seviyedeki kelime anlamlarının sıklık sıralarına eşit aralıklarla yerleşiyor. `en@1` yeniden derlendi (sha256 `6ef48eec08b00512…`; `tr-en@1` değişmedi). Motorla deneme: A0 öğrenci için sıra artık "Hello, have, do, get, Hi, like, just, go, Good morning, out, say, there, time, Good evening…"; ilk 100 öğede 25 kalıp. Yeniden yükleme bir sonraki satırda. pytest 279. |
| 2026-09-30 | 1 | F1-11 | Uygulama: `SupabasePackRemote` (kayıt defteri + özel `packs` kovası), `PackRepository.sync` (kursun en yeni hedef ve çift paketi; kimlik ve sağlama toplamı aynıysa atlanır), `PackImporter` (dosya yerel veritabanına `ATTACH` edilir; biçim sürümü, manifest kimliği, `min_engine_version` ve normalizasyon örnekleri kontrol edilir; aynı ailenin satırları tek işlemde değiştirilir), `ContentDao`, `ContentController` (yerel öncelikli: cihazda içerik varsa hemen hazır, güncelleme arka planda). Bugün ekranı indirme durumunu, hazır olunca paket özetini gösteriyor; hatalar sakin metin ve "Yeniden dene" ile. Motor: `engineVersion`. Yeni bağımlılıklar: `crypto` 3.0.7 (sha256), `http` 1.6.0 (ağ hatası türü); ikisi de zaten dolaylı bağımlılıktı. **Kitaplık davranışları (kaynak kodundan doğrulandı):** PostgREST GET isteklerini varsayılan olarak 3 kez, artan beklemeyle yeniden deniyor; açılışı geciktirmemek için kayıt defteri sorgusunda kapatıldı. Storage indirmesinde ağ hatası `StorageException`'a sarılmadan `ClientException` olarak geliyor. Python tarafına sözleşme testi eklendi: S9 tabloları = drift `content_*` tabloları. Web'de dosya sistemi olmadığı için aktarım henüz yok (`unsupported`). **Telefonda doğrulandı** (Galaxy A55, üretim yapılandırması): iki paket indirildi ve içe aktarıldı, ekranda "İçerik hazır: 600 kelime, 120 kalıp, 588 cümle". Uygulama testleri 94, motor 285, pytest 280. |
| 2026-09-30 | 1 | F1-10 / F1-11 (üretim) | 👤 Onayla `en@1` yeniden yüklendi (CLI oturumuyla; sesler değişmedi, atlandı). Kayıt defterinde sağlama toplamı `6ef48eec08b00512…`. Sürüm numarası aynı kaldı, çünkü henüz başka kullanıcı yok; yayından sonra içerik değişikliği yeni sürüm numarası ister. Telefonda arka plan güncellemesi doğrulandı: uygulama yeniden açılınca yeni paketi indirip içe aktardı (uygulamanın debug veritabanında `en@1` yeni toplamla, Hello #11, Hi #40; `PRAGMA integrity_check` temiz; 600 anlam, 120 kalıp, 588 cümle, 40 gramer noktası, 8.472 lemma, 360 X_Lex maddesi, 19.394 biçim, 2.068 çift girdisi, 3.292 bağ). |
| 2026-09-30 | 1 | F1-12 | Karşılama akışı (`09` §5.1, 9 adım). **Sunucu:** `create_team` (kod sunucuda üretilir; çağıranın kendi yetkisiyle; yinelenen istek aynı ekibi döndürür) ve `join_team` (SECURITY DEFINER, davet kodu) — `20260930151033_team_functions.sql`, pgTAP 8 dosya / 81 test. **Veri katmanı:** `ProfileRepository` (drift + outbox; profil ve kurs ekip adımı için hemen gönderilir, `restore` başka cihazda yapılmış profili getirir), `TeamRepository`, `PermissionGateway`. **Akış:** yalnızca isim zorunlu; ses kaydı onayı ve yapay zekâ veri onayı kapalı başlar, kullanıcı başına ve zamanıyla `profiles.settings` içinde saklanır; mikrofon izni yalnızca ses onayından sonra istenir, onay ya da izin yoksa sessiz mod; bildirimde "Şimdi değil" sistem penceresini açmaz; ekip adımı o ana kadarki cevapları taslak olarak gönderir (taslak akışı bitirmez). **Açılış kapısı:** `/opening` → `/welcome` → ana kabuk; cihazda bitmiş profil yoksa önce sunucuya bakılır, sunucuya ulaşılamazsa akış başlatılmaz (aynı dile ikinci kurs sunucuda reddedilir; `unique (profile_id, l2)`), "Yeniden dene" gösterilir; `main` açılış ekranını durum bilinene kadar (en fazla 1 sn) tutar. **Plandan sapmalar:** QR yok (kod yetiyor); 9. adım seviye testi yerine kullanıcının yaklaşık seviyesi (test F1-13'te bağlanacak). Android manifestine `RECORD_AUDIO` ve `POST_NOTIFICATIONS` eklendi. **Testler:** controller, kapı, yönlendirme, tüm akış (widget), 360 dp genişlik + 2 kat yazıda her adımın taşmadan sığması ve dokunma hedefleri, sistem geri tuşu; uygulama testleri 168. **Yerel yığınla uçtan uca doğrulandı** (tek seferlik betik; gerçek PostgREST + RLS + RPC, iki test kullanıcısı): taslak ve bitmiş profilin gönderimi, ikinci cihazda `restore`, profil yokken ekip kurmanın reddi, ekip kurma ve yinelenen istek, yanlış ve doğru kodla katılma, partnerin diğer profili okuyamaması (I-18), sunucu yokken `network` hatası. **Telefonda** (Galaxy A55, üretim yapılandırması) dokuz adımın hepsi görüldü; akış bilerek bitirilmedi, çünkü onaylar ve sistem izinleri kullanıcıya ait. **Kitaplık davranışları:** Riverpod 3 widget ağacı dışındaki yeniden kurmaları sıfır süreli `Timer` ile zamanlıyor (widget testinde saat ilerletilmeli); Flutter saat seçicinin elle giriş modu yerel ayara değil yalnızca `alwaysUse24HourFormat`'a bakıyor, bu yüzden 24 saat zorlandı. **Düzeltilen kararsız test:** `content_controller_test` arka plan yenilemesini sabit sayıda tur bekliyordu; yük altında yetmiyordu, artık durumu bekliyor. Üretime `db push` 👤 onayı bekliyor; o zamana kadar üretimde ekip adımı çalışmaz, akışın geri kalanı çalışır. |
| 2026-09-30 | 1 | F1-13 | Seviye testi (A24, `06` §2). **Motor `placement/`:** `Staircase` (A2'den başlar, doğruda bir seviye yukarı, diğer her cevapta bir aşağı; 12–15 madde, son 6 madde iki komşu seviyede kaldıysa biter; seviye kararı en az 2 maddede ≥ 2/3 doğru ulaştı, ≤ 1/3 ulaşmadı), `LevelLadder` (seviye merdiveni: alt uç ulaşılmayan ilk seviyenin altı, üst uç sorulan en yüksek kararsız seviye, en üst ulaşıldıysa açık aralık), `DictationScore` (WER; dilin kelimesi olmayan, 4–7 harfte 1, 8+ harfte 2 düzenleme uzaktaki yazım hata sayılmaz), `VocabLevels` (X_Lex puanı → seviye, paket verisinden), `PlacementOutcome` (başlangıç = kelime ve gramerden zayıf olanı), `LevelEstimate`/`Confidence`/`Skill`; motor testleri 361, satır kapsamı %100. **İçerik:** `placement-tests` (S8): 48 maddelik gramer bankası (A1/A2/B1/B2: 12'şer) ve sürüm başına 5 dikte cümlesi; maddeler cevapsız bağımsız kontrolden geçti (alt ajan, 2 tur; 1. turdan sonra 5 madde düzeltildi), kontrolü olmayan madde pakete girmez; manifestte `placement.vocab_levels`; paket yeniden derlendi (`en@1` sha256 `50ff39df2d2215f5…`, 10.243 öğe; `tr-en@1` değişmedi); pytest 303. gitleaks allowlist'i `en.pgram`/`en.pdict` anahtarları ve içerik testleri için genişletildi (yanlış alarm). **Uygulama:** `PlacementBankRepository`, `DriftAssessmentRepository` (değişmez `assessments` satırı + kursun seviye tahminleri ve `vocab_estimate`, outbox), `PackAudio` (klipler destek klasöründe), `ClipPlayer` (just_audio), `PlacementController`, test ekranları ve Bugün'de davet kartı. Bölümler sırayla; bitmiş bölümler kaydedilir, yarım kalan kaydedilmez; dikte atlanabilir; sonuçta not yok, seviye ya da aralık. Yeni bağımlılık: `path_provider` 2.1.6 (zaten dolaylıydı). Uygulama testleri 213 (2 kat yazı ve 360 dp'de her görünüm dahil). **Plandan sapmalar:** başlangıç kaydı F1-19'a taşındı; `en@1` cümleleri A2'de bittiği için dikte en çok "A2 ve üstü" der; gramer bankası B2'de biter. **Bekleyen:** 👤 `en@1` yeniden yükleme onayı; ardından telefonda deneme. |
| 2026-09-30 | 1 | F1-12 / F1-13 (üretim) | 👤 Onayla `db push`: `20260930151033_team_functions.sql` üretimde (`create_team` çağıranın yetkisiyle, `join_team` SECURITY DEFINER, anon çalıştıramaz; salt okunur SQL ile doğrulandı). 👤 Onayla `en@1` yeniden yüklendi (CLI oturumuyla; sha256 `50ff39df2d2215f5…`; sesler değişmedi, atlandı). Kullanıcı karşılama akışını telefonda kendisi tamamladı (üretimde 1 profil, 1 kurs). Seviye testi telefonda henüz denenmedi: telefon bağlı değildi. |
| 2026-09-30 | 1 | F1-14 (1. kısım) | **Sunucu:** `speech` fonksiyonu, `transcribe` rotası (`08` §5.0): oturum doğrulama, ses türü ve boyut sınırı (2 MB), Deepgram Nova-3 adaptörü (kelimesi kelimesine: `filler_words`, biçimlendirme kapalı, `mip_opt_out`; API context7 ile doğrulandı), sağlayıcı hataları sabit kodlara, her başarılı tanıma `speech_usage`'a (Deepgram kredisinden düşen tutarla). `speech_config.ts` ADR-0009'a göre yeniden yazıldı (Azure yok). Migrasyon `20260930192923_speech_usage.sql` + pgTAP (9 dosya / 89 test); deno testleri 38, `deno lint`/`fmt` temiz. Yerel yığında gerçek oturumla denendi: oturumsuz 401, anahtar yokken 503 `stt_unavailable`. **Uygulama:** `AnswerRecorder` (`record` 7; AAC-LC 16 kHz mono 32 kbps; kart sesi geçici dosyadan okunup silinir), `SpeechRepository`, Ayarlar > Mikrofon denemesi (ses kaydı onayı yoksa kayıt yok; 12 sn'de kendiliğinden durur). Uygulama testleri 234. **Bekleyen:** 👤 Deepgram anahtarı (`19` §1, `supabase secrets set`), 👤 üretime `db push` (speech_usage) ve `speech` fonksiyonunun dağıtımı, telefonda deneme. |
| 2026-09-30 | 1 | F1-14 (üretim) | 👤 Onayla `db push`: `20260930192923_speech_usage.sql` üretimde. Salt okunur SQL ile doğrulandı: RLS açık, tek politika `speech_usage_select_own`, `authenticated` yalnızca SELECT, `anon` yetkisiz, yazma yalnızca servis rolünde. 👤 Onayla `speech` fonksiyonu dağıtıldı. Oturumsuz çağrı fonksiyonun kendi 401'ini (`MISSING_CREDENTIALS`) döndürüyor; yani `verify_jwt = false` ve ortak `deno.json` üretimde de çalışıyor. CLI 2.118, `config.toml`'daki `import_map` satırı için "artık desteklenmiyor, `deno.json` kullanın" uyarısı veriyor. Belgelerin önerisi fonksiyon başına `deno.json`; `tutor` yeniden dağıtılırken (F1-15) buna geçilecek. Anahtar girilene kadar oturumlu çağrı 503 `stt_unavailable` alır (yerel yığında doğrulandı). |
| 2026-09-30 | 1 | F1-15 (1. kısım) | **Sunucu:** `tutor/answer_check` (`07` §4.1). Zincir: Gemini 3.1 Flash-Lite → Groq `gpt-oss-120b` → deterministik yol. Adaptörler REST ile yazıldı, SDK yok (gerekçe `07` §3); API'ler context7 ile doğrulandı. Gemini'de `responseJsonSchema` ve düşünme düzeyi, Groq'ta katı `json_schema` ve `reasoning_effort` kullanılıyor. Zincir veri onayı olmayanı Gemini'ye göndermiyor, adil payı aşanı atlıyor. Günlük 429 ile dakikalık 429'u ayırıyor. Geçersiz cevabı bir kez yeniden istiyor, kesik cevabı iki kat sınırla. Her çağrı `llm_usage`'a yazılıyor; migrasyon `20260930200023_llm_usage.sql` + `llm_usage_counts`. Sözleşme zod ile; etiketler çift paketin kapalı listesi (`_shared/catalogs/tr_en.ts`, paketten üretilir). Sabit istem `answer_check@1` (~4,7 bin token, 10 örnek). Korumalar: gereksiz merdiven yok; alıntıdan konuma çevrilen hata aralıkları; cevabı ele veren ipucu boşaltılır, istemci şablonla doldurur. **Eval:** 285 vakalık altın set. Vakaları `dilbaz-content eval-cases` paketten kuruyor; listeler kart hedefine göre ayrılıyor, dilbilgisi kartında S4 etiketleyicisiyle. Etiketler kör kontrolden geçti: 2 tur, 259/259 ve 36/36; kontrolsüz vaka sete girmiyor. `evals/run.ts` kotada kesilirse kaldığı yerden sürüyor; `07` §8 ölçütlerini yazıyor. **Deterministik yol:** Aynı set motorda CI testi oldu. İlk ölçümde doğru cevapların %19,8'i yanlış sayılıyordu. Tanıma dolguları, tekrarlar, isimden sonraki "'s" ve hedefsiz yeniden ifadeler düzeltilince oran %2,3'e indi (eşik %3), sızıntı %0 (`03` §0.5, ADR-0009 notu). Normalizasyon sözleşmesi değişti: `engineVersion` 2, paketler `min_engine_version: 2`. Beş fazla varyant silindi, paketler yeniden derlendi: `en@1` `f1b7feaf…`, `tr-en@1` `72815b24…`. **Başka değişiklikler:** Fonksiyonların her biri kendi `deno.json`'ıyla dağıtılıyor; `import_map` kaldırıldı, yerel `functions serve` ile denendi. **Plandan sapmalar:** İstemler `.md` değil `.ts` dosyasında. ADR'deki "Flash-Lite 3.5" belgelerde yok. Dilbilgisi kartları için paket cevap başına gramer kodu taşımalı; bu F1-16'ya kaldı. **Testler:** deno 81 (+ evals 9), pgTAP 10 dosya / 100, motor 373 (%100), pytest 331, uygulama 234. **Bekleyen:** 👤 Gemini ve Groq anahtarları (`19` §1, Groq'ta ZDR açık). 👤 Onaylar: üretime `db push` (llm_usage), `tutor` ve `speech` dağıtımı, `en@1` ve `tr-en@1` yüklemesi. Anahtarlardan sonra eval koşusu ve sonuçlara göre zincir sırası. |
| 2026-09-30 | 1 | F1-15 (üretim) | 👤 Onayla `db push`: `20260930200023_llm_usage.sql` üretimde. Salt okunur SQL ile doğrulandı: RLS açık, tek politika `llm_usage_select_own`; `authenticated` yalnızca SELECT; `anon` yetkisiz; `llm_usage_counts`'u yalnızca servis rolü çalıştırabiliyor. 👤 Onayla `tutor` (answer_check) ve `speech` fonksiyon başına `deno.json` ile dağıtıldı; `import_map` uyarısı artık yok. Oturumsuz çağrılar fonksiyonların kendi 401'ini, ön kontrol 204 döndürüyor. Güvenlik danışmanında yeni bulgu yok. Paketler (`en@1`, `tr-en@1`, motor sürümü 2) 👤 kararıyla yeni APK telefona kurulunca yüklenecek: eski uygulama onları geri çevirip eski içerikle sürer, ama her açılışta yeniden indirir. **CI:** F1-11'den beri uygulama ve APK işleri düşüyordu. Neden, motorun üretilmiş kodunun (git dışı) CI'da oluşturulmamasıydı; iki işe motorda `build_runner` adımı eklendi. |
| 2026-10-08 | 1 | F1-16 | **Motor:** `Scaffolds.forLevel` (iskele matrisi `02` §3: açıklama dili, yavaş ses, kendiliğinden açılan ipucu, deneme hakkı; A0'da 2 hak), `CardReview.autoHintLevel`, `AnswerChecker.targetSpan` ve `listed`, `LearnerSnapshot.newToday` (günlük yeni öğe tavanı gün içindeki oturumları da sayar). 382 test, kapsam %100. **Uygulama:** drift şema v2 (yerel `devices`, adım adım geçiş ve doğrulanmış yükseltme testi). `CardRepository`: kanıt projeksiyonu, gecikmeler, tanıtım, gösterim başına tek işlem (zincirli denemeler, puan ve `card_state_after` sonuncusunda, outbox), kişisel varyantlar denemelerden. `CardContentRepository`: taşıyıcı seçimi, cevap anahtarı, sesler, notlar. `TutorRepository`: `tutor/answer_check` istemcisi, 15 sn bekleme, hata kodları. `CardSessionController`: planlayıcı ve müfredatla kuyruk (önce tekrarlar), A00 → A01/A02, deterministik eşleşme → LLM → hizalama, ipucu merdiveni (LLM'in boş bıraktığı ipucu şablondan), "yanlış duyuldu", "Bunu mu demek istedin?", sessiz mod, otomatik FSRS puanı. Ekran: Pratik → Kartlar; basılı tut-konuş, hata yerleri, ipucu ve göster, son ekranda cümle, Dinle ve "Bir kez de sen söyle", özet. 57 ARB metni, yasak kelime testi geçiyor. Uygulama testleri 290 (kart denetleyicisi 24; ekran 7, küçük telefonda 2 kat yazı dahil). Plan/gerçek farkları (`03`, `05`, `13`'te not edildi): kart ilk değerlendirme kaydedilirken oluşuyor; kişisel varyantlar ayrı tabloda değil, denemelerden okunuyor; `spentToday` F1-18'e kadar 0. F1-21'e taşındı: `llm_resolved`, `user_dispute`, `content_reports`. Telefonda denenmedi: LLM anahtarları ve yeni APK bekleniyor. |
