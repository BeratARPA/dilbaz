# ADR-0003 — Yerel öncelikli çalışma ve olay günlüğüyle senkron

- **Durum:** Kabul edildi (2026-09-26)

## Bağlam
Kartlar yolda, internetsiz de çalışmalı. Kullanıcı telefon, Windows ve web arasında geçiş yapacak. Öğrenme durumunun tek gerçek kaynağı denemelerdir (I-03).

## Karar
- Arayüz yerel drift veritabanından beslenir. Her yazma aynı işlemde outbox'a da düşer.
- **Olay verisi** değiştirilemez ve UUIDv7 kimliklidir. Sunucuya idempotent eklenir (`on conflict do nothing`): denemeler, düzeltmeler, oturumlar, medya kayıtları, değerlendirmeler.
- **Durum verisi** (kartlar, profil) son yazan kazanır kuralıyla birleşir. Kartlarda karşılaştırma `last_review` zamanına göre yapılır.
- Senkron iki Postgres RPC'siyle yapılır: `sync_push` ve `sync_pull`. Artımlı çekme `server_seq` imleciyle olur.
- Kart durumu her denemeyle birlikte `card_state_after` olarak saklanır. Gerekirse denemeler yeniden oynatılarak durum baştan hesaplanır.

## Değerlendirilen alternatifler
- **PowerSync:** Olgun, drift ile uyumlu ve Supabase entegrasyonu var. Ama ek hizmet ve kısıtlar getirir (ücretsiz katman, web beta). Özel senkronun bakımı zorlaşırsa **plan B**.
- **Yalnızca çevrimiçi:** Çevrimdışı kart deneyimini ve güvenilirliği bozar.

## Sonuçlar
- Aynı kartın iki cihazda çevrimdışı incelenmesi seyrek bir çakışma üretir. Daha yeni inceleme kazanır, kaybeden denemeler günlükte kalır.
- Senkron kodu testlerle korunmalıdır: çok cihaz senaryoları, idempotentlik.
