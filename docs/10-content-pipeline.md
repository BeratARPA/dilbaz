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
  - Paket sesleri ayrı bir uv ortamındadır: `content/tts` (Python 3.12; `kokoro-onnx`, `misaki`, `soundfile`). misaki, Kokoro'nun eğitildiği G2P'dir ve Python < 3.13 istiyor (ADR-0009).
  - `pydantic`, `typer` (CLI), `rich`, `pytest`
  - `fsrs[optimizer]` (FSRS optimizasyonu; ayrı araç)
- **Başka hedef diller:** spaCy'nin resmî modeli olmayan diller için Stanza. Örneğin Türkçe hedef dil olursa Stanza'nın Türkçe modelleri kullanılır.
- **CLI:** `uv run dilbaz-content <komut>` (bkz. §4).
  - `version`, `check-manifest`: manifest şeması (`11` §3); kaynak başına lisans ve atıf zorunlu (I-16).
  - `ingest [kaynak…] [--refresh]` (S0): Haftalık dökümler yalnızca `--refresh` ile yeniden indirilir.
  - `lexicon` (S1).
  - `select [--max-level A2] [--limit 600]` (S2).
  - `carriers [--per-target 3]` (S3: Tatoeba taşıyıcı adayları).
  - `sentences` (S4: taşıyıcı cümleler, kontroller; engelleyici sorun varsa çıkış kodu 1).
  - `pair [--l1 tr] [--l2 en]` (S5: çift paketi, kontroller; engelleyici sorun varsa çıkış kodu 1).
  - `audio [--l2 en]` (S6: paket sesleri; `content/tts` işçisini çağırır).
  - `placement [--l1 tr] [--l2 en]` (S8: X_Lex bankası).
  - `build [--l1 tr] [--l2 en]` (S9: paket dosyaları; engelleyici sorun varsa hiçbir dosya yazılmaz, çıkış kodu 1).
  - `report [--l1 tr] [--l2 en]` (S10: derleme raporu).
  - Diğer aşama komutları sonraki görevlerde eklenir.
- **Kod:** `content/tools/src/dilbaz_content/`, testler `content/tools/tests/`. `requires-python >= 3.12`, yerel yorumlayıcı 3.14 (`.python-version`). Denetimler: ruff (lint + format), mypy (pydantic eklentisi), pytest.
- Büyük kaynak dosyaları `content/sources/` altında durur (git dışı, sağlama toplamıyla). Ara çıktılar `content/work/`, paket çıktıları `content/build/` altındadır (git dışı).

## 4. Aşamalar

```text
S0 ingest ─▶ S1 lexicon ─▶ S2 select ─▶ S3 carriers ─▶ S4 sentences ─▶ S5 pair ─▶ S6 audio
      ─▶ S7 texts & tasks ─▶ S8 placement ─▶ S9 build ─▶ S10 report ─▶ (upload)
```

| Aşama | Komut | Girdi → Çıktı | Açıklama |
|---|---|---|---|
| S0 | `ingest` | `sources.yaml` → `sources/<kimlik>/<sürüm ya da tarih>/` | İndir, sağlama toplamını doğrula, `SNAPSHOT.json` yaz |
| S1 | `lexicon` | Kaynaklar → `work/lexicon.en.jsonl` + rapor | Lemma, yazım varyantları, sıklık sırası, NGSL/NGSL-S üyeliği, CEFR-J/Octanove seviyesi, sözcük türü, çekimli biçimler, IPA (ABD/İngiltere), ARPAbet, anlamlar, kaynaklar (ayrıntı: §4.1) |
| S2 | `select --max-level A2` | Sözlük + `curation/<l2>/` → `packs/<l2>/items/` (ayrıntı: §4.2) | Kelime anlamları (lemma başına en sık 1–2 anlam), kalıplar (NGSL-Spoken + Claude Code oturumu önerileri), gramer noktaları (`02` §5 kodları), sesler ve minimal çiftler (CMUdict + sıklık filtresi) |
| S3 | `carriers` | Kelime anlamları + Tatoeba → `work/carriers.en.candidates.jsonl` (ayrıntı: §4.3) | Seviye ve gramer filtresinden geçen Tatoeba adayları, anlam başına en iyi 3 |
| S4 | `sentences` | Adaylar + `curation/<l2>/sentences.yaml` → `packs/<l2>/items/sentences.jsonl` (ayrıntı: §4.4, §5) | Seçim; eksik ya da kötü adayların yerine Claude Code oturumunda yazılan cümleler; deterministik kontroller; ayrı oturumda doğrulama geçişi; 👤 örneklem |
| S5 | `pair --l1 tr` | Hedef paket + `curation/tr-en/` + S4 çevirileri → `packs/tr-en/` (ayrıntı: §6) | Türkçe karşılıklar ve istemler, açıklamalar, karşıtlık notları, kabul edilebilir varyantlar, H3 kural notları, hata etiketi kataloğu |
| S6 | `audio` | Öğeler + `packs/<l2>/voices.yaml` → `build/audio/<l2>/<sürüm>/` + `packs/<l2>/audio.jsonl` (ayrıntı: §4.5) | Kokoro-82M, çevrimdışı: öğe başına ≥ 2 ses; minimal çiftler için ≥ 4 ses; A0–A1 için yavaş sürüm; ses düzeyi normalizasyonu |
| S7 | `texts`, `tasks` | Seviye → metin, diyalog, görev | Kapsama kontrollü metinler + sorular + cevap anahtarları; diyaloglar (2 ses); konuşma, rol, bilgi boşluğu, yazma, aracılık görevleri |
| S8 | `placement` | Sözlük + `curation/<l2>/xlex.yaml` → `packs/<l2>/placement/xlex.jsonl` (ayrıntı: §5.3) | 3 sürüm × (5 bant × 20 kelime + 20 uydurma kelime) |
| S9 | `build` | Tümü → `build/<id>.sqlite`, `<id>.manifest.json`, `<id>.LICENSES.md` (ayrıntı: §4.6) | Lemma listeleri, `forms` tablosu, normalizasyon kuralları, manifest, sağlama toplamı, lisanslar |
| S10 | `report` | Build → `build/en@N.report.md` (ayrıntı: §4.7) | Sayılar, ret oranları, üretim oturumları, insan kontrolü örneklemi |
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
  - Çok kelimeli ya da tireli girdilerin (207; wordfreq tirede de böler: "part-time") sırası yoktur, çünkü öbek tahmini çok kaba. Bu girdiler sona yazılır. Tireli yazım varyantları da aileye katılmaz. X_Lex bantları yalnızca tek kelimeli girdilerden seçilir.
