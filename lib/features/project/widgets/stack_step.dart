import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_plan.dart';
import '../project_planner.dart';
import 'project_widgets.dart';

/// Step 3 · Stack e convenções: the planner's choices with alternatives
/// (left) and the CLAUDE.md that every session reads (right, editable).
class StackStep extends ConsumerWidget {
  const StackStep({super.key, required this.workspace, required this.data});

  final Workspace workspace;
  final ProjectPlanData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(
      projectPlannerProvider.select((m) => m[workspace.id]),
    );
    final busy = activity?.busy;
    final planner = ref.read(projectPlannerProvider.notifier);
    final stack = data.stack;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepHeader(
                title: 'Stack e convenções',
                subtitle:
                    'Proposta do planner a partir da visão. Clique numa '
                    'alternativa para trocar.',
                actions: [
                  PlannerButton(
                    key: const ValueKey('project-stack-again'),
                    label: stack.isReady
                        ? 'Pedir outra proposta'
                        : 'Propor stack',
                    onTap: busy == null
                        ? () => planner.proposeStack(workspace)
                        : null,
                  ),
                ],
              ),
              if (busy != null || activity?.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: busy != null
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: PlannerBusy(busy),
                        )
                      : NoticeBox.error(
                          text: activity!.error!,
                          action: SmallButton(
                            label: 'Fechar',
                            onTap: () => planner.clearError(workspace.id),
                          ),
                        ),
                ),
              Expanded(
                child: stack.isReady
                    ? ListView(
                        key: const ValueKey('project-stack-list'),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        children: [
                          for (final d in stack.decisions)
                            _DecisionRow(
                              decision: d,
                              onChoose: busy == null
                                  ? (o) => planner.chooseStack(
                                      workspace,
                                      d.area,
                                      o,
                                    )
                                  : null,
                            ),
                        ],
                      )
                    : StepEmpty(
                        title: busy == null ? 'Sem proposta ainda' : '',
                        text: busy == null
                            ? 'O planner sugere as tecnologias e escreve o '
                                  'CLAUDE.md do projeto a partir da visão.'
                            : '',
                      ),
              ),
            ],
          ),
        ),
        SidePanel(
          title: 'CLAUDE.md',
          width: 380,
          trailing: const InfoTag('editável'),
          footer: StepNav(
            onBack: () => planner.goTo(workspace, ProjectStep.vision),
            nextKey: const ValueKey('project-stack-next'),
            nextLabel: 'Próximo: Roadmap',
            onNext: stack.isReady && busy == null
                ? () async {
                    await planner.goTo(workspace, ProjectStep.roadmap);
                    if (!data.roadmap.isReady) {
                      await planner.planRoadmap(workspace);
                    }
                  }
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stack.claudeMdStale)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: NoticeBox.warning(
                    text:
                        'Uma escolha mudou depois que o CLAUDE.md foi '
                        'escrito.',
                    action: SmallButton(
                      key: const ValueKey('project-claudemd-refresh'),
                      label: 'Atualizar',
                      onTap: busy == null
                          ? () => planner.proposeStack(
                              workspace,
                              keepChoices: true,
                            )
                          : null,
                    ),
                  ),
                ),
              Expanded(
                child: _ClaudeMdEditor(
                  text: stack.claudeMd,
                  enabled: busy == null,
                  onChanged: (t) => planner.editClaudeMd(workspace, t),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({required this.decision, required this.onChoose});

  final StackDecision decision;
  final ValueChanged<String>? onChoose;

  @override
  Widget build(BuildContext context) {
    final d = decision;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                d.area.toUpperCase(),
                style: sectionTitleStyle.copyWith(fontSize: 11),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      d.choice,
                      key: ValueKey('project-stack-choice-${d.area}'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: d.isUndecided
                            ? AppColors.textSecondary
                            : AppColors.text,
                      ),
                    ),
                    if (d.isUndecided)
                      const _Tag('decidir', AppColors.amber)
                    else if (d.pinned)
                      const _Tag('sua escolha', AppColors.teal),
                  ],
                ),
                if (d.why.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    d.why,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (d.alternatives.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in d.alternatives)
                  ChipButton(
                    key: ValueKey('project-stack-alt-${d.area}-$a'),
                    label: a,
                    height: 26,
                    onTap: onChoose == null ? null : () => onChoose!(a),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}

/// Monospace editor of the CLAUDE.md; saves 500 ms after the last change
/// and follows new text coming from the planner.
class _ClaudeMdEditor extends StatefulWidget {
  const _ClaudeMdEditor({
    required this.text,
    required this.enabled,
    required this.onChanged,
  });

  final String text;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_ClaudeMdEditor> createState() => _ClaudeMdEditorState();
}

class _ClaudeMdEditorState extends State<_ClaudeMdEditor> {
  late final _controller = TextEditingController(text: widget.text);
  Timer? _debounce;

  /// Last text sent to [_ClaudeMdEditor.onChanged] (echoes are ignored).
  late String _saved = widget.text;

  @override
  void didUpdateWidget(_ClaudeMdEditor old) {
    super.didUpdateWidget(old);
    if (widget.text != _saved && widget.text != _controller.text) {
      _debounce?.cancel();
      _saved = widget.text;
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    final pending = _debounce?.isActive ?? false;
    _debounce?.cancel();
    if (pending) widget.onChanged(_controller.text);
    _controller.dispose();
    super.dispose();
  }

  void _changed(String t) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _saved = t;
      widget.onChanged(t);
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    decoration: BoxDecoration(
      color: AppColors.background,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: TextField(
      key: const ValueKey('project-claudemd'),
      controller: _controller,
      enabled: widget.enabled,
      onChanged: _changed,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        height: 1.6,
        color: AppColors.text,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(12),
        hintText: 'O CLAUDE.md aparece aqui quando o planner propõe a stack.',
        hintStyle: TextStyle(color: AppColors.textMuted),
      ),
    ),
  );
}
