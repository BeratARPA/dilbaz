# 13 — Veri Modeli

Sunucu şeması (Postgres), yerel ayna (drift), RLS politikaları, senkron RPC'leri, depolama bucket'ları ve saklama işleri. İçerik paketleri Postgres'e **normalize edilmez**. Paketler versiyonlu SQLite dosyalarıdır (`11` §5). Postgres yalnızca kullanıcı verisini ve paket kayıt defterini tutar. Bu, veritabanını küçük tutar (ücretsiz plan 500 MB).

## 1. Genel kurallar

- **Kimlik:** Kullanıcı verisinde istemcinin ürettiği `uuid` (v7). `profiles.id = auth.users.id`.
- **Zaman:** Her zaman `timestamptz`, UTC.
- **Senkron alanları:** Senkronlanan her tabloda:
  - `server_seq bigint not null default nextval('sync_seq')`
  - güncelleme tetikleyicisi `server_seq`'i yeniler
  - `created_at timestamptz default now()`
- **Değişmezlik:** Olay tablolarında (`attempts`, `attempt_amendments`, `sessions`, `media_logs`, `assessments`) **UPDATE ve DELETE politikası yoktur**. Silme yalnızca "tüm verimi sil" fonksiyonuyla, servis rolüyle yapılır.
- **Öğe referansları:** `item_ref text` iki biçimde olur:
  - paket anahtarı (`en.sent.i_am_going_home`)
  - kişisel öğe (`personal:<uuid>`)

## 2. Tablolar

### 2.1 Kimlik ve ekip

```sql
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null,
  l1 text not null default 'tr',
  ui_locale text not null default 'tr',
  time_budget_min int not null default 30 check (time_budget_min between 5 and 120),
  weekly_days_goal int not null default 5 check (weekly_days_goal between 1 and 7),
  anchors jsonb not null default '[]',          -- [{label:"sabah kahvesi", time:"08:30"}]
  quiet_hours jsonb,                            -- {from:"22:30", to:"08:00"}
  goal_text text, interests text[] not null default '{}',
  scaffold_overrides jsonb not null default '{}',
  settings jsonb not null default '{}',         -- sessiz mod, kart kayıtlarını sakla, deney onayı…
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'),
  created_at timestamptz not null default now()
);

create table teams (
  id uuid primary key, name text not null, invite_code text unique not null,
  created_by uuid not null references profiles, created_at timestamptz not null default now()
);

create table team_members (
  team_id uuid references teams on delete cascade,
  profile_id uuid references profiles on delete cascade,
  role text not null default 'member',
  share_levels boolean not null default false,     -- partner seviye tahminimi görsün mü
  share_monthly boolean not null default false,    -- aylık test özetimi görsün mü
  joined_at timestamptz not null default now(),
  primary key (team_id, profile_id)
);

create table courses (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  l2 text not null, pair_pack text not null,          -- 'tr-en'
  level_estimates jsonb not null default '{}',        -- {speaking:{low:2,high:3,confidence:"medium"},…}
  vocab_estimate int, fsrs_params jsonb,              -- {production:[21 sayı], receptive:[…], dictation:[…]}
  desired_retention numeric not null default 0.90 check (desired_retention between 0.80 and 0.97),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'),
  created_at timestamptz not null default now(),
  unique (profile_id, l2)
);
```

**`profiles.settings` anahtarları** (karşılama akışı yazar, Ayarlar değiştirir):

| Anahtar | Değer | Anlam |
|---|---|---|
| `audio_consent` | `{granted: bool, at: ISO-8601 UTC}` | Ses kaydı onayı (`14` §4). Verilmediyse kayıt yapılmaz. |
| `ai_data_consent` | `{granted: bool, at: ISO-8601 UTC}` | Metnin Gemini ücretsiz katmanına gitmesine onay (ADR-0009). Yoksa istek Groq'a ya da deterministik yola gider. |
| `daily_invitation` | bool | Günde tek davet bildirimi isteniyor mu (`09` §6). |
| `silent_mode` | bool | Yazılı cevap varsayılanı. Ses onayı ya da mikrofon izni yoksa `true` başlar. |
| `onboarded_at` | ISO-8601 UTC | Karşılama akışının bittiği an. Yoksa akış gösterilir (ekip adımı için gönderilen taslak profilde bulunmaz). |

