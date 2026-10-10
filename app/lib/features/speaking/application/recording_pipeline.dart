import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';

/// What the measures need from the packs: the language's forms and
/// fillers, its connectors and the frequency ranks of its lemmas.
typedef MeasureKit = ({
  LanguageServices language,
  List<String> connectors,
  Map<String, int> ranks,
});

/// The tutor's marks, or why there are none yet.
typedef Marks = ({AnnotatedSpeech? annotated, TutorFailure? waiting});

/// A task or test recording from the microphone to its measures
/// (docs/08-speech.md §5.2): kept on the device, written down, marked by
/// the tutor and measured by the engine. Each step stores what it found,
/// so nothing said is lost when a later step fails.
class RecordingPipeline {
  const new({
    required this._store,
    required this._recordings,
    required this._speech,
    required this._tutor,
    required this._now,
  });

  final DateTime Function() _now;
  final RecordingStore _store;
  final RecordingRepository _recordings;
  final SpeechRepository _speech;
  final TutorRepository _tutor;

  /// Keeps [audio] as the recording [id] of [taskRef], on this device; it
  /// goes up to the server after a sync (RecordingFiles).
  Future<void> keep({
    required String id,
    required String userId,
    required String courseId,
    required String taskRef,
    required RecordedAudio audio,
    bool isAssessment = false,
    String? assessmentId,
  }) async {
    final kept = await _store.save(id, audio);
    await _recordings.create(
      id: id,
      userId: userId,
      courseId: courseId,
      taskRef: taskRef,
      // Kept here under the same file name (RecordingStore.find).
      audioPath: kept == null
          ? null
          : recordingStoragePath(
              userId: userId,
              id: id,
              at: _now(),
              contentType: audio.contentType,
            ),
      duration: audio.duration,
      isAssessment: isAssessment,
      assessmentId: assessmentId,
    );
  }

  /// What was said, word by word with times.
  Future<Result<Transcript, SpeechFailure>> transcribe(
    String id,
    RecordedAudio audio,
  ) async {
    final heard = await _speech.transcribe(audio);
    if (heard case Ok(:final value)) {
      await _recordings.update(id, transcript: value);
    }
    return heard;
  }

  /// The tutor's marks of the transcript.
  Future<Marks> mark(String id, SpeakingAnnotateRequest request) async {
    switch (await _tutor.speakingAnnotate(request)) {
      case Ok(:final value):
        await _recordings.update(id, annotated: value);
        return (annotated: value, waiting: null);
      case Err(:final error):
        return (annotated: null, waiting: error);
    }
  }

  /// The engine's measures of [words], with the marks when there are any.
  Future<SpeechMetrics?> measure(
    String id,
    List<TimedWord> words,
    MeasureKit kit, {
    SpeechAnnotation? annotation,
  }) async {
    final metrics = SpeechMetrics.of(
      words,
      language: kit.language,
      annotation: annotation,
      connectors: kit.connectors,
      rankOf: (lemma) => kit.ranks[lemma],
    );
    if (metrics != null) await _recordings.update(id, metrics: metrics);
    return metrics;
  }
}

/// A transcript's words as the engine reads them.
List<TimedWord> timedWords(Transcript transcript) => [
  for (final word in transcript.words)
    TimedWord(
      text: word.w,
      startMs: word.startMs,
      endMs: word.endMs,
      confidence: word.conf,
    ),
];
