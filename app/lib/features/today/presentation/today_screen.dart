import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Today tab: the planner's suggestions (docs/09 §5.2).
class TodayScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabToday)),
      body: Center(child: Text(l10n.sectionInPreparation)),
    );
  }
}
