import 'dart:async';
import 'dart:math';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/audio/recorder_config.dart';
import 'package:dilbaz_app/data/repositories/attempt_draft.dart';
import 'package:dilbaz_app/data/repositories/card_content.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'card_session_controller.g.dart';

/// One card of the session: a review, or a new item (no card yet) that is
/// introduced first (A00).
typedef _Entry = ({StoredCard? card, CardContent content});

/// An answer as it was given.
typedef _Answer = ({
  String text,

  /// How the attempt was given; it names the activity.
  AnswerInput input,

  /// What speech recognition heard; null for a typed answer.
  Transcript? heard,

  /// The text typed over what was heard, or over an answer the LLM was not
  /// sure of: what it replaced.
  String? correctedFrom,
  int latencyMs,
  int? durationMs,
});

/// What the checks said about an answer.
typedef _Judged = ({
  Evaluation evaluation,

  /// The LLM's check; null when it was not needed or gave no answer.
  LlmAnswerCheck? llm,

  /// The templated ladder, for the hints the LLM left blank.
  HintLadder? template,

  /// Why the LLM gave no answer.
  TutorFailure? failure,
});

/// What the session keeps from its start.
typedef _Session = ({
  String userId,
  String courseId,
  String deviceId,
  String l2,
  CefrLevel level,
  StudySettings settings,
  Scaffolds scaffolds,
  AnswerChecker checker,
  CardMode newCardMode,
  Map<AnswerInput, LatencyProfile> latencies,
});

/// The card under review and everything its attempts need.
final class _Review {
  new(this.entry, this.state, {required this.input, required this.introducing})
    : key = entry.content.answerKey;

  final _Entry entry;

  /// The answer key; answers the LLM accepts join it for the rest of the
  /// review.
  AnswerKey key;
  CardReview state;

  /// What the latest answer changed, for an answer typed over it.
  ({CardReview state, AnswerKey key, LlmLadder? ladder, HintLadder? template})?
  before;
  AnswerInput input;
  bool introducing;
  CardPhase phase = const CardPhase.asking();
  final attempts = <AttemptDraft>[];
  final answers = <_Answer>[];
  _Judged? judged;

  /// The hints of the latest miss.
  LlmLadder? ladder;
  HintLadder? template;

  /// An answer the LLM was not sure of, before "did you mean …?".
  ({_Answer answer, _Judged judged})? pending;
  LastAnswer? last;
  TutorFailure? offline;
  SpeechFailure? speechFailure;
  RecordFailure? recordFailure;

  /// Latency of an answer being typed, taken at its first key.
  int? typingLatency;
  bool playing = false;
  bool saved = false;
}

/// A card session (A00, A01, A02; docs/03-activities.md, docs/09 §5.3).
///
/// The planner picks the due reviews and the new items when the session
/// starts. A new item is introduced, then asked once. Every answer goes
/// through the deterministic check first; what it cannot match goes to
/// the LLM, and without the LLM the check aligns it (docs/03 §0.5). The
/// review ends with an automatic rating (docs/03 §0.3); its attempts and
/// the card's new memory are stored in one transaction when the learner
/// goes on (I-03).
@riverpod
class CardSessionController extends _$CardSessionController {
  late _Session _session;
  var _queue = <_Entry>[];
  var _index = 0;
  _Review? _review;
  var _reviewed = 0;
  var _introduced = 0;

  /// The session, for `sessions` (docs/13 §2.4): when it began, its time
  /// on cards and what was planned.
  DateTime? _startedAt;
  Duration _active = Duration.zero;
  Map<String, Object?> _planned = const {};

  /// When the card on screen opened.
  DateTime? _openedAt;

  /// Longest time one card counts: a card left open is not study time.
  static const _cardCap = Duration(minutes: 3);
  final _scheduler = SrsScheduler();

  /// From the prompt (or the latest feedback) to the answer.
  final _watch = Stopwatch();

  /// From the first key to the typed answer.
  final _typing = Stopwatch();
  Timer? _limit;

