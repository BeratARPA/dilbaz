import 'dart:convert';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CardMemory JSON (attempts.card_state_after)', () {
    final reviewed = CardMemory(
      fsrsCardId: 1758873600000,
      state: MemoryState.relearning,
      due: DateTime.utc(2026, 9, 29, 8, 10),
      step: 0,
      stability: 1.25,
      difficulty: 6.5,
      lastReview: DateTime.utc(2026, 9, 29, 8),
    );

    test('round-trips through JSON text', () {
      final decoded = jsonDecode(jsonEncode(reviewed.toJson()));
      expect(CardMemory.fromJson(decoded as Map<String, Object?>), reviewed);
    });

    test('uses database column names and codes', () {
      expect(reviewed.toJson(), {
        'fsrs_card_id': 1758873600000,
        'state': 3,
        'due': '2026-09-29T08:10:00.000Z',
        'step': 0,
        'stability': 1.25,
        'difficulty': 6.5,
        'last_review': '2026-09-29T08:00:00.000Z',
      });
    });

    test('reads timestamps back as UTC', () {
      final back = CardMemory.fromJson(reviewed.toJson());
      expect(back.due.isUtc, isTrue);
      expect(back.lastReview!.isUtc, isTrue);
    });

    test('accepts integral numbers for stability and difficulty', () {
      // Postgres jsonb may store 3.0 as 3.
      final json = {...reviewed.toJson(), 'stability': 3, 'difficulty': 5};
      final card = CardMemory.fromJson(json);
      expect(card.stability, 3.0);
      expect(card.difficulty, 5.0);
    });

    test('keeps nulls for a card that was never reviewed', () {
      final fresh = CardMemory(
        fsrsCardId: 1,
        state: MemoryState.learning,
        due: DateTime.utc(2026, 9, 26),
        step: 0,
      );
      expect(CardMemory.fromJson(fresh.toJson()), fresh);
      expect(fresh.toJson()['last_review'], isNull);
    });
  });

  group('Codes shared with the database', () {
    test('memory states use FSRS state codes', () {
      expect(MemoryState.values.map((s) => s.code), [1, 2, 3]);
    });

    test('ratings use FSRS rating codes', () {
      expect(ReviewRating.values.map((r) => r.code), [1, 2, 3, 4]);
    });
  });
}
