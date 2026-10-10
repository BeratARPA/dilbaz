import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/profile_remote.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';

/// An in-memory server for the profile rows.
class FakeProfileRemote implements ProfileRemote {
  /// The stored profile and courses; null while there is none.
  RemoteProfile? stored;

  /// Failure of the next calls; null means they work.
  ProfileFailure? failure;

  /// How many times the rows were written.
  int upserts = 0;

  @override
  Future<Result<RemoteProfile?, ProfileFailure>> fetch(String userId) async {
    final failure = this.failure;
    return failure == null ? Ok(stored) : Err(failure);
  }

  @override
  Future<Result<void, ProfileFailure>> upsert({
    required Map<String, Object?> profile,
    required List<Map<String, Object?>> courses,
  }) async {
    final failure = this.failure;
    if (failure != null) return Err(failure);
    upserts++;
    // The server assigns the sync sequence (docs/13 §1).
    stored = (
      profile: {...profile, 'server_seq': 41},
      courses: [
        for (final course in courses) {...course, 'server_seq': 42},
      ],
    );
    return const Ok(null);
  }
}
