import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/pack_repository.dart';
import 'package:dilbaz_app/data/repositories/supabase_pack_remote.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'pack_repository_provider.g.dart';

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
PackRemote packRemote(Ref ref) => SupabasePackRemote(Supabase.instance.client);

@Riverpod(keepAlive: true)
PackRepository packRepository(Ref ref) {
  final database = ref.watch(appDatabaseProvider);
  return PackRepository(
    remote: ref.watch(packRemoteProvider),
    importer: PackImporter(database),
    content: database.contentDao,
  );
}
