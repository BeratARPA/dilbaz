# 10 — İçerik Hattı

Dil paketlerini (kelimeler, kalıplar, cümleler, gramer noktaları, sesler, metinler, görevler, testler) üreten, doğrulayan ve yayınlayan çevrimdışı araç zinciri. Kod: `content/tools/` (Python). Paket formatı: `11-language-packs.md`.

## 1. İlkeler

1. **Açık lisanslı kaynak + kendi üretimimiz.** Lisansı belirsiz veri pakete girmez (I-16).
2. **Her öğenin kaynağı kayıtlıdır:** `source`, `license`, `attribution` alanları.
3. **Otomatik kontroller önce, insan kontrolü örneklemle.** Her üretim partisinden rastgele 20 öğe kullanıcıya gösterilir.
4. **Seviye disiplini:** Bir seviyenin cümlesi, hedef öğe dışında yalnızca o seviye ve altındaki lemmaları içerir.
5. **Tekrarlanabilirlik:** Her adımın girdisi ve çıktısı dosyadır. Adımlar yeniden çalıştırılabilir. LLM ile üretilen içerik (Claude Code oturumları, ADR-0009) dosyada saklanır; yeniden üretim gerekmez.

## 2. Kaynaklar ve lisanslar (2026-09-25'te doğrulandı)

| Kaynak | Ne için | Lisans | Not |
|---|---|---|---|
| **NGSL 1.2** (2.809 kelime) | Çekirdek sıklık listesi | CC BY-SA 4.0 | Genel İngilizcenin %92+'sı. Yalnızca sıra listesi (`*_stats.csv`) kullanılır. Lemmatize listeler "isn", "gettin" gibi belirteç parçaları içerdiği için biçimler Wiktionary'den alınır. |
| **NGSL-Spoken 1.2** (721 kelime) | Sohbet çantası önceliği | CC BY-SA 4.0 | Hazırlıksız konuşmanın ~%90'ı. İstatistik dosyasında "true" satırı bozuk (`TRUE,#N/A,…`); lemma üye sayılır, sırası boş kalır. |
| **CEFR-J Wordlist v1.5** (+ Grammar Profile 20180315) | A1–B2 seviye etiketleri | Araştırma, eğitim ve ticari kullanım serbest; belirtilen atıfla | © Tono Lab, TUFS. v1.6 yalnızca istek formuyla veriliyor; aynı koşullarla yayımlanan v1.5 Open Language Profiles'tan alınır. |
| **Octanove Vocabulary Profile C1/C2** | C1–C2 seviye etiketleri | CC BY-SA 4.0 | |
| **wordfreq 3.1.1** | Sıklık sıraları (SUBTLEX dahil) | Kod Apache-2.0, veri CC BY-SA 4.0 | Veri ~2021'de dondu, güncellenmeyecek. SUBTLEX için yazarlara atıf. |
| **Tatoeba** | Aday taşıyıcı cümleler, EN–TR çiftleri (~523K) | Cümleler CC BY 2.0 FR (bir kısmı CC0) | Cümle ve yazar kimliği saklanır. Ses lisansları katkıcıya göre değişir; boş lisanslı ses kullanılmaz. |
| **CMU Pronouncing Dictionary** | Telaffuz, vurgu, minimal çift bulma | BSD 2-clause | Amerikan İngilizcesi |
| **Wiktionary (Wiktextract/kaikki)** | IPA, anlamlar, sözcük türü | CC BY-SA 4.0 + GFDL | Anlam ayrımı için referans |
| **CEFR Companion Volume (2020)** | Can-do tanımları | © Council of Europe, açık lisans yok | Pakete **yalnızca kod + kendi kısa özetimiz** girer. Tam metin kopyalanmaz. |
| **English Vocabulary/Grammar Profile** | Seviye kontrolü | © CUP; yalnızca kişisel, ticari olmayan araştırma/öğretim; toplu indirme yok | **Pakete girmez.** Yalnızca elle referans. |
| **LLM üretimi (Claude Code oturumları)** | Cümle, açıklama, varyant, metin, görev | Kendi içeriğimiz | Ayrı oturumda doğrulama + insan örneklemi (ADR-0009) |
| **Kokoro-82M** | Paket sesleri (S6) | Model Apache-2.0; üretilen ses kendi içeriğimiz | Çevrimdışı, içerik makinesinde |
| **Kullanıcı içeriği** | Söyleyemediklerim, altyazı, düzeltmeler | Kişisel | Pakete girmez; kişisel öğe olarak senkronlanır |

