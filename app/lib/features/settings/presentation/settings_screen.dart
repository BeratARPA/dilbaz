import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Settings (docs/09 §5.12).
class SettingsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Center(child: Text(l10n.sectionInPreparation)),
    );
  }
}
