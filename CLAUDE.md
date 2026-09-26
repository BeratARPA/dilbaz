# Dilbaz — Claude Code çalışma talimatı

## Proje
Dilbaz, bir dili **sıfırdan (A0) ileri seviyeye (C1–C2) gerçekten öğreten**, her kararı öğrenme bilimi ve ikinci dil edinimi araştırmasına dayanan kişisel bir öğrenme sistemidir.
- **Dil çifti:** Türkçe konuşanlar için İngilizce (`l1=tr`, `l2=en`). Motor dilden bağımsızdır.
- **Kullanıcılar:** Berat ve sevgilisi (ikisi de ~A1–A2, hedef 12 ayda B1 konuşma).
- **Platform:** Android (öncelik), Windows, web.
- **Kısıtlar:** Günde en fazla 30 dk ve **iş gibi hissettirmeyecek**.
- **Yığın:** Flutter + saf Dart motor + Supabase + Claude API + Deepgram/Azure ses.

## Her oturumun başında
1. `docs/17-roadmap.md` → mevcut faz, ilk işaretlenmemiş görev, alttaki ilerleme günlüğü.
2. Görevin gerektirdiği dokümanlar (harita: `docs/00-overview.md` §7). Pedagojiye dokunan her işte `docs/01-pedagogy.md` §3'teki kurallar.
3. `git status` ve `git log --oneline -10`.
4. Görev bitince: "tamamlandı" tanımı (aşağıda) → roadmap kutusunu işaretle → günlüğe satır ekle → commit.

## Değişmez kurallar (ayrıntı: docs/01-pedagogy.md §3)
- **I-01** Öğrenci denemeden doğru cevap gösterilmez. İstisnalar: yeni öğe tanıtımı ve Söyleyemediklerim önerisi.
- **I-02** Hata olursa ipucu merdiveni (H1 tür → H2 yer → H3 kural → H4 cevap). Konuşma/akıcılık görevlerinde geri bildirim görev sonunda, en fazla 3 düzeltme.
- **I-03** Her deneme `attempts`'e değiştirilemez olarak yazılır. Kart durumu denemelerden yeniden hesaplanabilir.
- **I-04** Uydurma yüzde yok. İlerleme yalnızca kanıt kurallarıyla (`04`). Belirsizlik aralık ve güvenle gösterilir.
- **I-05** Varsayılan cevap biçimi **sesli üretim**. Tanıma, üretim kanıtı sayılmaz.
- **I-06** Okuma/dinleme metninin kişisel kapsaması < %95 ise önerilmez. %95–98 ise önce ön öğretim.
- **I-07** Yeni öğe sayısı tekrar yükünü tavanın altında tutar.
- **I-08** Tekrar zamanlarını yalnızca FSRS belirler.
- **I-09** İskeleler seviyeyle azalır (`02` §3).
- **I-10** Karışan öğeler, ilk öğrenmeden sonra karışık çalıştırılır.
- **I-11** LLM düşünmeyi devralmaz: cevapsız çağrı yok, kapalı etiket listesi, emin değilse `uncertain`.
- **I-12** Suçluluk yok: "kaçırıldı", seri, kota, kırmızı uyarı yok. Yasak kelime testi ARB'yi tarar.
- **I-13** Planlayıcı zaman bütçesini (varsayılan 30 dk) aşmaz.
- **I-14** Planlayıcı önerir, kullanıcı seçer (≥ 2 seçenek). Hiçbir şey zorunlu değil.
- **I-15** `packages/engine` içinde dile özgü kelime/kural/liste/metin yok. Testler sentetik dil `zz` ile.
- **I-16** Pakete giren her öğe doğrulanmış, kaynağı ve lisansı kayıtlı.
- **I-17** Doğru cevabın geçerli varyantları kabul edilir.
- **I-18** Ses ve ayrıntılı veri yalnızca sahibine açık. Partner yalnızca özet görür.

Bir kuralı değiştirmek gerekirse **önce** `docs/01-pedagogy.md`'yi gerekçesiyle güncelle ve kullanıcıya sor; sonra kodu değiştir.

