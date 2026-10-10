# ADR-0009 — Sıfır bütçe: ücretsiz katmanlarla en iyi kalite

- **Durum:** Kabul edildi (2026-09-26).
- **Kullanıcı kararı:** Her bileşende ücretsiz olan en iyi seçenek kullanılır. Gemini de kullanılabilir; ücretsiz katmanın veriyi ürün geliştirmede kullanması kullanıcı için sorun değil.
- **Kısmen değiştirdiği kararlar:** ADR-0005 (Claude API), ADR-0006 (ses sağlayıcıları), ADR-0008 (içerik hattı).

## Bağlam

- Bütçe sıfır, banka kartı yok (`18` §0). Claude Code aboneliği var. API kullanımı aboneliğe dahil değil ve kart istiyor.
- Özgün plan iki ücretli kaleme dayanıyordu:
  - Claude API: etkileşimli rotalar ~$25–35/ay, içerik üretimi toplam ~$150–300
  - Azure Speech: ücretsiz katmanı bile kart doğrulaması istiyor
- `07` §1.6 çekirdek döngünün LLM'e bağlı olmamasını zaten şart koşuyor.
- **Ücretsiz katmanlar haber vermeden değişir.** Örneğin Gemini'nin Pro modelleri 2026-05'te ücretli katmana geçti; Flash modellerinin günlük kotası 2025 sonunda ~250'den ~20 isteğe indi.

Fiyat, kota ve koşullar 2026-09-26'da doğrulandı (kaynaklar en altta).

## Karar

### İlkeler

1. Ücretli ya da kart isteyen hiçbir servis kullanılmaz.
2. Her bileşende **ücretsiz olan en iyi seçenek** kullanılır. "En iyi" tahminle değil, kendi eval setlerimizle ölçülür.
3. Her dış servis bir adaptör arkasındadır. Çağrı sırası: birincil sağlayıcı → yedek sağlayıcı → deterministik yol. Kota dolması ya da ücretsiz katmanın kalkması hiçbir özelliği durdurmaz.
4. Değişmez kurallar (I-01…I-18) aynen kalır.

### 1. LLM rotaları

| Rota | Birincil | Yedek | Son çare |
|---|---|---|---|
| `answer_check` (çok istek, düşük gecikme) | Gemini Flash-Lite | Groq `openai/gpt-oss-120b` | Deterministik değerlendirme (§2) |
| `gap_suggest` (az istek, kalite önemli) | Gemini Flash (en güncel sürüm) | Gemini Flash-Lite → Groq | Yakalama + bekleyen öneri |
| `speaking_annotate` ve aylık test (az istek, uzun bağlam) | Gemini Flash | Gemini Flash-Lite | Deterministik akıcılık ölçümleri; işaretleme sonradan |
| Sonraki fazların rotaları (`roleplay_*`, `writing_feedback`, `mediation_check`, `comprehension_check`) | O fazda eval ile seçilir | | Rotaya göre |

**Ücretsiz kotalar (2026-09-26):**
- **Gemini:** Kotalar proje ve model başınadır; gerçek değerler AI Studio'da görünür.
  - Flash sürümleri (3.5–3.8): günde ~20 istek
  - Flash-Lite sürümleri (3.1, 3.5): günde ~500 istek
  - Günlük kota Pasifik saatiyle gece yarısı sıfırlanır.
- **Groq (`gpt-oss-120b`):** Dakikada 30 istek, günde 1.000 istek, dakikada 8K ve günde 200K token. Önbellekten okunan tokenlar sınıra sayılmaz.

