# 12 — Mimari

## 1. Sistem görünümü

```text
┌──────────────────────────── Cihaz (Android · Windows · Web) ────────────────────────────┐
│ Flutter uygulaması (dilbaz_app)                                                          │
│   features/* (UI)  ──▶  controllers (Riverpod)  ──▶  dilbaz_engine (saf Dart)            │
│                                  │                     FSRS · öğrenci modeli · planlayıcı│
│                                  │                     ölçümler · eşleştirme · kapsama   │
│                                  ▼                                                       │
│   repositories  ──▶  drift/SQLite: içerik paketleri (salt okunur) + kullanıcı verisi     │
│        │   ▲                      + outbox (gönderilmemiş olaylar)                       │
└────────┼───┼─────────────────────────────────────────────────────────────────────────────┘
         │   │  HTTPS + JWT (senkron RPC, fonksiyon çağrıları)     WebSocket (Realtime: ikili görevler)
┌────────▼───┴──────────────────────────────── Supabase ───────────────────────────────────┐
│ Auth (e-posta tek kullanımlık kod) · Postgres + RLS · Storage · Cron (pg_cron + pg_net)  │
│ Edge Functions (Deno 2): tutor · speech · pair · ops          RPC: sync_push · sync_pull │
└────────┬───────────────────────────┬────────────────────────────┬────────────────────────┘
         ▼                           ▼                            ▼
   Gemini + Groq (ücretsiz LLM)   Deepgram (İngilizce STT)   Türkçe STT yedeği (Groq/Gemini)

Cihaz üstü: Türkçe STT (speech_to_text), dinamik TTS (flutter_tts). Paket sesleri: Kokoro (çevrimdışı). ADR-0009.

Çevrimdışı araçlar: content/tools (Python) ──▶ paketler (SQLite + ses) ──▶ Storage/packs
CI: GitHub Actions (format, analyze, test, pgTAP, deno test, pytest, APK build)
```

## 2. Depo yapısı (monorepo)

```text
/                                   (proje kökü)
├─ CLAUDE.md · README.md · .gitignore · .editorconfig
├─ docs/  (plan dokümanları, adr/)
├─ prompts/  (kodlama oturumu başlatma promptları)
├─ app/                              Flutter uygulaması (package: dilbaz_app)
│  ├─ lib/
│  │  ├─ main.dart
│  │  ├─ app/          router (go_router), tema, bootstrap, üst düzey provider'lar
│  │  ├─ core/         config (env), logging, hata tipleri (sealed Result), yardımcılar
│  │  ├─ data/
│  │  │  ├─ db/        drift veritabanı, tablolar, DAO'lar, migrasyonlar
│  │  │  ├─ sync/      outbox, push/pull, çakışma kuralları
│  │  │  ├─ remote/    Edge Function ve RPC istemcileri (supabase_flutter)
│  │  │  ├─ audio/     kayıt (record), oynatma, kodlayıcı seçimi
│  │  │  ├─ packs/     paket indirme, doğrulama, içe aktarma
│  │  │  └─ repositories/
│  │  ├─ features/
│  │  │  ├─ onboarding/ today/ cards/ introduce/ gap_journal/ speaking/ fluency/
│  │  │  ├─ roleplay/ together/ listening/ reading/ media/ writing/ mediation/
│  │  │  └─ assessment/ progress/ settings/
│  │  └─ l10n/         app_tr.arb (Türkçe arayüz metinleri)
│  ├─ test/            birim + widget + golden testler
│  └─ integration_test/
├─ packages/
│  └─ engine/                        saf Dart (package: dilbaz_engine) — Flutter bağımlılığı YOK
│     ├─ lib/src/  fsrs/ model/ planner/ scoring/ metrics/ curriculum/ language/ coverage/
│     └─ test/     sentetik dil paketi (zz) ile testler
├─ supabase/
│  ├─ config.toml · seed.sql
│  ├─ migrations/                    SQL (13-data-model.md)
│  ├─ functions/
│  │  ├─ _shared/  llm_config.ts, speech_config.ts, schemas/, prompts/, speech/ (adaptörler), auth.ts, budget.ts
│  │  ├─ tutor/    rota tabanlı: answer_check, speaking_annotate, gap_suggest, roleplay_turn, roleplay_debrief,
│  │  │            writing_feedback, mediation_check, comprehension_check
│  │  ├─ speech/   transcribe, assess, tts
│  │  ├─ pair/     create, join, submit (+ Realtime kanal yetkisi)
│  │  └─ ops/      retention_cleanup, backup_export (cron tetikler)
│  └─ tests/                         pgTAP (RLS, RPC)
├─ content/
│  ├─ packs/en/ · packs/tr-en/       paket kaynakları (11-language-packs.md)
│  ├─ tools/                         Python CLI (dilbaz-content), pyproject.toml (uv)
│  ├─ sources/ · work/ · build/      git dışı
├─ evals/
│  ├─ tutor/<rota>/cases.jsonl · run.ts · results/
│  └─ asr/                           karşılaştırma testi verisi (git dışı ses) + sonuçlar
├─ tools/
│  ├─ fsrs/optimize.py               py-fsrs Optimizer
│  └─ analysis/                      deney analizleri
└─ .github/workflows/                ci.yml, (ileride) web-deploy.yml
```