  @override
  Future<CardSessionState> build({bool beyondBudget = false}) async {
    ref.onDispose(() => _limit?.cancel());
    // Kept for the whole session.
    ref
      ..watch(answerRecorderProvider)
      ..watch(clipPlayerProvider);
    final content = ref.watch(cardContentRepositoryProvider);
    final cards = ref.watch(cardRepositoryProvider);
    final devices = ref.watch(deviceRepositoryProvider);
    final planned = await planCards(ref, beyondBudget: beyondBudget);
    if (planned == null) return const CardSessionState.unavailable();
    if (planned.plan.enough) return const CardSessionState.enough();
    final course = planned.course;
    final plan = planned.plan;
    final knowledge = planned.knowledge;
    final byId = planned.cards;
    final queue = <_Entry>[];
    Future<void> add(String itemKey, StoredCard? card) async {
      final found = await content.content(itemKey, knowledge: knowledge);
      if (found == null) return;
      final own = await cards.personalAnswers(
        courseId: course.id,
        itemRef: itemKey,
        carrierKey: found.carrierKey,
      );
      final key = found.answerKey;
      queue.add((
        card: card,
        content: found.copyWith(
          answerKey: key.copyWith(
            variants: [...key.variants, ...own.variants],
            alternatives: [...key.alternatives, ...own.alternatives],
          ),
        ),
      ));
    }

    for (final review in plan.reviews) {
      final card = byId[review.id]!;
      await add(card.itemRef, card);
    }
    for (final key in plan.newItems) {
      await add(key, null);
    }
    if (queue.isEmpty) return const CardSessionState.empty();

    _session = (
      userId: planned.userId,
      courseId: course.id,
      deviceId: await devices.deviceId(planned.userId),
      l2: course.l2,
      level: course.level,
      settings: planned.settings,
      scaffolds: Scaffolds.forLevel(course.level),
      checker: AnswerChecker(planned.language),
      newCardMode: plan.newCardMode,
      latencies: {
        for (final input in AnswerInput.values)
          input: LatencyProfile.of(
            await cards.recentLatencies(course.id, _mode(input)),
          ),
      },
    );
    _queue = queue;
    _index = 0;
    _reviewed = 0;
    _introduced = 0;
    _active = Duration.zero;
    _startedAt = ref.read(clockProvider)();
    _planned = {
      'reviews': plan.reviews.length,
      'new': plan.newItems.length,
      'estimate_ms': plan.estimate.inMilliseconds,
    };
    return _open(0);
  }

  static CardMode _mode(AnswerInput input) => switch (input) {
    AnswerInput.speak => CardMode.speak,
    AnswerInput.type => CardMode.type,
  };

  /// Opens the card at [index]: a new item is introduced first.
  CardSessionState _open(int index) {
    final entry = _queue[index];
    final settings = _session.settings;
    final typed =
        settings.silentMode ||
        (entry.card?.mode ?? _session.newCardMode) == CardMode.type;
    final review = _Review(
      entry,
      _session.scaffolds.review(),
      input: typed ? AnswerInput.type : AnswerInput.speak,
      introducing: entry.card == null,
    );
    _review = review;
    _openedAt = ref.read(clockProvider)();
    _restartWatch();
    // After the state is in place; out loud only when that suits the
    // learner (silent mode).
    if (review.introducing && !settings.silentMode) unawaited(Future(play));
    return _stateOf(review);
  }

  CardSessionState _stateOf(_Review review) {
    final content = review.entry.content;
    if (review.introducing) {
      return CardSessionState.introduction(
        IntroductionView(
          number: _index + 1,
          total: _queue.length,
          headword: content.headword,
          meaning: content.meaning,
          sentence: content.answerKey.reference,
          sentenceMeaning: content.prompt,
          input: review.input,
          usageNote: content.usageNote,
          contrastNote: content.contrastNote,
          hasClip: _clip(content) != null,
          playing: review.playing,
        ),
      );
    }
    final state = review.state;
    final asking = review.phase is CardAsking;
    final hintLevel = state.hintLevel;
    return CardSessionState.card(
      CardView(
        number: _index + 1,
        total: _queue.length,
        prompt: content.prompt,
        contextNote: content.contextNote,
        input: review.input,
        phase: review.phase,
        canSpeak: _session.settings.audioConsent,
        hints: [
          for (var level = 1; level <= min(hintLevel, 3); level++)
            ?_hint(review, level),
        ],
        canHint:
            asking &&
            hintLevel >= 1 &&
            hintLevel < 3 &&
            _hint(review, hintLevel + 1) != null,
        canReveal: asking && (state.misses > 0 || state.reprompted),
        canRetype: _canRetype(review),
        last: review.last,
        offline: review.offline,
        speechFailure: review.speechFailure,
        recordFailure: review.recordFailure,
        hasClip: _clip(content) != null,
        playing: review.playing,
      ),
    );
  }