**Seçim ve adaptör kuralları:**
- **Sıra eval'le kesinleşir.** Tablodaki sıra bir tahmindir. Her rota için birincil ve yedek sağlayıcıyı F1-15'teki eval belirler. "En iyi", `07` §8 eşiklerini geçenler arasında en yüksek doğruluğu veren seçenektir; eşitlikte gecikmeye bakılır.
- **Aile içi yedek:** Kota model başına olduğu için yönlendirici aynı ailenin eval'den geçmiş başka bir sürümüne de düşebilir.
- **Model adları** yalnızca `llm_config.ts`'dedir.
- **SDK seçimi** F1-15'te belgelerle (context7) doğrulanarak yapılır. OpenAI uyumlu uç nokta sunan sağlayıcılar (Groq ve Gemini'nin uyumluluk katmanı) tek bir adaptörü paylaşabilir.
- **Adil paylaşım:** İki kullanıcı aynı kotayı paylaşır. Her kullanıcıya her kotanın yarısı ayrılır; biri kotasını bitirirse ötekinin payına dokunulmaz.
- **Veri:** Gemini'nin ücretsiz katmanında gönderilen içerik Google ürünlerini geliştirmede kullanılabilir ve insanlar tarafından incelenebilir.
  - Berat bunu kabul etti.
  - Partner kendi adına karşılamada (F1-12) açıkça onay verir. Onay yoksa o kullanıcının istekleri Groq'a gider; Groq istek içeriğini varsayılan olarak saklamıyor ve hesapta ZDR açılır. Groq kullanılamıyorsa istek deterministik yola gider.
  - Hiçbir LLM sağlayıcısına ad, e-posta, kullanıcı kimliği ya da ses gitmez.

### 2. Deterministik değerlendirme (her zaman çalışan temel)

`03` §0.5'i genişletir. LLM'ler bu katmanın üstünde çalışır.

1. **Eşleşme:** Normalize edilmiş cevap referansla, paket varyantlarıyla ya da kişisel varyantlarla birebir eşleşirse → `correct`. LLM çağrılmaz; bu, bugünkü kuraldır.
2. **LLM varsa:** Eşleşmeyen cevap `answer_check`'e gider (özgün tasarım).
3. **LLM yoksa** (çevrimdışı, kota dolu ya da onay yok): Cevap en yakın referans ya da varyantla **kelime düzeyinde hizalanır**. Lemma ve biçim bilgisi paketten gelir. Bulunan farklar: eksik kelime, fazla kelime, aynı lemmanın yanlış biçimi, sıra değişikliği, başka kelime.
   - **Küçük ve sınıflanabilir fark** → `minor_error` ya da `wrong`. Kapalı katalogdan yalnızca kuralla kesin bulunabilen etiketler eklenir (ör. eksik tanımlık, 3. tekil -s, eksik yardımcı fiil). Fark hedef parçadaysa `target_ok=false`.
   - **Hedef parça doğru ama cümlenin geri kalanı çok farklı** → `uncertain`, çünkü geçerli başka bir söyleyiş olabilir.
     - Deneme **üretim kanıtı sayılmaz** (I-04).
     - FSRS'e `Hard` yazılır: ceza da yok, şişirme de yok.
     - Deneme `llm.pending=true` olarak işaretlenir. LLM erişilebilir olunca kontrol edilir ve sonuç `attempt_amendments` (`llm_resolved`) olarak eklenir (I-03).
   - **Hedef parça yok ve fark büyük** → `off_target`.
4. **İtiraz:** Kullanıcı her sonuca "cevabım da doğru olabilir" diyebilir.
   - İtiraz `attempt_amendments` (`user_dispute`) olarak yazılır.
   - LLM varsa yeniden kontrol edilir. İçerik bildirimi olarak da kaydedilir; kabul edilen varyant sonraki paket yamasına girer (`10` §8).
   - Kendi kendine kabul yoktur; `03` §0.3'teki öz değerlendirme yasağı korunur. A1–A2 öğrencisi kendi varyantının doğruluğunu güvenilir biçimde yargılayamaz.

**LLM'siz ipucu merdiveni şablonludur:**
- **H1:** Hizalamadan çıkan tür ("bir kelime eksik", "kelimenin biçimi", "sıra").
- **H2:** Farkın cevaptaki yeri işaretlenir.
- **H3:** Öğenin gramer kodu için paketteki Türkçe kural notu.
- **H4:** Referans.