## 3. Flutter uygulama mimarisi

- **Katmanlar:** UI (widget) → controller (Riverpod `Notifier`/`AsyncNotifier`) → engine (saf Dart) → repository (drift + uzak).
- **Kurallar:**
  1. Widget'larda iş mantığı yoktur.
  2. Pedagojik kararların tamamı `dilbaz_engine` içindedir.
  3. Tüm IO repository arkasındadır. Controller'lar doğrudan Supabase ya da drift çağırmaz.
  4. Modeller `freezed` ile değişmezdir. Hatalar `sealed class Result<T>` ile taşınır. Beklenen hatalar için exception fırlatılmaz.
  5. Tüm zamanlar UTC'dir (`DateTime.now().toUtc()`). Yerel saate yalnızca gösterimde çevrilir.
  6. Kimlikler istemcide üretilen **UUIDv7**'dir (`uuid` paketi, `Uuid().v7()`).
  7. Kullanıcıya görünen metinler yalnızca ARB'den gelir. Yasak kelime testi vardır (`15`).
- **Yönlendirme:** `go_router`; her özellik kendi rotalarını tanımlar.
- **Durum yönetimi:** Riverpod 3 + kod üretimi (`riverpod_generator`). freezed ve json_serializable zaten kod ürettiği için tutarlıdır.
- **Özellik bayrakları:** `app_config` tablosu + yerel varsayılanlar. Yarım kalan özellikler bayrak arkasında birleştirilir.

## 4. Sürümler (2026-09-25'te doğrulandı)

Yeni bağımlılık eklemeden ya da sürüm yükseltmeden önce pub.dev ve context7 ile güncel kararlı sürüm kontrol edilir.

