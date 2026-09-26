import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'database_provider.g.dart';

/// The app-wide local database; tests override it with an in-memory one.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final database = AppDatabase(driftDatabase(name: 'dilbaz'));
  ref.onDispose(database.close);
  return database;
}
