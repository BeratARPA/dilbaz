# ADR-0005 — Yapay zekâ: Claude API, sunucu tarafında

- **Durum:** Kabul edildi (2026-09-26)

## Bağlam
Cevap değerlendirme, ipucu merdiveni, konuşma işaretleme, rol oyunu ve içerik üretimi için bir LLM gerekiyor. Pedagojik korkuluklar ve maliyet kontrolü şart (P21, I-11).

## Karar
- Claude API yalnızca sunucuda (Supabase Edge Functions, resmî TypeScript SDK) ve çevrimdışı içerik araçlarında (resmî Python SDK, Batch API) kullanılır. Anahtar uygulamaya girmez.
- **Varsayılan model:** tüm rotalarda `claude-opus-5`. Maliyet ve hız rota başına `effort` ile ayarlanır.
- **Model değişikliği kullanıcının kararıdır** ve eval sonuçlarıyla desteklenmelidir.
- **Çıktı:** yapılandırılmış JSON (`output_config.format`, zod).
- **Maliyet:** Prompt önbelleği; kullanıcı başı günlük bütçe.
- **Reddetme:** Etkileşimli rotalarda sunucu tarafı reddetme yedeklemesi (fallback) açık.
- **Değerlendirme:** Her prompt ve model değişikliğinde eval zorunlu.
- **Kodlama öncesi zorunlu:** LLM kodu yazılmadan önce `claude-api` skill'i yüklenir.

## Değerlendirilen alternatifler
- **İstemcide doğrudan LLM çağrısı:** Anahtar güvenliği yok.
- **Başka sağlayıcılar:** Değerlendirildi. Tek sağlayıcıyla tutarlı SDK, yapılandırılmış çıktı ve Batch/önbellek maliyet avantajı tercih edildi. Adaptör katmanı değişimi mümkün kılar.

## Sonuçlar
- Tahmini işletim maliyeti iki kullanıcı için ~$25–35/ay (`07` §9).
- Modelde örnekleme parametreleri (temperature) yok. Tutarlılık, rubrik, örnekler ve değerlendirmelerde çift işaretlemeyle sağlanır.
- Sağlayıcının veri kullanım politikası kurulumda kontrol edilip buraya not edilir.
