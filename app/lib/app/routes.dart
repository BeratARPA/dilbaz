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

  /// The placement test, over the tabs.
  static const placement = '/placement';
}
