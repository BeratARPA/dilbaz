import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_gate.g.dart';

/// Id of the signed-in user; null when signed out.
@Riverpod(keepAlive: true)
Stream<String?> currentUserId(Ref ref) async* {
  final auth = ref.watch(authRepositoryProvider);
  yield auth.userId;
  // Stream errors are network failures while refreshing the session; the
  // current session stays valid.
  await for (final _ in auth.watchSignedIn().handleError((Object _) {})) {
    yield auth.userId;
  }
}

/// Whether the signed-in learner has finished the welcome flow.
///
/// Null when that cannot be told: this device has no profile and the server
/// could not be asked, so one made on another device may exist. Emits
/// nothing while signed out.
@Riverpod(keepAlive: true)
Stream<bool?> onboarded(Ref ref) async* {
  final userId = ref.watch(currentUserIdProvider).value;
  if (userId == null) return;
  final profiles = ref.watch(profileRepositoryProvider);
  if (!await profiles.watchOnboarded(userId).first) {
    // A profile made on another device spares the learner the flow. Going
    // through it again would open a second course for the same language,
    // which the server refuses, so without an answer the flow waits.
    if (await profiles.restore(userId) case Err()) {
      yield null;
      return;
    }
  }
  yield* profiles.watchOnboarded(userId);
}

/// Waits until it is known where a signed-in learner starts, so that the
/// launch screen gives way to the right page at once. A server lookup is
/// not waited for beyond [patience]; the opening page covers the rest.
Future<void> startSettled(
  ProviderContainer container, {
  Duration patience = const Duration(seconds: 1),
}) async {
  if (!container.read(authRepositoryProvider).isSignedIn) return;
  // Reading alone would leave the stream paused.
  final gate = container.listen(onboardedProvider, (_, _) {});
  await container
      .read(onboardedProvider.future)
      // A failure stays in the gate, where the opening page shows it.
      .then<void>((_) {}, onError: (Object _) {})
      .timeout(patience, onTimeout: () {});
  gate.close();
}
