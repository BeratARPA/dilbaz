import 'package:flutter/material.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Asks for a time of day, starting from [initial] (`HH:mm`); the picked
/// time as `HH:mm`, or null when the learner closed the picker. It is kept
/// and shown as `HH:mm`, whatever the clock setting of the device.
Future<String?> pickDayTime(BuildContext context, String initial) async {
  final [hour, minute] = initial.split(':');
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: int.parse(hour), minute: int.parse(minute)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (picked == null) return null;
  return '${_twoDigits(picked.hour)}:${_twoDigits(picked.minute)}';
}