H1–H3'ün cevabı içermediği paket derlemesinde (S9) test edilir (I-02).

**Not (2026-09-30, F1-15):** `answer_check` altın seti deterministik yolda ölçüldü. Doğru cevapların %19,8'i yanlış sayılıyordu; ADR'nin eşiği %3.
- **Nedenler:** tanıma dolguları ve tekrarlar hedefi bölüyordu; isimden sonraki "'s" çoğul gibi okunuyordu; hedefsiz yeniden ifadeler "hedef yok, fark büyük" kuralıyla `off_target` oluyordu.
- **Değişiklikler:**
  - Normalizasyona `fillers` ve `collapse_repeats` eklendi.
  - "'s" artık "is" okunuyor.
  - 3. maddedeki "Hedef parça yok ve fark büyük → off_target" kuralı inceltildi: cevap doğru cevabın kelimelerinin en az üçte birini koruyor ve yalnızca eksiltmiyorsa `uncertain` olur (`03` §0.5).
- **Sonuç:** Oran %2,3'e indi; sızıntı %0.

**Varyant kapsamı en önemli kaldıraçtır.** Her kart cümlesi için paket; kısaltmalı biçimleri, eş anlamlı kalıpları ve sıra alternatiflerini içerir.

### 3. İçerik üretimi (`10`)

Ücretsiz LLM kotaları binlerce öğe için yetersiz. Claude Code oturumları hem ücretsiz (abonelik) hem de en yüksek kaliteli seçenek.

- **S3:** Önce Tatoeba EN–TR adayları kullanılır (CC BY 2.0 FR; cümle ve yazar kimliği saklanır). Eksik kalan hedefler için cümleler Claude Code oturumlarında yazılır ve `content/work/` altına JSONL olarak kaydedilir. Kaynak `llm`, lisans `own` (I-16). Çıktı dosyada durduğu için yeniden üretim gerekmez (`10` §1.5).
- **S4:** Deterministik kontroller aynen uygulanır (`10` §5.1). LLM doğrulama geçişi (§5.2) yerine iki adım gelir:
  - Üretenden ayrı bir Claude Code oturumunda bağımsız gözden geçirme
  - Her partide 👤 20 örneklik inceleme
- **S5 (tr-en):** Türkçe karşılıklar, açıklamalar, varyantlar, karşıtlık notları, hata kataloğu ve H3 kural notları aynı yolla üretilir.
- **S8 (X_Lex):** Kabul kuralları deterministiktir (`10` §5.3). Adaylar oturumda ya da basit bir ses dizimi üreteciyle çıkarılır.
- **Ölçek:** `en@1` paketi ~1.400 öğedir (`11` §3 manifest örneği). Birkaç oturuma yayılır.

### 4. Ses

| İhtiyaç | Karar | Yedek ve karşılaştırma |
|---|---|---|
| S1 İngilizce öğrenci konuşması | **Deepgram Nova-3, kayıt kredisiyle** ($200, kart yok). Tahmini tüketim ~$2/ay, yani kredi yıllarca yeter. | F2-01 karşılaştırma testine ücretsiz adaylar eklenir: Gemini Transcribe, Groq `whisper-large-v3`, cihaz üstü tanıma (Android, `sherpa-onnx`) ve ücretsiz kredisi varsa AssemblyAI. Kredi biterse testte ikinci gelen kullanılır. |
| S2 Türkçe (Söyleyemediklerim) | **Cihaz üstü:** `speech_to_text` (`tr-TR`). Normal doğruluk yeterli. | Windows/web ya da cihazda Türkçe yoksa sunucu: Groq `whisper-large-v3` ya da Gemini Transcribe |
| S3 Telaffuz (A07, F2-05) | **Faz 2 başında karar verilir.** Azure kartsız kullanılamıyor. Adaylar: açık kaynak ses birimi tanıma + GOP puanı, Gemini ses anlama (güvenilirliği ölçülmeli), ASR kelime güven puanları. | Karar çıkana kadar gölgeleme puansız çalışır: kullanıcı kendi kaydını model sesle karşılaştırır. |
| S4 Paket sesleri (S6) | **Kokoro-82M** (Apache-2.0), içerik makinesinde çevrimdışı üretilir. Amerikan ve İngiliz sesleri (kadın/erkek), hız ayarı var. | F1-05'te kısa dinleme karşılaştırması: Kokoro ve Gemini Flash TTS (ücretsiz katman). Gemini'nin kotası paketi makul sürede karşılıyorsa 👤 kullanıcı seçer. |
| S4 Dinamik TTS | **Cihaz üstü:** `flutter_tts` (Android, Windows, web) | Aynı metnin paket sesi varsa o çalınır. |

