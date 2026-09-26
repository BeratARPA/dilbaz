# ADR-0001 — İstemci: Flutter + Riverpod + go_router + freezed + drift

- **Durum:** Kabul edildi (2026-09-26)

## Bağlam
Tek kod tabanıyla Android (öncelik), Windows ve web desteklenmeli. Uygulama çevrimdışı çalışmalı ve karmaşık yerel sorgular yapmalı (kartlar, kapsama, model).

## Karar
- **Çatı:** Flutter (stable, 2026-09: 3.47.x).
- **Durum yönetimi:** Riverpod 3 + `riverpod_generator`. Proje zaten kod üretimi kullanıyor (freezed, json_serializable).
- **Yönlendirme:** go_router 18.
- **Modeller:** freezed 4 + json_serializable.
- **Yerel veritabanı:** drift 2.35 + drift_flutter. Windows ve web destekli; `sqlite3_flutter_libs` kullanılmaz.
- **Mimari:** özellik öncelikli (feature-first). UI → controller → engine → repository.

## Değerlendirilen alternatifler
- **Kotlin Multiplatform / native Android:** Web ve Windows için ek iş gerekir.
- **React Native:** Windows/web olgunluğu ve yerel SQLite deneyimi daha zayıf. Kullanıcının tercihi Flutter.
- **Bloc:** Geçerli bir seçenek, ama Riverpod daha az kalıp kodla test edilebilir ve bağımlılık yönetimi sağlıyor.
- **Isar / Hive:** İlişkisel sorgular ve migrasyon için drift daha uygun.

## Sonuçlar
- Windows'ta Geliştirici Modu şart (eklenti sembolik bağları).
- freezed 4, Dart 3.13 gerektirir, yani Flutter 3.47+.
- Web'de drift için wasm ve worker dosyaları, OPFS için COOP/COEP başlıkları gerekir.
