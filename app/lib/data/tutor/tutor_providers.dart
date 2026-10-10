import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'tutor_providers.g.dart';

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
TutorRepository tutorRepository(Ref ref) =>
    SupabaseTutorRepository(Supabase.instance.client);
