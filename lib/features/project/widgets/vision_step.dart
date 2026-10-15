import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_plan.dart';
import '../project_planner.dart';
import 'project_widgets.dart';

/// Step 2 · Visão: conversation with the planner (left) and the plan it
/// keeps up to date (right).
class VisionStep extends ConsumerWidget {
  const VisionStep({super.key, required this.workspace, required this.data});

  final Workspace workspace;
  final ProjectPlanData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(
      projectPlannerProvider.select((m) => m[workspace.id]?.busy),
    );
    final planner = ref.read(projectPlannerProvider.notifier);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepHeader(
                title: 'Visão do projeto',
                subtitle:
                    'Converse com o planner. O plano à direita é preenchido '
                    'a cada resposta.',
                actions: [InfoTag('planner · somente leitura')],
              ),
              Expanded(
                child: _Conversation(
                  messages: data.messages,
                  busy: busy,
                  onSuggestion: (s) => planner.sendVision(workspace, s),
                ),
              ),
              _Composer(
                enabled: busy == null,
                onSend: (text) => planner.sendVision(workspace, text),
              ),
            ],
          ),
        ),
        SidePanel(
          title: 'Plano do projeto',
          trailing: InfoTag('rascunho'),
          footer: StepNav(
            nextKey: const ValueKey('project-vision-next'),
            nextLabel: 'Próximo: Stack e convenções',
            onNext: data.vision.isReady && busy == null
                ? () async {
                    await planner.goTo(workspace, ProjectStep.stack);
                    if (!data.stack.isReady) {
                      await planner.proposeStack(workspace);
                    }
                  }
                : null,
          ),
          child: _PlanPanel(vision: data.vision),
        ),
      ],
    );
  }
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.messages,
    required this.busy,
    required this.onSuggestion,
  });

  final List<PlanMessage> messages;
  final String? busy;
  final ValueChanged<String> onSuggestion;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_Conversation old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length ||
        old.busy != widget.busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    if (msgs.isEmpty && widget.busy == null) {
      return const StepEmpty(
        title: 'Conte a ideia',
        text:
            'Descreva o que você quer construir e para quem. O planner faz '
            'perguntas e monta o plano: resumo, público, MVP e o que fica de '
            'fora.',
      );
    }
    final lastPlanner = msgs.lastIndexWhere((m) => !m.fromUser && !m.error);
    return ListView(
      key: const ValueKey('project-conversation'),
      controller: _scroll,
      padding: const EdgeInsets.all(20),
      children: [
        for (final (i, m) in msgs.indexed) ...[
          if (m.note != null) _NoteLine(m.note!),
          _Bubble(
            message: m,
            suggestions: i == lastPlanner && widget.busy == null
                ? m.suggestions
                : const [],
            onSuggestion: widget.onSuggestion,
          ),
          const SizedBox(height: 16),
        ],
        if (widget.busy != null)
          Align(
            alignment: Alignment.centerLeft,
            child: PlannerBusy(widget.busy!),
          ),
      ],
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        const Expanded(child: Divider(color: projectLilacBorder)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: projectLilac),
          ),
        ),
        const Expanded(child: Divider(color: projectLilacBorder)),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.suggestions,
    required this.onSuggestion,
  });

  final PlanMessage message;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: SessionColors.selectedBg,
              border: Border.all(color: SessionColors.selectedBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              m.text,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: projectLilacBg,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: AppIcon(
              m.error ? AppIcons.warning : AppIcons.sparkle,
              size: 14,
              color: m.error ? AppColors.red : projectLilac,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  m.text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: m.error ? AppColors.red : AppColors.text,
                  ),
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in suggestions)
                        ChipButton(
                          key: ValueKey('project-suggestion-$s'),
                          label: s,
                          onTap: () => onSuggestion(s),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.enabled, required this.onSend});

  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (!widget.enabled || t.isEmpty) return;
    _text.clear();
    widget.onSend(t);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _send,
            },
            child: TextField(
              key: const ValueKey('project-composer'),
              controller: _text,
              minLines: 2,
              maxLines: 6,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Responda ou descreva mais sobre o projeto…',
                hintStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
          Row(
            children: [
              const Text(
                'Ctrl+Enter envia',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: _text,
                builder: (_, _) => AmberButton(
                  key: const ValueKey('project-send'),
                  label: 'Enviar',
                  height: 28,
                  onTap: widget.enabled && _text.text.trim().isNotEmpty
                      ? _send
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({required this.vision});

  final VisionPlan vision;

  @override
  Widget build(BuildContext context) {
    final v = vision;
    if (v.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Vazio por enquanto. O planner preenche esta coluna conforme a '
          'conversa avança.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    const body = TextStyle(fontSize: 13, color: AppColors.text, height: 1.45);
    Widget list(List<String> items, {Color dot = AppColors.teal}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Dot(dot, size: 6),
                ),
                Expanded(child: Text(i, style: body)),
              ],
            ),
          ),
      ],
    );
    return ListView(
      key: const ValueKey('project-plan-panel'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (v.name.isNotEmpty) ...[
          const Text(
            'Nome',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          Text(
            v.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (v.summary.isNotEmpty) ...[
          const PlanHeading('Resumo'),
          Text(v.summary, style: body),
          const SizedBox(height: 16),
        ],
        if (v.audience.isNotEmpty) ...[
          const PlanHeading('Público'),
          Text(v.audience, style: body),
          const SizedBox(height: 16),
        ],
        if (v.mvp.isNotEmpty) ...[
          const PlanHeading('MVP'),
          list(v.mvp),
          const SizedBox(height: 10),
        ],
        if (v.outOfScope.isNotEmpty) ...[
          const PlanHeading('Fora do escopo'),
          list(v.outOfScope, dot: AppColors.textMuted),
          const SizedBox(height: 10),
        ],
        if (v.openQuestions.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SessionColors.approvalBg,
              border: Border.all(color: SessionColors.approvalBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlanHeading('Em aberto · ${v.openQuestions.length}'),
                list(v.openQuestions, dot: AppColors.amber),
              ],
            ),
          ),
      ],
    );
  }
}
