import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Together tab: partner activities and the shared weekly goal (docs/09 §5.9).
class TogetherScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabTogether)),
      body: Center(child: Text(l10n.sectionInPreparation)),
    );
  }
}
