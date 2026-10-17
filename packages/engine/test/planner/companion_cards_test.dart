import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  test('listening: words and chunks, introduced at A0–B1 (A03)', () {
    for (final level in [CefrLevel.a0, CefrLevel.a2, CefrLevel.b1]) {
      expect(
        CompanionCards.listening(kind: ItemKind.wordSense, level: level),
        isTrue,
      );
      expect(
        CompanionCards.listening(kind: ItemKind.chunk, level: level),
        isTrue,
      );
    }
    expect(
      CompanionCards.listening(kind: ItemKind.wordSense, level: CefrLevel.b2),
      isFalse,
    );
    expect(
      CompanionCards.listening(
        kind: ItemKind.grammarPoint,
        level: CefrLevel.a1,
      ),
      isFalse,
    );
  });

  test('cloze: words from A1, once recallable (A04)', () {
    bool cloze(ItemKind kind, CefrLevel level, ItemLevel production) =>
        CompanionCards.cloze(kind: kind, level: level, production: production);
    expect(
      cloze(ItemKind.wordSense, CefrLevel.a1, ItemLevel.recallable),
      isTrue,
    );
    expect(cloze(ItemKind.wordSense, CefrLevel.c1, ItemLevel.durable), isTrue);
    expect(
      cloze(ItemKind.wordSense, CefrLevel.a1, ItemLevel.learning),
      isFalse,
    );
    expect(
      cloze(ItemKind.wordSense, CefrLevel.a0, ItemLevel.recallable),
      isFalse,
    );
    expect(cloze(ItemKind.chunk, CefrLevel.a2, ItemLevel.recallable), isFalse);
  });
}