  /// "Yanlış duyuldu": the latest answer was heard, and it did not end the
  /// review as recalled.
  static bool _canRetype(_Review review) {
    if (review.last?.heard != true) return false;
    return switch (review.phase) {
      CardAsking() => review.last?.feedback != null,
      CardEnded(:final outcome, :final almost) =>
        outcome is! Recalled || almost,
      _ => false,
    };
  }

  /// Hint [level] (1–3): the LLM's words, else the template.
  static Hint? _hint(_Review review, int level) {
    final written = switch (level) {
      1 => review.ladder?.h1,
      2 => review.ladder?.h2,
      _ => review.ladder?.h3,
    };
    if (written != null && written.trim().isNotEmpty) {
      return Hint.written(written.trim());
    }
    final template = review.template;
    if (template == null) return null;
    return switch (level) {
      1 => Hint.kind(template.kind),
      2 when template.place != null => Hint.place(template.place!),
      // The rule note is H3 of grammar cards only (docs/03 §0.5).
      _ => null,
    };
  }

  /// The clip at the level's speed (docs/02 §3).
  String? _clip(CardContent content) => _session.scaffolds.slowAudio
      ? content.slowClip ?? content.clip
      : content.clip ?? content.slowClip;

  void _emit(_Review review) {
    if (_review != review || !ref.mounted) return;
    state = AsyncData(_stateOf(review));
  }

  void _restartWatch() {
    _watch
      ..reset()
      ..start();
  }

  /// From the introduction to its card: "now you say it".
  void begin() {
    final review = _review;
    if (review == null || !review.introducing) return;
    review.introducing = false;
    _restartWatch();
    _emit(review);
  }

  /// Plays the card's sentence.
  Future<void> play() async {
    // It may come after the session was closed.
    if (!ref.mounted) return;
    final review = _review;
    if (review == null || review.playing) return;
    final clip = _clip(review.entry.content);
    if (clip == null) return;
    review.playing = true;
    _emit(review);
    final file = await ref.read(packAudioProvider).file(clip);
    if (!ref.mounted) return;
    // Nothing plays for a card the learner has left.
    if (file case Ok(value: final path) when _review == review) {
      await ref.read(clipPlayerProvider).play(path);
      if (!ref.mounted) return;
    }
    review.playing = false;
    _emit(review);
  }

  /// Types instead of speaking, or speaks again.
  void switchInput() {
    final review = _review;
    if (review == null || review.phase is! CardAsking) return;
    final next = review.input == AnswerInput.speak
        ? AnswerInput.type
        : AnswerInput.speak;
    if (next == AnswerInput.speak && !_session.settings.audioConsent) return;
    review
      ..input = next
      ..speechFailure = null
      ..recordFailure = null;
    _emit(review);
  }

  /// Starts recording the answer; it stops by itself at the card limit.
  Future<void> startSpeaking() async {
    final review = _review;
    if (review == null ||
        review.phase is! CardAsking ||
        review.input != AnswerInput.speak ||
        !_session.settings.audioConsent) {
      return;
    }
    final latency = _watch.elapsedMilliseconds;
    review
      ..phase = const CardPhase.listening()
      ..speechFailure = null
      ..recordFailure = null;
    _emit(review);
    unawaited(ref.read(clipPlayerProvider).stop());
    final recorder = ref.read(answerRecorderProvider);
    final started = await recorder.start();
    if (!ref.mounted) return;
    // Let go before the microphone opened: nothing to keep.
    if (started is Ok && review.phase is! CardListening) {
      await recorder.cancel();
      return;
    }
    if (started case Err(:final error)) {
      review
        ..phase = const CardPhase.asking()
        ..recordFailure = error;
      _emit(review);
      return;
    }
    review.typingLatency = latency;
    _limit = Timer(RecorderConfig.cardLimit, () => unawaited(stopSpeaking()));
  }

  /// Stops recording, and checks what was heard.
  Future<void> stopSpeaking() async {
    final review = _review;
    if (review == null || review.phase is! CardListening) return;
    _limit?.cancel();
    final latency = review.typingLatency ?? 0;
    review
      ..typingLatency = null
      ..phase = const CardPhase.checking();
    _emit(review);
    final audio = await ref.read(answerRecorderProvider).stop();
    if (!ref.mounted || _review != review) return;
    if (audio == null) {
      review.phase = const CardPhase.asking();
      _emit(review);
      return;
    }
    final heard = await ref
        .read(speechRepositoryProvider)
        .transcribe(audio, lang: _session.l2);
    if (!ref.mounted || _review != review) return;
    switch (heard) {
      case Err(:final error):
        // The card can be typed instead (docs/08 §5.3).
        review
          ..phase = const CardPhase.asking()
          ..speechFailure = error;
        _emit(review);
      case Ok(value: final transcript):
        await _answer(review, (
          text: transcript.text,
          input: AnswerInput.speak,
          heard: transcript,
          correctedFrom: null,
          latencyMs: latency,
          durationMs: audio.duration.inMilliseconds,
        ));
    }
  }

