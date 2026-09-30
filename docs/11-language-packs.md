# 11 — Dil Paketleri ve Dilden Bağımsızlık

Motor (`dilbaz_engine`) hiçbir dili bilmez (I-15). Dile özgü her şey paketlerden gelir. Bu doküman paket türlerini, formatını, yükleme sürecini ve yeni dil ekleme adımlarını tanımlar.

## 1. Paket türleri

| Tür | Kimlik | İçerik | Kime bağlı |
|---|---|---|---|
| **Hedef dil paketi** | `en@1` | Sözlük, öğeler, bağlar, metinler, görevler, can-do kodları, seviye testi bankası, ses listesi, normalizasyon ve biçim tabloları | Yalnızca öğrenilen dile (L2) |
| **Dil çifti paketi** | `tr-en@1` | Karşılıklar, açıklamalar, hata etiketi kataloğu, karşıtlık notları, can-do özetleri, görev yönergeleri, öğrenme notu şablonları | Anadil (L1) + öğrenilen dil |
| **Arayüz dili** | Flutter ARB (`app_tr.arb`) | Uygulama metinleri | Yalnızca anadil. Paket değil, uygulamanın parçası. |

## 2. Kaynak dizin yapısı

```text
content/packs/en/
  manifest.yaml
  lexicon.jsonl            # lemma, rank, levels, pos, ipa, senses
  forms.jsonl              # yüzey biçim → lemma(lar)   (çalışma zamanı lemmatizasyonu için)
  normalization.yaml       # kısaltmalar, yazım varyantları, sayı sözcükleri, noktalama kuralları
  items/
    word_senses.jsonl
    chunks.jsonl
    sentences.jsonl
    grammar_points.jsonl
    sounds.jsonl           # ses karşıtlıkları + minimal çift kelimeleri
    patterns.jsonl
  links.jsonl              # requires / contains / contrasts_with / supports / variant_of / example_of
  texts.jsonl              # okuma/dinleme metinleri + lemma listeleri + sorular
  dialogues.jsonl
  tasks.jsonl              # konuşma, rol, bilgi boşluğu (role_a/role_b), yazma, aracılık
  can_dos.jsonl            # kod, seviye, ölçek (metin yok; özetler çift paketinde)
  grammar_codes.jsonl      # kapalı gramer kodu listesi (LLM kataloğu)
  connectors.jsonl         # bağlaç listesi (karmaşıklık ölçümü)
  fillers.jsonl            # dolgu sözcükleri (akıcılık ölçümü)
  placement/xlex.jsonl     # version (A/B/C), band (1–5; uydurma kelimede null), word, is_pseudo
  voices.yaml              # TTS ses kimlikleri, yerel ayar, cinsiyet, motor (en@1: Kokoro), ses çiftleri, yavaş hız
  audio.jsonl              # öğe başına klip: key, voice, speed, file (pack-audio'da <ses>/<karma>.mp3), duration_ms
  LICENSES.md

content/packs/tr-en/
  manifest.yaml
  glosses.jsonl            # item_key → meaning, explanation, usage_note, context (cümle/kalıp istemi)
  contrast_notes.jsonl
  error_tags.jsonl         # code, category, severity, description, examples, grammar_codes, pron_map
  variants.jsonl           # item_key → varyantlar (hedefi söyleyen doğru cevaplar) ve alternatifler (hedefsiz doğru cevaplar, `03` §0.2)
  rule_notes.jsonl         # gramer kodu → H3 kural notu (cevabı içermez, I-02)
  can_do_summaries.jsonl
  task_instructions.jsonl
  learning_notes.jsonl     # A25 şablonları
  LICENSES.md
```

## 3. Manifest

```yaml
id: en@1
kind: target               # target | pair
l2: en
l1: null                   # pair paketinde: tr
version: 1                 # tam sayı; yamalar 1.1, 1.2 …
min_engine_version: 1
level_scheme: CEFR
script: { direction: ltr, word_separator: space }   # Çince/Japonca: none
tokenizer: { build_time: "spacy:en_core_web_md", runtime: "forms_table" }
fsrs_defaults: null        # null → paket kütüphanesinin varsayılanları
counts: { word_senses: 612, sentences: 604, chunks: 120, grammar_points: 40, tasks: 23 }
sources:
  - { name: NGSL, version: "1.2", license: "CC BY-SA 4.0", attribution: "Browne, Culligan & Phillips" }
  - { name: CEFR-J Wordlist, version: "1.6", license: "free with citation", attribution: "Tono Lab, TUFS" }
checksum: sha256:…
created_at: 2026-10-…
```

## 4. Öğe biçimleri (örnekler)

