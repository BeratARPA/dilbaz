import 'package:dilbaz_app/core/permissions/permission_gateway.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/repositories/drift_profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_remote.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/team_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'profile_repository_provider.g.dart';

// The Supabase-backed providers require `Supabase.initialize` (main.dart);
// tests override them with fakes.

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) => DriftProfileRepository(
  ref.watch(appDatabaseProvider),
  SupabaseProfileRemote(Supabase.instance.client),
);

@Riverpod(keepAlive: true)
TeamRepository teamRepository(Ref ref) =>
    SupabaseTeamRepository(Supabase.instance.client);

@Riverpod(keepAlive: true)
PermissionGateway permissionGateway(Ref ref) => const DevicePermissionGateway();