**`assessments` satırı, `kind = placement`:** `results` = `{version, seed, xlex: {score, band_rates, false_alarm_rate, answers: [{key, known}]}, grammar: {steps: [{key, level, choice, correct}]}, dictation: {sentences: [{key, level, typed, plays, words, errors, slips}]}, duration_ms: {words, grammar, dictation}}`; yapılmayan bölümün anahtarı yoktur. `level_estimates` = ölçülen beceriler + `overall` (`06` §2). Satır değişmez; testin tekrarı yeni satırdır (sürüm sırası satır sayısından çıkar).

**`courses.level_estimates` başlangıcı:** Seviye testi yapılana kadar `{overall: {low, high, confidence: "low", source: "self"}}`; `low` = `high` = kullanıcının seçtiği seviyenin ölçek değeri (`04` §10).

### 2.2 İçerik kayıt defteri ve kişisel öğeler

```sql
create table packs (
  id text primary key,                    -- 'en@1', 'tr-en@1'
  kind text not null check (kind in ('target','pair')),
  l2 text not null, l1 text,
  version numeric not null, status text not null check (status in ('draft','published','deprecated')),
  manifest jsonb not null, storage_path text not null, checksum text not null,
  created_at timestamptz default now()
);

create table personal_items (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  kind text not null check (kind in ('sentence','chunk','word_sense')),
  text_l2 text not null, lemmas text[] not null default '{}', cefr text,
  source text not null check (source in ('gap','subtitle','task_correction','reading_lookup','openenglish','manual')),
  gloss_l1 text, notes text, variants text[] default '{}', audio_path text,
  deprecated boolean not null default false,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);
```

### 2.3 Öğrenme durumu: kartlar ve denemeler

```sql
create table cards (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  item_ref text not null,
  mode text not null check (mode in ('speak','type','cloze','contrast','recognize_audio','dictation')),
  fsrs_card_id bigint not null,
  state smallint not null,               -- 1 learning, 2 review, 3 relearning (fsrs State)
  step int, stability double precision, difficulty double precision,
  due timestamptz not null, last_review timestamptz,
  reps int not null default 0, lapses int not null default 0,
  suspended boolean not null default false,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now(),
  unique (profile_id, item_ref, mode)
);

create table attempts (
  id uuid primary key,                   -- UUIDv7 (istemci)
  profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  device_id uuid not null,
  activity text not null,                -- 'card.produce_speak', 'speaking_task', …
  item_ref text, card_id uuid, task_ref text, text_ref text,
  parent_attempt_id uuid,                -- aynı öğedeki tekrar denemesi zinciri
  prompt jsonb not null,
  response jsonb not null,               -- {text, source:'asr'|'typed', audio_path?, transcript?, asr:{provider,model,conf}}
  verdict text, target_ok boolean, error_tags text[] not null default '{}',
  hints_used smallint not null default 0, hint_max_level smallint not null default 0,
  rating smallint check (rating between 1 and 4),
  latency_ms int, duration_ms int,
  card_state_after jsonb,                -- FSRS sonrası kart durumu (senkron determinizmi)
  llm jsonb,                             -- {route, pending:boolean, request_id}
  experiment jsonb,                      -- {id, arm}
  created_at_client timestamptz not null,
  server_seq bigint not null default nextval('sync_seq'),
  created_at timestamptz not null default now()
);

create table attempt_amendments (        -- değişmez denemelere sonradan gelen bilgi
  id uuid primary key, attempt_id uuid not null references attempts on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  kind text not null check (kind in ('llm_resolved','asr_override','user_dispute')),
  payload jsonb not null,
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);
```

