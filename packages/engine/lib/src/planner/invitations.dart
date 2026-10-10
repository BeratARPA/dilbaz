/// A time of day on the learner's clock.
typedef DayTime = ({int hour, int minute});

/// `HH:mm` as a [DayTime]; null for anything else.
DayTime? parseDayTime(String? text) {
  final parts = (text ?? '').split(':');
  bool digits(String part, int length) =>
      part.isNotEmpty &&
      part.length <= length &&
      part.codeUnits.every((unit) => unit >= 0x30 && unit <= 0x39);
  if (parts.length != 2 ||
      !digits(parts[0], 2) ||
      parts[1].length != 2 ||
      !digits(parts[1], 2)) {
    return null;
  }
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

/// The hours no invitation goes out in, [from] up to [to]; they may run
/// past midnight (22:30–08:00).
final class QuietHours {
  /// Quiet from [from] up to [to].
  const new({required this.from, required this.to});

  /// Where the quiet starts.
  final DayTime from;

  /// Where it ends: the first minute an invitation may go out again.
  final DayTime to;

  static int _minutes(DayTime time) => time.hour * 60 + time.minute;

  /// Whether [time] falls in the quiet hours.
  bool covers(DayTime time) {
    final at = _minutes(time);
    final start = _minutes(from);
    final end = _minutes(to);
    if (start == end) return false;
    return start < end ? at >= start && at < end : at >= start || at < end;
  }
}

/// When the daily invitation goes out (docs/09-ux-motivation.md §6, P19):
/// at the learner's anchor, at most once a day, never on a day already
/// studied and never in quiet hours.
///
/// The times are local wall-clock times of the next [days] days, from
/// [now] on. They are set ahead, so a learner away for a while gets no
/// more than [days] of them: the invitations stop until the app is opened
/// again, rather than going on without end.
List<DateTime> invitationTimes({
  required DateTime now,
  required DayTime anchor,
  required bool studiedToday,
  QuietHours? quiet,
  int days = 7,
}) {
  if (quiet?.covers(anchor) ?? false) return const [];
  return [
    for (var day = studiedToday ? 1 : 0; day < days; day++)
      if (DateTime(
            now.year,
            now.month,
            now.day + day,
            anchor.hour,
            anchor.minute,
          )
          case final at when at.isAfter(now))
        at,
  ];
}
