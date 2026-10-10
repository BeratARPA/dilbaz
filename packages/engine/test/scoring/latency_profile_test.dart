import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('LatencyProfile (docs/03-activities.md §0.3)', () {
    test('the threshold is the 25th percentile of recent latencies', () {
      final profile = LatencyProfile.of([
        for (var s = 20; s >= 1; s--) s * 1000,
      ]);
      // Sorted ranks 4 and 5 of 0–19 are 5000 and 6000; the percentile
      // lies three quarters of the way between them.
      expect(profile.easyBelowMs, 5750);
      expect(profile.isFast(5749), isTrue);
      expect(profile.isFast(5750), isFalse);
    });

    test('too little history makes nothing fast', () {
      final profile = LatencyProfile.of(
        List.filled(LatencyProfile.minSamples - 1, 5000),
      );
      expect(profile.easyBelowMs, isNull);
      expect(profile.isFast(0), isFalse);
      expect(LatencyProfile.none.isFast(0), isFalse);
      expect(
        LatencyProfile.of(List.filled(LatencyProfile.minSamples, 5000))
            .easyBelowMs,
        5000,
      );
    });

    test('only the newest 200 latencies count', () {
      final newest = List.filled(LatencyProfile.window, 1000);
      final older = List.filled(100, 9000);
      expect(LatencyProfile.of([...newest, ...older]).easyBelowMs, 1000);
    });

    test('rejects a negative latency', () {
      expect(
        () => LatencyProfile.of([...List.filled(30, 1000), -1]),
        throwsArgumentError,
      );
    });
  });
}
