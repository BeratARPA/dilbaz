import 'package:flutter/material.dart';

/// Title and optional explanation at the top of a welcome-flow step.
class StepHeader extends StatelessWidget {
  const new({required this.title, this.body, super.key});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineSmall),
          ),
          if (body case final body?)
            Text(body, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