```jsonc
// items/sentences.jsonl
{ "key": "en.sent.i_am_going_home", "text": "I'm going home.", "cefr": "A1",
  "lemmas": ["i","be","go","home"], "targets": ["en.chunk.go_home"],
  "grammar": ["gp.present_continuous.now"], "audio": ["v1","v3"], "source": "llm", "license": "own" }

// items/word_senses.jsonl
{ "key": "en.ws.watch.v.1", "lemma": "watch", "pos": "VERB", "sense": "look at for a time",
  "cefr": "A1", "rank": 412, "ipa": "/wɒtʃ/", "carriers": ["en.sent.we_watch_tv"] }

// links.jsonl
{ "from": "en.ws.say.v.1", "to": "en.ws.tell.v.1", "type": "contrasts_with" }

// tr-en/glosses.jsonl
{ "key": "en.chunk.go_home", "meaning": "eve gitmek",
  "explanation": "home'dan önce 'to' gelmez: go home.",
  "usage_note": "house = bina, home = yuva/ev hissi" }
{ "key": "en.sent.do_you_have_a_room", "meaning": "Odanız var mı?", "context": "otelde",
  "provenance": { "source": "dilbaz curation", "license": "own" } }

// tr-en/variants.jsonl: normalizasyondan sonra referanstan farklı cevaplar.
// variants hedef kelimeyi içerir; alternatives içermez: doğru sayılır, hedef için yeniden sorulur.
// Listeler cümlenin seçilmiş hedeflerine göre yazılır; motor ayrımı kartın hedefine göre yeniden yapar (`03` §0.5).
{ "key": "en.sent.i_have_a_job", "variants": ["I've got a job."], "provenance": { … } }
{ "key": "en.sent.here_s_a_present_for_you", "variants": ["This is a present for you."],
  "alternatives": ["Here's a gift for you."], "provenance": { … } }

// tr-en/rule_notes.jsonl
{ "code": "gp.be.present", "note": "Cümlede be olmalı: I ile am, he/she/it ile is, you/we/they ile are.",
  "provenance": { … } }

// tr-en/contrast_notes.jsonl
{ "items": ["en.ws.say.v.1", "en.ws.tell.v.1"],
  "note": "İkisi de söylemek: tell'den sonra kişi gelir (tell him), say'den sonra söz gelir (say yes, say it to him).",
  "provenance": { … } }

// tr-en/error_tags.jsonl
{ "code": "art.missing", "category": "grammar", "severity": 1.0,
  "description": "Tekil sayılabilir isimden önce a/an/the eksik.",
  "examples": ["I have problem → I have a problem"], "grammar_codes": ["gp.articles.a_an"] }
{ "code": "phon.th", "category": "pronunciation", "severity": 0.3,
  "description": "th sesleri /θ/ ve /ð/ yerine t, d, s ya da z söylenmiş.",
  "examples": ["tink → think", "dis → this", "tree (three demek istenirken) → three"],
  "pron_map": { "θ": "t", "ð": "d" } }   // beklenen ses → yerine söylenen
```

**Anahtar kuralları:**
- Anahtar `{l2}.{tür}.{kimlik}` biçimindedir ve **asla değişmez**.
- Kaldırılan öğe `deprecated: true` olur. Kartlar askıya alınır, geçmiş korunur.

## 5. Derleme ve dağıtım