- **Telaffuz:**
  - ABD IPA'sı CMUdict'in ilk (sözlük) telaffuzundan çevrilir. Wiktionary'nin GA etiketi bazen zayıf biçimi gösteriyor ("you" /jə/). Çevirmen vurguyu en uzun hece başı ilkesiyle hece başına koyar; kısaltmalardaki çift ana vurgunun öndekini ikincil yapar (/ˌtiˈvi/).
  - İngiltere IPA'sı Wiktionary'nin RP/UK etiketli ilk değeridir. ABD için olağan bir değer etiketlenmemişse etiketsiz ilk değer genel kabul edilir. Köşeli parantezli fonetik yazımlar alınmaz.
  - **Marjinal söyleyişler** iki aksanda da son çaredir. Marjinal sayılanlar:
    - niteleyici etiketliler (dated, dialectal, rare, nonstandard, also, sometimes, unstressed…)
    - notunda niteleyici geçenler ("spelling pronunciation", "in fast speech", "weak form", "some speakers"…)

    Wiktextract'ın `note` alanı bunun için alt kümede tutulur (`SLIM_VERSION` 5). Aksan ya da ses değişimi adı taşıyan notlar ("happy-tensing", "wine–whine merger") olağan biçimi de anlatır, bu yüzden marjinal sayılmaz. Sonuç (2026-09-27): sözlükte 31 İngiltere değeri değişti. İşlev sözcükleri zayıf biçim yerine sözlük biçimini alıyor (must /mʌst/, that /ðæt/), 9 sözcük ilk kez değer aldı. İngiltere kapsaması %87,8.
  - Kaynağın hiç işaretlemediği hatalar S2 küratörlüğünde düzeltilir (§4.2). Wiktionary, "breakfast"ın yazılışa göre söylenişini (/ˈbreɪkˌfɑːst/) not düşmeden RP diye etiketliyor.
  - ARPAbet de saklanır; minimal çiftler bununla bulunur.
- **Anlamlar:** Wiktionary'den sözcük türü başına en fazla 8 anlam. Seviye listesindeki türler önce gelir. Eskimiş, arkaik ve nadir anlamlar alınmaz. "Biçimi" (form-of) anlamlar yalnızca girdinin başka anlamı yoksa tutulur ("TV" → "Abbreviation of television").
- **Wiktionary alt kümesi:** 3 GB'lık döküm bir kez taranır; yalnızca sözlüğün kelimeleri `work/wiktextract.en.subset.jsonl` dosyasına yazılır. Döküm, kelime listesi ya da alt küme biçimi (`SLIM_VERSION`) değişmedikçe yeniden taranmaz. Tam çalıştırma ~30 sn sürer.
- **Rapor:** `work/lexicon.en.report.json`. İçinde sayılar, birleştirmeler ve kullanılan kaynak anlık görüntülerinin sağlama toplamları var.
- **İlk çıktı (2026-09-26):**
  - 8.679 girdi: A1 1.048, A2 1.239, B1 2.139, B2 2.417, C1 913, C2 875, seviyesiz 48
  - NGSL'in 2.809, NGSL-Spoken'ın 721 kelimesinin tamamı içeride
  - Kapsama: IPA ABD %95,6, İngiltere %87,7; anlam %99,6
  - İlk 5.000 sıranın 4.956'sının seviyesi var

