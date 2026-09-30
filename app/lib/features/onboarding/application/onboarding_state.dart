import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/team_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'onboarding_state.freezed.dart';

/// Steps of the welcome flow, in order (docs/09-ux-motivation.md §5.1).
enum OnboardingStep {
  welcome,
  name,
  goal,
  time,
  anchor,
  notifications,
  partner,
  voice,
  level,
}

@freezed
abstract class OnboardingState with _$OnboardingState {
  const factory({
    @Default(OnboardingStep.welcome) OnboardingStep step,
    @Default(OnboardingAnswers()) OnboardingAnswers answers,

    /// The team created or joined in the partner step.
    Team? team,

    /// Why the last team attempt did not work.
    TeamFailure? teamFailure,

    /// Waiting for the server or for a system dialog.
    @Default(false) bool busy,
  }) = _OnboardingState;

  const new _();

  /// Whether the current step may be left forwards; only the name is
  /// required.
  bool get canGoOn =>
      step != OnboardingStep.name || answers.displayName.trim().isNotEmpty;

  bool get isFirst => step == OnboardingStep.values.first;

  bool get isLast => step == OnboardingStep.values.last;
}