  /// The first key of a typed answer: its latency ends here.
  void startTyping() {
    final review = _review;
    if (review == null ||
        review.phase is! CardAsking ||
        review.typingLatency != null) {
      return;
    }
    review.typingLatency = _watch.elapsedMilliseconds;
    _typing
      ..reset()
      ..start();
  }

  /// A typed answer.
  Future<void> submit(String text) async {
    final review = _review;
    final answer = text.trim();
    if (review == null || review.phase is! CardAsking || answer.isEmpty) {
      return;
    }
    final latency = review.typingLatency;
    review.typingLatency = null;
    await _answer(review, (
      text: answer,
      input: AnswerInput.type,
      heard: null,
      correctedFrom: null,
      latencyMs: latency ?? _watch.elapsedMilliseconds,
      durationMs: latency == null ? null : _typing.elapsedMilliseconds,
    ));
  }

  /// Types the answer over what was heard ("yanlış duyuldu"), or over an
  /// answer the LLM was not sure of. It stays the same attempt
  /// (docs/03 §0.3).
  Future<void> retype(String text) async {
    final review = _review;
    final typed = text.trim();
    if (review == null || typed.isEmpty) return;
    final _Answer replaced;
    if (review.pending case (:final answer, judged: _)) {
      replaced = answer;
      review.pending = null;
    } else if (_canRetype(review)) {
      replaced = review.answers.removeLast();
      final before = review.before!;
      review
        ..state = before.state
        ..key = before.key
        ..ladder = before.ladder
        ..template = before.template
        ..attempts.removeLast();
    } else {
      return;
    }
    await _answer(review, (
      text: typed,
      input: replaced.input,
      heard: replaced.heard,
      correctedFrom: replaced.text,
      latencyMs: replaced.latencyMs,
      durationMs: replaced.durationMs,
    ));
  }

  /// "Did you mean …?" — yes: the answer counts as the LLM left it.
  void confirm() {
    final review = _review;
    final pending = review?.pending;
    if (review == null || pending == null) return;
    review.pending = null;
    _apply(review, pending.answer, pending.judged);
  }

  /// Opens the next hint (H2, H3) after a miss.
  void nextHint() {
    final review = _review;
    if (review == null) return;
    final view = _stateOf(review);
    if (view is! CardSessionCard || !view.view.canHint) return;
    review.state = review.state.nextHint();
    _emit(review);
  }

  /// Shows the answer (H4) on request; it ends the review.
  void reveal() {
    final review = _review;
    if (review == null) return;
    final view = _stateOf(review);
    if (view is! CardSessionCard || !view.view.canReveal) return;
    review.state = review.state.reveal();
    _end(review);
  }

  /// Stores the ended review and opens the next card.
  Future<void> next() async {
    final review = _review;
    if (review == null || review.phase is! CardEnded) return;
    await _save(review);
    if (!ref.mounted || _review != review) return;
    unawaited(ref.read(clipPlayerProvider).stop());
    if (_index + 1 < _queue.length) {
      _index++;
      state = AsyncData(_open(_index));
    } else {
      _review = null;
      await _record();
      if (!ref.mounted) return;
      state = AsyncData(
        CardSessionState.done(reviewed: _reviewed, introduced: _introduced),
      );
    }
  }

  /// Leaves the session. An ended review is stored; one under way is not.
  Future<void> leave() async {
    _limit?.cancel();
    final review = _review;
    _review = null;
    unawaited(ref.read(clipPlayerProvider).stop());
    if (review != null) {
      if (review.phase is CardListening) {
        await ref.read(answerRecorderProvider).cancel();
      }
      await _save(review);
    }
    await _record();
  }

  /// Writes the session to `sessions` once, if a card was stored; the
  /// Today screen counts its time (I-13).
  Future<void> _record() async {
    final startedAt = _startedAt;
    if (startedAt == null || _reviewed + _introduced == 0) return;
    _startedAt = null;
    await ref
        .read(sessionRepositoryProvider)
        .record(
          userId: _session.userId,
          courseId: _session.courseId,
          deviceId: _session.deviceId,
          startedAt: startedAt,
          endedAt: ref.read(clockProvider)(),
          strands: {Strand.language: _active},
          planned: _planned,
          done: {'reviewed': _reviewed, 'introduced': _introduced},
        );
  }

