# ADR-0002 — Sunucu: Supabase

- **Durum:** Kabul edildi (2026-09-26)

## Bağlam
İki kullanıcı için kimlik doğrulama, veritabanı, dosya depolama, sunucu fonksiyonları (LLM/ses anahtarlarını saklamak için) ve gerçek zamanlı iletişim (ikili görevler) gerekiyor. Maliyet düşük olmalı, bakım yükü az olmalı.

## Karar
Supabase kullanılır: Auth (e-posta OTP), Postgres + RLS, Storage, Edge Functions (Deno 2), Realtime (özel kanallar), Cron (pg_cron + pg_net). Proje ücretsiz planda, AB (Frankfurt) bölgesinde açılır.

## Değerlendirilen alternatifler
- **Kendi ASP.NET Core API'miz + PostgreSQL:** Kullanıcı .NET'e hâkim. Ama kimlik doğrulama, depolama, gerçek zamanlı iletişim ve barındırma ayrıca kurulmalı; ilk sürüm gecikir. İleride gerekirse Postgres şeması taşınabilir.
- **Firebase:** Firestore'un belge modeli, ilişkisel sorgular (kartlar, denemeler, raporlar) ve SQL testleri (pgTAP) için daha az uygun.

## Sonuçlar
- **Ücretsiz planın kısıtları:**
  - 500 MB veritabanı, 1 GB depolama
  - **Otomatik yedek yok:** kendi yedeğimiz (`12` §9)
  - 1 hafta hareketsizlikte proje duraklar
- Yerel geliştirme Docker Desktop ister.
- Güvenlik RLS'e dayanır. Her tablo için pgTAP testi zorunludur.
