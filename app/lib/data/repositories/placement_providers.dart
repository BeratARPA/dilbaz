import 'package:dilbaz_app/core/audio/clip_player.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/pack_audio.dart';
import 'package:dilbaz_app/data/repositories/placement_bank.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'placement_providers.g.dart';

@Riverpod(keepAlive: true)
AssessmentRepository assessmentRepository(Ref ref) =>
    DriftAssessmentRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
PlacementBankRepository placementBankRepository(Ref ref) =>
    PlacementBankRepository(ref.watch(appDatabaseProvider).contentDao);

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
PackAudio packAudio(Ref ref) => PackAudio(
  SupabasePackAudioRemote(Supabase.instance.client),
  // Clips stay until the app's data is cleared; a cache could lose them
  // just when the learner is offline.
  directory: () async => (await getApplicationSupportDirectory()).path,
);

/// The player of one screen; it is freed with the screen.
@riverpod
ClipPlayer clipPlayer(Ref ref) {
  final player = JustAudioClipPlayer();
  ref.onDispose(player.dispose);
  return player;
}
