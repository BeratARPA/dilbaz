# dilbaz_engine

Dilbaz'ın saf Dart öğrenme motoru: FSRS, öğrenci modeli, planlayıcı, puanlama, ölçümler, kapsama. Flutter, IO, ağ ya da veritabanı bağımlılığı yoktur (ADR-0007).

## Kurallar
- **Dilden bağımsız (I-15):** `lib/` içinde dile özgü kelime, kural, liste ya da metin yoktur. `test/architecture/` bunu denetler: içe aktarma sınırı, `package:fsrs` yalnızca `lib/src/fsrs/` içinde ve `as fsrs` önekiyle, dize sabiti taraması.
- **Sentetik dil:** Testler `test/fixtures/zz/zz_pack.dart` üretecinin tohumlu `zz` paketiyle çalışır.
- **FSRS:** Yalnızca `SrsScheduler` üzerinden kullanılır. Tüm zamanlar UTC'dir, UTC olmayan zaman `ArgumentError` fırlatır. Canlıda bulanıklaştırma açık, tekrar oynatmada `SrsConfig.replay` ile kapalı.

## Komutlar
```bash
dart pub get && dart run build_runner build
dart analyze --fatal-infos
dart test --coverage-path=coverage/lcov.info && dart run tool/check_coverage.dart
```
