# ADR-0008 — İçerik hattı: Python araçları ve versiyonlu SQLite paketleri

- **Durum:** Kabul edildi (2026-09-26). **ADR-0009 ile kısmen değiştirildi:** LLM üretimi ve doğrulaması Batch API yerine Claude Code oturumlarında yapılır; paket sesleri Kokoro ile üretilir.

## Bağlam
Her seviye için binlerce doğrulanmış öğe, ses, metin ve görev gerekiyor. Kaynakların lisansı temiz olmalı. İçerik dilden bağımsız paket formatında dağıtılmalı.

## Karar
- Araçlar Python ile yazılır (`content/tools`, uv, typer). NLP için spaCy, gerekirse Stanza kullanılır. LLM için Anthropic Python SDK ve Batch API.
- **Seviye etiketleri** açık lisanslı kaynaklardan gelir:
  - CEFR-J (atıfla serbest)
  - Octanove C1/C2 (CC BY-SA)
  - NGSL (CC BY-SA)
  - wordfreq sıklıkları
- **English Vocabulary/Grammar Profile pakete girmez.** Lisansı yalnızca kişisel, ticari olmayan kullanıma izin veriyor; toplu kullanım yok. Yalnızca elle referans olarak kullanılır.
- **CEFR Companion Volume** tanımlarının tam metni kopyalanmaz. Pakette kod + kendi özetimiz durur.
- Paketler versiyonlu SQLite dosyası olarak Supabase Storage'da dağıtılır. Postgres'e normalize edilmez.

## Değerlendirilen alternatifler
- **İçeriği Postgres tablolarında tutmak:** Ücretsiz plan 500 MB sınırı ve atomik sürüm geçişi zorluğu.
- **Dart ile araç yazmak:** NLP ekosistemi yetersiz.

## Sonuçlar
- CC BY-SA kaynaklar yüzünden paketler dağıtılırsa CC BY-SA 4.0 olmalıdır. Kişisel kullanımda sorun yok, atıflar `LICENSES.md`'de tutulur.
- Paket sürümü değişince öğe anahtarları korunur.
