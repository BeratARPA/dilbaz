import 'package:dilbaz_engine/src/curriculum/link_type.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'item_link.freezed.dart';

/// Directed edge between two items of the curriculum graph.
@freezed
abstract class ItemLink with _$ItemLink {
  /// Creates an edge.
  const factory({
    /// Key of the source item.
    required String from,

    /// Key of the target item.
    required String to,

    /// Edge type.
    required LinkType type,
  }) = _ItemLink;
}
