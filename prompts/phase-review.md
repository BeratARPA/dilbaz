# Faz sonu gözden geçirme promptu

---

Mevcut fazı kapatmadan önce gözden geçirme yap:

1. `docs/17-roadmap.md`'deki bu fazın tüm görevleri ve kabul kriterleri sağlandı mı? Sağlanmayanları listele.
2. Tüm testleri çalıştır:
   - motor, uygulama
   - pgTAP, deno, pytest
   - entegrasyon testleri (varsa)

   Sonuçları özetle.
3. Değişmez kurallar (`docs/01-pedagogy.md` §3): bu fazda eklenen kod hangi kurallara dokunuyor? Her birinin testi var mı (`docs/15-testing.md` §2)?
4. Dokümanlar kodla tutarlı mı? Sapmaları düzelt ya da ADR yaz.
5. Maliyet: bu fazda `llm_usage` ve `speech_usage` toplamları, içerik üretim maliyeti.
6. Faz raporunu `docs/17-roadmap.md` ilerleme günlüğüne yaz:
   - yapılanlar
   - bilinen sorunlar
   - kullanıcı kullanım kapısı önerisi
7. Bana kısa bir özet ver. Birleştirmeyi (`main`) ve varsa üretime migrasyonu, paket yüklemeyi ve push'u **benim onayımla** yap.
