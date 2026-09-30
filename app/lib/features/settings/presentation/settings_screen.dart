import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/features/auth/application/session_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings (docs/09 §5.12).
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.mic_none),
            title: Text(l10n.microphoneCheckTitle),
            onTap: () => unawaited(context.push(AppRoutes.microphoneCheck)),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.signOut),
            onTap: () => unawaited(
              ref.read(sessionControllerProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
    );
  }
}
