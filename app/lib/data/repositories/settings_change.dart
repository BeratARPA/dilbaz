import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_change.freezed.dart';

/// Quiet hours as the profile keeps them: `HH:mm` to `HH:mm`.
typedef QuietHoursSetting = ({String from, String to});

/// What the Settings screen shows and changes (docs/09-ux-motivation.md
/// §5.12), read from the profile.
typedef ProfileSettings = ({
  int timeBudgetMin,
  int weeklyDaysGoal,

  /// The habit anchor's code (`morning_coffee`, …) and its `HH:mm` time.
  String anchor,
  String anchorTime,

  /// The daily invitation (docs/09 §6) and when nothing goes out.
  bool dailyInvitation,
  QuietHoursSetting? quietHours,

  /// Typed answers by default.
  bool silentMode,

  /// Recording audio (docs/14 §4) and sending text to Gemini (ADR-0009).
  bool audioConsent,
  bool aiDataConsent,
});

/// One change of the learner's settings; each is saved on its own.
@freezed
sealed class SettingsChange with _$SettingsChange {
  /// Minutes a day (I-13).
  const factory budget(int minutes) = BudgetChange;

  /// Days a week.
  const factory daysGoal(int days) = DaysGoalChange;

  /// The habit anchor and its time.
  const factory anchor({required String anchor, required String time}) =
      AnchorChange;

  const factory invitation({required bool wanted}) = InvitationChange;

  /// Null: no quiet hours.
  const factory quietHours(QuietHoursSetting? hours) = QuietHoursChange;

  const factory silentMode({required bool on}) = SilentModeChange;

  /// Given or taken back, with its time.
  const factory audioConsent({required bool granted}) = AudioConsentChange;

  const factory aiDataConsent({required bool granted}) = AiDataConsentChange;
}
