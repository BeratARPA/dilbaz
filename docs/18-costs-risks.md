# 18 — Maliyet ve Riskler

## 1. Aylık işletim maliyeti (iki kullanıcı, tahmini)

Fiyatlar 2026-09 itibarıyla doğrulanmıştır. Gerçek değerler `llm_usage` ve `speech_usage` tablolarından izlenir.

| Kalem | Plan | Aylık tahmin | Not |
|---|---|---|---|
| Supabase | Ücretsiz | $0 | 500 MB DB, 1 GB depolama, otomatik yedek yok, 1 hafta hareketsizlikte durur |
| Claude API (etkileşimli rotalar) | Kullandıkça öde | ~$25–35 | Varsayılan `claude-opus-5`; bkz. `07` §9 |
| Deepgram (İngilizce ASR) | Kullandıkça öde | ~$2 | Yeni hesaba verilen $200 kredi yıllarca yeter |
| Azure AI Speech (TTS, telaffuz, Türkçe ASR) | Ücretsiz katman (F0) | $0–5 | F0: 5 saat STT/ay, 0,5M karakter TTS/ay |
| GitHub | Ücretsiz | $0 | Actions dakikaları kişisel depo için yeterli |
| Vercel (Faz 6, web) | Hobby | $0 | Kişisel kullanım |
| **Toplam** | | **~$30–40/ay** | |

**Tek seferlik ve dönemsel:**
- İçerik üretimi (Batch LLM): seviye paketi başına ~$20–60. A0–C2 boyunca toplam ~$150–300.
- Paket TTS'i: ücretsiz katman ya da paket başına ~$2–8.
- LLM eval çalıştırmaları: çalıştırma başına ~$1–5 (her çalıştırmada ölçülür).

**Harcama korumaları:**
- Anthropic, Deepgram ve Azure panellerinde aylık harcama limiti (👤 kullanıcı ayarlar).
- Uygulamada kullanıcı başı günlük LLM bütçesi ($1,50).
- Maliyet panosu (Ayarlar > Kullanım).

## 2. Riskler

| # | Risk | Olasılık | Etki | Önlem |
|---|---|---|---|---|
| R1 | **Kapsam büyümesi:** proje İngilizce çalışmanın yerini alır | Orta | Yüksek | Faz 1 hızlıca kullanılabilir olmalı. Kullanım kapıları. Her faz kullanılabilir sürüm üretir. |
| R2 | **ASR öğrenci hatalarını düzeltir** | Yüksek (araştırma bunu gösteriyor) | Yüksek | Kelimesi kelimesine sağlayıcı, karşılaştırma testi, transkript görünürlüğü, "yanlış duyuldu" |
| R3 | **LLM yanlış geri bildirim verir** (doğruyu yanlış sayar, uydurma kural) | Orta | Yüksek | Deterministik ön kontrol, kapalı etiket listesi, `uncertain`, eval eşikleri, kullanıcı itirazı |
| R4 | İçerik kalitesi (doğal olmayan cümle, yanlış çeviri) | Orta | Orta | İki aşamalı doğrulama, insan örneklemi, "hata bildir" |
| R5 | **Motivasyon düşüşü** | Orta | Yüksek | Suçluluksuz tasarım, seçim, birlikte görevler, kendi sesinden ilerleme, 30 dk sınırı |
| R6 | Maliyetin beklentiyi aşması | Düşük–orta | Orta | Bütçeler, önbellek, Batch, effort ayarı, maliyet panosu. Model değişikliği kullanıcı kararı. |
| R7 | Supabase ücretsiz plan sınırları (duraklama, yedeksizlik, 500 MB) | Orta | Orta | Günlük kullanım, gece yedeği, ses saklama kuralı, içerik Postgres dışında |
| R8 | Sağlayıcı değişiklikleri (model emekliliği, fiyat, API değişikliği) | Orta | Orta | Tek yapılandırma dosyası, adaptör katmanı, `claude-api` skill'iyle güncel kalma |
| R9 | Mahremiyet ihlali (RLS hatası) | Düşük | Yüksek | Varsayılan-red, pgTAP testleri, partnere yalnızca özet |
| R10 | Senkron hataları (veri kaybı, çift kayıt) | Orta | Yüksek | Değişmez olaylar, idempotent push, outbox, yeniden oynatma aracı, PowerSync plan B |
| R11 | Windows ve web platform sorunları (ses, bildirim, wasm) | Orta | Düşük | Android öncelikli; masaüstü ve web sonraki fazlarda, doğrulama görevleriyle |
| R12 | Lisans sorunları (ShareAlike, CEFR/EVP metinleri) | Düşük (kişisel kullanım) | Orta | Açık lisanslı kaynaklar, kendi özetlerimiz, atıflar, `LICENSES.md` |
| R13 | Seviye tahmini yanıltıcı olur | Orta | Orta | Aralık + güven, dış kalibrasyon, CAF'ı seviyeye çevirmeme |
| R14 | Partnerler arasında karşılaştırma gerilimi | Düşük | Orta | Sıralama yok, varsayılan yalnızca özet, paylaşım anahtarları |
