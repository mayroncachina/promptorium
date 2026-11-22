import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/memory/ai_memory_state.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_memory.dart';
import 'ai_memory_view.dart';

/// `app_settings` key: the Memória tab opens on the ai-memory section
/// (SPEC-098 R8).
const aiMemoryPanelOpenKey = 'aiMemory.panelOpen';

/// Projeto → Memória (F8): the lines of `.promptorium/memoria.md` with
/// origin and date; add, remove and clear old ones. With ai-memory
/// installed, a selector "Fatos do projeto · ai-memory" on top (SPEC-098
/// P1, R8); without it the tab is exactly as before (R2).
class ProjectMemoryView extends ConsumerStatefulWidget {
  const ProjectMemoryView({super.key, required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<ProjectMemoryView> createState() => _ProjectMemoryViewState();
}

class _ProjectMemoryViewState extends ConsumerState<ProjectMemoryView> {
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  String get _path => widget.workspace.path;

  Future<void> _save(ProjectMemory m) async {
    await ProjectMemory.save(_path, m);
    ref.invalidate(projectMemoryProvider(_path));
  }

  Future<void> _add(ProjectMemory m) async {
    final text = _new.text.trim();
    if (text.isEmpty) return;
    _new.clear();
    await _save(m.add(MemoryEntry(text: text, date: DateTime.now())));
  }

  @override
  Widget build(BuildContext context) {
    final installed =
        ref.watch(aiMemoryDetectionProvider).value?.installed ?? false;
    final facts = _facts(context);
    if (!installed) return facts;
    final settings = ref.watch(appSettingsProvider);
    final onAiMemory = settings[aiMemoryPanelOpenKey] == '1';
    void pick(bool ai) => ref
        .read(appSettingsProvider.notifier)
        .set(aiMemoryPanelOpenKey, ai ? '1' : '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _MemorySelector(aiMemory: onAiMemory, onPick: pick),
          ),
        ),
        Expanded(
          child: onAiMemory
              ? SingleChildScrollView(
                  key: const ValueKey('ai-memory-section'),
                  padding: const EdgeInsets.all(24),
                  child: AiMemoryPanel(workspace: widget.workspace),
                )
              : facts,
        ),
      ],
    );
  }

  Widget _facts(BuildContext context) {
    final m =
        ref.watch(projectMemoryProvider(_path)).value ??
        const ProjectMemory([]);
    String day(DateTime? d) => d == null
        ? ''
        : ' · ${d.day.toString().padLeft(2, '0')}/'
              '${d.month.toString().padLeft(2, '0')}';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Memória do projeto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Fica em ${ProjectMemory.filePath} (faça commit). Vai no '
              'prompt de cada etapa, do revisor automático e do Planejar. '
              'As sessões acrescentam linhas com APRENDIZADO: e a '
              'verificação anota quanto os comandos demoram. Máximo de '
              '${ProjectMemory.maxEntries} linhas.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('memory-new'),
                    controller: _new,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText:
                          'ex.: os testes de integração precisam do '
                          'docker rodando',
                    ),
                    onSubmitted: (_) => _add(m),
                  ),
                ),
                const SizedBox(width: 8),
                SmallButton(
                  key: const ValueKey('memory-add'),
                  label: 'Adicionar',
                  onTap: () => _add(m),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (m.isEmpty)
              const Text(
                'Nada anotado ainda.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            for (final (i, e) in m.entries.indexed)
              Container(
                key: ValueKey('memory-entry-$i'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.text, style: const TextStyle(fontSize: 13)),
                          Text(
                            '${e.origin}${day(e.date)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('memory-remove-$i'),
                      tooltip: 'Excluir',
                      iconSize: 16,
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => _save(m.remove(e)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SmallButton(
                key: const ValueKey('memory-clean'),
                label: 'Limpar entradas com mais de 30 dias',
                onTap: m.isEmpty
                    ? null
                    : () => _save(m.withoutOlderThan(const Duration(days: 30))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Fatos do projeto | ai-memory" (mock 1).
class _MemorySelector extends StatelessWidget {
  const _MemorySelector({required this.aiMemory, required this.onPick});

  final bool aiMemory;
  final void Function(bool aiMemory) onPick;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool on, bool value) => InkWell(
      key: ValueKey('memory-selector-${value ? 'ai-memory' : 'facts'}'),
      borderRadius: BorderRadius.circular(5),
      onTap: () => onPick(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.amberTint : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? AppColors.amber : AppColors.textSecondary,
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option('Fatos do projeto', !aiMemory, false),
          option('ai-memory', aiMemory, true),
        ],
      ),
    );
  }
}
