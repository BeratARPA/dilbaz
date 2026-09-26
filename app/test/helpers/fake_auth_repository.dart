import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/auth_repository.dart';

/// In-memory auth for widget and controller tests.
class FakeAuthRepository implements AuthRepository {
  new({this._signedIn = false});

  bool _signedIn;
  final _changes = StreamController<bool>.broadcast();

  /// Failure returned by the next calls; null means success.
  AuthFailure? sendFailure;
  AuthFailure? verifyFailure;

  final sentTo = <String>[];
  final verified = <(String, String)>[];

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> watchSignedIn() => _changes.stream;

  @override
  Future<Result<void, AuthFailure>> sendCode(String email) async {
    sentTo.add(email);
    final failure = sendFailure;
    return failure == null ? const Ok(null) : Err(failure);
  }

  @override
  Future<Result<void, AuthFailure>> verifyCode({
    required String email,
    required String code,
  }) async {
    verified.add((email, code));
    final failure = verifyFailure;
    if (failure != null) return Err(failure);
    _set(signedIn: true);
    return const Ok(null);
  }

  @override
  Future<void> signOut() async => _set(signedIn: false);

  void _set({required bool signedIn}) {
    _signedIn = signedIn;
    _changes.add(signedIn);
  }
}