**Kaynak kaydı:** `content/sources.yaml` her kaynağın URL'sini, sürümünü, lisansını ve atfını tutar. Sabit dosyalar sha256 ile sabitlenir; üstteki dosya değişirse `ingest` durur ve inceleme ister. Haftalık dökümler (Tatoeba, Wiktextract) indirme tarihine göre anlık görüntü olarak saklanır; sağlama toplamları `SNAPSHOT.json`'dadır.

**ShareAlike notu:** NGSL, Octanove, wordfreq verisi ve Wiktionary CC BY-SA'dır. Paketler dağıtılırsa CC BY-SA 4.0 ile dağıtılmalıdır. Kişisel kullanımda sorun yoktur, ama her paket `LICENSES.md` ve manifest atıflarıyla üretilir.

## 3. Araçlar

- **Python ≥ 3.12**, `uv` ile sanal ortam. Kullanıcıda 3.14 var; spaCy 3.8 Python 3.10–3.14'ü destekliyor.
- **Paketler:**
  - `spacy` + `en_core_web_md` (lemma, sözcük türü)
  - `wordfreq`
  - Çalışma anı LLM SDK'sı yok: LLM işleri Claude Code oturumlarında yapılır (ADR-0009)
  - `kokoro` (paket sesleri; Python < 3.13 istediği için ayrı bir uv ortamında)
  - `pydantic`, `typer` (CLI), `rich`, `pytest`
  - `fsrs[optimizer]` (FSRS optimizasyonu; ayrı araç)
- **Başka hedef diller:** spaCy'nin resmî modeli olmayan diller için Stanza. Örneğin Türkçe hedef dil olursa Stanza'nın Türkçe modelleri kullanılır.
- **CLI:** `uv run dilbaz-content <komut>` (bkz. §4).
  - `version`, `check-manifest`: manifest şeması (`11` §3); kaynak başına lisans ve atıf zorunlu (I-16).
  - `ingest [kaynak…] [--refresh]` (S0): Haftalık dökümler yalnızca `--refresh` ile yeniden indirilir.
  - `lexicon` (S1).
  - Diğer aşama komutları sonraki görevlerde eklenir.
- **Kod:** `content/tools/src/dilbaz_content/`, testler `content/tools/tests/`. `requires-python >= 3.12`, yerel yorumlayıcı 3.14 (`.python-version`). Denetimler: ruff (lint + format), mypy (pydantic eklentisi), pytest.
- Büyük kaynak dosyaları `content/sources/` altında durur (git dışı, sağlama toplamıyla). Ara çıktılar `content/work/`, paket çıktıları `content/build/` altındadır (git dışı).

## 4. Aşamalar

```text
S0 ingest ─▶ S1 lexicon ─▶ S2 select ─▶ S3 generate ─▶ S4 validate ─▶ S5 pair ─▶ S6 audio
      ─▶ S7 texts & tasks ─▶ S8 placement ─▶ S9 build ─▶ S10 report ─▶ (upload)
```