- `attempts.card_state_after` motorun `CardMemory` JSON'udur: `{fsrs_card_id, state, step, stability, difficulty, due, last_review, reps, lapses}`. Bu alanlar `cards` satırının FSRS sütunlarının tamamıdır, bu yüzden kart satırı son puanlı denemeden yeniden kurulabilir (I-03).
- **Kart denemeleri (F1-16):**
  - `prompt` = `{prompt_l1, reference, carrier, context?}`
  - `response` = `{text, source: 'asr'|'typed', transcript?, asr?: {provider, model, conf?}, asr_override?, corrected_from?}`
  - `llm` = `{route, pending, provider?, model?, catalog?, confidence?, code?}` (`07` §7); deterministik eşleşmede `null`.
  - `hints_used`, `hint_max_level`: cevaptan önce açılan ipuçları. Puanlı son denemede gösterimin en yüksek ipucudur; istekle açılan cevap (H4) dahil.

### 2.4 Kişisel içerik, kayıtlar, değerlendirme

**F1-17:** `gap_entries.suggestion`, `gap_suggest` rotasının cevabıdır, olduğu gibi saklanır. "Karta ekle" aynı işlemde kişisel öğeleri (`source = gap`; cümle `kind = sentence`, kalıp `chunk`) yazar, yakalamayı `carded` yapar ve kimlikleri `personal_item_ids`'e koyar. Kişisel öğenin kartı `cards.item_ref = personal:<id>` taşır (`10` §7).

```sql
create table gap_entries (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  l1_text text not null, audio_path text,
  context text not null check (context in ('live_class','daily','pair','speaking_task','media')),
  note text, suggestion jsonb,           -- gap_suggest çıktısı
  status text not null default 'new' check (status in ('new','carded','dismissed')),
  personal_item_ids uuid[] not null default '{}',
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);

create table recordings (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  task_ref text, attempt_id uuid, audio_path text,     -- saklama süresi dolunca null (§7)
  duration_ms int not null,
  asr jsonb,                             -- {provider, model, words:[{w,start_ms,end_ms,conf}]}
  annotation jsonb,                      -- {runs:[…], merged:{…}}
  metrics jsonb,                         -- 06 §3.3
  outcome text check (outcome in ('done','partial','not_done')),
  is_assessment boolean not null default false, assessment_id uuid,
  keep boolean not null default false,   -- kullanıcı yıldızladı → otomatik silinmez
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);

create table assessments (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  kind text not null check (kind in ('placement','monthly_speaking','vocab_retest','writing_sample','listening_mini','external')),
  results jsonb not null, level_estimates jsonb,
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);

create table writings (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  task_ref text not null, drafts jsonb not null default '[]', feedback jsonb, final_text text,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);

create table sessions (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade, device_id uuid not null,
  started_at timestamptz not null, ended_at timestamptz,
  planned jsonb, done jsonb, active_ms int not null default 0,
  strand_ms jsonb not null default '{}',  -- {input:…, output:…, language:…, fluency:…}
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);

create table media_logs (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  kind text not null check (kind in ('series','film','podcast','video','book','other')),
  title text, minutes int not null check (minutes between 1 and 600),
  subtitles text check (subtitles in ('none','l2','l1')), with_partner boolean not null default false,
  day date not null,
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);

create table subtitle_imports (
  id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  course_id uuid not null references courses on delete cascade,
  title text not null, file_path text not null, coverage numeric, unknown jsonb,
  status text not null default 'imported' check (status in ('imported','prepared','watched','mined')),
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('sync_seq'), created_at timestamptz default now()
);
```

### 2.5 Birlikte

