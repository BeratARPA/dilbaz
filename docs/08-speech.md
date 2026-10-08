# 08 — Ses: Konuşma Tanıma, Seslendirme, Telaffuz

Dilbaz'ın hedefi konuşmak olduğu için ses hattı çekirdek altyapıdır. Bu doküman ses tanıma (ASR/STT), seslendirme (TTS), telaffuz değerlendirmesi, kayıt formatları, işleme hattı ve sağlayıcı seçimini tanımlar. Sağlayıcı bilgileri 2026-09-25'te doğrulanmıştır. Fiyatlar değişebilir; kurulumda kontrol edilir.

## 1. İhtiyaçlar

| # | İhtiyaç | Nerede | Kritik özellik |
|---|---|---|---|
| S1 | Öğrencinin İngilizce konuşmasını yazıya dökmek | A01, A04, A08, A11–A13, A15, A21–A23 | **Kelimesi kelimesine** olmalı: hataları "düzeltmemeli", dolgu sözcüklerini (uh, um) tutmalı, kelime zamanlarını vermeli |
| S2 | Türkçe konuşmayı yazıya dökmek | A19 Söyleyemediklerim | Normal doğruluk yeterli |
| S3 | Telaffuz değerlendirmesi (referans metne karşı) | A07 gölgeleme | Kelime/ses düzeyinde doğruluk, eksik/fazla ses, vurgu/ritim |
| S4 | Seslendirme (TTS) | Tüm öğe sesleri, diyaloglar, rol oyunu, ses ayırt etme | Birden çok ses ve aksan, hız ayarı (SSML) |

## 2. Neden "kelimesi kelimesine" ASR şart?

Genel amaçlı ASR modelleri güçlü bir dil modeliyle çalışır ve konuşmayı "düzgün" yazıya çevirmeye eğilimlidir. Öğrenci "He go to work" dese bile transkript "He goes to work" çıkabilir. O zaman hata görünmez olur ve Dilbaz yanlış geri bildirim verir. Araştırmalar bunu doğruluyor:

- Whisper duraksama ve tekrarları atlamaya eğilimlidir. Kelimesi kelimesine çıktı için ince ayar ya da prompt gerekir (Ma, Qian, Gales & Knill, 2023).
- İkinci dil öğrencilerinin serbest konuşmasında test edilen üç ASR sistemi de yanlış fiil ve isim biçimlerini düzeltti; en çok Whisper (LET Journal of Central Japan, 2025).
- Okuma hatalarını ASR sonrası tespit etmek, transkript kelimesi kelimesine değilse başarısız olur (Smith vd., Interspeech 2025).

**Sonuç:** Varsayılan sağlayıcı Whisper tabanlı olmayacak. Seçim, kendi kayıtlarımızla yapılan **karşılaştırma testiyle** (§3) kesinleşir. Kullanıcı transkripti her zaman görür ve "yanlış duyuldu" diyebilir (`03` §0.3).

## 3. Sağlayıcı seçimi (ADR-0006, ADR-0009)

### 3.1 Başlangıç seçimi

Bütçe sıfırdır (ADR-0009). Azure kart doğrulaması istediği için kullanılmaz.