  Future<void> _answer(_Review review, _Answer answer) async {
    review
      ..phase = const CardPhase.checking()
      ..speechFailure = null
      ..recordFailure = null;
    _emit(review);
    final judged = await _judge(review, answer);
    if (!ref.mounted || _review != review) return;
    // The LLM was not sure: the learner confirms or corrects first.
    if (judged.evaluation case Evaluation(
      verdict: Verdict.uncertain,
      llmPending: false,
    )) {
      review
        ..pending = (answer: answer, judged: judged)
        ..phase = const CardPhase.confirming()
        ..last = LastAnswer(text: answer.text, heard: _heard(answer));
      _emit(review);
      return;
    }
    _apply(review, answer, judged);
  }

  static bool _heard(_Answer answer) =>
      answer.heard != null && answer.correctedFrom == null;

  /// Step 2, then the LLM, then step 4 without it (docs/03 §0.5).
  Future<_Judged> _judge(_Review review, _Answer answer) async {
    final checker = _session.checker;
    final matched = checker.match(answer.text, review.key);
    if (matched != null) {
      return (evaluation: matched, llm: null, template: null, failure: null);
    }
    final result = await ref
        .read(tutorRepositoryProvider)
        .answerCheck(_request(review, answer));
    final aligned = checker.checkWithoutLlm(answer.text, review.key);
    return switch (result) {
      Ok(value: final check) => (
        evaluation: check.evaluation,
        llm: check,
        template: aligned.ladder,
        failure: null,
      ),
      Err(:final error) => (
        evaluation: aligned.evaluation,
        llm: null,
        template: aligned.ladder,
        failure: error,
      ),
    };
  }

  AnswerCheckRequest _request(_Review review, _Answer answer) {
    final content = review.entry.content;
    final listed = _session.checker.listed(review.key);
    return AnswerCheckRequest(
      l1: _session.settings.l1,
      l2: _session.l2,
      level: _session.level,
      explainInL1: _session.scaffolds.explainInL1,
      itemKey: content.itemKey,
      prompt: content.prompt,
      reference: review.key.reference,
      variants: listed.withTarget,
      alternatives: listed.withoutTarget,
      targetSpan: content.targetSpan,
      answer: answer.text,
      typed: !_heard(answer),
      attemptNo: min(review.state.misses + 1, CardReview.defaultMaxAttempts),
      grammarCodes: content.grammarCodes.take(10).toList(),
      contextNote: content.contextNote,
      asrConfidence: _heard(answer) ? _confidence(answer.heard!) : null,
      previousResponses: [
        for (final earlier in review.answers.reversed.take(2).toList().reversed)
          earlier.text,
      ],
    );
  }

