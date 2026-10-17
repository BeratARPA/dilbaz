import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/tasks/speaking_task.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';

/// The speaking tasks and connectors of the imported packs (docs/11 §2).
abstract interface class TaskContentRepository {
  /// Speaking tasks with what the learner reads; a task without its
  /// instruction in the pair pack is left out.
  Future<List<SpeakingTask>> speakingTasks();

  /// The connectors counted by the speech measures (docs/06 §3.3).
  Future<List<String>> connectors();

  /// Frequency rank of each lemma of the pack's lexicon, for the share of
  /// words beyond the frequent ones (docs/06 §3.3).
  Future<Map<String, int>> lemmaRanks();

  /// The pack's can-do codes with their level and the pair pack's summary;
  /// a code without a summary is left out.
  Future<List<CanDo>> canDos();

  /// The chat cards (A14) with what they mean; a card without its meaning
  /// in the pair pack is left out.
  Future<List<ChatCard>> chatCards();

  /// The information gap tasks (A15) with their roles and answer keys; a
  /// task without its instructions in the pair pack is left out.
  Future<List<InfoGapTask>> infoGaps();
}

/// An option of the role that chooses (A15).
typedef GapOption = ({String id, String text});

/// What one role of an information gap task sees: its lines (English), its
/// options if it chooses, and what it is asked to do (learner's language).
typedef GapRole = ({
  List<String> lines,
  List<GapOption> options,
  String instruction,
});

/// An information gap task (A15, ADR-0012).
typedef InfoGapTask = ({
  String key,
  CefrLevel level,
  String title,
  String prompt,

  /// What doing it means, for the speaking annotation.
  String goal,
  GapRole a,
  GapRole b,
  InfoGapKey answer,
});

/// A chat card (A14): a question to talk about with the partner, two
/// follow-ups and three phrases, each with its meaning.
typedef ChatCard = ({
  String key,
  CefrLevel level,
  String title,
  String question,
  String meaning,
  List<String> followUps,
  List<String> followUpMeanings,
  List<String> phrases,
  List<String> phraseMeanings,
});

/// A can-do code as the Progress tab lists it (docs/04 §5).
typedef CanDo = ({String code, CefrLevel level, String summary});

class DriftTaskContentRepository implements TaskContentRepository {
  new(this._db, {this._l2 = 'en'});

  final AppDatabase _db;
  final String _l2;

  static const _speaking = 'speaking';
  static const _chat = 'pair_chat';
  static const _gap = 'pair_info_gap';
  static const _instruction = 'task_instruction';
  static const _lemma = 'lemma';
  static const _summary = 'can_do_summary';

  static List<String> _strings(Object? value) => switch (value) {
    final List<Object?> list => [
      for (final item in list)
        if (item case final String text) text,
    ],
    _ => const [],
  };

  @override
  Future<List<SpeakingTask>> speakingTasks() async {
    final instructions = await _db.contentDao.pairEntries(_instruction);
    final tasks = <SpeakingTask>[];
    for (final row in await _db.contentDao.tasks()) {
      final level = CefrLevel.values
          .where((l) => l.code == row.level)
          .firstOrNull;
      final read = instructions[row.key];
      if (row.kind != _speaking || level == null || read == null) continue;
      final (title, prompt) = (read['title'], read['prompt']);
      final goal = row.data['goal'];
      if (title is! String || prompt is! String || goal is! String) continue;
      tasks.add(
        SpeakingTask(
          key: row.key,
          level: level,
          goal: goal,
          title: title,
          prompt: prompt,
          anchor: switch (row.data['anchor']) {
            final String anchor => anchor,
            _ => null,
          },
          canDo: _strings(row.data['can_do']),
          phrases: _strings(row.data['phrases']),
          phraseMeanings: _strings(read['phrases']),
        ),
      );
    }
    return tasks;
  }

  @override
  Future<Map<String, int>> lemmaRanks() async {
    final ranks = <String, int>{};
    for (final row in await _db.contentDao.itemsOfKinds([_lemma])) {
      final rank = row.rank;
      if (rank == null) continue;
      for (final lemma in row.lemmas) {
        final known = ranks[lemma];
        if (known == null || rank < known) ranks[lemma] = rank;
      }
    }
    return ranks;
  }

