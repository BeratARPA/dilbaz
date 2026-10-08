import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// The microphone of a spoken card: it records while it is held
/// (docs/09 §5.3). A screen reader taps it once to start and once to stop.
class HoldToSpeakButton extends StatelessWidget {
  const new({
    required this.listening,
    required this.onStart,
    required this.onStop,
    super.key,
  });

  final bool listening;
  final VoidCallback onStart;
  final VoidCallback onStop;

  static const size = 96.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: context.l10n.cardsHoldToSpeak,
      onTap: listening ? onStop : onStart,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => onStart(),
        onPointerUp: (_) => onStop(),
        onPointerCancel: (_) => onStop(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: listening ? scheme.primary : scheme.primaryContainer,
          ),
          child: Icon(
            Icons.mic,
            size: 44,
            color: listening ? scheme.onPrimary : scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
