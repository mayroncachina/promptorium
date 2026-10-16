import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../sessions/agent_names.dart';
import '../../sessions/widgets/session_style.dart';
import '../spec_file.dart';

/// Subagents of the open spec: list + "adicionar" row. Changes go to the
/// frontmatter of the text in the editor ([onChange]); the user saves as
/// always. [locked] (spec already started) only shows them.
class SubagentsEditor extends ConsumerStatefulWidget {
  const SubagentsEditor({
    super.key,
    this.mainAgent,
    required this.workspacePath,
    required this.subagents,
    this.requirements = const [],
    this.locked = false,
    this.allowStep = true,
    this.initiallyOpen = false,
    required this.onChange,
  });

  /// Agent of the sessions (warns when it cannot call subagents).
  final String? mainAgent;
  final String workspacePath;
  final List<SpecSubagent> subagents;
  final List<SpecRequirement> requirements;
  final bool locked;

  /// Offers "ao terminar uma etapa" (only a spec has steps).
  final bool allowStep;
  final bool initiallyOpen;
  final ValueChanged<List<SpecSubagent>> onChange;

  @override
  ConsumerState<SubagentsEditor> createState() => _SubagentsEditorState();
}

class _SubagentsEditorState extends ConsumerState<SubagentsEditor> {
  String? _agent;
  SubagentWhen _when = SubagentWhen.specEnd;
  String? _step;
  final _instruction = TextEditingController();

  /// Collapsed by default: the steps list keeps the room.
  late bool _open = widget.initiallyOpen;

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  void _add() {
    final agent = _agent;
    if (agent == null) return;
    final step = _when == SubagentWhen.atStep
        ? (_step ?? widget.requirements.firstOrNull?.id)
        : null;
    if (_when == SubagentWhen.atStep && step == null) return;
    final text = _instruction.text.trim();
    widget.onChange([
      ...widget.subagents,
      SpecSubagent(
        agent: agent,
        when: _when,
        step: step,
        instruction: text.isEmpty ? null : text,
      ),
    ]);
    _instruction.clear();
  }

  @override
  Widget build(BuildContext context) {
    final agents =
        ref.watch(agentListProvider(widget.workspacePath)).value ??
        const <AgentRef>[];
    final byName = {for (final a in agents) a.name: a};
    final main = byName[widget.mainAgent];
    final noTask = main != null && !main.canUseSubagents;
    return Column(
      key: const ValueKey('subagents-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('subagents-toggle'),
          onTap: () => setState(() => _open = !_open),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'SUBAGENTES${widget.subagents.isEmpty ? '' : ' (${widget.subagents.length})'}',
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Icon(
                _open ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 6),
          if (widget.subagents.isEmpty)
            const Text(
              'Nenhum. Subagentes são chamados pelo agente da sessão em um '
              'momento da execução (ex.: revisor no fim da spec).',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          for (var i = 0; i < widget.subagents.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.subagents[i].summary +
                          (byName.containsKey(widget.subagents[i].agent)
                              ? ''
                              : ' (agente não encontrado)'),
                      key: ValueKey('subagent-item-$i'),
                      style: TextStyle(
                        fontSize: 12,
                        color: byName.containsKey(widget.subagents[i].agent)
                            ? AppColors.text
                            : AppColors.red,
                      ),
                    ),
                  ),
                  if (!widget.locked)
                    IconButton(
                      key: ValueKey('subagent-remove-$i'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      tooltip: 'Remover',
                      onPressed: () => widget.onChange([
                        for (var j = 0; j < widget.subagents.length; j++)
                          if (j != i) widget.subagents[j],
                      ]),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
          if (noTask) ...[
            const SizedBox(height: 4),
            Text(
              'O agente da spec (${main.name}) não tem a ferramenta '
              'Task/Agent nas "tools": ele não vai conseguir chamar subagentes.',
              key: const ValueKey('subagents-no-task'),
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ],
          if (!widget.locked) ...[
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: const ValueKey('subagent-agent'),
              isExpanded: true,
              isDense: true,
              hint: const Text('Subagente', style: TextStyle(fontSize: 12)),
              value: byName.containsKey(_agent) ? _agent : null,
              items: [
                for (final a in agents)
                  DropdownMenuItem(
                    value: a.name,
                    child: Text(a.name, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (v) => setState(() => _agent = v),
            ),
            DropdownButton<SubagentWhen>(
              key: const ValueKey('subagent-when'),
              isExpanded: true,
              isDense: true,
              value: _when,
              items: [
                for (final w in SubagentWhen.values)
                  if (widget.allowStep || w != SubagentWhen.atStep)
                    DropdownMenuItem(
                      value: w,
                      child: Text(
                        w.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
              ],
              onChanged: (v) => setState(() => _when = v ?? _when),
            ),
            if (_when == SubagentWhen.atStep)
              DropdownButton<String>(
                key: const ValueKey('subagent-step'),
                isExpanded: true,
                isDense: true,
                value: widget.requirements.any((r) => r.id == _step)
                    ? _step
                    : widget.requirements.firstOrNull?.id,
                items: [
                  for (final r in widget.requirements)
                    DropdownMenuItem(
                      value: r.id,
                      child: Text(
                        '${r.id} · ${r.text}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _step = v),
              ),
            TextField(
              key: const ValueKey('subagent-instruction'),
              controller: _instruction,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Instrução (opcional)',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: SmallButton(
                key: const ValueKey('subagent-add'),
                label: 'Adicionar subagente',
                onTap: _agent == null ? null : _add,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
