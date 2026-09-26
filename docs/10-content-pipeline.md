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
  - `select [--max-level A2] [--limit 600]` (S2).
  - `carriers [--per-target 3]` (S3: Tatoeba taşıyıcı adayları).
  - `sentences` (S4: taşıyıcı cümleler, kontroller; engelleyici sorun varsa çıkış kodu 1).
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
  - Çok kelimeli ya da tireli girdilerin (207; wordfreq tirede de böler: "part-time") sırası yoktur, çünkü öbek tahmini çok kaba. Bu girdiler sona yazılır. Tireli yazım varyantları da aileye katılmaz. X_Lex bantları yalnızca tek kelimeli girdilerden seçilir.
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
  - **Eşleşme:** Cümle hedef anlamın lemmasını aynı sözcük türüyle içerir. spaCy'nin AUX etiketi fiil sayılır, özel isim etiketi (günler) isim sayılır. Pakette tek anlamı seçilmiş bir lemma isimle zarf arasında geçebilir, çünkü spaCy "today, tomorrow" için isim diyor, listeler zarf diyor. Lemma tanınmazsa yüzey biçimi denenir: spaCy "clothes" için "clothe" veriyor.
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
- **Gramer etiketleyici:** spaCy'nin Penn etiketleri ve lemmalarıyla çalışan kurallar. Kural emin değilse kod vermez. "I've got to go" zorunluluk sayılır (`gp.modals.obligation`), "have got" değil.
- **Kontroller (§5.1):**
  - Engelleyici: sözlükte olmayan kelime, paket seviyesini aşma, hedefin seviyesini aşma, uzunluk, hedef anlamın cümlede olmaması, uygunsuz kelime, biçim (tırnak, iki cümle), seçilmemiş belirsiz anlam.
  - Uyarı: yakın tekrar.
- **Çıktılar:**
  - `packs/<l2>/items/sentences.jsonl`
  - `word_senses.jsonl` içindeki `carriers`: anlamın seçilen cümleleri (`11` §4). S2 bu alanı boşaltır, S4 yeniden doldurur.
  - `work/sentences.<l2>.turkish.jsonl`: Tatoeba'nın Türkçe çevirileri (S5 için)
  - `work/sentences.<l2>.report.json`: sayılar, gramer dağılımı ve sorunlar
- **İlk sonuç (2026-09-27):**
  - 600 anlamın 344'ünde otomatik seçim değiştirildi: 320'sinde başka bir Tatoeba cümlesi, 24'ünde kendi cümlemiz.
  - 587 cümle (563 Tatoeba, 24 kendi). Seviyeler: A0 44, A1 408, A2 135. Ortalama 5,4 kelime. Engelleyici sorun yok.
  - Otomatik seçimin sık hataları şunlardı: deyimler ("a tall order", "right on the money"), yanlış anlam ("glasses" = gözlük), karamsar ton ("I don't have a family."), "I've got to …" yığılması ve etiketleyicinin kaçırdığı yapılar (edilgen, used to). Son ikisi kurallara eklendi.

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