### 4.2 S2 seçim kuralları

**Küratörlük dosyaları.** S2'nin kararları `content/curation/<l2>/` altında commit edilen üç dosyadadır. Çıktılar `content/packs/<l2>/items/` altına yazılır; bunlar paketin kaynak dosyalarıdır ve commit edilir.
- `word_senses.yaml`
- `chunks.yaml`
- `grammar_points.yaml`

**Kelime anlamları (`word_senses.jsonl`):**
- **Sıra:**
  1. Küratörlük listesindeki gündelik sözcükler (`include`: yemek, ev, günler, hava, aile, duygular…)
  2. NGSL-Spoken üyeleri
  3. Diğerleri

  Her grup kendi içinde sıklık sırasıyla dizilir. Konuşma listesi öne alınır, çünkü hedef konuşma. wordfreq'in genel sıklığı haber ağırlıklıdır (government, court, political).
- **Dışlananlar (`exclude`):**
  - Dilbilgisiyle öğretilenler: be, not, soru sözcükleri, karşılaştırma biçimleri, edat kökenli zarflar (in, on, about…)
  - Kalıp olarak öğretilenler: please, thank you, sorry, OK
  - Unvanlar, isim-fiiller
  - Gündelik konuşmada az kullanılan soyut ve haber sözcükleri
- **Sözcük türü:** Yalnızca içerik türleri (isim, fiil, sıfat, zarf) kelime kartı olur. Lemma başına en fazla 2 anlam alınır.
- **Seviye:** Seviye listelerinden gelir. En sık 300 ailenin A1 anlamları A0 sayılır (`02` §2: A0 < 300 kelime).
- **Açıklamalar:** Wiktionary'nin ilk anlamı öğrenci için sık sık yanlış ("pen" = ağıl, "tell" = saymak). Bu yüzden seçilen her anlamın İngilizce açıklaması küratörlük dosyasında kendi sözlerimizle yazılır (lisans: `own`). `select` çıktısında otomatik açıklama kalmamalıdır.
- **Anahtar:** `en.ws.<lemma>.<tür>.<n>` (ör. `en.ws.watch.v.1`); anahtar hiç değişmez.
- **Söyleniş düzeltmesi:** `senses` içindeki `ipa_uk`/`ipa_us`, S1'in kaynaktan doğru seçemediği değerin yerine geçer (breakfast, §4.1).
  - Eş yazımlılarda kaynaklar kelime başına tek söyleniş verir, bu da çoğu zaman başka bir sözcük türününkidir: CMUdict'te close önce /kloʊs/. en@1'de 7 anlam böyle düzeltildi: use, live, read, close (fiil ve sıfat), record, subject. Taramayı CMUdict'te birden çok söylenişi olan kelimeler üzerinde yaptık.
- **İlk seçim (2026-09-27):** 546 lemma, 600 anlam (A0 167, A1 299, A2 134).

**Sohbet çantası (`chunks.jsonl`):**
- 120 kalıp, 17 iletişim işlevi: selamlaşma, anlamadığını söyleme, tepki, fikir, kişisel bilgi, istek, alışveriş, yol tarifi, sorunlar…
- Seviyeler: A0 45, A1 57, A2 18.
- Anahtar metinden türetilir (`en.chunk.how_are_you`). Aynı anahtara düşen iki metin hatadır.
- 👤 Kullanıcılar listeyi gözden geçirir.

**Gramer noktaları (`grammar_points.jsonl`):**
- 40 nokta (A0 8, A1 22, A2 10), `02` §5'teki ilerlemeden. Seviyeler CEFR-J Grammar Profile'daki CEFR-J, Core Inventory ve EGP sütunlarıyla karşılaştırıldı; üçünün de A1 dediği maddeler A1'dedir.
- Kodları (`gp.be.present`) kapalı listedir: hata etiketleri, öğeler ve LLM rotaları yalnızca bunları kullanır.
- Her noktanın en az 2 örneği vardır. Türkçe konuşanlara özgü zorluk notları S5'te tr-en paketine yazılır.

### 4.3 S3 taşıyıcı adayları

