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
- [ ] **F0-02** Araç doğrulama: `flutter doctor -v`, `docker info`, `supabase --version`, `deno --version`, `uv --version`, `node --version`. Eksik varsa 👤 `19-setup.md` §2.
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
- [ ] **F0-05** drift şema v1: kullanıcı tabloları, outbox, sync_state, boş içerik tabloları (`13` §8). drift_flutter kurulumu, migrasyon testi.
- [ ] **F0-06** Supabase yerel:
  - `supabase init`
  - `config.toml`: e-posta OTP açık, kayıt izin listesi
  - İlk migrasyon: `sync_seq`, `profiles`, `courses`, `teams`, `team_members` + RLS
  - pgTAP testleri; `supabase start && supabase test db` geçer
- [ ] **F0-07** Edge Functions iskeleti:
  - `_shared/`: auth, budget, `llm_config.ts`, `speech_config.ts`, yapılandırılmış log
  - `tutor` fonksiyonunda `health` rotası
  - `deno test`
- [ ] **F0-08** İçerik araçları iskeleti: `content/tools` (uv, typer CLI `dilbaz-content --help`, pytest, ruff).
- [ ] **F0-09** CI: `.github/workflows/ci.yml` (`15` §5) + gizli anahtar taraması. İlk koşu yeşil.
- [ ] **F0-10** 👤 Hesaplar ve anahtarlar (`19-setup.md` §1):
  - Supabase projesi (Frankfurt)
  - Anthropic, Deepgram, Azure Speech anahtarları
  - `supabase link` ve `supabase secrets set` (kullanıcı çalıştırır)
  - `env/prod.json`
- [ ] **F0-11** Android'de uçtan uca iskelet: debug APK telefonda açılır, e-posta kodu ile giriş, boş Bugün ekranı. Migrasyonlar üretime 👤 onayla `supabase db push`.

**Kabul:** CI yeşil; Android'de giriş çalışıyor; yerel pgTAP testleri geçiyor; anahtarlar yalnızca secrets'ta.

---

## Faz 1 — Çekirdek döngü (v0.1)
Dal: `faz-1`

### İçerik
- [ ] **F1-01** Hat S0–S1:
  - Kaynakları indir: NGSL, NGSL-S, CEFR-J, Octanove, wordfreq, CMUdict, Tatoeba EN–TR, Wiktextract alt kümesi
  - `lexicon.en.jsonl` üret, testleri yaz
- [ ] **F1-02** S2 seçim (A0–A2):
  - Kelime anlamları
  - 120 kalıplık sohbet çantası (NGSL-Spoken + LLM önerisi + 👤 hızlı gözden geçirme)
  - 40 gramer kodu
- [ ] **F1-03** S3–S4 cümle üretimi ve doğrulama:
  - Tatoeba adayları + Batch LLM
  - **`claude-api` skill'ini yükle**
  - QA raporu; 👤 20 örneklik inceleme
- [ ] **F1-04** S5 tr-en:
  - Karşılıklar, açıklamalar, varyantlar, karşıtlık notları
  - ~30 etiketlik hata kataloğu (`10` §6)
- [ ] **F1-05** Paketin tamamlanması:
  - S6 ses (Azure TTS, 2 ses + yavaş)
  - S8 X_Lex bankası
  - S9 derleme: `en@1.sqlite`, `tr-en@1.sqlite`
  - S10 rapor
  - 👤 onayla `upload`

### Motor
- [ ] **F1-06** FSRS adaptörü + otomatik puan (`03` §0.3) + `card_state_after`.
- [ ] **F1-07** `LanguageServices` (normalize/tokenize/lemma) + deterministik ön kontrol (`03` §0.5) + varyantlar. Sentetik dil testleri.
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
- [ ] **F1-12** Karşılama akışı (`09` §5.1): ekip oluşturma/katılma, ses onayı dahil.
- [ ] **F1-13** Seviye testi (A24: X_Lex + gramer + dikte) + başlangıç kaydı.
- [ ] **F1-14** Ses altyapısı:
  - Kayıt ve kodlayıcı seçimi (`08` §4)
  - `speech/transcribe` fonksiyonu: Deepgram adaptörü (İngilizce), Azure adaptörü (Türkçe)
  - `speech_usage` kaydı
- [ ] **F1-15** `tutor/answer_check` (`07` §4.1):
  - **`claude-api` skill'ini yükle**
  - zod şeması, önbellekli sistem promptu, merdiven sızıntı kontrolü, bütçe, `llm_usage`
  - deno testleri
  - Eval seti v1 (≥ 200 vaka); 👤 onayla ilk eval çalıştırması, maliyet raporlanır
- [ ] **F1-16** Kart oturumu (A00, A01, A02): merdiven, "yanlış duyuldu", sessiz mod, otomatik puan, deneme + outbox.
- [ ] **F1-17** Söyleyemediklerim (A19): yakalama butonu, yazılı ve sesli (Türkçe) yakalama, `tutor/gap_suggest`, karta ekleme, Android paylaş menüsü hedefi.
- [ ] **F1-18** Bugün ekranı v1 + "Bugünlük yeter" + "bugün ne kadar vaktin var?".
- [ ] **F1-19** Konuşma görevi v1 (A11) + `tutor/speaking_annotate` + akıcılık ölçümleri (motor) + aylık test v1 (A23: tek işaretleme).
- [ ] **F1-20** İlerleme v1: kanıt sayıları, önce/sonra ses dinleme, basit eğilimler.
- [ ] **F1-21** Senkron v1: outbox, `sync_push`/`sync_pull` RPC'leri, Faz 1 tabloları, pgTAP RLS testleri.
- [ ] **F1-22** Bildirim: çıpa saatinde tek davet, sessiz saatler, bugün çalışıldıysa gönderilmez.
- [ ] **F1-23** Ayarlar v1: bütçe, çıpa, sessiz mod, dışa aktar (JSON), tüm verimi sil.
- [ ] **F1-24** Teslim:
  - Entegrasyon testleri (`15` §4: 1, 2, 3, 5)
  - İmzalı sürüm APK (yerel keystore, 👤 parola)
  - İki telefona kurulum rehberi

**Kabul:**
- İki kullanıcı Android'de şunları kullanıyor: seviye testi, kart döngüsü, Söyleyemediklerim, konuşma görevi, aylık test.
- Denemeler senkronlanıyor.
- I-01…I-08, I-12…I-15 ve I-17 testleri yeşil.
- answer_check eval eşikleri sağlandı.
- Maliyet `llm_usage` ve `speech_usage` tablolarında görünüyor.

---

## Faz 2 — Konuşma, ses ve birlikte (v0.2)
Dal: `faz-2`

- [ ] **F2-01** ASR karşılaştırma testi (`08` §3.2):
  - Kayıt aracı ve 👤 veri seti kaydı
  - AssemblyAI, Azure STT ve OpenAI adaptörleri
  - Sonuçlar; ADR-0006 güncellemesi; gerekirse varsayılan sağlayıcıyı değiştir
- [ ] **F2-02** Konuşma görevi tam (A11):
  - İskeleler, yeniden yapma
  - Düzeltmelerin kişisel öğe olması
  - Aktarım tespiti → `transferred` düzeyi
- [ ] **F2-03** 4/3/2 (A12).
- [ ] **F2-04** Dikte (A05): hizalama, WER, `perc.*` etiketleri.
- [ ] **F2-05** Gölgeleme (A07): `speech/assess` (Azure telaffuz, REST, WAV 16 kHz), `pron.*` eşlemesi.
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