- `dilbaz-content build` her paket sürümü için tek bir **SQLite dosyası** üretir (`en@1.sqlite`, `tr-en@1.sqlite`). Ses dosyaları ayrıca `pack-audio/` altındadır.
- Yanında `<id>.manifest.json` (manifest + sayılar + dosyanın `checksum`'ı) ve `<id>.LICENSES.md` bulunur.
- Supabase Storage `packs/` bucket'ına yüklenir. `packs` tablosunda `published` olarak kaydedilir.
- **Uygulama tarafı** (F1-11; `PackRepository`, `PackImporter`, `ContentController`):
  1. **Yerel öncelikli açılış:** Cihazda kursun iki paketi de varsa içerik hemen hazırdır; kayıt defteri arka planda sorulur. Yalnızca ilk indirme beklenir ("İçerik indiriliyor…").
  2. **Seçim:** Kursun hedef paketi (`kind=target`, `l2`) ve çift paketi (`kind=pair`, `l1`–`l2`) için yayımlanmış en yüksek sürüm alınır. Cihazdaki paketin kimliği ve sağlama toplamı aynıysa indirilmez; aynı kimlikle yeniden derlenmiş paket (toplam farklı) yeniden indirilir.
  3. **Doğrulama:** dosyanın sha256'sı kayıt defterindekiyle aynı olmalı. Dosya açılınca biçim sürümü (`PRAGMA user_version`), manifestteki kimlik, `min_engine_version` ve hedef pakette normalizasyon örnekleri (uygulamadaki motorla çalıştırılır) kontrol edilir.
  4. **Atomik aktarım:** Dosya yerel veritabanına `ATTACH` edilir. Tek işlemde aynı ailenin (tür + diller) eski satırları silinir ve paket satırları olduğu gibi kopyalanır; hata olursa eski içerik yerinde kalır. `content_packs.manifest`, paketin `pack_meta` tablosunun tamamını tutar (manifest, normalizasyon, sesler).
  5. **Hatalar** sakin bir metin ve "Yeniden dene" ile gösterilir: bağlantı yok, paket yayımlanmamış, dosya bozuk, uygulama eski. Cihazda içerik varken güncelleme hatası kullanıcıya gösterilmez.
  6. **Web:** Dosya sistemi olmadığı için aktarım henüz yok (`unsupported`); Faz 1 hedefi Android'dir.
- **Sözleşme testi:** S9'un oluşturduğu tablolar, uygulamanın drift şema anlık görüntüsündeki `content_*` tablolarıyla aynı sütunlara sahip olmalıdır (`content/tools/tests/test_build_step.py`).
- Ses dosyaları ilk kullanımda indirilir ve önbelleğe alınır. İsteğe bağlı "seviyemin seslerini önceden indir" (çevrimdışı hazırlık).

### 5.1 Paket dosyası (SQLite, biçim sürümü 1)

- Tablolar uygulamanın drift içerik tablolarıyla aynı ad ve sütunlardadır (`13`, `app/lib/data/db/tables/content_tables.dart`). İçe aktarma satırları olduğu gibi kopyalar.
- Biçim sürümü `PRAGMA user_version` değeridir. Tablolar değişince artar; uygulama tanımadığı sürümü reddeder.
- JSON sütunları metindir: `lemmas`, `targets`, `grammar`, `data`.
- **`pack_meta`** (`key` → JSON değer):
  - `format_version`
  - `manifest`: `manifest.yaml` + `counts`
  - Hedef pakette ayrıca: `normalization` (`normalization.yaml`), `voices` (`voices.yaml`), `audio` (`{"bucket": "pack-audio", "prefix": "en/1/"}`)
- **Hedef paket** (`en@1.sqlite`):
  - `content_items`, `kind`'e göre:

    | kind | text_l2 | data |
    |---|---|---|
    | `word_sense` | lemma | `pos`, `sense`, `ipa_us`, `ipa_uk`, `carriers`, `audio`, `provenance` |
    | `chunk` | kalıp | `function`, `note`, `audio`, `provenance`. `rank` sütunu dolu: kalıbın müfredattaki yeri (aşağıda). |
    | `sentence` | cümle | `audio`, `provenance`. `targets` ve `grammar` sütunları dolu. |
    | `grammar_point` | İngilizce ad | `code`, `description`, `examples`, `provenance` |
    | `lemma` | yazılışı | `pos`, `ipa_us`, `ipa_uk`. Kişisel kapsama (I-06) ve X_Lex bantları için sözlük; anahtar `en.lemma.<lemma>`. |
    | `xlex` | kelime | `version`, `band`, `is_pseudo`. Anahtar `en.xlex.<sürüm>.<kelime>`; gerçek kelimede `rank` dolu. |

  - **Kalıp sırası (`rank`):** Kalıbın kendi sıklığı yoktur; müfredat yeni öğeleri seviye ve sıklık sırasına göre dizer (`02` §4.3). Sırasız kalsalar kalıplar tek blok hâlinde gelir. Bu yüzden her seviyenin kalıpları, sohbet çantasındaki sıralarıyla, o seviyedeki kelime anlamlarının sıklık sıralarına eşit aralıklarla yerleştirilir (S9). `en@1`'de A0 için sonuç: Hello, have, do, get, Hi, like, just, go, Good morning…
  - `audio`: `[{voice, speed, file, duration_ms}]`. Dosyanın yolu `pack-audio/<prefix><file>`'dır.
  - `content_links`:
    - `contains`: cümle → hedef anlam
    - `example_of`: cümle → gramer noktası
  - `content_forms`: biçim → lemma. Her lemma, yazım varyantları ve çekimli biçimleri S1 sözlüğünden gelir.
  - `content_texts`, `content_tasks`: en@1'de boş.
- **Çift paketi** (`tr-en@1.sqlite`):
  - `content_pair_entries`, `kind`'e göre:
    - `gloss` (anahtar: öğe)
    - `variants` (anahtar: öğe; `variants`, `alternatives`)
    - `rule_note` (anahtar: gramer kodu)
    - `contrast_note` (anahtar: öğeler `|` ile)
    - `error_tag` (anahtar: kod)
  - `content_links`: karşıtlık notlarından `contrasts_with`. Bağ simetriktir, küçük anahtar `from_key`'dedir. Karşıtlıklar anadile göre değiştiği için çift paketindedir.

## 6. Motorun dile özgü işlemleri: veri ile çözmek

Motor, dile özgü işlemleri **kod yazmadan, paket verisiyle** yapar:

```dart
/// Paket verisinden kurulan, dilden bağımsız servisler.
abstract interface class LanguageServices {
  String normalize(String text);              // normalization.yaml kuralları
  List<String> tokenize(String text);         // script.word_separator + noktalama kuralları
  Set<String> lemmasOf(String token);         // forms tablosu; yoksa {token}
  double coverage(Iterable<String> lemmas, KnownLemmaModel known); // I-06
}
```

- **Durum (F1-07):** `normalize`, `tokenize` ve `lemmasOf` motorda hazır (`PackLanguage`: paketin normalizasyon kuralları, kelime ayırıcısı ve `forms` tablosu). `coverage` öğrenci modelindedir: `LemmaKnowledge.coverage` (F1-08; `06` §2).
- **Kelime ayırıcı:** `script.word_separator` tek karakterdir (`space` → boşluk). Normalizer ve hizalama bu karakterle çalışır; motor testleri boşluksuz bir ayırıcıyla da koşar.

- **`forms` tablosu:** Derleme zamanında spaCy/Stanza ile geniş bir kelime listesinin çekimli biçimlerinden üretilir (go/goes/went/gone → go).
- **Sondan eklemeli diller:** Türkçe ya da Fince hedef dil olursa biçim tablosu çok büyür. Manifest `tokenizer.runtime: "remote"` diyebilir; o zaman lemmatizasyon bir sunucu fonksiyonuyla (Stanza) yapılır. Bu genişleme noktası baştan tanımlıdır, ama ilk sürümde uygulanmaz.
- **Normalizasyon kuralları veridir:** Kısaltma açma (I'm → I am), yazım varyantları (colour/color) ve sayı sözcükleri (2 → two) `normalization.yaml`'da tanımlıdır, kodda değil. Dosyanın `tests` bölümündeki örnekleri hem motor hem içerik araçları (S5 varyant kontrolü) geçmelidir.

## 7. Dilden bağımsızlığı zorunlu kılan kontroller

1. **Paket sınırı:** `dilbaz_engine` paketi `app/`, `content/` ya da herhangi bir dil verisini içe aktaramaz. `dependency_validator`/import kontrol testi bunu doğrular.
2. **Sentetik dil testi:** Motorun tüm birim testleri, rastgele üretilmiş anlamsız kelimelerden oluşan sentetik bir dil paketiyle (`zz`) çalışır. İngilizceye özgü bir varsayım (ör. boşlukla ayrılmış kelime, "the") bu testlerde kırılır.
3. **Metin taraması:** Motor kaynak kodunda doğal dil metni (İngilizce ya da Türkçe cümle/kelime) bulunmaz. Kullanıcıya gösterilen tüm metinler ARB'den ya da paketten gelir. Bir test, `packages/engine/lib` altındaki dize sabitlerini izin listesine (tanımlayıcılar, log anahtarları) karşı kontrol eder.
4. **Kanıt paketi (Faz 7):** `de@0` + `tr-de@0`. Yalnızca paket ekleyerek küçük bir Almanca A1 setinin uçtan uca çalıştığı gösterilir.

## 8. Yeni dil ekleme kontrol listesi

1. **Seviye ve sıklık kaynakları:** Varsa Avrupa Konseyi'nin dil bazlı seviye tanımları (RLD: Almanca, Fransızca, İspanyolca, İtalyanca, Portekizce, Çekçe, Hırvatça); açık lisanslı sıklık listesi (ör. wordfreq verisi, altyazı korpusları).
2. **Belirteçleyici/lemmatizer seçimi:** spaCy ya da Stanza. `forms` tablosu mu, uzak lemmatizasyon mu?
3. `normalization.yaml`: kısaltmalar, yazım varyantları, sayılar.
4. **Ses:** TTS sesleri (≥ 4, farklı bölgeler); telaffuz değerlendirmesi yerel ayar desteği; öncelikli ses karşıtlıkları (L1'e göre).
5. **Gramer ilerlemesi** (dilin RLD'sine göre) ve kapalı gramer kodu listesi.
6. **Her anadil için çift paketi:** karşılıklar, açıklamalar, hata etiketi kataloğu (o L1'in tipik hataları), karşıtlık notları, görev yönergeleri.
7. **ASR karşılaştırma testi** o dil için (`08` §3.2 yöntemiyle).
8. Arayüz dili yeni bir anadilse yeni ARB dosyası.
9. Sentetik dil testleri + yeni paketle uçtan uca test.
