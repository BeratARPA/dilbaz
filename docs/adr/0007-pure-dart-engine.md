# ADR-0007 — Motor: ayrı, saf Dart paketi (`dilbaz_engine`)

- **Durum:** Kabul edildi (2026-09-26)

## Bağlam
Pedagojik mantık (FSRS, öğrenci modeli, planlayıcı, puanlama, ölçümler, kapsama) sistemin kalbidir. Bu mantık kolay test edilebilmeli, arayüzden ve IO'dan bağımsız olmalı ve **hiçbir dili bilmemelidir** (I-15).

## Karar
- `packages/engine` saf bir Dart paketidir: Flutter, drift ya da ağ bağımlılığı yoktur. Girdi olarak veri alır, çıktı olarak karar ve durum üretir.
- Dile özgü her şey `LanguageServices` gibi arayüzlerle, **paket verisinden** gelir (`11` §6).
- Testler sentetik bir dille (`zz`) çalışır. İçe aktarma sınırı ve dize sabiti taraması CI'da denetlenir.

## Değerlendirilen alternatifler
- **Mantığın uygulama içinde (controller'larda) olması:** Test etmesi zor, dile özgü varsayımlar sızar.
- **Mantığın sunucuda olması:** Çevrimdışı çalışmayı bozar.

## Sonuçlar
- Uygulama, veritabanı satırlarını motor modellerine eşleyen ince bir katman içerir.
- Motor ileride başka istemcilerde de kullanılabilir. Örneğin Dart CLI ile simülasyon ve analiz.
