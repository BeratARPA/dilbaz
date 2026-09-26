import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Capture page of "Söyleyemediklerim" (A19, docs/09 §5.5).
class GapCaptureScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gapCaptureTitle)),
      body: Center(child: Text(l10n.sectionInPreparation)),
    );
  }
}
