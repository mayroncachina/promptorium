import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/memory/handoff.dart';
import '../../../data/providers.dart';
import 'continue_dialog.dart' show PathOption;
import 'continue_link.dart';

/// Where the handoff of the dialog stands.
enum HandoffSourceStatus { none, unavailable }

/// What the ai-memory part of the dialog tells it (SPEC-099 R4–R6).
@immutable
class HandoffSourceState {
  const HandoffSourceState({
    required this.status,
    this.installed = false,
    this.handoff,
    this.owner,
    this.openTerminal,
  });

  const HandoffSourceState.none() : this(status: HandoffSourceStatus.none);

  final HandoffSourceStatus status;

  /// ai-memory is connected (else the dialog shows the discreet line).
  final bool installed;
  final Handoff? handoff;
  final String? owner;

  /// Opens `ai-memory run` in the terminal (R6); null = unavailable.
  final Future<void> Function(Session origin)? openTerminal;

  /// The ai-memory handoff path can be chosen.
  bool get available => false;

  /// "Continuar" can be pressed (false while waiting for the handoff).
  bool get ready => true;

  /// The ways to pass the work, in the dialog's order (R3).
  List<PathOption> options({
    required String targetName,
    required String fromName,
  }) => [
    PathOption(
      title: 'Resumo do app',
      text: installed
          ? 'Montado pelo app, sem chamar modelo; você edita.'
          : 'Único caminho sem o ai-memory. Montado pelo app, sem chamar '
                'modelo; você edita.',
      path: ContinuePath.summary,
    ),
  ];
}

/// The ai-memory part of the dialog. Without ai-memory it shows nothing and
/// the app summary is the only path (R7).
class HandoffSource extends ConsumerStatefulWidget {
  const HandoffSource({
    super.key,
    required this.origin,
    required this.target,
    required this.selected,
    required this.onChanged,
    this.chosen,
  });

  final Session origin;
  final String target;
  final Handoff? chosen;
  final bool selected;
  final ValueChanged<HandoffSourceState> onChanged;

  @override
  ConsumerState<HandoffSource> createState() => _HandoffSourceState();
}

class _HandoffSourceState extends ConsumerState<HandoffSource> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onChanged(
          const HandoffSourceState(status: HandoffSourceStatus.unavailable),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
