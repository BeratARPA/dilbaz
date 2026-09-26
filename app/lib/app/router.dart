import 'dart:async';

import 'package:dilbaz_app/app/home_shell.dart';
import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/features/auth/presentation/sign_in_screen.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_capture_screen.dart';
import 'package:dilbaz_app/features/practice/presentation/practice_screen.dart';
import 'package:dilbaz_app/features/progress/presentation/progress_screen.dart';
import 'package:dilbaz_app/features/settings/presentation/settings_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:dilbaz_app/features/together/presentation/together_screen.dart';
import 'package:flutter/widgets.dart';
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

  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: AppRoutes.today,
    refreshListenable: signedIn,
    redirect: (context, state) {
      final onSignIn = state.matchedLocation == AppRoutes.signIn;
      if (!signedIn.value) return onSignIn ? null : AppRoutes.signIn;
      return onSignIn ? AppRoutes.today : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
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
        path: AppRoutes.gapCapture,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const GapCaptureScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    router.dispose();
    signedIn.dispose();
  });
  return router;
}