| Aşama | Komut | Girdi → Çıktı | Açıklama |
|---|---|---|---|
| S0 | `ingest` | `sources.yaml` → `sources/<kimlik>/<sürüm ya da tarih>/` | İndir, sağlama toplamını doğrula, `SNAPSHOT.json` yaz |
| S1 | `lexicon` | Kaynaklar → `work/lexicon.en.jsonl` + rapor | Lemma, yazım varyantları, sıklık sırası, NGSL/NGSL-S üyeliği, CEFR-J/Octanove seviyesi, sözcük türü, çekimli biçimler, IPA (ABD/İngiltere), ARPAbet, anlamlar, kaynaklar (ayrıntı: §4.1) |
| S2 | `select --level A1` | Sözlük → hedef öğe listesi | Kelime anlamları (lemma başına en sık 1–2 anlam), kalıplar (NGSL-Spoken + Claude Code oturumu önerileri), gramer noktaları (`02` §5 kodları), sesler ve minimal çiftler (CMUdict + sıklık filtresi) |
| S3 | `generate sentences` | Hedefler → aday cümleler | Önce Tatoeba'dan uygun adaylar (seviye filtresi). Eksik kalanlar Claude Code oturumunda üretilir: araç, hedef ve izinli kelime listesini içeren bir iş dosyası çıkarır; oturumda üretilen JSONL `work/` altına yazılır ve şemayla doğrulanır. Bağlamlar: günlük hayat + ilgi alanları. |
| S4 | `validate` | Adaylar → kabul/ret | Deterministik kontroller + ayrı oturumda doğrulama geçişi + 👤 örneklem (§5) |
| S5 | `pair --l1 tr` | Kabul edilen öğeler → tr-en paketi | Türkçe karşılıklar, açıklamalar, karşıtlık notları, kabul edilebilir varyantlar, hata etiketi kataloğu |
| S6 | `audio` | Metinler → ses dosyaları | Kokoro-82M, çevrimdışı: öğe başına ≥ 2 ses; minimal çiftler için ≥ 4 ses; A0–A1 için yavaş sürüm; ses düzeyi normalizasyonu |
| S7 | `texts`, `tasks` | Seviye → metin, diyalog, görev | Kapsama kontrollü metinler + sorular + cevap anahtarları; diyaloglar (2 ses); konuşma, rol, bilgi boşluğu, yazma, aracılık görevleri |
| S8 | `placement` | Sözlük → X_Lex bankası | 3 sürüm × (5 bant × 20 kelime + 20 uydurma kelime) |
| S9 | `build` | Tümü → `build/en@N.sqlite` + ses manifesti | Lemma listeleri, `forms` tablosu, normalizasyon kuralları, manifest, sağlama toplamı, lisanslar |
| S10 | `report` | Build → `build/en@N.report.md` | Sayılar, ret oranları, üretim oturumları, insan kontrolü örneklemi |
| — | `upload` | Build → Supabase Storage `packs/` + `packs` satırı | Yalnızca kullanıcı onayıyla (dışa yayın) |

### 4.1 S1 sözlük kuralları

- **Anahtar:** Seviye listesindeki ilk yazımın küçük harfli hâli ("color/colour" → `color`; diğer yazımlar `spellings`). NGSL'de başka yazımla geçen lemma aynı anahtara bağlanır. CEFR-J'deki "'m", "'re", "'s" alınmaz; kısaltmaları normalizasyon açar (`03` §0.5).
- **Çekimlerin birleştirilmesi:** Seviye listeleri bazı çekimleri ayrı satır olarak verir ("is", "did", "these"). Fiil, yardımcı fiil, belirleyici ya da zamir olan bir başlık şu koşullarda lemmasına katılır ve onun biçimi olur:
  - başka tek bir başlık onu aynı sözcük türünde çekim olarak listeliyorsa,
  - başlığın kendi çekimi yoksa.

  Böylece am/is/are/was/were/been → be, did/does/doing/done → do, had/has → have, these/those → this/that olur. "found" (kurmak: founded) ve "lay" (laid) kendi çekimleri olduğu için ayrı kalır; "later" gibi karşılaştırma biçimleri de ayrı kalır. Birleştirmeler raporda listelenir.
- **Seviye:** Sözcük türü başına listelerin verdiği en düşük seviye. Lemmanın seviyesi bunların en düşüğüdür. Yalnızca NGSL'de olan lemmaların seviyesi boştur; S2'de sıklıktan tahmin edilir.
- **Biçimler:** Wiktionary'den, seviye listesindeki sözcük türlerinin girdilerinden alınır. Böylece "I" zamirine harf anlamının çoğulu "is" karışmaz. Bir biçimin tüm etiketleri dilbilgisel olmalı (çoğul, geçmiş, ortaç, karşılaştırma…) ya da standart bir çeşidi göstermeli (US "gotten"). Lehçe, argo, kısaltma ve eskimiş biçimler alınmaz.
- **Sıra:** Tek kelimeli girdiler, ailenin wordfreq sıklık toplamına göre sıralanır. Aile: lemma, tek kelimeli yazımlar ve çekimli biçimler.
  - Kendisi de başlık olan bir biçim ("saw", "number") sıklığını başka aileye vermez.
  - Başlık olmayan ve iki ailede geçen bir biçim, aileler arasında eşit bölünür.
  - Çok kelimeli girdilerin (147) sırası yoktur: wordfreq'in öbek tahmini çok kaba. Bu girdiler sona yazılır; X_Lex bantları yalnızca tek kelimeli girdilerden seçilir.
