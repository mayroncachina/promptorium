import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/instructions_files.dart';
import '../../core/providers/structured_run.dart' show PlannerException;
import '../../core/providers/workspace_assets.dart';
import '../../core/text/line_diff.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/app_toast.dart';
import '../sessions/widgets/session_style.dart';
import 'unify_service.dart';

/// "Unificar instruções" (SPEC-113 R4, R5; mock `3-unificar.png`): the
/// differences on the left, the two files as they will be on the right;
/// nothing is written until "Unificar 2 arquivos".

/// Opens the Unificar dialog for the project at [workspacePath] (R3, R4)
/// and, once confirmed, writes both files together (R5) and offers
/// "Desfazer" in the snack bar. Does nothing (and says so) when there is
/// nothing to unify.
Future<void> showUnifyDialog(
  BuildContext context,
  WidgetRef ref, {
  required String workspacePath,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final claude = await readInstructionsSnapshot('$workspacePath/$claudeMdName');
  final agents = await readInstructionsSnapshot('$workspacePath/$agentsMdName');
  if (!context.mounted) return;
  void toast(String text, {Key? key, SnackBarAction? action}) {
    messenger
      ?..hideCurrentSnackBar()
      ..showAppToast(
        SnackBar(
          key: key,
          duration: const Duration(seconds: 10),
          persist: false,
          content: Text(text),
          action: action,
        ),
      );
  }

  if (!canUnifyTexts(claude: claude.text, agents: agents.text)) {
    toast(
      claude.text == null
          ? 'O projeto não tem CLAUDE.md para unificar.'
          : 'As instruções já estão unificadas.',
    );
    return;
  }
  final result = await showAppDialog<InstructionsWriteResult>(
    context: context,
    builder: (_) => UnifyDialog(
      workspacePath: workspacePath,
      claude: claude,
      agents: agents,
    ),
  );
  if (result == null) return;
  container.invalidate(instructionsInventoryProvider(workspacePath));
  toast(
    'Instruções unificadas: o AGENTS.md é a fonte e o CLAUDE.md importa.',
    key: const ValueKey('unify-toast'),
    action: SnackBarAction(
      label: 'Desfazer',
      textColor: AppColors.amber,
      onPressed: () async {
        try {
          await container.read(unifyUndoProvider)(result);
          container.invalidate(instructionsInventoryProvider(workspacePath));
          toast('Unificação desfeita: os dois arquivos voltaram.');
        } on InstructionsException catch (e) {
          toast(e.message);
        }
      },
    ),
  );
}

/// Label of a destination (R4).
String unifyTargetLabel(UnifyTarget t) => switch (t) {
  UnifyTarget.agents => 'Vai para o AGENTS.md',
  UnifyTarget.claudeOnly => 'Fica no CLAUDE.md',
  UnifyTarget.claudeVersion => 'Versão do CLAUDE.md',
  UnifyTarget.agentsVersion => 'Versão do AGENTS.md',
  UnifyTarget.custom => 'Outro texto',
};

/// The Unificar dialog (R4): pops with the [InstructionsWriteResult] of the
/// write, or null when cancelled.
class UnifyDialog extends ConsumerStatefulWidget {
  const UnifyDialog({
    super.key,
    required this.workspacePath,
    required this.claude,
    required this.agents,
  });

  final String workspacePath;
  final InstructionsSnapshot claude;
  final InstructionsSnapshot agents;

  @override
  ConsumerState<UnifyDialog> createState() => _UnifyDialogState();
}

class _UnifyDialogState extends ConsumerState<UnifyDialog> {
  late final UnifyPlan _plan = buildUnifyPlan(
    claude: widget.claude.text,
    agents: widget.agents.text,
  );
  late final Map<String, UnifyTarget> _choices = _plan.defaults;
  final _custom = <String, TextEditingController>{};
  Map<String, UnifySuggestion> _suggestions = const {};
  bool _asking = false;
  String? _aiError;
  bool _writing = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _custom.values) {
      c.dispose();
    }
    super.dispose();
  }

  UnifyResult get _result => composeUnify(
    _plan,
    choices: _choices,
    custom: {for (final e in _custom.entries) e.key: e.value.text},
  );

  void _choose(UnifyDiff d, UnifyTarget t) => setState(() {
    _choices[d.id] = t;
    if (t == UnifyTarget.custom) {
      _custom.putIfAbsent(
        d.id,
        () => TextEditingController(text: d.claudeText ?? d.agentsText ?? ''),
      );
    }
  });

  Future<void> _ask() async {
    setState(() {
      _asking = true;
      _aiError = null;
    });
    try {
      final s = await ref.read(unifySuggesterProvider)(
        _plan,
        cwd: widget.workspacePath,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = s;
        if (s.isEmpty) _aiError = 'A IA não sugeriu nada.';
      });
    } on PlannerException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } catch (e) {
      if (mounted) setState(() => _aiError = '$e');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _confirm() async {
    final r = _result;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      // AGENTS.md first: if the CLAUDE.md fails, the AGENTS.md goes back (R5).
      final written = await ref.read(unifyWriterProvider)([
        InstructionsWrite(widget.agents, r.agents),
        InstructionsWrite(widget.claude, r.claude),
      ]);
      if (mounted) Navigator.of(context).pop(written);
    } on InstructionsConflict catch (e) {
      if (mounted) {
        setState(() {
          _writing = false;
          _error = '${e.message} Feche e abra o Unificar de novo.';
        });
      }
    } on InstructionsException catch (e) {
      if (mounted) {
        setState(() {
          _writing = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final name = widget.workspacePath.split('/').where((s) => s.isNotEmpty);
    return Dialog(
      key: const ValueKey('unify-dialog'),
      backgroundColor: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Unificar instruções',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (name.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: _Chip(name.last, color: AppColors.teal),
                    ),
                  ],
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Nada é gravado até você confirmar',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _plan.agentsGenerated
                    ? 'O AGENTS.md atual foi gerado pelo app e é só uma cópia: '
                          'o texto vem do CLAUDE.md. O texto comum vai para o '
                          'AGENTS.md; o CLAUDE.md fica com o import e o que é só '
                          'do Claude Code.'
                    : 'O texto comum vai para o AGENTS.md. O CLAUDE.md fica '
                          'com o import e o que é só do Claude Code.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 330, child: _diffColumn()),
                    const SizedBox(width: 16),
                    Expanded(child: _resultColumn(result)),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const ValueKey('unify-error'),
                  style: const TextStyle(fontSize: 12, color: AppColors.red),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Os dois arquivos mudam juntos, sem commit. O app guarda '
                      'uma cópia para desfazer.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  SmallButton(
                    key: const ValueKey('unify-cancel'),
                    label: 'Cancelar',
                    height: 34,
                    onTap: _writing ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  SmallButton(
                    key: const ValueKey('unify-confirm'),
                    label: _writing ? 'Gravando…' : 'Unificar 2 arquivos',
                    height: 34,
                    color: AppColors.onAmber,
                    border: AppColors.amber,
                    background: AppColors.amber,
                    fontWeight: FontWeight.w600,
                    onTap: _writing ? null : _confirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diffColumn() {
    final diffs = _plan.diffs;
    final pending = {
      for (final e in _suggestions.entries)
        if (_choices[e.key] != e.value.target) e.key: e.value,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('Diferenças · ${diffs.length}'),
        const SizedBox(height: 8),
        Expanded(
          child: diffs.isEmpty
              ? const Text(
                  'Os dois arquivos dizem o mesmo. Unificar só troca o '
                  'CLAUDE.md pelo import.',
                  key: ValueKey('unify-no-diffs'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                )
              : ListView.separated(
                  itemCount: diffs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (_, i) => _diffCard(diffs[i]),
                ),
        ),
        const SizedBox(height: 10),
        if (_aiError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _aiError!,
              key: const ValueKey('unify-ai-error'),
              style: const TextStyle(fontSize: 11, color: AppColors.red),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SmallButton(
              key: const ValueKey('unify-ai'),
              label: _asking ? 'A IA está lendo…' : 'Pedir ajuda da IA',
              icon: Icons.auto_awesome_outlined,
              color: AppColors.lilac,
              border: AppColors.lilac.withValues(alpha: 0.45),
              background: AppColors.lilac.withValues(alpha: 0.08),
              onTap: _asking || diffs.isEmpty || _writing ? null : _ask,
            ),
            if (pending.length > 1)
              SmallButton(
                key: const ValueKey('unify-use-all'),
                label: 'Usar as ${pending.length} sugestões',
                onTap: () => setState(() {
                  for (final e in pending.entries) {
                    _choices[e.key] = e.value.target;
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _diffCard(UnifyDiff d) {
    final target = _choices[d.id]!;
    final suggestion = _suggestions[d.id];
    final changed = d.kind == UnifyDiffKind.changed;
    final (String chip, Color tone) = switch (d.kind) {
      UnifyDiffKind.changed => ('diferente', AppColors.amber),
      _ when d.claudeSpecific => ('só do Claude', AppColors.lilac),
      UnifyDiffKind.onlyClaude => (
        d.wholeSection ? 'seção só no CLAUDE.md' : 'só no CLAUDE.md',
        AppColors.teal,
      ),
      UnifyDiffKind.onlyAgents => (
        d.wholeSection ? 'seção só no AGENTS.md' : 'só no AGENTS.md',
        AppColors.blue,
      ),
    };
    return Container(
      key: ValueKey('unify-diff-${d.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: changed ? AppColors.amberTint : AppColors.surfaceRaisedSolid,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: changed ? SessionColors.approvalBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _Chip(chip, color: tone),
            ],
          ),
          if (d.section.isNotEmpty && !d.wholeSection)
            Text(
              'em ${d.section}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          const SizedBox(height: 8),
          if (changed) ...[
            _Option(
              key: ValueKey('unify-target-${d.id}-claudeVersion'),
              selected: target == UnifyTarget.claudeVersion,
              label: claudeMdName,
              text: d.claudeText!,
              onTap: () => _choose(d, UnifyTarget.claudeVersion),
            ),
            const SizedBox(height: 6),
            _Option(
              key: ValueKey('unify-target-${d.id}-agentsVersion'),
              selected: target == UnifyTarget.agentsVersion,
              label: agentsMdName,
              text: d.agentsText!,
              onTap: () => _choose(d, UnifyTarget.agentsVersion),
            ),
            const SizedBox(height: 6),
            _Option(
              key: ValueKey('unify-target-${d.id}-custom'),
              selected: target == UnifyTarget.custom,
              label: 'Escrever outro texto',
              onTap: () => _choose(d, UnifyTarget.custom),
            ),
            if (target == UnifyTarget.custom) ...[
              const SizedBox(height: 6),
              TextField(
                key: ValueKey('unify-custom-${d.id}'),
                controller: _custom[d.id],
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.text,
                ),
                decoration: const InputDecoration(isDense: true),
              ),
            ],
          ] else ...[
            Text(
              d.claudeText ?? d.agentsText ?? '',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in d.targets)
                  _Pill(
                    key: ValueKey('unify-target-${d.id}-${t.name}'),
                    label: unifyTargetLabel(t),
                    selected: target == t,
                    onTap: () => _choose(d, t),
                  ),
              ],
            ),
          ],
          if (suggestion != null) ...[
            const SizedBox(height: 8),
            Row(
              key: ValueKey('unify-suggestion-${d.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 13,
                  color: AppColors.lilac,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'IA sugere: ${unifyTargetLabel(suggestion.target)}'
                    '${suggestion.reason.isEmpty ? '' : ' · ${suggestion.reason}'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.lilac,
                    ),
                  ),
                ),
                if (target != suggestion.target)
                  SmallButton(
                    key: ValueKey('unify-use-${d.id}'),
                    label: 'Usar',
                    height: 24,
                    fontSize: 11,
                    onTap: () => _choose(d, suggestion.target),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultColumn(UnifyResult result) {
    final before = widget.agents.text;
    final agentsLines = before == null
        ? [for (final l in _lines(result.agents)) (op: DiffOp.add, text: l)]
        : lineDiff(_trimEnd(before), _trimEnd(result.agents));
    final adds = agentsLines.where((l) => l.op == DiffOp.add).length;
    final dels = agentsLines.where((l) => l.op == DiffOp.del).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _FileLabel(agentsMdName),
            const SizedBox(width: 8),
            const _Chip('fonte', color: AppColors.amber),
            const Spacer(),
            Text(
              '+$adds',
              style: const TextStyle(fontSize: 11, color: AppColors.teal),
            ),
            const SizedBox(width: 6),
            Text(
              '−$dels',
              style: const TextStyle(fontSize: 11, color: AppColors.red),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          flex: 3,
          child: _Preview(
            key: const ValueKey('unify-agents-preview'),
            lines: agentsLines,
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            _FileLabel(claudeMdName),
            SizedBox(width: 8),
            _Chip('importa', color: AppColors.lilac),
            Spacer(),
            Text(
              'o texto movido sai daqui',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          flex: 2,
          child: _Preview(
            key: const ValueKey('unify-claude-preview'),
            lines: [
              for (final l in _lines(result.claude)) (op: DiffOp.same, text: l),
            ],
            importLine: true,
          ),
        ),
      ],
    );
  }
}

String _trimEnd(String s) =>
    s.endsWith('\n') ? s.substring(0, s.length - 1) : s;

List<String> _lines(String s) => _trimEnd(s).split('\n');

class _Preview extends StatelessWidget {
  const _Preview({super.key, required this.lines, this.importLine = false});

  final List<DiffLine> lines;

  /// Marks the first line (the `@AGENTS.md` of the CLAUDE.md).
  final bool importLine;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SessionColors.terminalPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final l = lines[i];
          final isImport = importLine && i == 0;
          final (Color? bg, String prefix) = switch (l.op) {
            DiffOp.add => (SessionColors.addBg, '+ '),
            DiffOp.del => (SessionColors.delBg, '- '),
            DiffOp.same => (
              isImport ? AppColors.lilac.withValues(alpha: 0.10) : null,
              '',
            ),
          };
          return Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              l.text.isEmpty ? ' ' : l.text,
              semanticsLabel: '$prefix${l.text}',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                height: 1.45,
                color: switch (l.op) {
                  DiffOp.add => AppColors.teal,
                  DiffOp.del => AppColors.red,
                  DiffOp.same => isImport ? AppColors.lilac : AppColors.text,
                },
                decoration: l.op == DiffOp.del
                    ? TextDecoration.lineThrough
                    : null,
                decorationColor: AppColors.red.withValues(alpha: 0.6),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.text,
  });

  final bool selected;
  final String label;
  final String? text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.panelSolid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.amber : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: selected ? AppColors.amber : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: text == null ? 12 : 11,
                        color: text == null
                            ? AppColors.text
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (text != null)
                      Text(
                        text!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.text,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.amberTint : AppColors.panelSolid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.amber : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppColors.amberLight : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10.5, color: color),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.textSecondary,
    ),
  );
}

class _FileLabel extends StatelessWidget {
  const _FileLabel(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(
    name,
    style: const TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
  );
}