| Bileşen | Sürüm | Not |
|---|---|---|
| Flutter / Dart | 3.47.5 / 3.13.4 | Windows'ta Geliştirici Modu şart (eklenti sembolik bağları) |
| flutter_riverpod · riverpod_generator | 3.4.3 · 4.0.9 | |
| go_router | 18.0.1 | Flutter ≥ 3.44 |
| freezed · freezed_annotation | 4.0.2 · 3.1.0 | Dart ≥ 3.13 |
| json_serializable | 6.14.1 | |
| drift · drift_flutter | 2.35.0 · 0.3.1 | `sqlite3_flutter_libs` **eklenmez** (kullanımdan kalktı). Web için `sqlite3.wasm` + `drift_worker.js`; OPFS için COOP/COEP başlıkları. |
| supabase_flutter | 2.17.2 | 3.x ön sürüm, kullanılmaz. Yeni projelerde "publishable key". |
| fsrs (Dart) | 2.0.1 (FSRS-6, 21 parametre) | Ayrıntı §5 |
| record | 7.1.1 | Windows'ta Opus yok → AAC-LC/WAV (`08` §4) |
| just_audio (+ just_audio_media_kit, Windows) · alternatif audioplayers | 0.10.6 · 6.8.1 | Windows oynatma için media_kit eklentisi ya da audioplayers. `just_audio_media_kit` Windows derlemesiyle birlikte F3-09'da eklenir (Faz 0'da Windows araç zinciri yok). |
| uuid | 4.6.0 | `v7()` var |
| fl_chart | 1.2.0 | |
| flutter_local_notifications | 22.3.1 | Web'de zamanlanmış bildirim yok |
| share_handler | 0.0.25 | Paylaş menüsü hedefi (receive_sharing_intent bakımı zayıf) |
| home_widget | 0.10.0 | Android widget |
| permission_handler | 13.0.2 | |
| Supabase Edge Functions | Deno 2.x (yerelde 2.9.7) | `npm:` içe aktarma destekli. `supabase/functions/deno.json` içe aktarma haritası; komutlar bu klasörden çalışır. |
| @supabase/server · @std/assert · @std/path | 1.8.0 · 1.0.19 · 1.1.6 | Fonksiyonlarda kimlik doğrulama ve testler |
| CI Flutter kurulumu | subosito/flutter-action@v2 | |
| Android Gradle Plugin · Gradle | 9.4.1 · 9.6.0 | Flutter 3.47.5 şablonu 9.1.0 · 9.3.1 getirir. `permission_handler_android` 14.1 `compileSdk = 37` kullanıyor; AGP 9.1 yeni `android-37.0` platform adını çözemediği için yükseltildi (2026-09-26). Uygulamada `compileSdk = 37`, `targetSdk` Flutter varsayılanı (36). Core library desugaring açık (`flutter_local_notifications`). **Risk:** `home_widget` ve `share_handler_android` hâlâ Kotlin Gradle eklentisini uyguluyor; Flutter ileride bunu hata sayacak. Güncellemeler izlenir. |

## 5. FSRS entegrasyonu

- `import 'package:fsrs/fsrs.dart' as fsrs;` **önek zorunlu**, çünkü `Card` ve `State` Flutter sınıflarıyla çakışır. FSRS yalnızca `dilbaz_engine` içinde kullanılır ve motor kendi tiplerini dışa açar.
- `fsrs.Card.cardId` bir `int`'tir. Dilbaz kartı UUID ile tanınır, FSRS kimliği ayrı alanda (`fsrs_card_id`) tutulur.
- İnceleme: `scheduler.reviewCard(card, rating, reviewDateTime: nowUtc)` → `(card, reviewLog)`. Hatırlama olasılığı: `scheduler.getCardRetrievability(card, currentDateTime: nowUtc)`.
- Aralık bulanıklaştırma (fuzz) canlıda açıktır. Sonuç `attempts.card_state_after` olarak saklanır (senkron deterministik).
- **Dart paketinde optimizasyon ve yeniden zamanlama yok:**
  - Kişisel parametreler `tools/fsrs/optimize.py` ile hesaplanır (py-fsrs 6.x, `fsrs[optimizer]`). py-fsrs, farklı günlere yayılmış 512'den az tekrarda varsayılan parametreleri döndürür.
  - Tam yeniden hesaplama gerekirse (parametre değişimi) motor, denemeleri fuzz kapalı olarak sırayla yeniden oynatır.

## 6. Yerel öncelikli veri ve senkron (ADR-0003)

- **Arayüzün tek kaynağı yerel drift veritabanıdır.** Her yazma aynı işlemde (transaction) hem yerel tabloya hem **outbox**'a gider.
- **Olay türü veriler** (denemeler, Söyleyemediklerim, kayıt meta verisi, oturumlar, medya günlüğü, değerlendirmeler):
  - Değiştirilemez ve UUIDv7 kimliklidir.
  - Sunucuda `insert … on conflict (id) do nothing` ile yazılır, yani idempotenttir. Çakışma olmaz.