```sql
create table pair_sessions (
  id uuid primary key, team_id uuid not null references teams on delete cascade,
  task_ref text not null, created_by uuid not null references profiles,
  participants uuid[] not null,
  state text not null check (state in ('invited','active','done','cancelled')),
  result jsonb, created_at timestamptz default now(), ended_at timestamptz
);

create table pair_roles (                 -- her katılımcı yalnız kendi rolünü görür
  pair_session_id uuid references pair_sessions on delete cascade,
  profile_id uuid references profiles on delete cascade,
  role text not null, payload jsonb not null, answer jsonb,
  primary key (pair_session_id, profile_id)
);

create table weekly_goals (
  id uuid primary key, team_id uuid references teams on delete cascade,
  profile_id uuid references profiles on delete cascade,
  week_start date not null, target jsonb not null,  -- {kind:'days'|'minutes', value:8}
  created_at timestamptz default now(),
  check ((team_id is null) <> (profile_id is null))
);

create table cheers (
  id uuid primary key, team_id uuid not null references teams on delete cascade,
  from_profile uuid not null references profiles, to_profile uuid not null references profiles,
  message_key text not null, created_at timestamptz default now()
);
```

### 2.6 İşletim, deney, kullanım

```sql
create table content_reports (id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  item_ref text not null, reason text not null, note text,
  status text not null default 'open' check (status in ('open','fixed','rejected')), created_at timestamptz default now());

create table experiments (id text primary key, hypothesis text not null, arms jsonb not null,
  unit text not null check (unit in ('item','card','session','profile')),
  status text not null check (status in ('draft','running','stopped','analyzed')),
  started_at timestamptz, ended_at timestamptz);

create table experiment_assignments (experiment_id text references experiments,
  profile_id uuid references profiles on delete cascade, unit_ref text not null, arm text not null,
  assigned_at timestamptz default now(), primary key (experiment_id, profile_id, unit_ref));

create table llm_usage (id bigserial primary key, profile_id uuid references profiles on delete set null,
  route text not null, provider text not null, model text not null, input_tokens int, output_tokens int,
  cache_read_tokens int, cache_write_tokens int, cost_usd numeric(10,6),  -- ücretsiz katmanda 0 (ADR-0009)
  stop_reason text,
  latency_ms int, created_at timestamptz default now());

create table speech_usage (id bigserial primary key, profile_id uuid references profiles on delete set null,
  provider text not null, kind text not null check (kind in ('stt','pron','tts')),
  seconds numeric, characters int, cost_usd numeric(10,6),  -- Deepgram kredisinden düşen tutar
  created_at timestamptz default now());

create table devices (id uuid primary key, profile_id uuid not null references profiles on delete cascade,
  platform text not null, app_version text, last_sync_at timestamptz);

create table app_events (id bigserial primary key, profile_id uuid references profiles on delete set null,
  device_id uuid, level text not null check (level in ('info','warn','error')), code text not null,
  payload jsonb, created_at timestamptz default now());

create table app_config (key text primary key, value jsonb not null);
```

### 2.7 Görünümler ve fonksiyonlar

- **`partner_week_summary(team_id, week_start)`** (security definer, üyelik kontrolü yapar). Her üye için şunları döner:
  - aktif gün sayısı, aktif dakika
  - kol dakikaları
  - birlikte görev sayısı
  - (`share_levels` açıksa) seviye aralıkları
  - (`share_monthly` açıksa) aylık özet
- **`delete_my_data()`** (security definer): kullanıcının tüm satırlarını ve Storage nesnelerini siler (servis çağrısıyla).
- **`llm_usage_counts(p_profile_id, p_models[], p_since[])`** (security invoker, yalnızca servis rolü; F1-15). Bir kullanıcının her modeldeki çağrı sayısını ve önbellek dışı token sayısını (`input − cache_read + output`) o modelin kota gününün başından beri verir. `tutor` adil payı bununla denetler (`07` §3).

## 3. İndeksler

```sql
create index on attempts (profile_id, created_at desc);
create index on attempts (card_id);
create index on attempts (profile_id, server_seq);
create index on cards (profile_id, due) where not suspended;
create index on cards (profile_id, server_seq);
create index on gap_entries (profile_id, status);
create index on recordings (profile_id, is_assessment, created_at desc);
create index on sessions (profile_id, started_at desc);
create index on llm_usage (profile_id, created_at);
-- server_seq indeksleri tüm senkron tablolarında
```