- **Havuz:** Tatoeba'nın Türkçe çevirisi olan ve en fazla 12 kelimelik İngilizce cümleleri. 2026-09 dökümünde 647 bin cümle var; 523 binini anadili İngilizce olan kullanıcılar yazmış (`eng_user_languages`, beceri 5).
- **Analiz:** spaCy `en_core_web_md` (ayrıştırıcı ve NER kapalı) her cümle için lemma, sözcük türü ve etiket çıkarır. Sonuç `work/tatoeba.en.analysis.jsonl.gz` dosyasında önbellekte tutulur. Anlık görüntü, çözümleyici ya da biçim değişmedikçe yeniden hesaplanmaz; ilk çalıştırma ~6 dakika sürer.
- **Aday koşulları:**
  - **Eşleşme:** Cümle hedef anlamın lemmasını aynı sözcük türüyle içerir. spaCy'nin AUX etiketi fiil sayılır, özel isim etiketi (günler) isim sayılır. Pakette tek anlamı seçilmiş bir lemma isimle zarf arasında geçebilir, çünkü spaCy "today, tomorrow" için isim diyor, listeler zarf diyor. Lemma tanınmazsa yüzey biçimi denenir: spaCy "clothes" için "clothe" veriyor. Çoğul özel isimlerde sondaki s atılarak denenir, çünkü spaCy "Mondays" kelimesini lemmalaştırmıyor.
  - **Kelime seviyesi:** Hedef dışındaki her kelime hedefin seviyesinde ya da altındadır. A0 hedefler A1 kelime kullanabilir, çünkü A0'ın kelimesi doğal cümle için çok az. Sözlükte olmayan kelime cümleyi eler; özel isimler, sayılar ve noktalama seviyeye katılmaz.
  - **Gramer seviyesi:** Kural tabanlı etiketleyicinin (§4.4) bulduğu gramer noktaları da hedefin seviyesini aşamaz. Bu, A1 bir kelimeye present perfect cümlesi gelmesini önler. Hedefin kendisiyle tetiklenen nokta sayılmaz: "much" sayılabilir/sayılamaz noktasını (A2) tetikler ama bu, "much"u geri tutmaz.
  - **Paket dışı yapılar:** en@1'in öğretmediği yapılar da `02` §5'teki seviyeleriyle sayılır: edilgen, used to, past continuous, might/may/could, would (would like hariç), if, yan cümleler (who, which, that, what…) B1; perfect continuous, past perfect ve "must have" türü kipler B2; when yan cümlesi ve ", so" A2. Bunlar paket kodu değildir, yalnızca seviyeyi belirler.
  - **Tireli bileşikler:** "well-known", "ten-year-old" içindeki kelime kendi anlamını taşımaz, eşleşme sayılmaz.
  - **Uzunluk:** Seviye sınırını aşmaz (§5.1).
  - **Biçim:** Tırnak, parantez ve iki cümleli metinler elenir. Aynı metin bir kez sayılır.
- **Puan (büyük olan iyi):**
  - anadil yazarı +2
  - özel isim başına −1,5 (Tatoeba "Tom" cümleleriyle dolu). Seçili bir anlam olan özel isim (günler) sayılmaz.
  - ideal uzunluktan uzaklık başına −0,3
  - kelimelerin ortalama sıklık sırası (log10) × −0,4
  - cümlenin taşıdığı başka her seçili anlam için +0,15, en fazla 3 için. Daha büyük bir ödül adayları "too" cümlelerine yığıyordu.
  - cümlenin hedefin seviyesini aştığı her seviye için −0,25: en basit bağlam öne çıkar. 0,5'lik ceza A0 hedeflere "It's now or never." türü kısa deyimler getirdi.
- **İlk sonuç (2026-09-27):** 600 anlamın hepsine 3 aday bulundu. Analiz önbellekteyken arama 38 sn sürüyor.
- **Çıktı:** Her anlamın en iyi 3 adayı `work/carriers.en.candidates.jsonl` dosyasına yazılır; adayı olmayan anlamlar dosyanın başındadır. Seçim ve eksik cümlelerin yazılması küratörlükle yapılır (S4).

### 4.4 S4 taşıyıcı cümleler

- **Seçim:** Her anlam S3'ün en iyi adayını alır. `curation/<l2>/sentences.yaml` bunu değiştirir:
  - `reject`: hiç kullanılmayacak Tatoeba kimlikleri.
  - `carriers`: anlam → taşıyıcılar. Her taşıyıcı ya bir Tatoeba kimliğidir (adaylar dışından da olabilir; analiz önbelleğinden okunur) ya da Claude Code oturumunda yazılmış kendi cümlemizdir (`license: own`).
- **Belirsiz anlamlar:** Aynı lemma ve sözcük türünde birden çok seçili anlam varsa (right: doğru/sağ, too: de/fazla, free: bedava/boş, letter: mektup/harf) etiketleyici ikisini ayıramaz. Bu anlamlar otomatik taşıyıcı almaz; küratörlük seçer, seçilmezse derleme durur. Böyle bir kelime cümlede yalnızca seçildiği anlama bağlanır.
- **Cümle kaydı:** Her cümle analiz edilir; seviye (kelimeler, paket kodları, paket dışı yapılar), lemmalar, içerdiği bütün seçili anlamlar (`targets`), gramer kodları ve kaynak (Tatoeba kimliği, lisans, yazar) yazılır. Anahtar metinden türetilir; aynı anahtara düşen ikinci metin yakın tekrar sayılır.
- **Gramer etiketleyici:** spaCy'nin Penn etiketleri ve lemmalarıyla çalışan kurallar. Kural emin değilse kod vermez. "I've got to go" zorunluluk sayılır (`gp.modals.obligation`), "have got" değil. Cümle başındaki "Don't …" soru değilse emirdir, geniş zaman olumsuzu değil. "in the afternoon", "on Sundays" zaman edatıdır.
- **Kontroller (§5.1):**
  - Engelleyici: sözlükte olmayan kelime, paket seviyesini aşma, hedefin seviyesini aşma, uzunluk, hedef anlamın cümlede olmaması, uygunsuz kelime, biçim (tırnak, iki cümle), seçilmemiş belirsiz anlam.
  - Uyarı: yakın tekrar; bağımsız doğrulamadan geçmemiş cümle (§5.2).
