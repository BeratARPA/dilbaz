import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// The tasks to choose from: the planner's suggestions first, the rest on
/// request (I-14).
class TaskChoicePage extends StatelessWidget {
  const new({
    required this.suggested,
    required this.others,
    required this.onChoose,
    super.key,
  });

  final List<TaskChoice> suggested;
  final List<TaskChoice> others;
  final void Function(String key) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            l10n.speakingChooseTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final task in suggested)
            _TaskTile(task: task, onTap: () => onChoose(task.key)),
          if (others.isNotEmpty)
            ExpansionTile(
              title: Text(l10n.speakingOtherTasks),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final task in others)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TaskTile(
                      task: task,
                      onTap: () => onChoose(task.key),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const new({required this.task, required this.onTap});

  final TaskChoice task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: EdgeInsets.zero,
    child: ListTile(
      title: Text(task.title),
      trailing: Text(
        task.level.code,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      onTap: onTap,
    ),
  );
}
