import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tasks/shadowing_repository.dart';
import 'package:dilbaz_app/data/tutor/pron_check.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/pack_fixture.dart';

void main() {
  late AppDatabase db;
  late ShadowingRepository repository;
  var ids = 0;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    repository = DriftShadowingRepository(
      db,
      now: () => cardNow,
      newId: () => 'try-${ids++}',
    );
  });
  tearDown(() => db.close());

  test('the pair pack pronunciation tags, by code', () async {
    expect(await repository.pronunciationTags(), {
      'zz.phon.a': (severity: 0.4, description: 'A sesi kısa kalmış.'),
      'zz.phon.b': (severity: 0.2, description: 'B sesi yumuşamış.'),
    });
  });

  test('each try is an attempt with its outbox row (I-03)', () async {
    const heard = HeardPronunciation(
      uncertain: false,
      issues: [(index: 0, word: 'Bada', tag: 'zz.phon.a', heard: 'bda')],
      catalog: 'qq-zz@1',
      promptVersion: 'pron_check@1',
      provider: 'gemini',
      model: 'm',
    );
    final first = await repository.recordTry(
      userId: 'u',
      courseId: 'c',
      deviceId: 'd',
      itemRef: badaSentence,
      reference: 'Bada kolu.',
      clip: 'zz/v1/0001.mp3',
      duration: const Duration(seconds: 2),
      at: cardNow,
      errorTags: ['zz.phon.a'],
      transcript: const Transcript(
        text: 'bda kolu',
        provider: 'fake',
        model: 'fake',
        durationMs: 2000,
      ),
      heard: heard,
    );
    await repository.recordTry(
      userId: 'u',
      courseId: 'c',
      deviceId: 'd',
      itemRef: badaSentence,
      reference: 'Bada kolu.',
      clip: 'zz/v1/0001.mp3',
      duration: const Duration(seconds: 2),
      at: cardNow,
      errorTags: const [],
      parentAttemptId: first,
    );
    final rows = await db.select(db.attempts).get();
    expect(rows.map((a) => a.activity), ['shadowing', 'shadowing']);
    expect(rows.first.itemRef, badaSentence);
    expect(rows.first.prompt, {
      'reference': 'Bada kolu.',
      'clip': 'zz/v1/0001.mp3',
    });
    expect(rows.first.response, {
      'source': 'asr',
      'text': 'bda kolu',
      'asr': {'provider': 'fake', 'model': 'fake'},
    });
    expect(rows.first.errorTags, ['zz.phon.a']);
    expect(rows.first.llm, heard.toJson());
    expect(rows.first.durationMs, 2000);
    expect(rows.last.parentAttemptId, first);
    expect(rows.last.response, {'source': 'asr'});
    expect(rows.last.llm, isNull);
    expect((await db.select(db.outbox).get()).map((o) => o.rowId), [
      'try-0',
      'try-1',
    ]);
  });
}