- **Çıktılar:**
  - `packs/<l2>/items/sentences.jsonl`
  - `word_senses.jsonl` içindeki `carriers`: anlamın seçilen cümleleri (`11` §4). S2 bu alanı boşaltır, S4 yeniden doldurur.
  - `work/sentences.<l2>.turkish.jsonl`: Tatoeba'nın Türkçe çevirileri (S5 için)
  - `work/sentences.<l2>.report.json`: sayılar, gramer dağılımı ve sorunlar
- **İlk sonuç (2026-09-27):**
  - 600 anlamın 344'ünde otomatik seçim değiştirildi: 320'sinde başka bir Tatoeba cümlesi, 24'ünde kendi cümlemiz.
  - 587 cümle (563 Tatoeba, 24 kendi). Seviyeler: A0 44, A1 408, A2 135. Ortalama 5,4 kelime. Engelleyici sorun yok.
  - Otomatik seçimin sık hataları şunlardı: deyimler ("a tall order", "right on the money"), yanlış anlam ("glasses" = gözlük), karamsar ton ("I don't have a family."), "I've got to …" yığılması ve etiketleyicinin kaçırdığı yapılar (edilgen, used to). Son ikisi kurallara eklendi.

### 4.5 S6 paket sesleri
- **Model:** Kokoro-82M v1.0, ONNX sürümü (Apache-2.0). Model ve ses dosyaları `sources.yaml`'da bir kaynak olarak kayıtlıdır ve sha256 ile sabitlenmiştir (`ingest kokoro`).
- **İşçi:** `content/tts` ortamı (Python 3.12). `audio` komutu iş listesini yazar ve işçiyi alt süreç olarak çalıştırır. İşçi her iş için MP3 üretir ve süresini döndürür.
- **Sesler (`packs/<l2>/voices.yaml`):**
  - en@1'in sesleri örnekler dinlenerek seçildi (👤, 2026-09-29): af_heart, am_michael (ABD), bf_emma, bm_george (İngiltere).
  - Her öğeyi bir ABD ve bir İngiliz sesi okur. Çiftler sırayla döner, böylece her ses eşit sayıda öğe okur.
  - Yavaş düzeylerin (A0–A1) öğelerini çiftin ilk sesi bir kez de 0,8 hızla okur.
- **Okunuş:**
  - Metin, Kokoro'nun eğitildiği misaki G2P ile fonemlere çevrilir. misaki eş yazımlıyı cümledeki sözcük türüne göre okur: "Close the door." /kloʊz/, "The shop is close." /kloʊs/. kokoro-onnx'in varsayılan espeak-ng yolu bu ayrımı yapamıyor.
  - Tek kelime, türünü belli eden bir çerçevede çözümlenir: fiil "to close", isim "the …", sıfat "it is …". Yalnızca kelimenin kendi fonemleri okunur.
  - Kalıptaki boşluk okunmaz: "My name is …" → "My name is".
- **Ses:**
  - Kenarlardaki sessizlik kırpılır, RMS −20 dBFS'e getirilir, tepe en çok −1 dBFS olur. İki uca 120 ms sessizlik eklenir.
  - Mono 24 kHz, sabit bit hızlı MP3: ortalama ~41 kbit/sn, klip başına ~9 KB.
- **Adlandırma ve önbellek:**
  - Dosya adı söylenen şeyin karmasıdır: motor, ses, yerel ayar, hız, sözcük türü ve metin. Yol `<ses kimliği>/<karma>.mp3`'tür, `pack-audio` kovasının `{l2}/{version}/{voice}/{hash}.mp3` düzenine uyar (`13`).
  - Süreler `work/audio.<l2>.durations.json`'da tutulur. Değişmeyen klip yeniden üretilmez. Durdurulan bir çalıştırma kaldığı yerden devam eder.