**Ses notları:**
- **Kokoro sesleri:** en-AU sesi yok. `08` §8'deki "en az 4 ses, en az ikisi en-US dışı" kuralı İngiliz sesleriyle karşılanır; Avustralya aksanı eksik kalır.
- **Kokoro Python sürümü:** `kokoro` 0.9.4 Python < 3.13, `kokoro-onnx` 0.6.1 Python < 3.14 istiyor. İçerik araçları 3.14'te çalışıyor. Ses adımı ayrı bir uv ortamında (3.12/3.13) çalışır.
- **Donanım:** Geliştirme makinesi Intel Core Ultra 7 258V, 32 GB RAM, NVIDIA GPU yok. Kokoro CPU'da hızlı çalışıyor. Büyük açık TTS modelleri bu makinede pratik değil.
- **Cihaz üstü yedek:** İngilizce tanıma cihaz üstü yedeğe düşerse denemeler `asr.provider=device` olarak işaretlenir. Güçlü dil modeli öğrenci hatalarını "düzeltebilir" (`08` §2); öğrenci modeli bu kanıtı ayrıca değerlendirir.

### 5. Eval ve kullanım kaydı

- **Eval:** Ücretsiz kotalarda çalışır. "Ücretli iş" onayı gerekmez, ama kullanıcıya süre ve kota etkisi önceden söylenir. Flash'ın günlük ~20 isteği yüzünden bazı rotaların eval'i birkaç güne yayılır.
- **Deterministik denetleyici:** Altın set (≥ 200 vaka) birim testi olarak CI'da çalışır.
- **`llm_usage`:** `provider` sütunu eklenir. Ücretsiz katmanda `cost_usd` = 0 olur; tablo kota tüketimini izler.
- **`speech_usage`:** Deepgram kredisinin tüketimini izler.
- **Kota sınırı:** Günlük kullanıcı bütçesi ($1,50) yerine sağlayıcı kotaları ve §1'deki adil paylaşım geçer.

## Faz 1'e etkisi

| Görev | Değişiklik |
|---|---|
| F1-03 | Batch LLM yerine Tatoeba + Claude Code oturumları. `claude-api` skill'i gerekmez. |
| F1-04 | Aynı yol; ayrıca H3 kural notları ve zengin varyant listeleri |
| F1-05 | S6: Kokoro + 👤 dinleme karşılaştırması |
| F1-07 | Hizalamaya dayalı deterministik değerlendirme + şablonlu merdiven (§2) |
| F1-12 | Karşılamada yapay zekâ veri onayı (kullanıcı başına) |
| F1-14 | Deepgram adaptörü (İngilizce) + cihaz üstü Türkçe. Azure adaptörü yok. |
| F1-15 | Sağlayıcı yönlendiricisi, Gemini ve Groq adaptörleri, kota ve adil paylaşım, altın set, ücretsiz kotalarda eval |
| F1-17 | `gap_suggest` Gemini Flash ile; kota dolunca bekleyen öneri |
| F1-19 | `speaking_annotate` Gemini Flash ile; kota yoksa sonradan işaretleme |
| Kabul | "answer_check eval eşikleri" korunur (seçilen sağlayıcıyla). Deterministik denetleyici için ayrıca: doğru ya da varyant cevabı "yanlış" sayma ≤ %3, H1–H3'te cevap sızıntısı %0. "Maliyet tablolarda görünüyor" yerine "kullanım ve kota tablolarda görünüyor" gelir. |