| İhtiyaç | Sağlayıcı | Gerekçe |
|---|---|---|
| S1 İngilizce öğrenci konuşması | **Deepgram Nova-3** (kayıtlı ses API'si), kayıt kredisiyle | Dolgu sözcükleri parametreyle açılabiliyor (`filler_words=true`), kelime başına başlangıç/bitiş zamanı var. ~$0,0043/dk; yeni hesaba kartsız $200 kredi, bizim kullanımımızla yıllarca yeter. |
| S2 Türkçe | **Cihaz üstü tanıma** (`speech_to_text`, `tr-TR`) | Ücretsiz, hızlı, ses cihazdan çıkmaz. Windows/web ya da cihazda Türkçe yoksa sunucu yedeği: Groq `whisper-large-v3` ya da Gemini Transcribe (ücretsiz katmanlar). |
| S3 Telaffuz | **Faz 2 başında seçilir** (F2-05 öncesi) | Adaylar: açık kaynak ses birimi tanıma + GOP puanı, Gemini ses anlama (güvenilirliği ölçülmeli), ASR kelime güven puanları. Karar çıkana kadar gölgeleme puansız çalışır. |
| S4 TTS, paket sesleri | **Kokoro-82M** (Apache-2.0), içerik makinesinde çevrimdışı | Amerikan ve İngiliz sesleri, hız ayarı; sınırsız ve ücretsiz. F1-05'te Gemini Flash TTS ile kısa bir dinleme karşılaştırması yapılır. |
| S4 TTS, dinamik | **Cihaz üstü** (`flutter_tts`) | Söyleyemediklerim önerisi, rol oyunu cevapları. Aynı metnin paket sesi varsa o çalınır. |

### 3.2 Karşılaştırma testi (ASR bake-off) — Faz 2

**Veri seti:** 60 ifade (her kullanıcıdan 30).
- **40 senaryolu cümle:** Türkçe konuşanlara özgü **bilinçli hatalar** içerir, kullanıcı doğal biçimde okur. Örnekler:
  - "I have problem with my key."
  - "He go to work every day."
  - "She have two brother."
  - "I am agree."
  - "Yesterday I go to cinema."
  - "How many years are you?"
  - "I didn't went there."
  - "He is doctor."
  - "I am living here since two years."
- **20 serbest konuşma:** 30–60 sn.

**Doğru transkript:**
- Senaryolu cümlelerde metnin kendisidir. Okunuş dinlenerek doğrulanır.
- Serbest konuşmada kullanıcı kendi konuşmasını dinleyerek kelimesi kelimesine yazar; dolgu sözcükleri de dahildir.

**Adaylar** (yalnızca ücretsiz erişilebilenler, ADR-0009; ücretsiz erişim Faz 2 başında yeniden doğrulanır):
- Deepgram Nova-3 (`filler_words=true`; kayıt kredisi)
- Gemini Transcribe (ücretsiz katman; dolgu sözcüklerini koruma talimatıyla)
- Groq `whisper-large-v3` (ücretsiz katman, kelime zamanlı)
- Cihaz üstü: Android `SpeechRecognizer` (`speech_to_text`), `sherpa-onnx` modelleri
- AssemblyAI (`disfluencies=true`; ücretsiz kredisi varsa)

**Ölçütler:**
1. **Hata koruma oranı:** bilinçli hataların düzeltilmeden transkripte geçme yüzdesi. Hedef ≥ %90.
2. Kelimesi kelimesine transkripte göre WER.
3. Dolgu sözcüğü yakalama oranı.
4. Gecikme (p50/p90).
5. Ücretsiz kota ya da kredi süresi.

**Karar kuralı:** Hata koruma ≥ %90 olanlar arasında en düşük WER. Eşitlikte gecikme ve ücretsiz kotaya bakılır. Sonuç `evals/asr/results/` altına ve ADR-0006'ya yazılır.

Hiçbir aday %90'a ulaşmazsa kartlar için şu hibrit yol denenir: beklenen cevap ve varyantları "ipucu" olarak veren (bias/prompt) bir sağlayıcı ayarı ya da hedef bölgede telaffuz değerlendirmesiyle çapraz kontrol.

### 3.3 Sağlayıcıdan bağımsız arayüz

Sunucu tarafında (Edge Functions, TypeScript):

```ts
interface SpeechToText {
  transcribe(audio: AudioInput, opts: { lang: string; verbatim: boolean; wordTimestamps: boolean;
    hints?: string[] }): Promise<Transcript>;
}
type Transcript = { text: string; words: { w: string; startMs: number; endMs: number; conf?: number }[];
                    provider: string; model: string; durationMs: number };

interface PronunciationAssessor {
  assess(audio: AudioInput, referenceText: string, lang: string): Promise<PronReport>;
}
type PronReport = { overall: number; accuracy: number; fluency: number; completeness: number; prosody?: number;
                    words: { w: string; accuracy: number; errorType: "None"|"Mispronunciation"|"Omission"|"Insertion"|"UnexpectedBreak"|"MissingBreak"|"Monotone";
                             phonemes?: { p: string; accuracy: number }[] }[] };

interface TextToSpeech {
  synthesize(text: string, opts: { voice: string; rate: number; format: "mp3"|"ogg" }): Promise<Uint8Array>;
}
```

Adaptörler `supabase/functions/_shared/speech/` altındadır: `deepgram.ts` (F1-14), Türkçe sunucu yedeği için `groq_stt.ts` (F1-17: Groq `whisper-large-v3`, `language=tr`, `verbose_json`; ücretsiz katman, `speech_usage`'da maliyet 0; `transcribe?lang=tr`, Groq anahtarı yoksa `stt_unavailable`), Faz 2'de karşılaştırma testinin adayları. Hangi rotanın hangi adaptörü kullandığı `speech_config.ts` dosyasında tanımlıdır. Cihaz üstü tanıma ve dinamik TTS istemcide, `app/lib/data/speech/` altında aynı arayüzlerin Dart karşılıklarıyla çalışır. Türkçe dikte (F1-17, `DeviceFirstDictation`): cihaz tanıyıcısı (`speech_to_text` 7.5) Türkçe yerel ayarını listeliyorsa ses cihazda kalır; listelemiyorsa (Windows'ta Türkçe paketi yoksa, bazı web tarayıcılarında) kayıt `transcribe?lang=tr`'ye gider. Karar dinlemeden önce verilir, çünkü cihaz tanıyıcısı sesi saklamaz. `TextToSpeech` arayüzü sunucuda yalnızca bir sağlayıcı seçilirse kullanılır.

## 4. Kayıt formatları (istemci)

`record` paketi (7.x) tüm platformlarda çalışır, ancak kodlayıcı desteği platforma göre değişir. Opus Windows'ta yoktur, AAC web'de yalnızca Safari'dedir.

| Amaç | Android | Windows | Web (Chrome/Firefox) |
|---|---|---|---|
| Genel ASR (S1, S2) | AAC-LC, 16 kHz mono, ~32 kbps (`.m4a`) | AAC-LC (`.m4a`) | Opus (`.webm`/`.ogg`) |
| Telaffuz (S3) | **WAV PCM16, 16 kHz mono** | WAV PCM16 | WAV PCM16 |

- Kodlayıcı seçimi tek bir yerdedir: `app/lib/data/audio/recorder_config.dart`.
- Telaffuz kayıtları ≤ 30 sn'dir (gölgeleme cümleleri kısa; sağlayıcı sınırı Faz 2'de doğrulanır). WAV boyutu ~32 KB/sn, yani 30 sn ≈ 1 MB.
- Kayıt süresi sınırları:

  | Etkinlik | En fazla |
  |---|---|
  | Kart | 12 sn |
  | Gölgeleme | 15 sn |
  | Konuşma görevi | 2 dk (sonra otomatik durur) |
  | 4/3/2 | 4 dk |

## 5. İşleme hattı

### 5.0 `speech/transcribe` (F1-14)

- **İstek:** `POST /functions/v1/speech/transcribe?lang=en`, gövde ses baytları, `Content-Type` ses türü (`audio/mp4`, `audio/aac`, `audio/wav`, `audio/webm`, `audio/ogg`), en çok 2 MB. Oturum JWT'si fonksiyonun içinde doğrulanır.
- **Cevap:** `{text, words: [{w, startMs, endMs, conf}], provider, model, durationMs}`. Deepgram'a `model=nova-3&language=en&filler_words=true&smart_format=false&punctuate=false&mip_opt_out=true` ile gider; dolgu sözcükleri ve öğrencinin kendi biçimleri kalır.
- **Hata kodları** (loga da yalnızca kod yazılır): `unsupported_language` (Türkçe cihazda tanınır), `stt_unavailable` (anahtar yok ya da reddedildi), `stt_quota` (kredi bitti), `stt_busy`, `stt_failed` (sağlayıcıya ulaşılamadı), `bad_audio`, `empty_audio`, `unsupported_audio`, `audio_too_large`. Uygulama bunları sakin metinlere çevirir; söyle kartı gerekirse yazılı karta geçer (§5.3).
- **Kullanım:** Her başarılı tanıma `speech_usage`'a yazılır (servis rolü; saniye, Deepgram kredisinden düşen tutar). Satır yazılamazsa transkript yine döner, log `usage_not_recorded` der.
- **Uygulama:** `AnswerRecorder` (kayıt, `record` 7; kart sesi geçici dosyadan okunur ve hemen silinir), `SpeechRepository` (fonksiyon çağrısı). Ayarlar > **Mikrofon denemesi**: bir cümle kaydedilir, duyulan metin gösterilir, hiçbir şey saklanmaz; ses kaydı onayı yoksa kayıt yapılmaz. Web'de kayıt henüz yok.

### 5.1 Kartlar (düşük gecikme)

```text
kayıt biter ─▶ ses baytları doğrudan speech-transcribe fonksiyonuna POST (Storage'a yüklemeden)
            ─▶ transkript + kelime zamanları (hedef p90 ≤ 1,2 sn)
            ─▶ deterministik ön kontrol ─▶ (gerekirse) answer_check
```

- Kart sesleri **varsayılan olarak saklanmaz**. Yalnızca cihazda geçici tutulur. Ayarlar'da "kart kayıtlarımı sakla" açılabilir (varsayılan kapalı).
- **Toplam hedef:** konuşmanın bitişinden geri bildirime p90 ≤ 2,5 sn (LLM gerekirse ≤ 4 sn).

### 5.2 Görevler ve testler

```text
kayıt ─▶ cihazda dosya ─▶ Storage audio-private/{uid}/{yyyy}/{mm}/{uuid}.m4a (yükleme)
      ─▶ speech-transcribe (yol ile) ─▶ akıcılık ölçümleri (motor, deterministik)
      ─▶ speaking_annotate ─▶ geri bildirim
```

Çevrimdışıyken kayıt yerel kuyruğa girer. Bağlantı gelince otomatik işlenir ve "Geri bildirimin hazır" bildirimi gelir.

**v1 (F1-19, `RecordingPipeline`):**
- Kayıt cihazda saklanır (`recordings/<id>.m4a`).
- Ses, kart gibi doğrudan `speech/transcribe`'a gider. 2 dakikalık AAC yaklaşık 0,5 MB'dir, 2 MB sınırının altında kalır.
- Kayıt satırları ve ölçümler senkronla sunucuya gider (F1-21). Aylık test ve başlangıç kayıtlarının sesi `audio-private`'a yüklenir (F1-22). Görev seslerinin yüklenmesi, 30 günlük silmeyle birlikte F3-08'de.
- Yolla tanıma gerekmedi: ses doğrudan gidiyor ve 2 MB sınırının altında kalıyor.
- Bağlantı yoksa kayıt satırı transkriptsiz kalır ve görevde "Yeniden dene" çıkar. Otomatik kuyruk ve "Geri bildirimin hazır" bildirimi F2-02'de: geçmiş bir kaydın geri bildirim ekranını gerektiriyor.

### 5.3 Çevrimdışı davranış

- Söyle kartı çevrimdışı değerlendirilemez. Uygulama çevrimdışı olduğunu fark edince önce **Yaz kartına** (deterministik ön kontrol çevrimdışı çalışır) ya da dinle-anla kartlarına geçmeyi önerir.
- LLM gerektiren yazılı cevaplar `pending_llm` olarak işaretlenir ve sonra kontrol edilir (`07` §7).

## 6. Akıcılık ölçümleri (deterministik)

`dilbaz_engine` içindeki `SpeechMetrics.of(words, language, annotation?, connectors, rankOf)` fonksiyonu (F1-19), `06` §3.3'teki tanımları uygular. Akıcılığın yanında işaretlemeden çıkan doğruluk ve karmaşıklık ölçümlerini de hesaplar. Sonuç `recordings.metrics`'e yazılır.

- İki kelime arasındaki sessizlik = `words[i+1].startMs − words[i].endMs`. ≥ 250 ms ise sessiz duraklama, ≥ 1000 ms ise uzun duraklama.
- Baştaki ve sondaki sessizlik hesaba katılmaz.
- Kelime sayısına dolgu sözcükleri girmez. Akış (`mlr`), iki sessiz duraklama arasındaki dolgusuz kelime sayısıdır.
- Dolgu sözcükleri: ASR'nin yazdığı `uh/um` + LLM işaretlemesindeki `fillers`. İngilizce dolgular paketin normalizasyon listesinden okunur (`normalization.yaml` `fillers`; motorda `LanguageServices.isFiller`). Bu yüzden ayrı bir `fillers.jsonl` yoktur. İşaretleme bir kelimeye Türkçe dolgu derse o kelime Türkçe dolgu sayılır. Türkçe dolgular ("ıı", "şey") İngilizce ASR'de kaybolabilir. Bu, `l1_fillers_per_min` ölçümünün bilinen bir sınırlılığıdır ve raporda belirtilir.
- Cümlecik sınırları gerektiren ölçümler (`mid_clause_pause_ratio`, EFC) LLM işaretlemesinden sonra hesaplanır.

## 7. Telaffuz değerlendirmesinin kullanımı (A07)

> Sağlayıcı Faz 2 başında seçilir (ADR-0009). Aşağıdaki eşleme Azure'un hata türleri içindir. Başka bir sağlayıcı seçilirse onun çıktısı aynı `pron.*` etiketlerine eşlenir.

- **Yerel ayar `en-US`:** IPA ses adları ve prozodi yalnızca bu yerel ayarda var. Aksan olarak Amerikan İngilizcesi hedeflenmez; ölçüt anlaşılırlıktır (P17).
- Azure hata türleri Dilbaz `pron.*` etiketlerine eşlenir:

  | Azure | Dilbaz etiketi | Not |
  |---|---|---|
  | Mispronunciation + ses düzeyi (/ɪ/↔/iː/) | `pron.vowel_length` / `pron.vowel_quality` | Eşleme tablosu tr-en paketinde |
  | Mispronunciation (/w/↔/v/) | `pron.w_v` | |
  | Mispronunciation (sonda /d/→/t/) | `pron.final_devoicing` | |
  | Insertion (küme başında) | `pron.epenthesis` | "istation" |
  | Omission | `pron.omission` | -s/-ed düşmesi dahil |
  | UnexpectedBreak / MissingBreak | `pron.phrasing` | |
  | Monotone | `pron.intonation` | B1+ |

- Kullanıcıya **yalnızca öncelik listesindeki** (`02` §6) ve o anki seviyesiyle ilgili en fazla 2 sorun gösterilir. Sayısal puanlar ekranda not gibi durmaz. İlerleme ekranında eğilim olarak görünür (I-04).

## 8. Seslendirme (TTS)

- **Paket sesleri önceden üretilir** (`10-content-pipeline.md` S6):
  - Motor: Kokoro-82M (Apache-2.0), içerik makinesinde çevrimdışı
  - Cümle, kalıp ve kelime başına en az 2 ses
  - Ses ayırt etme kelimeleri için en az 4 ses (HVPT çeşitliliği)
  - A0–A1 için yavaş sürüm (hız 0,8)
  - Ses düzeyi normalize edilir
  - Depolama: `pack-audio/en/{sürüm}/...`
- **Ses listesi** paket manifestindedir: ses kimliği, yerel ayar, cinsiyet.
  - En az 4 ses; en az ikisi en-US dışı.
  - Kokoro'da Amerikan (en-US) ve İngiliz (en-GB) sesleri var; en-AU sesi yok.
  - en@1'in sesleri F1-05'te örnekler dinlenerek seçildi (2026-09-29): `af_heart`, `am_michael` (ABD), `bf_emma`, `bm_george` (İngiltere). Gemini Flash TTS karşılaştırmasına gerek görülmedi.
  - Her öğeyi bir ABD ve bir İngiliz sesi okur. Okunuş misaki G2P ile yapılır, bu yüzden eş yazımlılar sözcük türüne göre okunur (`10` §4.5).
- **Dinamik TTS** (Söyleyemediklerim önerisi, rol oyunu cevapları): Cihazın TTS motoru (`flutter_tts`) kullanılır. Sunucuda TTS fonksiyonu ve `tts-cache` bucket'ı yoktur.
- **Sınırlar:**
  - Kokoro'nun kota sınırı yoktur.
  - Supabase Storage'ın 1 GB sınırı paket sesleri ve görev kayıtlarıyla paylaşılır.
  - Paket sesleri kısa ve sıkıştırılmış tutulur: mono 24 kHz MP3, ~41 kbit/sn, klip başına ~9 KB (`10` §4.5).

## 9. Gizlilik

- Sağlayıcılara yalnızca ses ve gerekli parametreler gider. Kullanıcı kimliği gönderilmez.
- Deepgram'ın model geliştirme programından çıkış parametresi kullanılır (`mip_opt_out=true`; kurulumda dokümantasyondan doğrulanır).
- Cihaz üstü tanıma ve TTS'te ses cihazdan çıkmaz. Android'de tanıyıcı, cihazın konuşma servisine göre çevrimiçi çalışabilir.
- Gemini ya da Groq ses yedeği kullanılırsa `07` §3'teki onay kuralı geçerlidir.
- Ses saklama kuralları: `14-security-privacy.md` §4.

## 10. Tahmini maliyet (iki kullanıcı, aylık)

Maliyet $0'dır (ADR-0009). Deepgram kredisi dışında hiçbir kalem para ya da kredi tüketmez.

| Kalem | Varsayım | Tahmin |
|---|---|---|
| İngilizce ASR (Deepgram) | Kişi başı ~8 dk/gün | ~480 dk/ay → kredinin ~$2'si. $200 kredi yıllarca yeter. |
| Türkçe ASR | Kısa kayıtlar, cihaz üstü | $0 |
| Telaffuz | Faz 2'de seçilecek | Ücretsiz seçenek |
| Dinamik TTS | Cihaz üstü | $0 |
| Paket TTS (tek seferlik) | Paket başına 150–500K karakter, Kokoro | $0 (içerik makinesinin CPU süresi) |
