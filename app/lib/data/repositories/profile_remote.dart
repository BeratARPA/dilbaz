import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A profile and its courses as server rows (column name → value).
typedef RemoteProfile = ({
  Map<String, Object?> profile,
  List<Map<String, Object?>> courses,
});

/// The server side of the profile: the learner's own rows under row level
/// security (docs/13-data-model.md §4).
abstract interface class ProfileRemote {
  /// The profile of [userId] with its courses; null if there is none.
  Future<Result<RemoteProfile?, ProfileFailure>> fetch(String userId);

  /// Writes the rows; existing rows are replaced.
  Future<Result<void, ProfileFailure>> upsert({
    required Map<String, Object?> profile,
    required List<Map<String, Object?>> courses,
  });
}

class SupabaseProfileRemote implements ProfileRemote {
  const new(this._client);

  final SupabaseClient _client;

  @override
  Future<Result<RemoteProfile?, ProfileFailure>> fetch(String userId) async {
    try {
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .retry(enabled: false);
      if (profile == null) return const Ok(null);
      final courses = await _client
          .from('courses')
          .select()
          .eq('profile_id', userId)
          .retry(enabled: false);
      return Ok((profile: profile, courses: courses));
    } on PostgrestException {
      return const Err(ProfileFailure.unknown);
    } on ClientException {
      return const Err(ProfileFailure.network);
    }
  }

  @override
  Future<Result<void, ProfileFailure>> upsert({
    required Map<String, Object?> profile,
    required List<Map<String, Object?>> courses,
  }) async {
    try {
      await _client.from('profiles').upsert(profile);
      if (courses.isNotEmpty) await _client.from('courses').upsert(courses);
      return const Ok(null);
    } on PostgrestException {
      return const Err(ProfileFailure.unknown);
    } on ClientException {
      return const Err(ProfileFailure.network);
    }
  }
}