- **Durum türü veriler** (kartlar, profil ayarları): son yazan kazanır (LWW).
  - Kartlarda karşılaştırma `last_review` zamanına göre yapılır. Profilde `updated_at` alanına göre.
  - Aynı kart iki cihazda çevrimdışı incelenirse daha yeni `last_review` kazanır. Kaybedenin denemeleri yine de günlükte kalır ve olay loglanır.
  - Seyrek bir durumdur. Gerekirse tam yeniden oynatma yapılır.
- **Push:** `sync_push(device_id, batch jsonb)` RPC'si. RLS ile çalışır; tek işlem, en fazla 500 kayıt.
- **Pull:** `sync_pull(since_seq bigint)` RPC'si. Kullanıcının tablolarında `server_seq > since` olan satırları döner (sayfalı), yeni imleci verir. `server_seq` global bir dizidir; ekleme ve güncellemede tetikleyiciyle atanır.
- **Tetikleyiciler:** uygulama açılışı, oturum sonu, 5 dakikada bir (ön planda), bağlantı geri gelince.
- **Paketler** senkron dışındadır: manifest kontrolü + indirme (`11` §5).
- **Plan B:** Özel senkron bakım yükü yaratırsa PowerSync (Flutter SDK 2.x, Supabase entegrasyonu, drift uyumlu) değerlendirilir.

## 7. Edge Functions

| Fonksiyon | Rotalar | Notlar |
|---|---|---|
| `tutor` | `07` §4'teki tüm rotalar | Tek dağıtım, rota parametresi. Günlük bütçe kontrolü, şema doğrulaması, merdiven sızıntı kontrolü, `llm_usage` kaydı. |
| `speech` | `transcribe`, `assess`, `tts` | Sağlayıcı adaptörleri (`08` §3.3). Kart sesi doğrudan gövdede, görev sesi Storage yolundan. `speech_usage` kaydı. |
| `pair` | `create`, `join`, `submit` | Rol yüklerini yalnızca ilgili katılımcıya verir. Realtime kanalı `pair:{id}` (özel kanal, RLS). |
| `ops` | `retention_cleanup`, `backup_export` | Yalnızca servis rolü, pg_cron + pg_net ile tetiklenir. |

**Ortak kurallar:**
- JWT doğrulaması fonksiyonun içinde, `@supabase/server` (`verifyAuth`, proje JWKS) ile yapılır. Platformun `verify_jwt` denetimi yeni API anahtarlarını (publishable/secret) anlamadığı için fonksiyonlarda `verify_jwt = false`'tur (`config.toml`).
- Rotalar yol parçasıdır: `/functions/v1/tutor/<rota>`. Kod: `supabase/functions/<fonksiyon>/handler.ts` (bağımlılıklar enjekte edilir, testler ağsız) + `index.ts` (`Deno.serve`).
- Kullanıcı başına dakikada 60 istek sınırı
- Yapılandırılmış JSON log (kimlik ve süre; transkript ya da metin loglanmaz)
- Anahtarlar Supabase secrets'ta tutulur (`GEMINI_API_KEY`, `GROQ_API_KEY`, `DEEPGRAM_API_KEY`; ADR-0009)

## 8. Ortamlar ve yapılandırma

| Ortam | Supabase | Uygulama yapılandırması |
|---|---|---|
| Yerel | `supabase start` (Docker Desktop) | `--dart-define-from-file=env/local.json` |
| Üretim | Barındırılan ücretsiz proje (bölge: eu-central-1, Frankfurt) | `env/prod.json` |

