import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/gap/gap_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gap_providers.g.dart';

@Riverpod(keepAlive: true)
GapRepository gapRepository(Ref ref) =>
    DriftGapRepository(ref.watch(appDatabaseProvider));
