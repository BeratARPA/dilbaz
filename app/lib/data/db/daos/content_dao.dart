import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/content_tables.dart';
import 'package:drift/drift.dart';

part 'content_dao.g.dart';

/// Reads the imported language packs (docs/11-language-packs.md §5.1).
/// Content is read-only: only the pack importer writes these tables.
@DriftAccessor(
  tables: [
    ContentPacks,
    ContentItems,
    ContentLinks,
    ContentForms,
    ContentPairEntries,
  ],
)
class ContentDao extends DatabaseAccessor<AppDatabase> with _$ContentDaoMixin {
  new(super.attachedDatabase);

  Future<List<ContentPackRow>> packs() => (select(
    contentPacks,
  )..orderBy([(t) => OrderingTerm(expression: t.packId)])).get();

  Stream<List<ContentPackRow>> watchPacks() => (select(
    contentPacks,
  )..orderBy([(t) => OrderingTerm(expression: t.packId)])).watch();

  /// The target pack of [l2], with its settings; null before its import.
  Future<ContentPackRow?> targetPack(String l2) =>
      (select(contentPacks)
            ..where((t) => t.kind.equals(_target) & t.l2.equals(l2))
            ..limit(1))
          .getSingleOrNull();

  /// Follows [targetPack]: a pack refresh may bring what was missing.
  Stream<ContentPackRow?> watchTargetPack(String l2) =>
      (select(contentPacks)
            ..where((t) => t.kind.equals(_target) & t.l2.equals(l2))
            ..limit(1))
          .watchSingleOrNull();

  static const _target = 'target';

  Future<ContentItemRow?> item(String key) =>
      (select(contentItems)..where((t) => t.key.equals(key))).getSingleOrNull();

  /// Items of the given [kinds], by key.
  Future<List<ContentItemRow>> itemsOfKinds(Iterable<String> kinds) =>
      (select(contentItems)
            ..where((t) => t.kind.isIn(kinds))
            ..orderBy([(t) => OrderingTerm(expression: t.key)]))
          .get();

  /// How many items there are of each kind.
  Future<Map<String, int>> itemCounts() async {
    final count = contentItems.key.count();
    final rows =
        await (selectOnly(contentItems)
              ..addColumns([contentItems.kind, count])
              ..groupBy([contentItems.kind]))
            .get();
    return {
      for (final row in rows) row.read(contentItems.kind)!: row.read(count)!,
    };
  }

  /// Links of one [type], from both packs.
  Future<List<ContentLinkRow>> linksOfType(String type) =>
      (select(contentLinks)..where((t) => t.type.equals(type))).get();

  /// The forms table: surface form → lemmas.
  Future<Map<String, Set<String>>> forms() async {
    final forms = <String, Set<String>>{};
    for (final row in await select(contentForms).get()) {
      (forms[row.form] ??= {}).add(row.lemma);
    }
    return forms;
  }

  /// A pair-pack entry, such as the `gloss` or the `variants` of an item.
  Future<Map<String, Object?>?> pairEntry(String kind, String key) async {
    final row = await (select(
      contentPairEntries,
    )..where((t) => t.kind.equals(kind) & t.key.equals(key))).getSingleOrNull();
    return row?.data;
  }
}
