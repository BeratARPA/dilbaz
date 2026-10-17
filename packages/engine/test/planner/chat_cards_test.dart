import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  const cards = <ChatCardRef>[
    (key: 'zz.chat.b', level: CefrLevel.a2),
    (key: 'zz.chat.a', level: CefrLevel.a1),
    (key: 'zz.chat.c', level: CefrLevel.a1),
    (key: 'zz.chat.d', level: CefrLevel.b1),
  ];

  test('at the level or below, by level then key', () {
    expect(chatCardOrder(cards: cards, level: CefrLevel.a2), [
      'zz.chat.a',
      'zz.chat.c',
      'zz.chat.b',
    ]);
    expect(chatCardOrder(cards: cards, level: CefrLevel.a0), [
      'zz.chat.a',
      'zz.chat.c',
    ]);
  });

  test('those talked about lately go last', () {
    expect(
      chatCardOrder(
        cards: cards,
        level: CefrLevel.b1,
        talkedLately: {'zz.chat.a'},
      ),
      ['zz.chat.c', 'zz.chat.b', 'zz.chat.d', 'zz.chat.a'],
    );
  });
}
