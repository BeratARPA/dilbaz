import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/repositories/session_repository.dart';
import 'package:dilbaz_app/data/repositories/week_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_providers.g.dart';

@Riverpod(keepAlive: true)
SessionRepository sessionRepository(Ref ref) =>
    DriftSessionRepository(ref.watch(appDatabaseProvider));

/// The week summary's reads (docs/09 §5.13).
@Riverpod(keepAlive: true)
WeekRepository weekRepository(Ref ref) =>
    DriftWeekRepository(ref.watch(appDatabaseProvider));
