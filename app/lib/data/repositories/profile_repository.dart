import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';

/// Why the profile could not be read from or written to the server.
enum ProfileFailure { network, unknown }

/// The learner's profile and course (docs/13-data-model.md §2.1).
///
/// Local first: the welcome flow writes to the local database and the
/// outbox; [push] sends the two rows right away, because teams need the
/// profile on the server before the general sync exists.
abstract interface class ProfileRepository {
  /// Whether [userId] has a profile on this device.
  Stream<bool> watchOnboarded(String userId);

  /// Brings a profile made on another device here. True if there was one.
  Future<Result<bool, ProfileFailure>> restore(String userId);

  /// Saves the answers of the welcome flow: the profile and its course.
  Future<void> create(String userId, OnboardingAnswers answers);

  /// Sends the profile and the course to the server.
  Future<Result<void, ProfileFailure>> push(String userId);
}