## 4. RLS politikaları

- Tüm tablolarda RLS **açık**. Varsayılan: hiçbir şeye izin yok.
- **Data API yetkileri açıktır:** `public` şemasındaki yeni tablolar `anon`/`authenticated` rollerine varsayılan olarak açılmaz (Supabase varsayılanı TRUNCATE dahil her şeyi verirdi; `20260926171355_explicit_grants.sql`). Her tablo, politikalarının gerektirdiği yetkileri migrasyonda açıkça verir; örneğin `profiles`/`courses`: SELECT, INSERT, UPDATE; `teams`/`team_members`: SELECT, INSERT; paylaşım anahtarları için sütun düzeyinde UPDATE. `service_role` (sunucu fonksiyonları) tüm kullanıcı tablolarında SELECT/INSERT/UPDATE/DELETE ve sıralarda kullanım yetkisini açıkça alır (`20260926172310_service_role_grants.sql`), çünkü üretimde "Automatically expose new tables" kapalıyken bu yetkiler de verilmiyor. Böylece yerel ve üretim aynı davranır.
- **Sahiplik:**
  - `profile_id = auth.uid()` için select/insert.
  - Durum tablolarında (profil, kurslar, kartlar, kişisel öğeler, Söyleyemediklerim, kayıtlar, yazılar, altyazılar) update de serbest.
  - **Olay tablolarında update/delete yok** (§1).
