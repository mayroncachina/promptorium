import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../board/board_rules.dart';
import '../../board/board_screen.dart' show SpecCardData;
import '../../board/widgets/run_spec_dialog.dart';
import '../spec_auto_planner.dart';

/// Opens the first session when the queue of "Criar projeto" ends (SPEC-037
/// R10). In the shell, not in the Projeto screen: leaving that screen does
/// not stop the queue, and the session must still open.
class FirstRunHost extends ConsumerWidget {
  const FirstRunHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(specAutoPlannerProvider.select((s) => s.firstRunReady.length), (
      _,
      _,
    ) {
      final planner = ref.read(specAutoPlannerProvider.notifier);
      for (final workspaceId
          in ref.read(specAutoPlannerProvider).firstRunReady) {
        final id = planner.takeFirstRun(workspaceId);
        if (id != null) unawaited(_open(context, ref, id));
      }
    });
    return const SizedBox.shrink();
  }

  Future<void> _open(BuildContext context, WidgetRef ref, int specId) async {
    // The refined spec, with the requirements the round added.
    final spec = await ref.read(specsRepoProvider).getById(specId);
    if (spec == null || !context.mounted) return;
    await runSpec(
      context,
      ref,
      SpecCardData(
        spec: spec,
        steps: stepsOf(spec, const []),
        sessions: const [],
        blockers: const [],
      ),
    );
  }
}
