import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Practice tab: every activity grouped by type (docs/09 §4).
class PracticeScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabPractice)),
      body: Center(child: Text(l10n.sectionInPreparation)),
    );
  }
}