- **Ekip:**
  - `teams`: üyeler ve kurucu okur. Kullanıcı yalnızca kendi adına (`created_by = auth.uid()`) ekip kurar.
  - `team_members`: yalnızca üyesi olunan ekiplerin satırları okunur. Kurucu kendini ekler. Başka bir ekibe katılım doğrudan ekleme değil, davet kodu fonksiyonuyla yapılır: `join_team(p_invite_code)` (SECURITY DEFINER; kodu doğrular, üyeliği ekler, yinelenen katılım zararsızdır). `create_team(p_name)` çağıranın kendi yetkisiyle çalışır: 10 karakterlik davet kodunu sunucuda üretir, ekibi ve kurucunun `owner` üyeliğini birlikte yazar. Çağıranın kurduğu bir ekip zaten varsa yenisini kurmaz, onu döndürür: yanıtı kaybolan bir isteğin yinelenmesi ikinci ekip bırakmaz. İkisi de yalnızca `authenticated` rolüne açıktır. Profil sunucuda yoksa ikisi de reddedilir (yabancı anahtar), bu yüzden istemci önce profili gönderir.
  - Üye yalnızca kendi `share_levels` / `share_monthly` anahtarlarını değiştirir (sütun düzeyinde UPDATE yetkisi); `role` değiştirilemez.
  - Üyelik denetimi `private.is_team_member()` ile yapılır (SECURITY DEFINER, politika özyinelemesini önler; `private` şeması Data API'ye açık değildir).
  - Partnerin verisine **doğrudan erişim yoktur**. Yalnızca `partner_week_summary` fonksiyonu kullanılır.
- **İkili görev:**
  - `pair_sessions`: katılımcılar okur.
  - `pair_roles`: `profile_id = auth.uid()` olan satır okunur.
  - Yazma işlemleri `pair` fonksiyonu üzerinden yapılır.
- **`packs`:** kimliği doğrulanmış herkes `status = 'published'` satırları okur. Yazma yalnızca servis rolüyle.
- **`llm_usage`, `speech_usage`:** kullanıcı kendi satırını okur. Yazma yalnızca servis rolüyle.
- **`app_config`:** herkes okur, yazma servis rolüyle.
- **Realtime:** `pair:{id}` özel kanalı. `realtime.messages` üzerinde katılımcı kontrolü yapan politika.
- **Test:** Her tablo için pgTAP testi yazılır: sahip okur/yazar, başka kullanıcı okuyamaz, partner ham veriyi okuyamaz (`15`).

## 5. Senkron RPC'leri

```sql
-- İstemci → sunucu. İdempotent. RLS altında çalışır (security invoker).
create function sync_push(p_device_id uuid, p_batch jsonb) returns jsonb …
--   p_batch = {attempts:[…], attempt_amendments:[…], cards:[…], gap_entries:[…], …}
--   olay tabloları: insert … on conflict (id) do nothing
--   durum tabloları: upsert; kartlarda yalnızca gelen last_review ≥ mevcut ise güncelle
--   dönüş: {accepted: n, conflicts: [{table,id,reason}]}

-- Sunucu → istemci. Sayfalı.
create function sync_pull(p_since bigint, p_limit int default 1000) returns jsonb …
--   kullanıcının tüm senkron tablolarında server_seq > p_since olan satırlar
--   dönüş: {rows: {table: […]}, next: bigint, more: boolean}
```

## 6. Depolama (Storage) bucket'ları

| Bucket | Yol | Erişim |
|---|---|---|
| `audio-private` | `{uid}/{yyyy}/{mm}/{uuid}.{m4a,webm,wav}` | Yalnız sahip (yol öneki = `auth.uid()`) |
| `subtitles-private` | `{uid}/{uuid}.srt` | Yalnız sahip |
| `packs` | `{pack_id}.sqlite`, `{pack_id}.LICENSES.md` | Kimliği doğrulanmış okur |
| `pack-audio` | `{l2}/{version}/{voice}/{hash}.mp3` | Kimliği doğrulanmış okur |
| `tts-cache` | `{hash}.mp3` | Kimliği doğrulanmış okur, servis rolü yazar |
| `backups` | `{tarih}/…` | Yalnız servis rolü |

Dosya boyutu sınırı: ücretsiz planda 50 MB. Uygulama kayıtları bunun çok altındadır.

## 7. Zamanlanmış işler (pg_cron → pg_net → `ops`)

| İş | Zaman (UTC) | Ne yapar |
|---|---|---|
| `retention_cleanup` | Her gün 02:00 | 30 günden eski, `is_assessment = false` ve `keep = false` olan kayıtların seslerini siler, `recordings.audio_path` → null. 90 günden eski `app_events` satırlarını siler. |
| `backup_export` | Her gün 02:30 | Kullanıcı tablolarını JSON olarak `backups/` altına yazar. 14 günden eskileri siler. |

## 8. Yerel veritabanı (drift) aynası

Kod: `app/lib/data/db/` (şema v1 F0-05; v2 F1-16: yerel `devices`).

- **Kullanıcı tabloları:** Sunucuda senkronlanan 13 tablonun aynısı (§2.2–2.4 ile `profiles`, `courses`; aynı sütun adları, `server_seq` dahil) + `pending_push boolean`.
  - Yerelde `server_seq` sunucu atayana kadar `null`dır.
  - `pending_push` yerel yazmalarda outbox kaydıyla aynı işlemde `true` yapılır. Sunucudan çekilen satırlar varsayılan `false` ile gelir.
  - **Sunucunun yabancı anahtarları ve CHECK kısıtları yerelde tekrarlanmaz.** Senkronun sayfa sırası ve sunucu şemasının evrimi yerel eklemeleri bozmamalı. Doğrulama sunucuda ve repository katmanında yapılır. Benzersizlikler (`cards (profile_id, item_ref, mode)`, `courses (profile_id, l2)`) korunur.
  - Zamanlar ISO-8601 metin olarak saklanır (drift `store_date_time_values_as_text`). UTC değerler UTC okunur.
  - `jsonb`, `text[]` ve `uuid[]` alanları JSON metnidir (tip dönüştürücüleriyle `Map`/`List`). `media_logs.day` `YYYY-MM-DD` metnidir.
- **`outbox`:** `id` (artan), `target_table`, `row_id`, `op` (`insert` olay / `upsert` durum), `created_at`, `attempts`, `next_attempt_at`, `last_error` (yalnızca hata kodu).
  - Kayıt yalnızca satırı adlandırır. Push satırın o anki hâlini okur, aynı durum satırının birden çok güncellemesi tek gönderime iner.
  - Push yalnızca okuduğu kayıtları siler. Böylece gönderim sırasında gelen yeni yazmalar kaybolmaz.
  - Gönderilemeyenler üstel geri çekilmeyle tekrar denenir.
- **`sync_state`:** profil başına son `server_seq` imleci (`last_server_seq`) ve son başarılı senkron (`last_sync_at`).
- **`sessions` (F1-18):** Kart oturumu bitince ya da bırakılınca tek satır yazılır. Satır olaydır: outbox'ta `insert` olarak durur. En az bir kart kaydedilmediyse satır yazılmaz.
  - `strand_ms` anahtarları `Strand.code`'dur. `active_ms` kol sürelerinin toplamıdır; kart başına en çok 3 dk sayılır.
  - `planned` = `{reviews, new, estimate_ms}`, `done` = `{reviewed, introduced}`.
  - Bugün ekranı günün süresini ve haftanın çalışılan günlerini buradan okur. Gün yerel gece yarısında, hafta pazartesi başlar.
- **Konuşma görevleri (F1-19):**
  - **`recordings`:** Kayıt biter bitmez satır açılır. `audio_path`, cihazdaki dosyadır (uygulama destek klasöründe `recordings/<id>.m4a`); `audio-private`'a yükleme senkronla gelir (F1-21).
    - Sonra sırayla dolar: `asr` (`{provider, model, words: [{w, start_ms, end_ms, conf}]}`), `annotation` (`{runs: [rota cevabı], merged: işaretleme}`), `outcome`, `metrics` (`SpeechMetrics`) ve en son `attempt_id`.
    - Durum satırıdır: her değişiklik outbox'a `upsert` olarak düşer.
  - **`attempts`:** Görev denemesinde:
    - `prompt` = `{prompt_l1}`, `response` = `{source: 'asr', recording_id, text?, asr?: {provider, model}}`
    - `error_tags` işaretlemedeki etiketlerdir, her biri bir kez. `duration_ms` kaydın süresidir.
    - `llm` = `{route: 'speaking_annotate', pending, provider?, model?, catalog?, code?}`
  - **Pratik denemeleri:** `prompt` = `{original, reference, tag}`, `response` = `{text, source}`. Önceki denemeye `parent_attempt_id` ile bağlıdır.
  - **`personal_items`:** `source = speaking_task`.
- **`devices`:** bu kurulumun kimliği. Profil başına ilk kullanımda bir satır açılır; her deneme onu `device_id` olarak taşır. Sütunlar sunucudaki `devices` ile aynıdır (§2.6), senkronu F1-21'de.
- **İçerik tabloları:** `content_packs`, `content_items`, `content_links`, `content_forms`, `content_texts`, `content_tasks`, `content_pair_entries` (karşılık, karşıtlık notu, hata etiketi, varyant, can-do özeti, görev yönergesi, öğrenme notu). Salt okunurdur ve paket SQLite dosyasından atomik olarak aktarılır (`11` §5). `content_packs.manifest`, paketin `pack_meta` tablosunun tamamıdır. Türe özgü alanlar `data` JSON sütunundadır, böylece paket biçimine eklemeler migrasyon gerektirmez.
- **Türetilmiş önbellekler** (`model_snapshot`, `coverage_cache`): motorun ara sonuçları. Silinirse yeniden hesaplanır. İlk ihtiyaç duyan görevde eklenir.
- **drift migrasyonları** şema sürümüyle ilerler. Her sürüm artışında `dart run drift_dev make-migrations` çalıştırılır: anlık görüntü `app/drift_schemas/` altına, doğrulama yardımcıları `app/test/drift/` altına üretilir ve her geçiş için bir yükseltme testi yazılır. `migration_test.dart`, koddaki şemanın dışa aktarılan son anlık görüntüyle aynı olduğunu denetler.