## Değişmeyenler

- Değişmez kuralların tamamı (I-01…I-18).
- Rota sözleşmeleri (`07` §4). Bütçe olursa Claude aynı sözleşmeyle geri döner; ADR-0005'in kararları askıya alınır, silinmez.
- Yerel öncelikli mimari, FSRS ve paket formatı.

## Sonuçlar

- **Maliyet:** Aylık işletim maliyeti $0. Deepgram kredisinden tahminen ~$2/ay tüketilir.
- **Kalite:** Ücretsiz modeller Claude'dan zayıf olabilir. Eşikleri geçmeyen sağlayıcı açılmaz, deterministik yol kalır.
- **Dayanıklılık:** Ücretsiz katman değişikliklerini yedek sağlayıcı ve deterministik yol karşılar. Kota ve model listesi her faz başında yeniden kontrol edilir.
- **Mahremiyet:** Gemini'ye giden metinler insan incelemesine açık olabilir. Bu yüzden onay kullanıcı başınadır (§1). Deepgram'a ses gider; `mip_opt_out=true` kullanılır.
- **👤 Hesaplar (kart yok):**
  - Google AI Studio API anahtarı (Google hesabı)
  - Groq (e-posta)
  - Deepgram (e-posta)
  - Anahtarları kullanıcı Supabase secrets'a girer (`19` §1).
- **Depolama:** Supabase Storage sınırı 1 GB. Paket sesleri ve görev kayıtları izlenir. Görev kaydı 32 kbps AAC ile dakikada ~240 KB tutar.
- **Kod:** `llm_config.ts` ve `speech_config.ts`, F1-14 ve F1-15'te bu karara göre yeniden yazılır. O zamana kadar Claude/Azure ayarlarını taşırlar ama hiçbir yerde kullanılmazlar.

## Kaynaklar (2026-09-26'da erişildi)

- **Gemini:**
  - Ücretsiz katman modelleri ve verinin kullanımı: <https://ai.google.dev/gemini-api/docs/pricing>
  - Kotalar (AI Studio'da görünür): <https://ai.google.dev/gemini-api/docs/rate-limits>
  - Model başına günlük istek sayıları: <https://www.scriptbyai.com/gemini-api-free-tier-limits/>
  - Bölgeler (Türkiye ve Almanya dahil): <https://ai.google.dev/gemini-api/docs/available-regions>
- **Groq:**
  - Kotalar: <https://console.groq.com/docs/rate-limits>
  - Veri politikası: <https://console.groq.com/docs/your-data>
  - Kartsız ücretsiz katman: <https://perkstack.co/blog/groq-api-free-tier>
- **Deepgram:** <https://deepgram.com/pricing>, <https://costbench.com/software/ai-transcription-apis/deepgram/free-plan/>
- **Kokoro-82M:**
  - Model kartı ve lisans: <https://huggingface.co/hexgrad/Kokoro-82M>
  - Sesler: <https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md>
  - PyPI: `kokoro` 0.9.4, `kokoro-onnx` 0.6.1
- **Değerlendirilip seçilmeyenler:**
  - Cerebras ücretsiz katmanı: günde 1M token, ama bağlam 8K ile sınırlı ve koşulları değişiyor. <https://inference-docs.cerebras.ai/support/rate-limits>
  - Mistral Experiment planı: "değerlendirme için, üretim için değil". <https://costbench.com/software/llm-api-providers/mistral-ai/free-plan/>
  - ML Kit cihaz üstü çeviri: yalnızca Android/iOS, seviye kontrolü yok. <https://developers.google.com/ml-kit/language/translation/translation-language-support>
- **pub.dev:** `flutter_tts` 4.2.5, `speech_to_text` 7.5.0, `sherpa_onnx` 1.13.8
