# 18 — Maliyet ve Riskler

## 0. Bütçe kısıtı: sıfır (2026-09-26)

Kullanıcının bütçesi **sıfırdır**. Yalnızca ücretsiz katmanlar kullanılır. Ücret doğurabilecek hiçbir iş (ücretli API, ücretli plan, kart doğrulaması isteyen kayıt) başlatılmaz. Karar: **ADR-0009** — her bileşende ücretsiz olan en iyi seçenek, eval ile seçilir.

- **Kullanımda:**
  - Supabase ücretsiz plan
  - GitHub: özel depo + ayda 2.000 Actions dakikası. Ödeme yöntemi yokken aşımda ücret alınmaz, işler durur.
  - Brevo SMTP: günde 300 e-posta; giriş kodları için
- **ADR-0009 ile eklenenler:**
  - Gemini API ücretsiz katmanı
  - Groq ücretsiz katmanı
  - Deepgram kayıt kredisi ($200, kart yok)
  - Cihaz üstü ses: Türkçe tanıma, dinamik TTS
  - Kokoro-82M: çevrimdışı paket sesleri
  - Claude Code aboneliği: içerik üretimi
- **Kullanılmayanlar:** Claude API ve Azure Speech (kart gerekiyor). Bütçe olursa ADR-0005/0006'ya dönülebilir; rota sözleşmeleri aynı kalır.

## 1. Aylık işletim maliyeti (iki kullanıcı)

Koşullar 2026-09-26'da doğrulanmıştır (ADR-0009). Gerçek kullanım `llm_usage` ve `speech_usage` tablolarından izlenir.

| Kalem | Plan | Aylık | Not |
|---|---|---|---|
| Supabase | Ücretsiz | $0 | 500 MB DB, 1 GB depolama, otomatik yedek yok, 1 hafta hareketsizlikte durur |
| LLM (Gemini + Groq) | Ücretsiz katman | $0 | Sınır kotadır, para değil (`07` §9) |
| Deepgram (İngilizce ASR) | Kayıt kredisi | $0 | Krediden ~$2/ay düşer; $200 yıllarca yeter |
| Cihaz üstü ses (Türkçe ASR, dinamik TTS) | — | $0 | |
| Kokoro (paket sesleri) | Açık kaynak | $0 | İçerik makinesinde çalışır |
| İçerik üretimi | Claude Code aboneliği | Ek ücret yok | Oturum süresi harcar |
| GitHub | Ücretsiz | $0 | Actions dakikaları kişisel depo için yeterli |
| Brevo | Ücretsiz | $0 | |
| Vercel (Faz 6, web) | Hobby | $0 | Kişisel kullanım |
| **Toplam** | | **$0/ay** | |

**Tek seferlik işler:** Yok. İçerik ve ses üretimi para değil, oturum ve işlemci süresi harcar.

**Kota korumaları:**
- Ücretli plan ve kart olmadığı için fatura oluşamaz.
- Kullanıcı başı kota payı (adil paylaşım, `07` §3).
- Deepgram kredisinin izlenmesi.
- Kullanım panosu (Ayarlar > Kullanım).

## 2. Riskler

| # | Risk | Olasılık | Etki | Önlem |
|---|---|---|---|---|
| R1 | **Kapsam büyümesi:** proje İngilizce çalışmanın yerini alır | Orta | Yüksek | Faz 1 hızlıca kullanılabilir olmalı. Kullanım kapıları. Her faz kullanılabilir sürüm üretir. |
| R2 | **ASR öğrenci hatalarını düzeltir** | Yüksek (araştırma bunu gösteriyor) | Yüksek | Kelimesi kelimesine sağlayıcı, karşılaştırma testi, transkript görünürlüğü, "yanlış duyuldu" |
| R3 | **LLM yanlış geri bildirim verir** (doğruyu yanlış sayar, uydurma kural) | Orta | Yüksek | Deterministik ön kontrol, kapalı etiket listesi, `uncertain`, eval eşikleri, kullanıcı itirazı |
| R4 | İçerik kalitesi (doğal olmayan cümle, yanlış çeviri) | Orta | Orta | İki aşamalı doğrulama, insan örneklemi, "hata bildir" |
| R5 | **Motivasyon düşüşü** | Orta | Yüksek | Suçluluksuz tasarım, seçim, birlikte görevler, kendi sesinden ilerleme, 30 dk sınırı |
| R6 | Ücretsiz kotaların yetmemesi ya da daralması | Orta | Orta | Yedek sağlayıcı, deterministik yol, adil paylaşım, faz başında kota kontrolü. Sağlayıcı değişikliği kullanıcı kararı ve eval ile. |
| R7 | Supabase ücretsiz plan sınırları (duraklama, yedeksizlik, 500 MB) | Orta | Orta | Günlük kullanım, gece yedeği, ses saklama kuralı, içerik Postgres dışında |
| R8 | Sağlayıcı değişiklikleri (model emekliliği, ücretsiz katmanın kalkması, API değişikliği) | Orta | Orta | Tek yapılandırma dosyası, adaptör katmanı, yedek sağlayıcı, context7 ile güncel belgeler |
| R9 | Mahremiyet ihlali (RLS hatası) | Düşük | Yüksek | Varsayılan-red, pgTAP testleri, partnere yalnızca özet |
| R10 | Senkron hataları (veri kaybı, çift kayıt) | Orta | Yüksek | Değişmez olaylar, idempotent push, outbox, yeniden oynatma aracı, PowerSync plan B |
| R11 | Windows ve web platform sorunları (ses, bildirim, wasm) | Orta | Düşük | Android öncelikli; masaüstü ve web sonraki fazlarda, doğrulama görevleriyle |
| R12 | Lisans sorunları (ShareAlike, CEFR/EVP metinleri) | Düşük (kişisel kullanım) | Orta | Açık lisanslı kaynaklar, kendi özetlerimiz, atıflar, `LICENSES.md` |
| R13 | Seviye tahmini yanıltıcı olur | Orta | Orta | Aralık + güven, dış kalibrasyon, CAF'ı seviyeye çevirmeme |
| R14 | Partnerler arasında karşılaştırma gerilimi | Düşük | Orta | Sıralama yok, varsayılan yalnızca özet, paylaşım anahtarları |
| R15 | **Sıfır bütçe:** ücretli yapay zekâ ve ses hizmetleri kullanılamaz | Kesin | Orta | ADR-0009: ücretsiz katmanlar, deterministik yol, cihaz üstü ses, açık veriler. Kalite eval ile korunur. |
| R16 | Gemini ücretsiz katmanında metinlerin ürün geliştirmede kullanılması ve insan incelemesine açık olması | Kesin (kabul edildi) | Düşük–orta | Kullanıcı başına onay, veri en aza indirme (ad/e-posta/ses gitmez), Groq ya da deterministik seçenek |
