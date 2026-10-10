/// A small deterministic random source (xorshift32).
///
/// It gives the same numbers on every platform, which `dart:math` does not
/// promise, so a plan depends on its inputs and seed alone (docs/05 §6).
final class SeededRandom {
  /// A source for [seed]; any integer is a valid seed.
  new(int seed) : _state = (seed & _mask) == 0 ? _zeroSeed : seed & _mask;

  static const _mask = 0xFFFFFFFF;

  /// Xorshift has no zero state.
  static const _zeroSeed = 0x9E3779B9;

  int _state;

  /// The next number, from 0 up to but not including [max].
  int nextInt(int max) {
    var x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    _state = x;
    return x % max;
  }

  /// [items] in a random order (Fisher-Yates); the list itself is left as
  /// it is.
  List<T> shuffled<T>(List<T> items) {
    final result = [...items];
    for (var i = result.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final swap = result[i];
      result[i] = result[j];
      result[j] = swap;
    }
    return result;
  }
}
