import 'dart:async';
import 'dart:io';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The folder of the live check (docs/15-testing.md §4a): `pair.env` with
/// the local stack's URL and anon key and two local test partners
/// (`make_live_pair.py`).
const _folder = String.fromEnvironment('DILBAZ_LIVE');

/// The Together repository as the app uses it, two partners against a local
/// Supabase stack: the team, an invitation over Realtime, its answer, and
/// presence on the private team channel (F2-07). Run by hand:
///
///     flutter test test_live/together_live_test.dart --dart-define=DILBAZ_LIVE=<folder>
void main() {
  final skip = _folder.isEmpty
      ? 'Live check: run by hand with --dart-define=DILBAZ_LIVE=<folder>'
      : null;
  late SupabaseClient a;
  late SupabaseClient b;

  Future<SupabaseClient> signIn(Map<String, String> env, String tag) async {
    final client = SupabaseClient(
      env['DILBAZ_LIVE_URL']!,
      env['DILBAZ_LIVE_ANON']!,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    await client.auth.signInWithPassword(
      email: env['DILBAZ_LIVE_${tag}_EMAIL'],
      password: env['DILBAZ_LIVE_${tag}_PASSWORD']!,
    );
    return client;
  }

  setUpAll(() async {
    if (skip != null) return;
    final env = {
      for (final line in File('$_folder/pair.env').readAsLinesSync())
        if (line.split('=') case [final key, ...final value])
          key: value.join('='),
    };
    a = await signIn(env, 'A');
    b = await signIn(env, 'B');
  });

  tearDownAll(() async {
    if (skip != null) return;
    await a.dispose();
    await b.dispose();
  });

  /// The first value of [stream] that passes [test], within 20 s.
  Future<T> first<T>(Stream<T> stream, bool Function(T) test) =>
      stream.firstWhere(test).timeout(const Duration(seconds: 20));

  test(
    'team, invitation over Realtime, answer, presence',
    () async {
      final ra = SupabaseTogetherRepository(a);
      final rb = SupabaseTogetherRepository(b);
      final team = (await ra.team() as Ok<TeamView?, TogetherFailure>).value!;
      expect(team.members.map((m) => m.name).toSet(), {'Canli A', 'Canli B'});
      final idA = a.auth.currentUser!.id;
      final idB = b.auth.currentUser!.id;

      // B listens; A invites; B sees it come.
      final seen = rb.invites().asBroadcastStream();
      await first(seen, (_) => true);
      expect(
        await ra.invite(
          teamId: team.id,
          from: idA,
          to: idB,
          taskRef: 'en.chat.chat_food',
        ),
        isA<Ok<void, TogetherFailure>>(),
      );
      final arrived = await first(
        seen,
        (list) => list.any((i) => i.state == InviteState.sent),
      );
      final invite = arrived.firstWhere((i) => i.state == InviteState.sent);
      expect((invite.from, invite.to), (idA, idB));

      // A cannot accept for B; B can, and A sees it.
      final watched = ra.invites().asBroadcastStream();
      await first(watched, (_) => true);
      expect(
        await ra.answer(invite.id, yes: true),
        isA<Err<void, TogetherFailure>>(),
      );
      expect(
        await rb.answer(invite.id, yes: true),
        isA<Ok<void, TogetherFailure>>(),
      );
      await first(
        watched,
        (list) => list.any(
          (i) => i.id == invite.id && i.state == InviteState.accepted,
        ),
      );

      // Both on the team channel: each sees the other.
      final hereA = ra.present(teamId: team.id, self: idA);
      final hereB = rb.present(teamId: team.id, self: idB);
      final subscription = hereB.listen((_) {});
      expect(await first(hereA, (ids) => ids.containsAll({idA, idB})), {
        idA,
        idB,
      });
      await subscription.cancel();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an information gap session: start, join, two answers, done',
    () async {
      final ra = SupabaseTogetherRepository(a);
      final rb = SupabaseTogetherRepository(b);
      final idA = a.auth.currentUser!.id;
      final idB = b.auth.currentUser!.id;
      final seen = rb.sessions().asBroadcastStream();
      await first(seen, (_) => true);
      const id = '9e000000-0000-4000-8000-0000000000b1';
      expect(
        await ra.startSession(
          id: id,
          taskRef: 'en.gap.gap_friend',
          partner: idB,
          role: 'a',
        ),
        isA<Ok<void, TogetherFailure>>(),
      );
      final invited = await first(
        seen,
        (list) => list.any((s) => s.id == id && s.state == PairState.invited),
      );
      expect(invited.firstWhere((s) => s.id == id).roles, {idA: 'a', idB: 'b'});
      expect(await rb.joinSession(id), isA<Ok<void, TogetherFailure>>());
      expect(await rb.answerSession(id, 'c'), isA<Ok<void, TogetherFailure>>());
      expect(
        await ra.answerSession(id, 'done'),
        isA<Ok<void, TogetherFailure>>(),
      );
      final done = await first(
        seen,
        (list) => list.any((s) => s.id == id && s.state == PairState.done),
      );
      expect(done.firstWhere((s) => s.id == id).answers, {
        idB: 'c',
        idA: 'done',
      });
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the week together and a cheer over Realtime',
    () async {
      final ra = SupabaseTogetherRepository(a);
      final rb = SupabaseTogetherRepository(b);
      final idA = a.auth.currentUser!.id;
      final idB = b.auth.currentUser!.id;
      final team = (await ra.team() as Ok<TeamView?, TogetherFailure>).value!;
      final week = await rb.week(
        teamId: team.id,
        since: DateTime.now().toUtc().subtract(const Duration(days: 6)),
        offsetMinutes: 180,
      );
      final summary = (week as Ok<TeamWeek, TogetherFailure>).value;
      expect(summary.members.map((m) => m.id).toSet(), {idA, idB});
      expect(summary.goalDays, greaterThan(0));

      final seen = rb.cheers().asBroadcastStream();
      await first(seen, (_) => true);
      expect(
        await ra.cheer(
          teamId: team.id,
          from: idA,
          to: idB,
          key: CheerKey.speaking,
        ),
        isA<Ok<void, TogetherFailure>>(),
      );
      final got = await first(
        seen,
        (list) => list.any((c) => c.from == idA && c.key == CheerKey.speaking),
      );
      expect(got.first.to, idB);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
