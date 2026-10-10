import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why the learner's data could not be deleted on the server.
enum MyDataFailure {
  /// The server could not be reached.
  network,
  unknown,
}

/// The server side of "Tüm verimi sil" (docs/13-data-model.md §2.7).
abstract interface class MyDataRemote {
  /// Deletes every row of the signed-in learner (`delete_my_data`).
  Future<Result<void, MyDataFailure>> deleteServerData();
}

class SupabaseMyDataRemote implements MyDataRemote {
  const new(this._client);

  final SupabaseClient _client;

  static const wait = Duration(seconds: 30);

  @override
  Future<Result<void, MyDataFailure>> deleteServerData() async {
    try {
      await _client.rpc<void>('delete_my_data').timeout(wait);
      return const Ok(null);
    } on PostgrestException {
      return const Err(MyDataFailure.unknown);
    } on ClientException {
      return const Err(MyDataFailure.network);
    } on TimeoutException {
      return const Err(MyDataFailure.network);
    }
  }
}
