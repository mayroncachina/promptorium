import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../sessions/widgets/session_style.dart';
import '../prompt_actions.dart';
import '../spec_batch.dart';
import '../spec_from_answer.dart';
import '../split_specs.dart';
import 'answer_spec_bar.dart';
import 'spec_batch_dialog.dart';

/// "Dividir em specs" (SPEC-068 R2): asks Claude to split [transcript] into
/// specs, with waiting rows and "Cancelar", then opens the review list (two
/// or more), the "Salvar spec" of today (one) or says there was none.
/// Returns the specs created.
Future<List<Spec>> splitIntoSpecs(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
  List<TranscriptEntry> transcript,
) async {
  final ws = await ref.read(workspacesRepoProvider).getById(c.workspaceId);
  if (ws == null || !context.mounted) return const [];
  final specs = await ref.read(specsRepoProvider).watchByWorkspace(ws.id).first;
  if (!context.mounted) return const [];
  final prompt = splitSpecsPrompt(
    transcript,
    existing: [for (final s in specs) '${s.code} (${s.title})'],
  );
  final found = await showAppDialog<List<AnswerSpec>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SplitSpecsDialog(workspace: ws, prompt: prompt),
  );
  if (found == null || found.isEmpty || !context.mounted) return const [];
  if (found.length == 1) {
    // Nobody else watches the target of this spec: keep it alive.
    final keep = ref.listenManual(
      answerSpecTargetProvider((c, found.single.id)),
      (_, _) {},
    );
    try {
      await showAnswerSpecPreview(context, ref, c, found.single);
    } finally {
      keep.close();
    }
    return const [];
  }
  return showSpecBatch(context, ref, c, [
    for (var i = 0; i < found.length; i++) SpecBatchItem.of(i, found[i]),
  ], answer: splitAnswerIndex);
}

/// The waiting card: Claude reads the conversation; nothing is created
/// before the review. Pops with the specs found (one or more).
class SplitSpecsDialog extends ConsumerStatefulWidget {
  const SplitSpecsDialog({
    super.key,
    required this.workspace,
    required this.prompt,
  });

  final Workspace workspace;
  final String prompt;

  @override
  ConsumerState<SplitSpecsDialog> createState() => _SplitSpecsDialogState();
}

class _SplitSpecsDialogState extends ConsumerState<SplitSpecsDialog> {
  Completer<void> _cancel = Completer<void>();
  bool _running = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    if (!_cancel.isCompleted) _cancel.complete();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    final cancel = _cancel = Completer<void>();
    try {
      final text = await ref.read(splitSpecsRunnerProvider)(
        widget.workspace,
        widget.prompt,
        cancelled: cancel.future,
      );
      if (!mounted || cancel.isCompleted) return;
      final specs = detectAnswerSpecs(text);
      if (specs.isEmpty) {
        setState(() {
          _running = false;
          _error = 'O Claude não devolveu nenhuma spec.';
        });
        return;
      }
      Navigator.pop(context, specs);
    } catch (e) {
      if (!mounted || cancel.isCompleted) return;
      setState(() {
        _running = false;
        _error = 'Não deu para dividir: $e';
      });
    }
  }

  void _close() {
    if (!_cancel.isCompleted) _cancel.complete();
    Navigator.pop(context);
  }

  Widget _skeleton(int i) => Container(
    height: 50,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaisedSolid,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.borderHover),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: const [0.7, 0.55, 0.6][i % 3],
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.borderHover,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: const [0.4, 0.25, 0.3][i % 3],
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Material(
          key: const ValueKey('split-specs-dialog'),
          color: AppColors.panelSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderHover),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.call_split,
                          size: 18,
                          color: AppColors.amber,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: const Text(
                                'Dividir em specs',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                error ??
                                    'O Claude está lendo a conversa e '
                                        'separando as specs…',
                                key: const ValueKey('split-specs-status'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: error == null
                                      ? AppColors.textSecondary
                                      : AppColors.amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_running)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [for (var i = 0; i < 3; i++) _skeleton(i)],
                    ),
                  ),
                if (_running) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Nada é criado antes de você revisar.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (!_running) ...[
                        SmallButton(
                          key: const ValueKey('split-specs-retry'),
                          label: 'Tentar de novo',
                          height: 34,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onAmber,
                          border: AppColors.amber,
                          background: AppColors.amber,
                          onTap: _run,
                        ),
                        const SizedBox(width: 8),
                      ],
                      SmallButton(
                        key: const ValueKey('split-specs-cancel'),
                        label: _running ? 'Cancelar' : 'Fechar',
                        height: 34,
                        background: Colors.transparent,
                        onTap: _close,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
