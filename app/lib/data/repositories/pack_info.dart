import 'package:freezed_annotation/freezed_annotation.dart';

part 'pack_info.freezed.dart';
part 'pack_info.g.dart';

/// A published content pack as the registry lists it (`packs`,
/// docs/13-data-model.md §2.2).
@freezed
abstract class PackInfo with _$PackInfo {
  const factory({
    /// Pack id with its version: `en@1`, `tr-en@1`.
    required String id,

    /// `target` (the language learned) or `pair` (that language for
    /// speakers of another).
    required String kind,
    required String l2,
    required double version,

    /// `sha256:<hex>` of the pack file.
    required String checksum,

    /// Bucket and path of the pack file: `packs/en@1.sqlite`.
    required String storagePath,
    String? l1,
  }) = _PackInfo;

  factory fromJson(Map<String, Object?> json) => _$PackInfoFromJson(json);
}
