# ADR-0009 — Sıfır bütçe: ücretli servis olmadan çalışma

- **Durum:** Önerildi (2026-09-26). Kullanıcı kararı bekleniyor (F1-00).
- **Etkilediği kararlar:** ADR-0005 (Claude API), ADR-0006 (ses sağlayıcıları), ADR-0008 (içerik hattı). Kabul edilirse bu üçüne "ADR-0009 ile kısmen değiştirildi" notu düşülür.

## Bağlam

- Bütçe sıfır, banka kartı yok (`18` §0). Claude Code aboneliği var. API kullanımı aboneliğe dahil değil ve kart istiyor.
- Özgün plan iki ücretli kaleme dayanıyordu:
  - Claude API: etkileşimli rotalar ~$25–35/ay, içerik üretimi toplam ~$150–300
  - Azure Speech: ücretsiz katmanı bile kart doğrulaması istiyor
- Değişmez kurallar (I-01…I-18) aynen kalır. Soru yalnızca bunların ücretsiz araçlarla nasıl sağlanacağıdır.
- `07` §1.6 çekirdek döngünün LLM'e bağlı olmamasını zaten şart koşuyor. Bu ADR o yolu varsayılan yapar.
- **Ücretsiz katmanlar haber vermeden değişir.** Örneğin Gemini'nin ücretsiz katmanı 2026-04'te yalnızca Flash/Flash-Lite modellerine indi. Bu yüzden hiçbir özellik tek bir ücretsiz katmana bağımlı olmaz. Her dış servis bir adaptör arkasındadır; servis kapanınca deterministik yol çalışmaya devam eder.

Fiyat, kota ve koşullar 2026-09-26'da doğrulandı (kaynaklar en altta).

## Önerilen karar

### 1. Kart cevabı değerlendirme (`answer_check`; F1-07, F1-15)

| Seçenek | Kalite | Mahremiyet | Risk |
|---|---|---|---|
| **A. Yalnızca deterministik** | Paketteki varyant listesi kadar iyi. İpuçları şablonlu. | En iyisi: cihazda çalışır | Listede olmayan doğru cevaplar `uncertain` kalır |
| **B. A + Groq ücretsiz katmanı** | Yüksek (açık ağırlıklı modeller, ör. `openai/gpt-oss-120b`) | İstekler varsayılan olarak saklanmıyor; sıfır saklama (ZDR) açılabilir | Kotalar değişebilir; o zaman A'ya düşülür |
| C. A + Gemini ücretsiz katmanı | Yüksek | Ücretsiz katman içerikleri ürün geliştirmede kullanılabiliyor, insan incelemesi var | Öğrenci metni için uygun değil |
| D. Claude API | En yüksek (özgün plan) | İyi | Kart ve bütçe gerekiyor |

**Öneri: A hemen; B isteğe bağlı ve eval'den geçerse açık.**

