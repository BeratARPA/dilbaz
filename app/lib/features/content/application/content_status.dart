import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'content_status.freezed.dart';

/// Whether the course's content is on the device.
@freezed
sealed class ContentStatus with _$ContentStatus {
  /// The packs are imported; the counts say what they hold.
  const factory ready({
    required int words,
    required int chunks,
    required int sentences,
  }) = ContentReady;

  /// There is no content on the device and it could not be fetched.
  const factory unavailable(PackFailure failure) = ContentUnavailable;
}
