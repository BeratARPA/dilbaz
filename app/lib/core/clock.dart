import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock.g.dart';

/// The current time in UTC; tests fix it.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => nowUtc;