## Mimari kurallar
- **Katmanlar:** UI (widget) → controller (Riverpod) → `dilbaz_engine` (saf Dart) → repository (drift + Supabase). Widget'ta iş mantığı yok. Pedagojik kararlar yalnızca motorda.
- **Yerel öncelikli:** Arayüz drift'ten beslenir. Yazmalar aynı işlemde outbox'a da düşer. Olaylar değiştirilemez ve idempotenttir (`docs/12` §6, `docs/13`).
- **Kimlik ve zaman:** UUIDv7, tüm zamanlar UTC.
- **Anahtarlar:** Gizli anahtarlar yalnızca Supabase secrets'ta. Uygulamada yalnızca URL + publishable key.
- **Veritabanı:** Her tabloda RLS açık ve varsayılan-red. Yeni tablo = yeni pgTAP testi.
- **İçerik:** Paketler versiyonlu SQLite dosyalarıdır. Postgres yalnızca kullanıcı verisini tutar.
- **FSRS:** Yalnızca motorda, `import 'package:fsrs/fsrs.dart' as fsrs;` (önek zorunlu). `reviewDateTime` UTC. Sonuç `card_state_after` olarak saklanır.
- **Mimari kararlar:** Değişiklik yeni bir ADR (`docs/adr/`) ile yapılır.

