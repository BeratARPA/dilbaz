# ADR-0011 — Telaffuz: Gemini ses dinleme + konuşma tanıma karşılaştırması

- **Durum:** Kabul edildi (2026-10-17). Model seçimi eval ile kesinleşir (`07` §8).
- **Kullanıcı kararı:** "Gemini + ses tanıma (Önerilen)".
- **İlgili:** ADR-0006 (Azure telaffuz değerlendirmesi), ADR-0009 (sıfır bütçe, S3), I-05, I-11, I-12, I-15; `02` §6, `03` A07, `07` §4.4, `08` §3.3 ve §7.

## Bağlam

- ADR-0006 telaffuz için Azure Pronunciation Assessment'ı seçmişti. Azure kart istiyor; ADR-0009 ile kullanılamıyor. Karar Faz 2 başına bırakılmıştı (S3).
- ADR-0009'daki adaylar:
  - **Açık kaynak ses birimi tanıma + GOP puanı:** Sunucuda model çalıştırmak gerekir. Edge Functions buna uygun değil; ücretsiz barındırma yok. Cihazda çalıştırmak (wav2vec2 türü, ~300 MB) uygulamayı büyütür, Windows/web desteği ayrı iş.
  - **ASR kelime güven puanları:** Deepgram kelime başına güven veriyor. Ama ASR dil modeli yanlış söyleneni çoğu zaman doğru kelimeye "düzeltir"; güven düşüklüğü hatanın türünü söylemez.
  - **Gemini ses dinleme:** Ücretsiz katmanda ses alır (`inlineData`, istek ≤ 20 MB). Hata türünü kapalı listeden adlandırabilir. Güvenilirliği ölçülmeli.
- Katalogda telaffuz etiketleri zaten var (tr-en çift paketi, `phon.*`, 7 etiket): `phon.vowel_length`, `phon.w_v`, `phon.final_devoicing`, `phon.epenthesis`, `phon.spelling`, `phon.th`, `phon.word_stress`. Her birinin Türkçe açıklaması, örnekleri ve `severity` değeri var.

## Karar

- **İki katman:**
  1. **Konuşma tanıma karşılaştırması (deterministik):** Kayıt `speech/transcribe` ile (Deepgram, kelimesi kelimesine) yazıya dökülür. Motor cümleyi transkriptle kelime kelime hizalar (dikte denetleyicisi, `DictationCheck`): söylenmeyen ya da başka kelime olarak duyulan kelimeler gösterilir. LLM yok.
  2. **Gemini ses dinleme (`tutor/pron_check`):** Ses (WAV 16 kHz, ≤ 15 sn) ve cümle Gemini'ye gider. Model yalnızca katalogdaki `phon.*` etiketlerini kullanır (I-11). Her sorun bir kelimeye bağlanır (cümledeki sırası) ve nasıl duyulduğunu kısaca yazar. Emin olmadığı sorunu işaretlemez; kaydı değerlendiremiyorsa `uncertain` der. Puan yok.
- **Seçim motorda:** Gösterilecek en fazla 2 sorunu motor seçer (`pickPronIssues`): öğrencinin kalıcı etiketleri önce, sonra etiketin `severity` değeri (anlaşılırlığa etkisi; `02` §6), sonra bu kayıttaki sıklık. Her etiketten bir sorun. Dile özgü liste motorda yok; ağırlıklar paketten gelir (I-15).
- **Model:** Rota zinciri yalnızca ses alan modellerden kurulur (`llm_config.ts` `audio: true`). Başlangıç zinciri `gemini-3.1-flash-lite` (günde ~500 istek; 3.5 Flash'ın 20 isteği gölgelemeye yetmez). Eval sonucu zinciri değiştirebilir.
- **Onay:** Gemini ücretsiz katmanı veriyi kullanabilir. Onay yoksa `pron_check` çağrılmaz; gölgeleme yalnızca tanıma karşılaştırması ve "kendini dinle" ile çalışır (ADR-0009'daki puansız yol).
- **Kanıt:** Gölgeleme tekrar etmektir; üretim kanıtı sayılmaz (I-05). Denemeler `attempts`'e `activity = 'shadowing'` ile yazılır, `error_tags` gösterilen ve gösterilmeyen tüm `phon.*` sorunlarıdır. Ses saklanmaz (`08` §5.1).

## Sonuçlar

- Sıfır maliyet; yeni sağlayıcı, yeni anahtar ya da paket değişikliği yok.
- Ses birimi düzeyinde puan (GOP) ve prozodi ölçümü yok. İlerleme ekranı telaffuzu sayıyla değil, etiket eğilimiyle gösterir (I-04).
- Gemini'nin yanlış alarm oranı ölçülmeden sonuçlar kullanıcıya "emin olunan sorun" diye gösterilir; eval eşiği `07` §8'e eklendi: doğru söylenmiş cümlelerde yanlış alarm ≤ %10, hatalı söylenmiş cümlelerde doğru etiket ≥ %60.
- **Eval seti:** Kokoro'nun ses birimi girişiyle üretilmiş sentetik hatalı söyleyişler (her etiket için) ve doğru söyleyişler; kullanıcının kayıtları (👤, ASR karşılaştırma kayıtlarıyla birlikte) geldiğinde gerçek ses.
- **Bilinen sınır:** `02` §6'daki öncelik basamakları (1: A0–A1, 2: A2–B1) katalogda ayrı alan olarak yok; `severity` sıralaması yerine geçiyor. Katalogda `phon.th` ve `phon.word_stress` ikinci basamak olduğu için `severity` değerleri düşürüldü (0,2); paketin bir sonraki derlemesinde yayınlanır.
- ADR-0006'nın telaffuz satırı bu ADR ile değişti.
