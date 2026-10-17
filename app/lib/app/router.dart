import 'dart:async';

import 'package:dilbaz_app/app/home_shell.dart';
import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/features/auth/presentation/sign_in_screen.dart';
import 'package:dilbaz_app/features/cards/presentation/card_session_screen.dart';
import 'package:dilbaz_app/features/dictation_practice/presentation/dictation_practice_screen.dart';
import 'package:dilbaz_app/features/fluency/presentation/fluency_screen.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_capture_screen.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_entry_screen.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_list_screen.dart';
import 'package:dilbaz_app/features/monthly/presentation/monthly_screen.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/features/onboarding/presentation/onboarding_screen.dart';
import 'package:dilbaz_app/features/onboarding/presentation/opening_screen.dart';
import 'package:dilbaz_app/features/placement/presentation/placement_screen.dart';
import 'package:dilbaz_app/features/practice/presentation/practice_screen.dart';
import 'package:dilbaz_app/features/progress/presentation/progress_screen.dart';
import 'package:dilbaz_app/features/settings/presentation/microphone_check_screen.dart';
import 'package:dilbaz_app/features/settings/presentation/settings_screen.dart';
import 'package:dilbaz_app/features/speaking/presentation/speaking_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:dilbaz_app/features/together/presentation/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final auth = ref.watch(authRepositoryProvider);
  final signedIn = ValueNotifier<bool>(auth.isSignedIn);
  // Stream errors are network failures while refreshing the session; the
  // current session stays valid, so they do not change the route.
  final subscription = auth.watchSignedIn().listen(
    (value) => signedIn.value = value,
    onError: (Object _) {},
  );

  // Null until it is known whether the learner has finished the welcome
  // flow; a profile made on another device is looked up first, and it
  // stays null while the server cannot be asked.
  final onboarded = ValueNotifier<bool?>(null);
  ref.listen(
    onboardedProvider,
    (_, next) => onboarded.value = next.isLoading ? null : next.value,
    fireImmediately: true,
  );

  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: AppRoutes.today,
    refreshListenable: Listenable.merge([signedIn, onboarded]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!signedIn.value) {
        return location == AppRoutes.signIn ? null : AppRoutes.signIn;
      }
      final target = switch (onboarded.value) {
        null => AppRoutes.opening,
        false => AppRoutes.welcome,
        true => null,
      };
      if (target != null) return location == target ? null : target;
      return _beforeHome.contains(location) ? AppRoutes.today : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.opening,
        builder: (context, state) => const OpeningScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.today,
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.practice,
                builder: (context, state) => const PracticeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.together,
                builder: (context, state) => const TogetherScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.progress,
                builder: (context, state) => const ProgressScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.microphoneCheck,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const MicrophoneCheckScreen(),
      ),
      GoRoute(
        path: AppRoutes.gaps,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const GapListScreen(),
      ),
      // Before `/gap/:id`, so that "new" is not taken for an id.
      GoRoute(
        path: AppRoutes.gapCapture,
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            GapCaptureScreen(sharedText: state.extra as String?),
      ),
      GoRoute(
        path: '${AppRoutes.gaps}/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            GapEntryScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.placement,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const PlacementScreen(),
      ),
      GoRoute(
        path: AppRoutes.cards,
        parentNavigatorKey: rootKey,
        builder: (context, state) => CardSessionScreen(
          beyondBudget: state.uri.queryParameters['more'] == '1',
        ),
      ),
      GoRoute(
        path: AppRoutes.speaking,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const SpeakingScreen(),
      ),
      GoRoute(
        path: AppRoutes.fluency,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const FluencyScreen(),
      ),
      GoRoute(
        path: AppRoutes.dictation,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const DictationPracticeScreen(),
      ),
      GoRoute(
        path: AppRoutes.monthly,
        parentNavigatorKey: rootKey,
        builder: (context, state) => MonthlyScreen(
          baseline: state.uri.queryParameters['baseline'] == '1',
        ),
      ),
    ],
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    router.dispose();
    signedIn.dispose();
    onboarded.dispose();
  });
  return router;
}

/// Pages a signed-in learner who has finished the welcome flow has no
/// business on.
const Set<String> _beforeHome = {
  AppRoutes.signIn,
  AppRoutes.opening,
  AppRoutes.welcome,
};
