import 'dart:async';
import 'dart:io';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/audio/answer_recorder_io.dart';
import 'package:dilbaz_app/data/audio/recorder_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';

/// The recording plugin, as far as the recorder uses it: files are
/// written by the fake itself.
class FakeRecordPlatform extends RecordPlatform
    with MockPlatformInterfaceMixin {
  bool permission = true;
  bool broken = false;
  List<int> written = [1, 2, 3];
  RecordConfig? config;
  String? path;
  int cancels = 0;
  double amplitude = -30;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permission;

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    if (broken) throw PlatformException(code: 'record');
    this.config = config;
    this.path = path;
  }

  @override
  Future<String?> stop(String recorderId) async {
    final path = this.path;
    if (path == null) return null;
    File(path).writeAsBytesSync(written);
    return path;
  }

  @override
  Future<void> cancel(String recorderId) async => cancels++;

  @override
  Future<bool> isRecording(String recorderId) async => path != null;

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: amplitude, max: 0);

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  // The recorder uses nothing else of the plugin.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late Directory directory;
  late FakeRecordPlatform platform;
  late AnswerRecorder recorder;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dilbaz_answers');
    platform = FakeRecordPlatform();
    RecordPlatform.instance = platform;
    recorder = PlatformAnswerRecorder(
      AudioRecorder(),
      directory: () async => directory,
    );
  });

  tearDown(() => directory.delete(recursive: true));

  group('AnswerRecorder (docs/08-speech.md §4)', () {
    test('records speech as AAC-LC, 16 kHz, mono, 32 kbps', () async {
      expect(await recorder.start(), isA<Ok<void, RecordFailure>>());

      final config = platform.config!;
      expect(config.encoder, AudioEncoder.aacLc);
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(config.bitRate, 32000);
      expect(platform.path, startsWith(directory.path));
      expect(platform.path, endsWith('.m4a'));
    });

    test('records pronunciation as 16 kHz mono WAV (ADR-0011)', () async {
      await recorder.start(pronunciation: true);
      final config = platform.config!;
      expect(config.encoder, AudioEncoder.wav);
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(platform.path, endsWith('.wav'));
      expect((await recorder.stop())!.contentType, 'audio/wav');

      // The next answer is speech again.
      await recorder.start();
      expect(platform.config!.encoder, AudioEncoder.aacLc);
    });

    test('hands over the answer and keeps no file of it', () async {
      await recorder.start();

      final audio = (await recorder.stop())!;

      expect(audio.bytes, Uint8List.fromList([1, 2, 3]));
      expect(audio.contentType, 'audio/mp4');
      expect(audio.duration, greaterThanOrEqualTo(Duration.zero));
      expect(directory.listSync(), isEmpty);
    });

    test('nothing recorded is nothing to hand over', () async {
      expect(await recorder.stop(), isNull);
      platform.written = [];
      await recorder.start();
      expect(await recorder.stop(), isNull);
    });

    test('without the microphone permission nothing starts', () async {
      platform.permission = false;
      expect((await recorder.start() as Err).error, RecordFailure.permission);
      expect(platform.path, isNull);
    });

    test('a microphone that cannot be opened is a device failure', () async {
      platform.broken = true;
      expect((await recorder.start() as Err).error, RecordFailure.device);
    });

    test('a cancelled answer is thrown away', () async {
      await recorder.cancel();
      expect(platform.cancels, 0, reason: 'nothing to cancel');
      await recorder.start();
      await recorder.cancel();
      expect(platform.cancels, 1);
      expect(await recorder.stop(), isNull);
    });

    test('tells the loudness while recording', () async {
      await recorder.start();
      final first = await recorder.level().first;
      expect(first, closeTo(0.5, 1e-9));
    });
  });

  test('loudness runs from silence at -60 dBFS to full at 0', () {
    expect(loudness(-90), 0);
    expect(loudness(-60), 0);
    expect(loudness(-30), 0.5);
    expect(loudness(0), 1);
    expect(loudness(3), 1);
    expect(loudness(double.nan), 0);
  });

  test('the web records Opus, and every answer kind has a limit', () {
    final web = RecorderConfig.speech(web: true);
    expect(web.config.encoder, AudioEncoder.opus);
    expect(web.contentType, 'audio/webm');
    expect(RecorderConfig.cardLimit, const Duration(seconds: 12));
    expect(RecorderConfig.taskLimit, const Duration(minutes: 2));
    expect(
      RecorderConfig.shadowingLimit,
      lessThan(RecorderConfig.fourThreeTwoLimit),
    );
  });
}