  @override
  Future<List<CanDo>> canDos() async {
    final pack = await _db.contentDao.targetPack(_l2);
    final summaries = await _db.contentDao.pairEntries(_summary);
    return switch (pack?.manifest) {
      {'can_dos': final List<Object?> codes} => [
        for (final entry in codes)
          if (entry case {
            'code': final String code,
            'level': final String levelCode,
          })
            if (CefrLevel.values.where((l) => l.code == levelCode).firstOrNull
                case final level?)
              if (summaries[code]?['summary'] case final String summary)
                (code: code, level: level, summary: summary),
      ],
      _ => const [],
    };
  }

  @override
  Future<List<String>> connectors() async {
    final pack = await _db.contentDao.targetPack(_l2);
    return switch (pack?.manifest) {
      {'connectors': final List<Object?> connectors} => [
        for (final connector in connectors)
          if (connector case {'text': final String text}) text,
      ],
      _ => const [],
    };
  }

  @override
  Future<List<ChatCard>> chatCards() async {
    final instructions = await _db.contentDao.pairEntries(_instruction);
    final cards = <ChatCard>[];
    for (final row in await _db.contentDao.tasks()) {
      final level = CefrLevel.values
          .where((l) => l.code == row.level)
          .firstOrNull;
      final read = instructions[row.key];
      if (row.kind != _chat || level == null || read == null) continue;
      final (title, meaning, question) = (
        read['title'],
        read['prompt'],
        row.data['question'],
      );
      if (title is! String || meaning is! String || question is! String) {
        continue;
      }
      cards.add((
        key: row.key,
        level: level,
        title: title,
        question: question,
        meaning: meaning,
        followUps: _strings(row.data['follow_ups']),
        followUpMeanings: _strings(read['follow_ups']),
        phrases: _strings(row.data['phrases']),
        phraseMeanings: _strings(read['phrases']),
      ));
    }
    return cards;
  }

  static List<int> _ints(Object? value) => switch (value) {
    final List<Object?> list => [
      for (final item in list)
        if (item case final int i) i,
    ],
    _ => const [],
  };

  static GapRole? _role(Object? role, Object? instruction) {
    if (role is! Map<String, Object?> || instruction is! String) return null;
    return (
      lines: _strings(role['lines']),
      options: switch (role['options']) {
        final List<Object?> list => [
          for (final option in list)
            if (option case {'id': final String id, 'text': final String text})
              (id: id, text: text),
        ],
        _ => const <GapOption>[],
      },
      instruction: instruction,
    );
  }

  @override
  Future<List<InfoGapTask>> infoGaps() async {
    final instructions = await _db.contentDao.pairEntries(_instruction);
    final tasks = <InfoGapTask>[];
    for (final row in await _db.contentDao.tasks()) {
      final level = CefrLevel.values
          .where((l) => l.code == row.level)
          .firstOrNull;
      final read = instructions[row.key];
      if (row.kind != _gap || level == null || read == null) continue;
      final roles = row.data['roles'];
      final said = read['roles'];
      if (roles is! Map<String, Object?> || said is! Map<String, Object?>) {
        continue;
      }
      final a = _role(roles['a'], said['a']);
      final b = _role(roles['b'], said['b']);
      final answer = switch ((row.data['type'], row.data['answer'])) {
        (
          'choose',
          {'chooser': final String chooser, 'option': final String option},
        ) =>
          ChooseKey(chooser: chooser, option: option),
        ('differences', final Map<String, Object?> key) => DifferencesKey(
          a: _ints(key['a']),
          b: _ints(key['b']),
        ),
        _ => null,
      };
      final (title, prompt, goal) = (
        read['title'],
        read['prompt'],
        row.data['goal'],
      );
      if (a == null ||
          b == null ||
          answer == null ||
          title is! String ||
          prompt is! String ||
          goal is! String) {
        continue;
      }
      tasks.add((
        key: row.key,
        level: level,
        title: title,
        prompt: prompt,
        goal: goal,
        a: a,
        b: b,
        answer: answer,
      ));
    }
    return tasks;
  }
}
