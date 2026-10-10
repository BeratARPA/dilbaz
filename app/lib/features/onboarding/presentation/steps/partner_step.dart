import 'dart:async';

import 'package:dilbaz_app/data/repositories/team_repository.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The calm text for a team [failure].
String teamFailureText(AppLocalizations l10n, TeamFailure failure) =>
    switch (failure) {
      TeamFailure.network => l10n.teamFailureNetwork,
      TeamFailure.inviteNotFound => l10n.teamFailureInviteNotFound,
      TeamFailure.unknown => l10n.teamFailureUnknown,
    };

/// Step 7: creating a team or joining the partner's with an invite code.
/// Optional; the bottom bar skips it.
class PartnerStep extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PartnerStep> createState() => _PartnerStepState();
}

class _PartnerStepState extends ConsumerState<PartnerStep> {
  final _name = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final (team, failure, busy) = ref.watch(
      onboardingControllerProvider.select(
        (s) => (s.team, s.teamFailure, s.busy),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          title: l10n.onboardingPartnerTitle,
          body: l10n.onboardingPartnerBody,
        ),
        if (team != null)
          SelectableText(
            team.inviteCode == null
                ? l10n.onboardingTeamJoined(team.name)
                : l10n.onboardingTeamCreated(team.inviteCode!),
            style: theme.textTheme.titleMedium,
          )
        else ...[
          TextField(
            controller: _name,
            enabled: !busy,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n.onboardingTeamNameLabel,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: _name,
            builder: (context, name, _) => FilledButton.tonal(
              onPressed: busy || name.text.trim().isEmpty
                  ? null
                  : () => unawaited(controller.createTeam(name.text)),
              child: Text(l10n.onboardingTeamCreate),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _code,
            enabled: !busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.onboardingInviteCodeLabel,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: _code,
            builder: (context, code, _) => FilledButton.tonal(
              onPressed: busy || code.text.trim().isEmpty
                  ? null
                  : () => unawaited(controller.joinTeam(code.text)),
              child: Text(l10n.onboardingTeamJoin),
            ),
          ),
          if (failure != null) ...[
            const SizedBox(height: 16),
            Row(
              spacing: 8,
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.error),
                Expanded(child: Text(teamFailureText(l10n, failure))),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