## Teknoloji yığını (2026-09-25'te doğrulandı; ayrıntı `docs/12` §4)
- **Flutter / Dart:** 3.47.x / 3.13.x
- **Uygulama paketleri:**
  - flutter_riverpod 3 + riverpod_generator
  - go_router 18
  - freezed 4, json_serializable
  - drift 2.35 + drift_flutter (`sqlite3_flutter_libs` **ekleme**)
  - supabase_flutter 2.x (3.x ön sürümünü kullanma)
  - fsrs 2.0.1
  - record 7 (Windows'ta Opus yok)
  - just_audio (+ just_audio_media_kit Windows için)
  - uuid (v7), fl_chart, flutter_local_notifications, share_handler, home_widget
- **Sunucu:** Supabase: Postgres, Auth (e-posta OTP), Storage, Edge Functions (Deno 2, `npm:` içe aktarma), Realtime, pg_cron.
- **Araçlar:** Python ≥ 3.12 + uv + spaCy 3.8, py-fsrs (optimizer).
- **Sürüm kontrolü:** Yeni bağımlılık eklemeden ya da sürüm yükseltmeden önce pub.dev / npm / PyPI'da güncel kararlı sürümü kontrol et. Kitaplık API'si için **context7 MCP** (`resolve-library-id`, `query-docs`) kullan. Hafızadan API yazma.

## Komutlar
```bash
# Motor (saf Dart)
cd packages/engine && dart pub get && dart run build_runner build && dart analyze --fatal-infos && dart test --coverage-path=coverage/lcov.info && dart run tool/check_coverage.dart

# Uygulama
cd app && flutter pub get && dart run build_runner build && flutter analyze && flutter test
cd app && flutter run -d <cihaz> --dart-define-from-file=env/local.json
cd app && flutter build apk --release --dart-define-from-file=env/prod.json

# Supabase (yerel; Docker Desktop açık olmalı)
npx supabase start | npx supabase stop
npx supabase migration new <ad> && npx supabase db reset && npx supabase test db
npx supabase functions serve
cd supabase/functions && deno test -A && deno lint && deno fmt --check

# İçerik araçları
cd content/tools && uv sync && uv run dilbaz-content --help && uv run pytest && uv run ruff check .

# LLM eval (ÜCRETLİ; kullanıcı onayıyla)
deno run -A evals/run.ts --route answer_check
```

## Kod kuralları
- **Dil:** Kod, tanımlayıcılar, kod yorumları ve commit mesajları **İngilizce**. Dokümanlar (`docs/`) **Türkçe**. Kullanıcıya görünen metinler **yalnızca** `app/lib/l10n/app_tr.arb` üzerinden; metin dili `docs/09-ux-motivation.md` §2.
- **Dart:** `very_good_analysis`, analiz uyarısı = hata. freezed ile değişmez modeller. Beklenen hatalar `sealed Result`. `dynamic` kullanılmaz. Genel `catch` yok. Dosya başına bir sorumluluk.
  - Dart 3.13 yapıcı sözdizimi (lint zorunlu kılar): `new(this.x)`, `new named()`, `factory fromJson(...)`, freezed'de `const factory ({...}) = _X;`. Enum yapıcısında `const` yazılmaz.
  - Üretilmiş dosyalar (`*.g.dart`, `*.freezed.dart`) git dışıdır; `build_runner build` ile üretilir (`-d` bayrağı build_runner 2.16'da kaldırıldı).
- **Özellik klasörü:** `features/<ad>/{presentation,application}/`. Paylaşılan veri erişimi `data/repositories/`.
- **Supabase SQL:** Her migrasyon geri alınamaz kabul edilir. Veri kaybettiren değişiklik yeni migrasyonla ve kullanıcı onayıyla yapılır.
- **Edge Functions:** Yapılandırma tek yerde (`_shared/llm_config.ts`, `_shared/speech_config.ts`). Sağlayıcılar adaptör arkasında. Loglarda transkript ya da kişisel metin yok.
- **Python:** `ruff` + tip ipuçları + `pydantic` şemaları. LLM çıktıları önbelleğe alınır.
- **Kapsam dışı yazma:** Görev dışı düzenleme, gereksiz soyutlama, konuşma dışı yorum ekleme yok. Mevcut kodun üslubuna uy.

## Claude API (uygulamanın kendi LLM kullanımı)
- LLM ile ilgili herhangi bir kodu yazmadan ya da değiştirmeden önce **`claude-api` skill'ini yükle.** Güncel API biçimleri oradadır: yapılandırılmış çıktı (`output_config.format`), effort, önbellek, Batch, reddetme yedeklemesi.
- **Varsayılan model:** `claude-opus-5` (`docs/07` §2). Model değişikliği yalnızca kullanıcı kararıyla ve eval sonuçlarıyla yapılır.
- **Prompt ya da model değişikliği → eval zorunlu** (`docs/07` §8). Eval ücretlidir, çalıştırmadan önce kullanıcıya tahmini maliyeti söyle.

## Test ve "tamamlandı" tanımı (ayrıntı: `docs/15-testing.md`)
Bir görev ancak şu koşullar sağlanınca tamamlanmış sayılır:
1. Analiz uyarısız, format temiz.
2. Testler yazıldı ve geçiyor (motorda satır kapsamı ≥ %90). İlgili değişmez kural testleri güncel.
3. Arayüz metinleri ARB'de, yasak kelime testi geçiyor.
4. Etkilenen dokümanlar güncellendi. Karar değiştiyse ADR yazıldı.
5. `docs/17-roadmap.md` kutusu işaretlendi, günlüğe satır eklendi.
6. Commit atıldı.

## Git
- **Dallar:** Faz başına dal (`faz-0`, `faz-1`, …). Her görev en az bir commit. Faz kabul kriterleri sağlanınca `main`'e `--no-ff` birleştirme ve kısa faz raporu (`docs/17` günlüğü).
- **Commit mesajı:** Konvansiyonel ve İngilizce (`feat(engine): …`, `fix(app): …`, `test: …`, `docs: …`, `chore: …`). Sonuna Claude Code'un o oturumda verdiği atıf satırını ekle.
- **Push:** Kullanıcı remote verdikten sonra faz sonlarında yapılır. **İlk push'tan önce bir kez onay al.**
- **Asla commit edilmeyecekler:** `env/*.json`, `supabase/functions/.env`, keystore, ses verisi, `content/{sources,work,build}`. Commit öncesi gizli anahtar taraması yapılır.

## Kullanıcıya ne zaman sorulur / ne yapılmaz
Şu durumlarda **dur ve sor**, `docs/19-setup.md`'deki ilgili bölümü göster:
- Hesap açma, API anahtarı oluşturma ya da girme, ödeme/harcama limiti.
- Sistem veya güvenlik ayarı (Windows Geliştirici Modu vb.). Sisteme araç kurulumu gerekiyorsa komutu öner, onay al.
- Üretime migrasyon (`supabase db push`), paket yükleme (`upload`), web yayını, veri silme.
- Ücretli toplu işler: eval, Batch içerik üretimi, TTS paket üretimi. Önce tahmini maliyeti söyle.
- Değişmez bir kuralı esnetmek, varsayılan modeli değiştirmek, yeni ücretli sağlayıcı eklemek.
- İnsan girdisi gereken işler: içerik örneklem incelemesi, ASR veri seti kaydı.

Asla yapma:
- API anahtarını koda, loga, commit'e ya da sohbete yazmak.
- Kullanıcı adına hesap açmak.
- Testleri geçirmek için testi zayıflatmak.
- Onaysız `--force` push etmek ya da geçmişi yeniden yazmak.

Kararı kod ya da dokümanlar veriyorsa sorma, uygula ve raporla.

## Kullanıcıyla iletişim
- **Türkçe**, kısa ve net: ne yapıldı, ne test edildi, sırada ne var, senden ne gerekiyor.
- Başarısız test ya da atlanan adım varsa açıkça söyle.
- Kullanıcı yazılımcı. Teknik terim kullanılabilir, ama gereksiz jargon yok.
