import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/device_recognizer.dart';
import 'package:dilbaz_app/data/speech/dictation.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_speech.dart';

/// A device recognizer that says what it is told.
class FakeDeviceRecognizer implements DeviceRecognizer {
  new({this.languages = const {'tr'}});

  final Set<String> languages;
  void Function(String words, {required bool done})? _onWords;
  void Function(DeviceRecognitionError error)? _onError;
  final listened = <(String, Duration)>[];
  int stops = 0;
  int cancels = 0;

  /// What the learner says; [done] makes it final.
  void say(String words, {bool done = false}) =>
      _onWords?.call(words, done: done);

  void fail(DeviceRecognitionError error) => _onError?.call(error);

  @override
  Future<bool> supports(String language) async => languages.contains(language);

  @override
  Future<void> listen({
    required String language,
    required Duration listenFor,
    required void Function(String words, {required bool done}) onWords,
    required void Function(DeviceRecognitionError error) onError,
  }) async {
    listened.add((language, listenFor));
    _onWords = onWords;
    _onError = onError;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;
}

void main() {
  group('on the device', () {
    late FakeDeviceRecognizer device;
    late FakeAnswerRecorder recorder;
    late FakeSpeechRepository speech;
    late DeviceFirstDictation dictation;

    setUp(() {
      device = FakeDeviceRecognizer();
      recorder = FakeAnswerRecorder();
      speech = FakeSpeechRepository();
      dictation = DeviceFirstDictation(
        device,
        recorder,
        speech,
        finalWait: Duration.zero,
      );
    });

    test('Turkish is written down where it is said', () async {
      expect(await dictation.start(), isA<Ok<void, DictationFailure>>());
      expect(device.listened, [('tr', DeviceFirstDictation.limit)]);
      device
        ..say('canım')
        ..say('canım sıkıldı ', done: true);
      final heard = await dictation.stop();
      expect((heard as Ok<String, DictationFailure>).value, 'canım sıkıldı');
      expect(device.stops, 1);
      // Nothing left the device.
      expect(recorder.starts, 0);
      expect(speech.asked, isEmpty);
    });

    test('the last words count when the final ones do not come', () async {
      await dictation.start();
      device.say('yarın görüşürüz');
      final heard = await dictation.stop();
      expect((heard as Ok).value, 'yarın görüşürüz');
    });

    test('its errors become failures, words win over them', () async {
      for (final (error, failure) in [
        (DeviceRecognitionError.permission, DictationFailure.permission),
        (DeviceRecognitionError.network, DictationFailure.network),
        (DeviceRecognitionError.nothingHeard, DictationFailure.nothingHeard),
        (DeviceRecognitionError.other, DictationFailure.unavailable),
      ]) {
        await dictation.start();
        device.fail(error);
        expect(
          (await dictation.stop() as Err).error,
          failure,
          reason: '$error',
        );
      }
      await dictation.start();
      device
        ..say('bir şey')
        ..fail(DeviceRecognitionError.network);
      expect((await dictation.stop() as Ok).value, 'bir şey');
      await dictation.start();
      expect(
        (await dictation.stop() as Err).error,
        DictationFailure.nothingHeard,
      );
    });

    test('cancelled, nothing is kept', () async {
      await dictation.start();
      await dictation.cancel();
      expect(device.cancels, 1);
    });
  });

  group('without Turkish on the device', () {
    late FakeAnswerRecorder recorder;
    late FakeSpeechRepository speech;
    late DeviceFirstDictation dictation;

    setUp(() {
      recorder = FakeAnswerRecorder();
      speech = FakeSpeechRepository(heard: ' Bulaşıkları ben yıkarım. ');
      dictation = DeviceFirstDictation(
        FakeDeviceRecognizer(languages: {}),
        recorder,
        speech,
      );
    });

    test('it is recorded and recognized by the speech function', () async {
      expect(await dictation.start(), isA<Ok<void, DictationFailure>>());
      expect(recorder.recording, isTrue);
      final heard = await dictation.stop();
      expect((heard as Ok).value, 'Bulaşıkları ben yıkarım.');
      expect(speech.asked, hasLength(1));
    });

    test('nothing recorded or heard is said so', () async {
      recorder.silent = true;
      await dictation.start();
      expect(
        (await dictation.stop() as Err).error,
        DictationFailure.nothingHeard,
      );
      recorder.silent = false;
      speech.heard = '  ';
      await dictation.start();
      expect(
        (await dictation.stop() as Err).error,
        DictationFailure.nothingHeard,
      );
    });

    test("the function's failures and the microphone are told apart", () async {
      for (final (failure, told) in [
        (SpeechFailure.network, DictationFailure.network),
        (SpeechFailure.quota, DictationFailure.quota),
        (SpeechFailure.busy, DictationFailure.busy),
        (SpeechFailure.unavailable, DictationFailure.unavailable),
        (SpeechFailure.badAudio, DictationFailure.nothingHeard),
        (SpeechFailure.unknown, DictationFailure.unknown),
      ]) {
        speech.failure = failure;
        await dictation.start();
        expect((await dictation.stop() as Err).error, told, reason: '$failure');
      }
      recorder.failure = RecordFailure.permission;
      expect(
        (await dictation.start() as Err).error,
        DictationFailure.permission,
      );
      recorder.failure = RecordFailure.device;
      expect(
        (await dictation.start() as Err).error,
        DictationFailure.unavailable,
      );
      await dictation.cancel();
      expect(recorder.cancels, 1);
    });
  });
}
