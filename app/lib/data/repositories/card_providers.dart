import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/device_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'card_providers.g.dart';

@Riverpod(keepAlive: true)
CardRepository cardRepository(Ref ref) =>
    DriftCardRepository(ref.watch(appDatabaseProvider));

/// One per session: it keeps the pack's items while the session runs, and a
/// pack imported later is read afresh by the next session.
@riverpod
CardContentRepository cardContentRepository(Ref ref) =>
    DriftCardContentRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
DeviceRepository deviceRepository(Ref ref) =>
    DriftDeviceRepository(ref.watch(appDatabaseProvider));
