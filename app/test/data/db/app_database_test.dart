import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synced user tables mirror the server (docs/13-data-model.md §2).
const syncedTables = {
  'profiles',
  'courses',
  'personal_items',
  'cards',
  'attempts',
  'attempt_amendments',
  'gap_entries',
  'recordings',
  'assessments',
  'writings',
  'sessions',
  'media_logs',
  'subtitle_imports',
};

/// State tables merge by last-writer-wins and carry `updated_at`.
const stateTables = {
  'profiles',
  'courses',
  'personal_items',
  'cards',
  'gap_entries',
  'recordings',
  'writings',
  'subtitle_imports',
};

const localTables = {'outbox', 'sync_state'};

const contentTables = {
  'content_packs',
  'content_items',
  'content_links',
  'content_forms',
  'content_texts',
  'content_tasks',
  'content_pair_entries',
};

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() => db.close());

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.read<String>('name')};
  }

  final t0 = DateTime.utc(2026, 9, 26, 8, 30);

  CardsCompanion card({String id = 'c1', String mode = 'speak'}) =>
      CardsCompanion.insert(
        id: id,
        profileId: 'p1',
        courseId: 'k1',
        itemRef: 'zz.sent.0001',
        mode: mode,
        fsrsCardId: 1758873600000,
        state: 1,
        due: t0,
      );

  test('creates exactly the user, local and content tables', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final tables = {for (final row in rows) row.read<String>('name')};
    expect(tables, {...syncedTables, ...localTables, ...contentTables});
  });

  test('synced tables carry the sync columns', () async {
    for (final table in syncedTables) {
      final columns = await columnsOf(table);
      expect(
        columns,
        containsAll(['id', 'server_seq', 'created_at', 'pending_push']),
        reason: table,
      );
      expect(
        columns.contains('updated_at'),
        stateTables.contains(table),
        reason: table,
      );
    }
  });

  test('timestamps are stored as ISO text and read back in UTC', () async {
    await db.into(db.cards).insert(card());
    final stored = await db
        .customSelect(
          'SELECT due FROM cards WHERE id = ?',
          variables: [Variable.withString('c1')],
        )
        .getSingle();
    expect(stored.read<String>('due'), startsWith('2026-09-26T08:30:00'));

    final row = await db.select(db.cards).getSingle();
    expect(row.due.isUtc, isTrue);
    expect(row.due, t0);
    expect(row.createdAt.isUtc, isTrue);
    expect(row.updatedAt.isUtc, isTrue);
  });

  test('new rows are not yet synced and have no server sequence', () async {
    await db.into(db.cards).insert(card());
    final row = await db.select(db.cards).getSingle();
    expect(row.serverSeq, isNull);
    expect(row.pendingPush, isFalse);
    expect(row.reps, 0);
    expect(row.suspended, isFalse);
  });

  test('one card per profile, item and mode', () async {
    await db.into(db.cards).insert(card());
    await db.into(db.cards).insert(card(id: 'c2', mode: 'type'));
    await expectLater(
      db.into(db.cards).insert(card(id: 'c3')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('profile defaults mirror the server defaults', () async {
    await db
        .into(db.profiles)
        .insert(ProfilesCompanion.insert(id: 'p1', displayName: 'Deniz'));
    final profile = await db.select(db.profiles).getSingle();
    expect(profile.l1, 'tr');
    expect(profile.timeBudgetMin, 30);
    expect(profile.weeklyDaysGoal, 5);
    expect(profile.anchors, isEmpty);
    expect(profile.interests, isEmpty);
    expect(profile.settings, isEmpty);
    expect(profile.quietHours, isNull);
  });

  test('JSON columns round-trip objects, arrays and string lists', () async {
    await db
        .into(db.attempts)
        .insert(
          AttemptsCompanion.insert(
            id: 'a1',
            profileId: 'p1',
            courseId: 'k1',
            deviceId: 'd1',
            activity: 'card.produce_speak',
            prompt: const {'item': 'zz.sent.0001', 'mode': 'speak'},
            response: const {'text': 'bø la', 'source': 'typed', 'asr': null},
            errorTags: const Value(['agr.x', 'art.y']),
            cardStateAfter: const Value({'state': 2, 'stability': 3.5}),
            createdAtClient: t0,
          ),
        );
    final row = await db.select(db.attempts).getSingle();
    expect(row.prompt, {'item': 'zz.sent.0001', 'mode': 'speak'});
    expect(row.response['asr'], isNull);
    expect(row.errorTags, ['agr.x', 'art.y']);
    expect(row.cardStateAfter, {'state': 2, 'stability': 3.5});
    expect(row.llm, isNull);

    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p1',
            displayName: 'Deniz',
            anchors: const Value([
              {'label': 'kahve', 'time': '08:30'},
            ]),
          ),
        );
    final profile = await db.select(db.profiles).getSingle();
    expect(profile.anchors, [
      {'label': 'kahve', 'time': '08:30'},
    ]);
  });

  test('outbox keeps insertion order and starts without failures', () async {
    for (final id in ['a1', 'a2', 'c1']) {
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              targetTable: id.startsWith('a') ? 'attempts' : 'cards',
              rowId: id,
              op: id.startsWith('a') ? 'insert' : 'upsert',
            ),
          );
    }
    final entries = await (db.select(
      db.outbox,
    )..orderBy([(o) => OrderingTerm.asc(o.id)])).get();
    expect(entries.map((e) => e.rowId), ['a1', 'a2', 'c1']);
    expect(entries.every((e) => e.attempts == 0), isTrue);
    expect(entries.every((e) => e.nextAttemptAt == null), isTrue);
  });

  test('sync state starts from sequence 0', () async {
    await db
        .into(db.syncState)
        .insert(SyncStateCompanion.insert(profileId: 'p1'));
    final state = await db.select(db.syncState).getSingle();
    expect(state.lastServerSeq, 0);
    expect(state.lastSyncAt, isNull);
  });

  test('content tables accept pack rows', () async {
    await db
        .into(db.contentItems)
        .insert(
          ContentItemsCompanion.insert(
            key: 'zz.ws.bola.n.1',
            packId: 'zz@1',
            kind: 'word_sense',
            level: 'A1',
            lemmas: const Value(['bola']),
            data: const Value({'pos': 'NOUN', 'license': 'own'}),
          ),
        );
    await db
        .into(db.contentForms)
        .insert(
          ContentFormsCompanion.insert(
            form: 'bolaven',
            lemma: 'bola',
            packId: 'zz@1',
          ),
        );
    final item = await db.select(db.contentItems).getSingle();
    expect(item.lemmas, ['bola']);
    expect(item.data['pos'], 'NOUN');
    expect(item.deprecated, isFalse);
  });
}