**A — deterministik değerlendirme** (`03` §0.5'i genişletir):
1. Normalize edilmiş cevap referansla, paket varyantlarıyla ya da kişisel varyantlarla birebir eşleşirse → `correct`. Bu, bugünkü kuraldır.
2. Eşleşmezse cevap en yakın referans ya da varyantla **kelime düzeyinde hizalanır**. Lemma ve biçim bilgisi paketten gelir. Bulunan farklar: eksik kelime, fazla kelime, aynı lemmanın yanlış biçimi, sıra değişikliği, başka kelime.
3. Fark küçükse ve sınıflanabiliyorsa → `minor_error` ya da `wrong`. Kapalı katalogdan yalnızca kuralla kesin bulunabilen etiketler eklenir (ör. eksik tanımlık, 3. tekil -s, eksik yardımcı fiil). Fark hedef parçadaysa `target_ok=false`.
4. Hedef parça doğru ama cümlenin geri kalanı çok farklıysa → `uncertain`, çünkü geçerli başka bir söyleyiş olabilir.
   - Bu deneme **üretim kanıtı sayılmaz** (I-04).
   - FSRS'e `Hard` yazılır: ceza da yok, şişirme de yok. Kesin eşleme F1-07'de `03` §0.3'e yazılır.
   - Kullanıcı "cevabım da doğru olabilir" bildirimi gönderebilir. Bildirim `content_reports`'a düşer; kabul edilen varyant sonraki paket yamasına girer (`10` §8).
   - Kendi kendine kabul yoktur: `03` §0.3'teki öz değerlendirme yasağı korunur. A1–A2 öğrencisi kendi varyantının doğruluğunu güvenilir biçimde yargılayamaz.
5. Hedef parça yoksa ve fark büyükse → `off_target`.

**İpucu merdiveni şablonludur:**
- **H1:** Hizalamadan çıkan tür ("bir kelime eksik", "kelimenin biçimi", "sıra").
- **H2:** Farkın cevaptaki yeri işaretlenir.
- **H3:** Öğenin gramer kodu için paketteki Türkçe kural notu.
- **H4:** Referans.

H1–H3'ün cevabı içermediği paket derlemesinde (S9) test edilir (I-02).

**En önemli kaldıraç varyant kapsamıdır.** Her kart cümlesi için paket; kısaltmalı biçimleri, eş anlamlı kalıpları ve sıra alternatiflerini içerir. Bunlar içerik oturumlarında üretilir (§4).

**B — Groq adaptörü:**
- `07` §4.1 sözleşmesini kullanan sağlayıcıdan bağımsız rotaya bir adaptör olarak yazılır. Varsayılan olarak kapalıdır.
- Açık olduğunda eşleşmeyen her cevapta çağrılır (özgün tasarım). Kapalıyken ya da kota dolduğunda 2–5. adımlar çalışır.
- Açma koşulu: aynı altın set üzerinde `07` §8 eşiklerinin sağlanması. Eval ücretsiz kotaya yayılarak çalıştırılır.
- Ücretsiz kota (organizasyon başına, kart yok): `gpt-oss-120b` için dakikada 30 istek, günde 1.000 istek, dakikada 8K ve günde 200K token. Önbellekten okunan tokenlar sınıra sayılmaz.
- Tahmini kullanım: iki kullanıcı günde ~40–60 çağrı yapar. Çağrı başına ~1–3K token → günde 40–180K token. Sınırın altında ama sınıra yaklaşabilir. Aşılırsa A'ya düşülür.
- Aynı adaptörle başka ücretsiz sağlayıcılar da (Cloudflare Workers AI, OpenRouter'ın ücretsiz modelleri) denenebilir. Bunlar ayrıntılı incelenmedi.

### 2. Söyleyemediklerim önerisi (`gap_suggest`; F1-17)

- LLM olmadan doğal bir İngilizce karşılık güvenilir biçimde üretilemez.
- **Öneri:**
  - Groq açıksa `gap_suggest` çalışır (`07` §4.3; seviye kontrolü sunucuda).
  - Kapalıysa yakalama yine çalışır, öneri "bekliyor" durumunda kalır. Kullanıcı İngilizcesini kendisi yazabilir (ör. canlı derste öğrendiği ifade). Paketteki Tatoeba EN–TR çiftlerinden, Türkçe kelime örtüşmesiyle bulunan örnek cümleler de gösterilir.
  - LLM açıldığında bekleyen öneriler tamamlanır.
- **Değerlendirilip seçilmeyen:** ML Kit cihaz üstü çeviri. Ücretsiz ve Türkçeyi destekliyor, ama yalnızca Android/iOS'ta çalışıyor ve seviye kontrolü yok. Doğal olmayan bir çeviri karta dönüşürse öğrenci yanlış kalıbı ezberler.

### 3. Konuşma görevi ve aylık test işaretlemesi (`speaking_annotate`; F1-19)

- Akıcılık ölçümleri zaten deterministik (`08` §6). Konuşma hızı, duraklamalar ve dolgu sözcükleri kelime zamanlarından hesaplanır. Öğe kullanımı lemma eşleşmesiyle bulunur.
- Cümlecik sınırı isteyen ölçümler (EFC, cümlecik ortası duraklama) ve hata işaretleme LLM ister.
- **Öneri:**
  - Faz 1'de deterministik kısım çalışır. Görev ve test kayıtları zaten saklanıyor (`08` §5.2).
  - Groq açıksa işaretleme hemen yapılır. Değilse sonradan, saklanan kayıt ve transkript üzerinden geriye dönük yapılır.
  - Aylık testin (A23) ilk ölçümü deterministik ölçümlerle alınır. İşaretleme açıldığında aynı kayıtlar yeniden işlenir.

### 4. İçerik üretimi (F1-02…F1-05, `10`)

| Seçenek | Not |
|---|---|
| **A. Tatoeba + Claude Code oturumlarında taslak + deterministik doğrulama + 👤 örneklem** | Ücretsiz (abonelik). Batch'ten yavaş, oturum sınırları var. |
| B. Ücretsiz katmanlı LLM ile toplu üretim | Günlük 200K token binlerce öğe için yetersiz. Kalite ayrıca ölçülmeli. |
| C. Claude Batch API | Kart gerekiyor |

**Öneri: A.**
- **S3:** Önce Tatoeba EN–TR adayları kullanılır (CC BY 2.0 FR; cümle ve yazar kimliği saklanır). Eksik kalan hedefler için cümleler Claude Code oturumlarında yazılır ve `content/work/` altına JSONL olarak kaydedilir. Kaynak `llm`, lisans `own` (I-16). Çıktı dosyada durduğu için yeniden üretim gerekmez (`10` §1.5).
- **S4:** Deterministik kontroller aynen uygulanır (`10` §5.1). LLM doğrulama geçişi (§5.2) yerine iki adım gelir:
  - Üretenden ayrı bir Claude Code oturumunda bağımsız gözden geçirme
  - Her partide 👤 20 örneklik inceleme
- **S5 (tr-en):** Türkçe karşılıklar, açıklamalar, varyantlar, karşıtlık notları, hata kataloğu ve H3 kural notları aynı yolla üretilir.
- **S8 (X_Lex):** Kabul kuralları deterministiktir (`10` §5.3). Adaylar oturumda ya da basit bir ses dizimi üreteciyle çıkarılır.
- **Ölçek:** `en@1` paketi ~1.400 öğedir (`11` §3 manifest örneği). Birkaç oturuma yayılır.

### 5. Ses

| İhtiyaç | Öneri | Alternatif |
|---|---|---|
| S1 İngilizce öğrenci konuşması | **Deepgram Nova-3, kayıt kredisiyle** ($200, kart yok). Tahmini tüketim ~$2/ay, yani kredi yıllarca yeter. Kredi biterse cihaz üstü tanımaya düşülür. | Yalnızca cihaz üstü (`speech_to_text` → Android `SpeechRecognizer`). Ücretsiz, ama güçlü dil modeli öğrenci hatalarını "düzeltir" (`08` §2). Yanlış cevap "doğru" görünebilir (I-04 riski). |
| S2 Türkçe (Söyleyemediklerim) | **Cihaz üstü:** `speech_to_text` 7.5, `tr-TR`. Normal doğruluk yeterli. Windows desteği Faz 3'te kontrol edilir. | Groq `whisper-large-v3` (ücretsiz; günde 8 saat ses). Ağ gerektirir. |
| S3 Telaffuz (A07) | **Faz 4'e ertelenir;** Faz 1–3'te gerekmiyor. Faz 4 başında seçilir: bütçe varsa Azure, yoksa açık kaynak (ör. `sherpa-onnx` tabanlı). | — |
| S4 Paket sesleri (S6) | **Kokoro-82M** (Apache-2.0), içerik makinesinde çevrimdışı üretilir. Amerikan ve İngiliz sesleri (kadın/erkek), hız ayarı var. | Azure (kart gerekiyor). Cihaz TTS'iyle paket sesi (cihaza göre değişir, tutarsız). |
| S4 Dinamik TTS | **Cihaz üstü:** `flutter_tts` 4.2.5 (Android, Windows, web) | — |

**Ses notları:**
- **Kokoro sesleri:** en-AU sesi yok. `08` §8'deki "en az 4 ses, en az ikisi en-US dışı" kuralı İngiliz sesleriyle karşılanır; Avustralya aksanı eksik kalır. Model kartındaki notlara göre İngiliz seslerinin kalitesi en iyi Amerikan seslerinden düşük.
- **Kokoro Python sürümü:** `kokoro` 0.9.4 Python < 3.13, `kokoro-onnx` 0.6.1 Python < 3.14 istiyor. İçerik araçları 3.14'te çalışıyor. Ses adımı ayrı bir uv ortamında (3.12/3.13) çalışır; uv o Python sürümünü kendisi kurar.
- **Cihaz üstü yedek:** İngilizce tanıma cihaz üstü yedeğe düştüğünde denemeler `asr_source=device` olarak işaretlenir. Öğrenci modeli bu kanıtı ayrıca değerlendirebilir.

### 6. Eval ve kullanım kaydı

- **Deterministik denetleyici:** Altın set (≥ 200 vaka; `07` §8'deki vaka kaynakları) birim testi olarak CI'da, ücretsiz çalışır.
- **LLM sağlayıcısı açılacaksa:** Aynı set o sağlayıcıyla da çalıştırılır. Ücretsiz kotada çalıştığı için "ücretli iş" onayı gerekmez; yine de önceden haber verilir.
- **Kullanım tabloları:** `llm_usage` ve `speech_usage` kalır. Maliyet $0 olsa da kota ve kredi tüketimini gösterirler.

## Kullanıcı kararları

| # | Soru | Seçenekler |
|---|---|---|
| K1 | Çalışma anında LLM | **(a) Groq isteğe bağlı, eval'den geçerse açık [öneri]** · (b) hiç LLM yok · (c) Gemini ücretsiz katmanı · (d) Claude API için bütçeyi bekle |
| K2 | İngilizce konuşma tanıma | **(a) Deepgram kayıt kredisi [öneri]** · (b) yalnızca cihaz üstü |
| K3 | Paket sesleri | **(a) Kokoro, çevrimdışı [öneri]** · (b) yalnızca cihaz TTS |
| K4 | İçerik | **(a) Tatoeba + Claude Code oturumları + deterministik doğrulama + 👤 örneklem [öneri; gerçekçi tek yol]** |

👤 Hesaplar (kabulden sonra `19`'a eklenir):
- **K1=a:** Groq hesabı açılır (e-posta, kart yok). Anahtarı kullanıcı Supabase secrets'a girer. Hesapta ZDR açılır.
- **K2=a:** Deepgram hesabı açılır (e-posta, kart yok). Anahtarı kullanıcı Supabase secrets'a girer.

## Faz 1'e etkisi

| Görev | Değişiklik |
|---|---|
| F1-03 | Batch LLM yerine Tatoeba + Claude Code oturumları. `claude-api` skill'i gerekmez. |
| F1-04 | Aynı yol; ayrıca H3 kural notları ve zengin varyant listeleri |
| F1-05 | S6: Azure yerine Kokoro |
| F1-07 | Hizalamaya dayalı deterministik değerlendirme + şablonlu merdiven (§1) |
| F1-14 | Deepgram adaptörü (İngilizce) + cihaz üstü Türkçe. Azure adaptörü yok. |
| F1-15 | `answer_check`: sağlayıcıdan bağımsız rota, Groq adaptörü (kapalı), altın set |
| F1-17 | Öneri Groq'a bağlı; kapalıyken bekleyen öneri + Tatoeba örnekleri |
| F1-19 | Deterministik akıcılık + kayıt. LLM işaretlemesi isteğe bağlı ya da geriye dönük. |
| Kabul | "answer_check eval eşikleri" yerine deterministik denetleyicinin altın set eşikleri geçer: doğru/varyant cevabı "yanlış" sayma ≤ %3, H1–H3'te cevap sızıntısı %0, katalog dışı etiket %0. "Maliyet tablolarda görünüyor" yerine "kullanım ve kota tablolarda görünüyor" gelir. |

## Değişmeyenler

- Değişmez kuralların tamamı (I-01…I-18).
- Rota sözleşmeleri (`07` §4): sağlayıcıdan bağımsız kalır. Bütçe olursa Claude aynı sözleşmeyle geri döner; ADR-0005'in kararları askıya alınır, silinmez.
- Yerel öncelikli mimari, FSRS ve paket formatı.

## Sonuçlar

- **Maliyet:** Aylık işletim maliyeti $0. Deepgram kredisinden tahminen ~$2/ay tüketilir.
- **Kalite:** Açıklamalar şablonlu ve daha kısa. Listede olmayan doğru cevaplar `uncertain` kalır. İçeriğin en önemli parçası varyant kalitesi olur.
- **Deneyim:** Söyleyemediklerim ve konuşma geri bildirimi LLM olmadan zayıflar. K1=b seçilirse bu iki özellik Faz 1'de yalnızca "yakalama + kayıt + akıcılık" düzeyinde kalır.
- **Dayanıklılık:** Ücretsiz katman değişikliklerini adaptör ve deterministik yol karşılar.
- **Depolama:** Supabase Storage sınırı 1 GB. Paket sesleri ve görev kayıtları izlenir. Görev kaydı 32 kbps AAC ile dakikada ~240 KB tutar.
- **Mahremiyet (`14`):**
  - Groq'a yalnızca metin gider: cevap, istem, öğe bilgisi. Ad, e-posta ve ses gitmez.
  - Deepgram'a ses gider; `mip_opt_out=true` kullanılır.
- **Güncellenecek dokümanlar (kabulden sonra):**
  - `03` §0.3 ve §0.5
  - `07` §1–3 ve §7–9
  - `08` §3, §8 ve §10
  - `10` §2–5 ve §9
  - `11` (ses listesi)
  - `12` §4 (yeni paketler: `speech_to_text`, `flutter_tts`)
  - `14` (sağlayıcılar)
  - `17` (Faz 1 görev metinleri ve kabul)
  - `18` §0–1
  - `19` (Groq, Deepgram)
  - ADR-0005, 0006 ve 0008'e "kısmen değiştirildi" notu

## Kaynaklar (2026-09-26'da erişildi)

- **Groq:**
  - Kotalar: <https://console.groq.com/docs/rate-limits>
  - Veri politikası: <https://console.groq.com/docs/your-data>
  - Kartsız ücretsiz katman: <https://perkstack.co/blog/groq-api-free-tier>
- **Gemini ücretsiz katmanı:**
  - Verinin kullanımı: <https://ampm-aiops.com/en/guides/gemini-free-tier-data-tradeoff-2026/>
  - Modeller: <https://costbench.com/software/llm-api-providers/google-gemini-api/free-plan/>
- **Deepgram:** <https://deepgram.com/pricing>, <https://costbench.com/software/ai-transcription-apis/deepgram/free-plan/>
- **Kokoro-82M:**
  - Model kartı ve lisans: <https://huggingface.co/hexgrad/Kokoro-82M>
  - Sesler: <https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md>
  - PyPI: `kokoro` 0.9.4, `kokoro-onnx` 0.6.1
- **ML Kit çeviri dilleri:** <https://developers.google.com/ml-kit/language/translation/translation-language-support>
- **pub.dev:** `flutter_tts` 4.2.5, `speech_to_text` 7.5.0, `google_mlkit_translation` 0.15.1, `sherpa_onnx` 1.13.8