- **Telaffuz:**
  - ABD IPA'sı CMUdict'in ilk (sözlük) telaffuzundan çevrilir. Wiktionary'nin GA etiketi bazen zayıf biçimi gösteriyor ("you" /jə/). Çevirmen vurguyu en uzun hece başı ilkesiyle hece başına koyar; kısaltmalardaki çift ana vurgunun öndekini ikincil yapar (/ˌtiˈvi/).
  - İngiltere IPA'sı Wiktionary'nin RP/UK etiketli ilk değeridir. Hiçbir aksan etiketlenmemişse etiketsiz ilk değer genel kabul edilir. Köşeli parantezli fonetik yazımlar alınmaz.
  - ARPAbet de saklanır; minimal çiftler bununla bulunur.
- **Anlamlar:** Wiktionary'den sözcük türü başına en fazla 8 anlam. Seviye listesindeki türler önce gelir. Eskimiş, arkaik ve nadir anlamlar alınmaz. "Biçimi" (form-of) anlamlar yalnızca girdinin başka anlamı yoksa tutulur ("TV" → "Abbreviation of television").
- **Wiktionary alt kümesi:** 3 GB'lık döküm bir kez taranır; yalnızca sözlüğün kelimeleri `work/wiktextract.en.subset.jsonl` dosyasına yazılır. Döküm, kelime listesi ya da alt küme biçimi (`SLIM_VERSION`) değişmedikçe yeniden taranmaz. Tam çalıştırma ~30 sn sürer.
- **Rapor:** `work/lexicon.en.report.json`. İçinde sayılar, birleştirmeler ve kullanılan kaynak anlık görüntülerinin sağlama toplamları var.
- **İlk çıktı (2026-09-26):**
  - 8.679 girdi: A1 1.048, A2 1.239, B1 2.139, B2 2.417, C1 913, C2 875, seviyesiz 48
  - NGSL'in 2.809, NGSL-Spoken'ın 721 kelimesinin tamamı içeride
  - Kapsama: IPA ABD %95,6, İngiltere %87,7; anlam %99,6
  - İlk 5.000 sıranın 4.956'sının seviyesi var

## 5. Doğrulama kuralları (S4)

### 5.1 Deterministik
- **Seviye:** spaCy lemmaları. Hedef öğe dışındaki tüm lemmalar ≤ seviye listesinde olmalı. Özel isimler ve sayılar serbest.
- **Uzunluk sınırları (kelime):**

  | A0 | A1 | A2 | B1 | B2 | C1–C2 |
  |---|---|---|---|---|---|
  | ≤ 6 | ≤ 8 | ≤ 12 | ≤ 16 | ≤ 22 | ≤ 30 |

- **Tekrar yok:** normalize edilmiş eşleşme ve yakın benzerlik (Jaccard > 0,8).
- **Uygunsuz içerik listesi** filtresi.
- **Hedef öğe** cümlede gerçekten geçiyor (lemma/kalıp eşleşmesi).

### 5.2 Bağımsız doğrulama geçişi (Claude Code, ayrı oturum)
- Üreten oturumdan ayrı bir oturumda, üretim gerekçeleri görülmeden yapılır.
- Ölçütler: doğallık (1–5), dilbilgisi doğruluğu, anlam belirsizliği, hedef anlamın doğru kullanımı, Türkçe karşılığın doğruluğu (geri çeviri karşılaştırmasıyla).
- **Kabul:** doğallık ≥ 4, belirsizlik yok, çeviri doğru.
- Kararlar parti dosyasına yazılır. Ardından her partiden rastgele 20 öğe 👤 kullanıcıya gösterilir (§1.3).