  /// Mean confidence of the heard words; null when none has one.
  static double? _confidence(Transcript transcript) {
    final values = [for (final word in transcript.words) ?word.conf];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  void _apply(_Review review, _Answer answer, _Judged judged) {
    final before = review.state;
    final after = before.answer(judged.evaluation, latencyMs: answer.latencyMs);
    review
      ..before = (
        state: before,
        key: review.key,
        ladder: review.ladder,
        template: review.template,
      )
      ..state = after
      ..judged = judged
      ..offline = judged.failure
      ..answers.add(answer)
      ..attempts.add(_draft(review, answer, judged, before));
    final effect = after.lastEffect!;
    if (effect == AnswerEffect.missed) {
      review
        ..ladder = judged.llm?.ladder
        ..template = judged.template;
    }
    // Learned from the LLM: it matches without it next time (step 3).
    if (judged.llm case LlmAnswerCheck(
      verdict: Verdict.acceptableVariant,
      :final targetOk,
    )) {
      final key = review.key;
      review.key = targetOk
          ? key.copyWith(variants: [...key.variants, answer.text])
          : key.copyWith(alternatives: [...key.alternatives, answer.text]);
    }
    review.last = LastAnswer(
      text: answer.text,
      heard: _heard(answer),
      feedback: switch (effect) {
        _ when after.isDone => null,
        AnswerEffect.correctWithoutTarget => AnswerFeedback.withoutTarget,
        AnswerEffect.unintelligible => AnswerFeedback.unheard,
        _ => AnswerFeedback.tryAgain,
      },
      spans: judged.llm?.errorSpans ?? const [],
    );
    if (after.isDone) {
      _end(review);
      return;
    }
    review.phase = const CardPhase.asking();
    _restartWatch();
    _emit(review);
  }

  AttemptDraft _draft(
    _Review review,
    _Answer answer,
    _Judged judged,
    CardReview before,
  ) {
    final content = review.entry.content;
    final heard = answer.heard;
    final llm = judged.llm;
    final failure = judged.failure;
    return AttemptDraft(
      activity: cardActivity(_mode(answer.input)),
      prompt: {
        'prompt_l1': content.prompt,
        'reference': review.key.reference,
        'carrier': content.carrierKey,
        'context': ?content.contextNote,
      },
      response: {
        'text': answer.text,
        'source': _heard(answer) ? 'asr' : 'typed',
        if (heard != null) ...{
          'transcript': heard.text,
          'asr': {
            'provider': heard.provider,
            'model': heard.model,
            'conf': ?_confidence(heard),
          },
        },
        if (heard != null && answer.correctedFrom != null) 'asr_override': true,
        if (heard == null) 'corrected_from': ?answer.correctedFrom,
      },
      createdAtClient: ref.read(clockProvider)(),
      verdict: judged.evaluation.verdict.code,
      targetOk: judged.evaluation.targetOk,
      errorTags: llm?.errorTags ?? const [],
      hintsUsed: before.hintLevel,
      hintMaxLevel: before.hintLevel,
      latencyMs: answer.latencyMs,
      durationMs: answer.durationMs,
      llm: llm != null
          ? {
              'route': 'answer_check',
              'pending': false,
              'provider': llm.provider,
              'model': llm.model,
              'catalog': llm.catalog,
              'confidence': llm.confidence,
            }
          : failure != null
          ? {
              'route': 'answer_check',
              'pending': judged.evaluation.llmPending,
              'code': failure.name,
            }
          : null,
    );
  }

  void _end(_Review review) {
    final outcome = review.state.outcome!;
    final judged = review.judged;
    final almost =
        outcome is Recalled && judged?.evaluation.verdict == Verdict.minorError;
    // The learner's answer corrected: the LLM's H4, else the nearest
    // correct answer.
    final corrected = switch (outcome) {
      NotRecalled() => _written(review.ladder?.h4) ?? review.template?.answer,
      Recalled() when almost =>
        _written(judged?.llm?.ladder.h4) ?? judged?.template?.answer,
      _ => null,
    };
    final sentence = review.key.reference;
    final language = _session.checker.language;
    review.phase = CardPhase.ended(
      outcome: outcome,
      sentence: sentence,
      correction:
          corrected == null ||
              language.normalize(corrected) == language.normalize(sentence)
          ? null
          : corrected,
      almost: almost,
    );
    _emit(review);
    if (!_session.settings.silentMode) unawaited(play());
  }

  static String? _written(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Stores an ended review: a new item gets its card now (A00), and the
  /// attempts go in with the rating and the card's new memory.
  Future<void> _save(_Review review) async {
    if (review.saved || !review.state.isDone || review.attempts.isEmpty) {
      return;
    }
    review.saved = true;
    final cards = ref.read(cardRepositoryProvider);
    final entry = review.entry;
    final card =
        entry.card ??
        await cards.introduce(
          userId: _session.userId,
          courseId: _session.courseId,
          itemRef: entry.content.itemKey,
          mode: _session.newCardMode,
        );
    final input = review.answers.last.input;
    final rating = review.state.outcome!.rating(
      _session.latencies[input]!,
      justIntroduced: entry.card == null,
    );
    final after = _scheduler.review(
      card.memory,
      rating,
      at: ref.read(clockProvider)(),
    );
    // The rated attempt carries the review's highest hint, the answer
    // shown on request included.
    final hints = review.state.hintLevel;
    final attempts = [...review.attempts];
    attempts.last = attempts.last.copyWith(
      hintsUsed: max(attempts.last.hintsUsed, hints),
      hintMaxLevel: max(attempts.last.hintMaxLevel, hints),
    );
    await cards.recordReview(
      userId: _session.userId,
      courseId: _session.courseId,
      deviceId: _session.deviceId,
      card: card,
      attempts: attempts,
      rating: rating,
      after: after,
    );
    if (entry.card == null) {
      _introduced++;
    } else {
      _reviewed++;
    }
    final opened = _openedAt;
    if (opened != null) {
      final spent = ref.read(clockProvider)().difference(opened);
      _active += spent > _cardCap ? _cardCap : spent;
    }
  }
}
