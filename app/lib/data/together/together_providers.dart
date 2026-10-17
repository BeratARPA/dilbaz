import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'together_providers.g.dart';

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
TogetherRepository togetherRepository(Ref ref) =>
    SupabaseTogetherRepository(Supabase.instance.client);
