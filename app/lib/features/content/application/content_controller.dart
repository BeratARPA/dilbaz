import 'dart:async';

import 'package:dilbaz_app/core/config/course_defaults.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/daos/content_dao.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/repositories/pack_repository.dart';
import 'package:dilbaz_app/data/repositories/pack_repository_provider.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'content_controller.g.dart';

/// Tells whether the course's content is on the device and keeps it up to
/// date (docs/11-language-packs.md §5).
///
/// Local first: content already on the device is ready at once and is
/// refreshed in the background; only the first download is waited for.
@Riverpod(keepAlive: true)
class ContentController extends _$ContentController {
  late PackRepository _packs;
  late ContentDao _content;

  @override
  Future<ContentStatus> build() async {
    _packs = ref.watch(packRepositoryProvider);
    _content = ref.watch(appDatabaseProvider).contentDao;
    if (await _packs.hasContent(l2: defaultL2, l1: defaultL1)) {
      unawaited(_refresh());
      return await _ready();
    }
    return await _fetch();
  }

  /// Tries again after content could not be fetched.
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// The first download: nothing to show until it is done.
  Future<ContentStatus> _fetch() async =>
      switch (await _packs.sync(l2: defaultL2, l1: defaultL1)) {
        Ok() => await _ready(),
        Err(:final error) => ContentStatus.unavailable(error),
      };

  /// Looks for newer packs; a failure leaves the content as it is.
  Future<void> _refresh() async {
    final synced = await _packs.sync(l2: defaultL2, l1: defaultL1);
    if (synced case Ok(:final value) when value.isNotEmpty) {
      final refreshed = await _ready();
      if (ref.mounted) state = AsyncData(refreshed);
    }
  }

  Future<ContentStatus> _ready() async {
    final counts = await _content.itemCounts();
    return ContentStatus.ready(
      words: counts['word_sense'] ?? 0,
      chunks: counts['chunk'] ?? 0,
      sentences: counts['sentence'] ?? 0,
    );
  }
}
