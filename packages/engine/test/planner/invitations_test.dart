import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('parseDayTime', () {
    test('reads HH:mm', () {
      expect(parseDayTime('08:30'), (hour: 8, minute: 30));
      expect(parseDayTime('7:05'), (hour: 7, minute: 5));
      expect(parseDayTime('23:59'), (hour: 23, minute: 59));
    });

    test('anything else is no time', () {
      for (final text in [
        null,
        '',
        '24:00',
        '08:60',
        '8.30',
        'sabah',
        '-1:30',
        '108:30',
        '08:3',
        '08:+5',
      ]) {
        expect(parseDayTime(text), isNull, reason: '$text');
      }
    });
  });

  group('QuietHours', () {
    const night = QuietHours(
      from: (hour: 22, minute: 30),
      to: (hour: 8, minute: 0),
    );
    const noon = QuietHours(
      from: (hour: 12, minute: 0),
      to: (hour: 14, minute: 0),
    );

    test('run past midnight', () {
      expect(night.covers((hour: 23, minute: 0)), isTrue);
      expect(night.covers((hour: 7, minute: 59)), isTrue);
      expect(night.covers((hour: 22, minute: 30)), isTrue);
      expect(night.covers((hour: 8, minute: 0)), isFalse);
      expect(night.covers((hour: 12, minute: 0)), isFalse);
    });

    test('or within a day', () {
      expect(noon.covers((hour: 13, minute: 0)), isTrue);
      expect(noon.covers((hour: 14, minute: 0)), isFalse);
      expect(noon.covers((hour: 11, minute: 59)), isFalse);
    });

    test('an empty span covers nothing', () {
      const none = QuietHours(
        from: (hour: 9, minute: 0),
        to: (hour: 9, minute: 0),
      );
      expect(none.covers((hour: 9, minute: 0)), isFalse);
    });
  });

  group('invitationTimes (docs/09 §6)', () {
    const anchor = (hour: 8, minute: 30);

    test('one a day at the anchor, from today when it is still ahead', () {
      final times = invitationTimes(
        now: DateTime(2026, 10, 8, 7),
        anchor: anchor,
        studiedToday: false,
        days: 3,
      );
      expect(times, [
        DateTime(2026, 10, 8, 8, 30),
        DateTime(2026, 10, 9, 8, 30),
        DateTime(2026, 10, 10, 8, 30),
      ]);
    });

    test('from tomorrow once the anchor has passed', () {
      expect(
        invitationTimes(
          now: DateTime(2026, 10, 8, 9),
          anchor: anchor,
          studiedToday: false,
          days: 2,
        ),
        [DateTime(2026, 10, 9, 8, 30)],
      );
    });

    test('not on a day already studied', () {
      expect(
        invitationTimes(
          now: DateTime(2026, 10, 8, 7),
          anchor: anchor,
          studiedToday: true,
          days: 3,
        ),
        [DateTime(2026, 10, 9, 8, 30), DateTime(2026, 10, 10, 8, 30)],
      );
    });

    test('never in quiet hours', () {
      expect(
        invitationTimes(
          now: DateTime(2026, 10, 8, 7),
          anchor: (hour: 23, minute: 0),
          studiedToday: false,
          quiet: const QuietHours(
            from: (hour: 22, minute: 30),
            to: (hour: 8, minute: 0),
          ),
        ),
        isEmpty,
      );
    });

    test('a week ahead by default, across the month', () {
      final times = invitationTimes(
        now: DateTime(2026, 10, 30, 12),
        anchor: (hour: 20, minute: 0),
        studiedToday: false,
      );
      expect(times, hasLength(7));
      expect(times.first, DateTime(2026, 10, 30, 20));
      expect(times.last, DateTime(2026, 11, 5, 20));
    });
  });
}
