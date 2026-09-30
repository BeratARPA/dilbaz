import 'package:freezed_annotation/freezed_annotation.dart';

part 'onboarding_answers.freezed.dart';

/// What the learner tells the app in the welcome flow
/// (docs/09-ux-motivation.md §5.1).
@freezed
abstract class OnboardingAnswers with _$OnboardingAnswers {
  const factory({
    @Default('') String displayName,

    /// Codes of the chosen goals; they become the profile's interests.
    @Default(<String>{}) Set<String> goals,

    /// The goal in the learner's own words.
    @Default('') String goalText,

    /// Minutes a day (I-13).
    @Default(30) int timeBudgetMin,
    @Default(5) int weeklyDaysGoal,

    /// Code of the habit anchor, such as `morning_coffee`.
    @Default('morning_coffee') String anchor,

    /// Time of the anchor, `HH:mm`.
    @Default('08:30') String anchorTime,

    /// The learner wants the one daily invitation.
    @Default(false) bool notifications,

    /// Consent to recording and keeping audio (docs/14 §4).
    @Default(false) bool audioConsent,

    /// The system let the app use the microphone.
    @Default(false) bool microphone,

    /// Consent to sending answers to a provider that may use them to
    /// improve its products (ADR-0009); given by each user for themselves.
    @Default(false) bool aiDataConsent,

    /// The level the learner starts at until the placement test is taken.
    @Default('A1') String level,
  }) = _OnboardingAnswers;
}
