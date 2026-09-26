import 'dart:async';

import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:dilbaz_app/features/auth/application/sign_in_controller.dart';
import 'package:dilbaz_app/features/auth/application/sign_in_state.dart';
import 'package:dilbaz_app/features/auth/presentation/auth_failure_text.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Email-code sign-in; there are no passwords (docs/14 §2).
class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  SignInController get _controller =>
      ref.read(signInControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(signInControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.signInTitle, style: textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  ...switch (state) {
                    SignInEnterEmail() || SignInSendingCode() => _emailStep(
                      l10n,
                      busy: state is SignInSendingCode,
                    ),
                    SignInEnterCode(:final email) ||
                    SignInVerifyingCode(:final email) => _codeStep(
                      l10n,
                      email,
                      busy: state is SignInVerifyingCode,
                    ),
                  },
                  if (_failureOf(state) case final failure?) ...[
                    const SizedBox(height: 16),
                    _FailureNote(failure.text(l10n)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailStep(AppLocalizations l10n, {required bool busy}) => [
    Text(l10n.signInEmailIntro),
    const SizedBox(height: 16),
    TextField(
      controller: _email,
      enabled: !busy,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      textInputAction: TextInputAction.send,
      decoration: InputDecoration(labelText: l10n.signInEmailLabel),
      onSubmitted: (_) => unawaited(_controller.submitEmail(_email.text)),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: busy
          ? null
          : () => unawaited(_controller.submitEmail(_email.text)),
      child: busy ? const _Progress() : Text(l10n.signInSendCode),
    ),
  ];

  List<Widget> _codeStep(
    AppLocalizations l10n,
    String email, {
    required bool busy,
  }) => [
    Text(l10n.signInCodeSentTo(email)),
    const SizedBox(height: 16),
    TextField(
      controller: _code,
      enabled: !busy,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: l10n.signInCodeLabel),
      onSubmitted: (_) => unawaited(_controller.submitCode(_code.text)),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: busy
          ? null
          : () => unawaited(_controller.submitCode(_code.text)),
      child: busy ? const _Progress() : Text(l10n.signInConfirm),
    ),
    const SizedBox(height: 8),
    TextButton(
      onPressed: busy ? null : () => unawaited(_controller.resendCode()),
      child: Text(l10n.signInResendCode),
    ),
    TextButton(
      onPressed: busy
          ? null
          : () {
              _code.clear();
              _controller.changeEmail();
            },
      child: Text(l10n.signInChangeEmail),
    ),
  ];

  AuthFailure? _failureOf(SignInState state) => switch (state) {
    SignInEnterEmail(:final failure) => failure,
    SignInEnterCode(:final failure) => failure,
    _ => null,
  };
}

/// Neutral failure note: icon and text, never color alone (docs/09 §3).
class _FailureNote extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