- **Çıktılar:**
  - `build/audio/<l2>/<sürüm>/` (git dışı, `upload` ile Storage'a gider)
  - `packs/<l2>/audio.jsonl`: öğe başına klipler (`key`, `voice`, `speed`, `file`, `duration_ms`)
  - `work/audio.<l2>.report.json`

### 4.6 S9 derleme
- **Girdiler:**
  - `packs/<l2>/`: `manifest.yaml`, öğeler, normalizasyon, sesler, `audio.jsonl`, X_Lex
  - `packs/<l1>-<l2>/`: `manifest.yaml`, S5 çıktıları
  - `work/lexicon.<l2>.jsonl`: S1 çıktısı; yoksa önce `lexicon` çalıştırılır
  - `curation/<l2>/sentences.validation.jsonl`
- **Engelleyici kontroller:** Biri bile varsa hiçbir dosya yazılmaz.
  - `unvalidated_sentence`: Cümlenin metnini birebir tutan kabul edilmiş bağımsız doğrulaması yok (I-16, §5.2).
  - `missing_audio`: Cümle, kalıp ya da kelime anlamının iki sesle normal hızda klibi yok.
  - `missing_audio_file`: Klibin MP3 dosyası `build/audio/` altında yok.
  - `missing_gloss`: Öğenin çift paketinde karşılığı yok.
  - `unknown_link`: Bağ, pakette olmayan bir öğeyi anıyor.
- **Paket dosyası:** Biçimi `11` §5.1'de. Hedef pakette öğeler, kapsama için sözlük lemmaları, X_Lex maddeleri, biçim tablosu ve bağlar (`contains`, `example_of`) bulunur. Çift pakette S5 girdileri ve karşıtlıklardan kurulan `contrasts_with` bağları bulunur.
- **Manifest ve lisans:** `<id>.manifest.json`, `manifest.yaml`'a sayıları, tarihi ve dosyanın sha256'sını ekler. `<id>.LICENSES.md` manifestteki kaynaklardan yazılır. CC BY-SA kaynak varsa paketin bütününün CC BY-SA 4.0 ile dağıtılacağını söyler (§2).

### 4.7 S10 rapor
- `build/<id>.report.md`, yükleme kararı için adımların kayıtlarını toplar:
  - dosyalar, satır sayıları ve sağlama toplamları
  - seviyeye göre öğeler
  - doğrulama turları
  - sesler ve X_Lex
  - kaynaklar ve lisanslar
  - `content/reports/` altındaki QA raporları
- Yükleme (`upload`) kullanıcı onayıyla yapılır (👤).

## 5. Doğrulama kuralları (S4)

### 5.1 Deterministik
- **Seviye:** spaCy lemmaları. Hedef öğe dışındaki tüm lemmalar ≤ seviye listesinde olmalı. Özel isimler ve sayılar serbest.
- **Uzunluk sınırları (kelime):**

  | A0 | A1 | A2 | B1 | B2 | C1–C2 |
  |---|---|---|---|---|---|
  | ≤ 6 | ≤ 8 | ≤ 12 | ≤ 16 | ≤ 22 | ≤ 30 |

- **Hedef seviyesi:** Taşıyıcıda hedef dışındaki kelimeler, gramer ve paket dışı yapılar hedefin izin verdiği seviyeyi aşmaz (A0 hedef için A1, diğerleri için kendi seviyesi).
- **Tekrar yok:** normalize edilmiş eşleşme ve yakın benzerlik (Jaccard > 0,8).
- **Uygunsuz içerik listesi** filtresi.
- **Hedef öğe** cümlede gerçekten geçiyor (lemma/kalıp eşleşmesi).

### 5.2 Bağımsız doğrulama geçişi (Claude Code, ayrı oturum)
- Üreten oturumdan ayrı bir oturumda, üretim gerekçeleri görülmeden yapılır.
- Ölçütler: doğallık (1–5), dilbilgisi doğruluğu, anlam belirsizliği, hedef anlamın doğru kullanımı, Türkçe karşılığın doğruluğu (geri çeviri karşılaştırmasıyla).
- **Kabul:** doğallık ≥ 4, dilbilgisi doğru, belirsizlik yok, hedef anlam doğru, içerik uygun. Yanlış bir Türkçe çeviri İngilizce cümleyi reddetmez. Doğrulamanın önerdiği düzeltme (`turkish_fix`) S5'te kullanılır.
- **Kayıt:** Kararlar `curation/<l2>/sentences.validation.jsonl` dosyasına yazılır ve commit edilir. Her satırda cümlenin anahtarı ve metni, tur numarası, puanlar, `accepted` ve varsa gerekçeli istisna (`override`) bulunur. Aynı anahtarın son satırı geçerlidir. S4, bu dosyada metni birebir tutan kabul kaydı olmayan cümleyi `unvalidated` olarak raporlar (I-16). S9 derlemesi böyle bir cümleyi pakete almaz.
- Reddedilen cümlelerin yerine gelenler yeni bir turda yine bağımsız olarak doğrulanır. Ardından her partiden rastgele 20 öğe 👤 kullanıcıya gösterilir (§1.3).
- **İlk uygulama (2026-09-27):** 1. turda 587 cümlenin 523'ü kabul edildi (%89). Ret nedenleri: hedef anlam dışı kullanım 27, belirsizlik 22, doğallık 3 olanlar 25, uygunsuz 2. Yerlerine gelen cümlelerden 2. turda 65'in 61'i, 3. turda 4'ün 4'ü kabul edildi; paketteki 588 cümlenin hepsi doğrulanmış. Paketteki Tatoeba çevirilerinin 65'i S5'te düzeltilecek. Rapor: `content/reports/2026-09-27-en1-sentences-qa.md`.

### 5.3 X_Lex bankası (S8)
- **Gerçek kelimeler:**
  - Sözlük sırasının (§4.1) her bin kelimelik bandından alınır. Bantlar 1–1000'den 4001–5000'e kadardır. Yalnızca tek kelimeli girdiler alınır.
  - Dışarıda kalanlar:
    - büyük harfle yazılan adlar (Monday)
    - işlev sözcükleri
    - 3 harften kısa girdiler
    - engelli kelimeler
    - küratörlüğün dışladıkları (`curation/<l2>/xlex.yaml`): çoğunlukla Türkçe konuşanın İngilizce bilmeden tanıdığı alıntılar (popular: popüler, television: televizyon, pizza) ve yanıltıcı benzerlikler (magazine, fabric). Bunlara verilen "biliyorum" İngilizce kelime bilgisini ölçmez.
  - Wordfreq'in Türkçe sıklığı bu elemede kullanılamaz, çünkü Türkçe web metinlerindeki İngilizce kelimeleri de sayıyor (love, house).
  - Her bant tohumla bir kez karıştırılır ve sırayla okunur. Bir kelimeyi dışlamak yalnızca onun yerine bir sonrakini getirir.
  - Seçilen 60 kelime sıraya göre dizilir ve sürümlere dönüşümlü dağıtılır: A B C, B C A, C A B… Böylece hiçbir sürüm kolay kelimeleri toplamaz.
- **Uydurma kelimeler:**
  - İngilizce yazım kalıplarından üretilir: ön ses + ünlü + son ses + ek ("brastle", "cleepen").
  - Kabul koşulları:
    - wordfreq'te İngilizce ve öğrencinin dilinde sıklığı 0
    - CMUdict'te ve Wiktionary'nin başlıklarında yok
    - wordfreq'in en sık 50.000 İngilizce kelimesinden birine 1 harf uzaklıkta değil
    - bu kelimelerden biriyle başlamıyor ya da bitmiyor ("floodous")
    - kaba bir parça içermiyor (İngilizce ve Türkçe)
  - Elle reddedilenler küratörlükte durur.
  - Wiktionary başlıkları dökümden bir kez çıkarılır: `work/wiktionary.en.headwords.txt`, döküm değişince yenilenir.
- **İlk sonuç (2026-09-29):**
  - 360 madde: sürüm başına 100 gerçek kelime ve 20 uydurma kelime.
  - Bantlarda uygun kelime 796–943 arası. 165 alıntı dışlandı.
  - Uydurma kelime için 212 aday denendi. 62'si bir kelimeye 1 harf uzak, 43'ü bir kelimeyle başlıyor ya da bitiyor, 42'si sözlükte ya da sıklık listesinde vardı, 5'i elle reddedildi.

### 5.4 Metinler (S7)
- **Seviye metni:** metindeki lemmaların ≥ %98'i ≤ seviye listesinde. Kalan %2 önce öğretilecek kelimeler olarak işaretlenir.
- Sorular ve cevap anahtarı üretilir. Cevaplanamayan ya da belirsiz sorular bağımsız doğrulama geçişinde elenir.

## 6. Tr-en paketi içeriği (S5)

- **Karşılıklar (`glosses`):** anlam, kısa açıklama (A seviyeleri Türkçe), kullanım notu. Cümle ve kalıplarda anlam kartın istemidir; isteğe bağlı bağlam (`context`: "otelde", "günlük dil") istemle gösterilir ve cevabı söylemez.
- **Karşıtlık notları (`contrast_notes`):** Türkçe konuşanların karıştırdığı öğeler (aynı Türkçe kelime: say/tell, work/study, tall/long; yanıltıcı benzerlik: market, college) ve tek cümlelik Türkçe not. A00 tanıtımında ve A08 denemesinden sonra gösterilir.
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
- Can-do özetleri, görev yönergeleri ve öğrenme notu şablonları görevlerle (S7) birlikte eklenir. `tr-en@1` karşılıklar, karşıtlık notları, hata kataloğu, varyantlar ve kural notlarıyla başlar.

### 6.1 S5 kuralları

- **Küratörlük dosyaları** (`curation/tr-en/`, Claude Code oturumlarında yazılır):
  - `word_senses.yaml`: anlam başına Türkçe karşılıklar (`meaning`, olağan olan önce) ve isteğe bağlı kullanım notu (`note`).
  - `chunks.yaml`: kalıbın Türkçesi (kartın istemi), bağlam, not, varyantlar ve alternatifler.
  - `sentences.yaml`: cümlenin istemi (`turkish`; kendi cümlelerimizde zorunlu), bağlam, varyantlar ve alternatifler.
  - **Varyant ile alternatifin farkı** (`03` §0.2): Varyant, hedefi söyleyen başka bir doğru cevaptır ("I've got a job."). Alternatif, hedefi söylemeyen doğru cevaptır ("Here's a gift for you.", present kartında): hata sayılmaz, hedef için yeniden sorulur. Kalıplarda kalıbın kendi kelimelerini koruyan küçük farklar (kısaltma, please/so/very, sıra, it/this/that, can/could/may) varyanttır. Aynı işi başka kelimelerle gören ifade alternatiftir ("My pleasure.", You're welcome kartında).
  - `grammar.yaml`: gramer kodu başına Türkçe ad, açıklama ve H3 kural notu (`rule`).
  - `contrasts.yaml`, `error_tags.yaml`.
- **Cümle istemi sırası:** küratörlüğün Türkçesi → doğrulamanın düzeltmesi (`turkish_fix`, Tatoeba çevirisi yanlışsa; §5.2) → ilk Tatoeba çevirisi (kimliği, CC BY 2.0 FR lisansı ve çevirmen atfıyla).
- **Normalizasyon:** Varyantlar, cevaplar gibi `packs/<l2>/normalization.yaml` kurallarıyla karşılaştırılır (`03` §0.5). Motor aynı dosyayı kullanır (F1-07); dosyadaki `tests` örneklerini iki uygulama da geçmelidir. Kelime kurallarından sonra kalıp ifadeler düzeltilir ("he's got" → "he has got"), para birimi yazıya çevrilir ("$30" → "thirty dollars").
- **Engelleyici kontroller** (çıkış kodu 1):
  - `missing_gloss`: Hedef paketteki her anlamın, kalıbın ve gramer noktasının karşılığı vardır.
  - `unknown_key`: Küratörlük pakette olmayan bir öğeyi anmaz.
  - `missing_prompt`: Her cümlenin istemi vardır.
  - `variant_missing_target`: Varyant, cümlenin taşıyıcısı olduğu her anlamın kelimesini hâlâ içerir ("The film was too long.", `movie` kartında reddedilir; bu cevap alternatiftir).
    - Kelime herhangi bir biçimde olabilir. Biçimler S1 sözlüğünden gelir, çalışma anındaki biçim tablosu gibi ("good at singing" → sing).
    - Etiketleyici kelimeyi başka bir sözcük türü sayarsa lemma eşleşmesi yeter ("I don't feel well." içinde well zarf).
    - Tireli kelimenin parçası sayılmaz ("snow-covered").
  - `alternative_has_target`: Alternatif, hedeflerden en az birini söylemez. Aynı ölçüyle hedefi söyleyen cevap varyanttır; öğrenciye söylediği kelime yeniden sorulmaz.
  - `prompt_clash`: Aynı istemi paylaşan kartlar birbirinin referans cevabını varyant ya da alternatif olarak kabul eder. Büyük/küçük harf ve noktalama istemleri ayırmaz, bağlam ayırır. Aksi hâlde öğrenci hangi cevabın beklendiğini bilemez ve LLM'siz değerlendirme doğru cevabı reddeder.
  - `rule_note_leak`: H3 notu, o gramer noktasını kullanan hiçbir kartın cevabını içermez. Notun "a → b" örneklerinin sağ tarafı da bu kartların cevabında geçmez: "go → went", "I went to see a show today." kartının fiilini verir (I-02).
  - `unknown_grammar_code`: Hata etiketlerinin gramer kodları pakette vardır.
- **Uyarı:** `duplicate_variant`, yani normalizasyondan sonra referansla, başka bir varyantla ya da alternatifle aynı olan cevap. Atılır.
- **Çıktılar:** `packs/tr-en/{glosses,variants,rule_notes,contrast_notes,error_tags}.jsonl`, `work/pair.tr-en.report.json`.
- **Bağımsız inceleme:** Yazan oturumdan ayrı beş ajan oturumu içeriği yazım gerekçelerini görmeden inceledi. Bir oturum 600 anlamı, üçü 588 cümleyi, biri kalıpları, gramer notlarını, karşıtlıkları ve etiketleri aldı. Her oturum şunlara baktı:
  - Türkçenin doğruluğu
  - istemin hedef kelimeye götürüp götürmediği
  - yanlış ve eksik varyantlar
  - notların doğruluğu
  - H3 sızıntısı

  Öneriler tek tek değerlendirildi (`content/reports/2026-09-29-tr-en1-pair-qa.md`).
- **İlk sonuç (2026-09-29):**
  - Karşılıklar: 600 anlam, 120 kalıp, 588 cümle istemi, 40 gramer noktası. İstemlerin kaynağı: 364 Tatoeba, 166 küratörlük, 58 doğrulama düzeltmesi.
  - 601 kartta varyant, 274 alternatif, 34 karşıtlık notu, 45 hata etiketi. Engelleyici sorun yok.

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