### 5.3 Uydurma kelimeler (X_Lex)
- Adaylar Claude Code oturumunda ya da İngilizce ses dizimine uygun basit bir üreteçle çıkarılır.
- Kabul koşulları:
  - wordfreq sıklığı 0
  - CMUdict'te yok
  - Wiktionary'de yok
  - gerçek bir kelimeye 1 harf uzaklıkta değil
- Her sürüm için 20 uydurma kelime.

### 5.4 Metinler (S7)
- **Seviye metni:** metindeki lemmaların ≥ %98'i ≤ seviye listesinde. Kalan %2 önce öğretilecek kelimeler olarak işaretlenir.
- Sorular ve cevap anahtarı üretilir. Cevaplanamayan ya da belirsiz sorular bağımsız doğrulama geçişinde elenir.

## 6. Tr-en paketi içeriği (S5)

- **Karşılıklar (`glosses`):** anlam, kısa açıklama (A seviyeleri Türkçe), kullanım notu, karşıtlık notu.
- **Hata etiketi kataloğu (`error_tags`):**
  - Elle hazırlanır, Claude Code oturumlarında genişletilir.
  - Kaynak: Swan & Smith (2001), Türkçe konuşanlar bölümü kategorileri.
  - Başlangıçta ~30 etiket. Her etiket için: kod, kategori (gramer / kelime / telaffuz / algı / pragmatik), ciddiyet ağırlığı, Türkçe açıklama, 3+ örnek, ilgili gramer kodları.
  - Örnek kodlar:

    | Kod | Hata |
    |---|---|
    | `art.missing` | Artikel eksik |
    | `art.wrong` | Yanlış artikel |
    | `pron.he_she` | he/she karışması |
    | `agr.3sg_s` | 3. tekil -s |
    | `tense.pp_vs_ps` | Present Perfect / Past Simple karışması |
    | `wo.question` | Soru kurma sırası |
    | `prep.in_on_at` | in/on/at seçimi |
    | `lex.say_tell` | say/tell karışması |
    | `exist.there_have` | "var" → there is / have karışması |
    | `pl.missing` | Çoğul eki eksik |

- **Kabul edilebilir varyantlar:** kısaltmalar, eş anlamlılar, farklı ama doğal yapılar. Oturumda üretilir, deterministik kontrolden geçer. LLM'siz değerlendirmenin (ADR-0009 §2) temeli olduğu için her kart cümlesinde geniş tutulur.
- **Kural notları (H3):** her gramer kodu için Türkçe, kısa bir kural notu. Cevabı içermediği derlemede test edilir (I-02).
- **Can-do özetleri:** kendi kısa Türkçe özetlerimiz (resmî metin kopyalanmaz).
- **Görev yönergeleri ve öğrenme notu şablonları** (Türkçe).

## 7. Kişisel öğeler

Kullanıcıdan gelen içerik (Söyleyemediklerim, altyazı replikleri, konuşma düzeltmeleri, okumada aranan kelimeler) paket dışındadır:

- `personal_items` tablosunda durur.
- Anahtar biçimi: `personal:<uuid>`.
- Aynı motor kurallarıyla çalışır.
- Lemma listesi kayıt anında bir `normalize_lemmatize` fonksiyonuyla çıkarılır: pakette `forms` tablosu, yoksa sunucu fonksiyonu.

## 8. Kalite geri bildirimi

- Uygulamadaki "Bu içerikte hata var" bildirimi `content_reports` tablosuna düşer.
- Düzeltmeler bir sonraki paket yamasında (`en@1.1`) yayınlanır. Öğe anahtarları değişmez.
- Ret oranı yüksek aşamalar (> %40) promptun ya da kaynağın gözden geçirilmesini tetikler.

## 9. Maliyet

- $0 (ADR-0009). LLM işleri Claude Code aboneliğiyle, sesler Kokoro ile çevrimdışı yapılır.
- Sınır para değil, oturum süresidir. Büyük partiler birkaç oturuma yayılır.
- Her `report`, üretim oturumlarını, ret oranlarını ve insan örnekleminin sonucunu yazar.