- `env/*.json` git dışıdır. Yalnızca proje URL'si ve **publishable key** içerir. Gizli anahtar uygulamaya asla girmez. Biçim: `app/env.example.json`. Anahtarlar eksikse uygulama açılışta durur (`missing_env`).
- **Yerel:** `app/env/local.json` → `SUPABASE_URL = http://127.0.0.1:54321` (Android emülatöründe `http://10.0.2.2:54321`, telefonda bilgisayarın yerel ağ IP'si), anahtar `npx supabase status` çıktısındaki `PUBLISHABLE_KEY`. Debug derlemeleri yerel HTTP'ye izin verir (`usesCleartextTraffic`, yalnızca debug manifesti).
- **Web ile hızlı deneme:** `.claude/launch.json` → `app-web-local` (web sunucusu, port 5173, yerel Supabase).
- **Migrasyonlar:** yerelde `supabase db reset` ile test edilir, üretime `supabase db push` ile uygulanır. Push, kullanıcının onayıyla ve faz sonlarında yapılır.
- **Ücretsiz plan kısıtları:** 500 MB veritabanı, 1 GB depolama, 5 GB çıkış trafiği, **otomatik yedek yok**, **1 hafta hareketsizlikte proje durur**, en fazla 2 aktif proje.
  - Günlük kullanımda durma sorun olmaz. Uzun tatil öncesi uyarı notu gösterilir.
  - Ses saklama kuralı (`14` §4) depolamayı sınırda tutar.

## 9. Yedekleme (ücretsiz planda otomatik yedek yok)

- **Gece yedeği:**
  1. Gecelik pg_cron tetikler.
  2. `ops/backup_export`, kullanıcı tablolarını JSON olarak `backups/{tarih}/` (servis rolü) altına yazar.
  3. Son 14 gün tutulur.
- **Haftalık tam döküm:** GitHub Actions (zamanlanmış) `supabase db dump` çalıştırır, sonuç şifreli artifact olarak saklanır. DB parolası GitHub secret'tır; kullanıcı ekler.
- **Uygulama içi dışa aktarma:** Ayarlar > Veri > Dışa aktar (JSON + sesler, zip).

## 10. Platform notları

- **Android (birincil):**
  - İzinler: `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `INTERNET`.
  - Paylaş menüsü hedefi, hızlı ayar kutucuğu, ana ekran widget'ı.
  - Dağıtım: iki telefona doğrudan APK (mağaza yok). İleride GitHub Releases ya da Firebase App Distribution.
- **Windows (Faz 3):**
  - Visual Studio "Desktop development with C++" gerekir.
  - Ses kaydı AAC-LC/WAV.
  - Bildirimler sınırlı (yinelenen bildirim yok; iptal için MSIX gerekir).
- **Web (Faz 6):**
  - drift için `sqlite3.wasm` ve worker dosyaları gerekir.
  - OPFS için COOP/COEP başlıkları gerekir. Yayın Vercel'de `vercel.json` başlıklarıyla yapılır.
  - Zamanlanmış bildirim yok.
  - Mikrofon izni ve HTTPS gerekir.

## 11. Performans hedefleri

| Ölçüt | Hedef |
|---|---|
| Soğuk açılış (Android orta seviye telefon) | < 2 sn |
| Kartlar arası geçiş | < 100 ms |
| Kart: konuşma bitişi → sonuç (deterministik yol) | p90 < 1,5 sn |
| Kart: LLM'li yol | p90 < 4 sn |
| Planlayıcı (10.000 kart) | < 50 ms |
| Öğrenci modeli artımlı güncelleme (tek deneme) | < 5 ms |
| Paket içe aktarma (A0–A2) | < 5 sn, arka planda |

## 12. Gözlemlenebilirlik

- **İstemci hataları:** `app_events` tablosuna yazılır. Oran sınırlıdır ve kişisel veri içermez.
- **Fonksiyon logları:** Supabase log panosu. Yapılandırılmış log, rota, süre, `stop_reason`.
- **Kullanım panosu:** Ayarlar > Kullanım. `llm_usage` + `speech_usage` toplamları: sağlayıcı başına kota tüketimi ve Deepgram kredisi (ADR-0009).
