import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_controller.g.dart';

@riverpod
class SessionController extends _$SessionController {
  @override
  void build() {}

  /// The router returns to the sign-in page when the session ends.
  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();
}
