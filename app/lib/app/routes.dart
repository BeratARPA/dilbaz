/// Route paths of the app.
abstract final class AppRoutes {
  static const signIn = '/sign-in';

  /// Shown while it is not yet known whether the welcome flow is due.
  static const opening = '/opening';
  static const welcome = '/welcome';
  static const today = '/today';
  static const practice = '/practice';
  static const together = '/together';
  static const progress = '/progress';
  static const settings = '/progress/settings';
  static const microphoneCheck = '/progress/settings/microphone';
  static const gapCapture = '/gap/new';

  /// "Söyleyemediklerim", over the tabs.
  static const gaps = '/gap';

  /// One capture and its suggestion.
  static String gapEntry(String id) => '/gap/$id';

  /// The placement test, over the tabs.
  static const placement = '/placement';

  /// A card session, over the tabs.
  static const cards = '/cards';

  /// A card session after "Bugünlük yeter": the learner goes on
  /// (docs/05 §6).
  static const cardsBeyondBudget = '/cards?more=1';

  /// A speaking task, over the tabs (A11).
  static const speaking = '/speaking';

  /// 4/3/2, over the tabs (A12).
  static const fluency = '/fluency';

  /// Dictation, over the tabs (A05).
  static const dictation = '/dictation';

  /// The monthly speaking test, over the tabs (A23).
  static const monthly = '/monthly';

  /// The placement test's baseline recording (docs/06 §2 part 4).
  static const baseline = '/monthly?baseline=1';
}
