import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart';
import '../../core/codex/codex_agent_mapping.dart';
import '../../core/codex/codex_probe.dart' show CodexModelInfo;
import '../../core/providers/provider_preferences.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/session_style.dart';

/// Configurações → Provedores → Codex: "Modelos equivalentes para agentes"
/// (SPEC-106 R6, mock 2). One row per Claude alias and per effort, with
/// selectors fed by the cached `model/list`. It starts empty: no Codex
/// model name is fixed in the code. The suggestion of P1 waits for the
/// person's confirmation.
class CodexAgentModelsCard extends ConsumerWidget {
  const CodexAgentModelsCard({super.key});

  /// Value of "padrão do Codex" / "modelo do tipo de execução".
  static const none = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final cache = codexModelsCache(s);
    final models = cache?.models ?? const <CodexModelInfo>[];
    final table = CodexAgentTable.fromSettings(s);
    final suggestion = codexSuggestedModels(models);
    final pending =
        suggestion.isNotEmpty &&
        s[codexAgentSuggestionKey] != 'dismissed' &&
        !suggestion.keys.any(table.models.containsKey);
    final sessionModel = s['codex.model.${RunKind.session.name}'];

    Future<void> setModel(String alias, String v) async {
      if (v == none) {
        await notifier.remove(codexAgentModelKey(alias));
      } else {
        await notifier.set(codexAgentModelKey(alias), v);
      }
    }

    Future<void> useSuggestion() async {
      for (final MapEntry(:key, :value) in suggestion.entries) {
        await notifier.set(codexAgentModelKey(key), value);
      }
    }

    final allEfforts = <String>{for (final m in models) ...m.efforts};
    final highestNote = _highestNote(models);
    final ultra = models.any((m) => codexHighestOf(m.efforts) == 'ultra');

    Widget modelRow(String alias) {
      final saved = table.models[alias];
      final stale = saved != null && !models.any((m) => m.id == saved);
      final suggested = pending ? suggestion[alias] : null;
      final value = saved ?? suggested ?? none;
      final note = stale
          ? '$saved saiu do model/list'
          : suggested != null
          ? 'sugerido'
          : saved == null && alias == 'inherit'
          ? 'Sessões: ${sessionModel == null || sessionModel == 'inherit' ? 'padrão do Codex' : sessionModel}'
          : saved == null
          ? 'sem equivalente'
          : '';
      return _Row(
        label: alias,
        note: note,
        noteColor: stale || suggested != null
            ? AppColors.amber
            : AppColors.textMuted,
        child: _Select(
          key: ValueKey('codex-agent-model-$alias'),
          value: value,
          highlight: suggested != null,
          items: [
            (
              none,
              alias == 'inherit'
                  ? 'modelo do tipo de execução'
                  : 'padrão do Codex',
            ),
            for (final m in models) (m.id, m.id),
            if (stale) (saved, saved),
          ],
          onChanged: (v) => setModel(alias, v),
        ),
      );
    }

    Widget effortRow(String level) {
      final value = table.effortFor(level);
      final note = value == codexHighestEffort
          ? (level == 'max' && ultra ? 'ultra gasta mais cota' : highestNote)
          : '';
      return _Row(
        label: level,
        note: note,
        noteColor: level == 'max' && ultra && value == codexHighestEffort
            ? AppColors.amber
            : AppColors.textMuted,
        child: _Select(
          key: ValueKey('codex-agent-effort-$level'),
          value: value,
          items: [
            (codexHighestEffort, 'o maior do modelo'),
            (codexModelDefaultEffort, 'padrão do modelo'),
            for (final e in {...allEfforts, if (!value.startsWith('@')) value})
              if (e != codexModelDefaultEffort) (e, e),
          ],
          onChanged: (v) => notifier.set(codexAgentEffortKey(level), v),
        ),
      );
    }

    final modelsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Head('Alias do agente', 'Modelo do Codex'),
        for (final a in codexAgentModelAliases) modelRow(a),
      ],
    );
    final effortsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Head('Esforço do agente', 'Esforço do Codex'),
        for (final l in codexAgentEffortLevels) effortRow(l),
      ],
    );

    return AgentCard(
      key: const ValueKey('codex-agent-models'),
      title: 'Modelos equivalentes para agentes',
      trailing: Text(
        cache == null
            ? 'model/list ainda não lido'
            : 'model/list · Codex ${cache.version ?? '?'} · '
                  '${models.length} modelos',
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      children: [
        if (pending)
          Container(
            key: const ValueKey('codex-agent-suggestion'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amberTint,
              border: Border.all(color: SessionColors.approvalBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sugestão pela posição no model/list (maior → opus, médio '
                  '→ sonnet, menor → haiku). Nada vale até você confirmar.',
                  style: TextStyle(fontSize: 12, color: AppColors.amberLight),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    AmberButton(
                      key: const ValueKey('codex-agent-use-suggestion'),
                      label: 'Usar sugestão',
                      onTap: useSuggestion,
                    ),
                    SmallButton(
                      key: const ValueKey('codex-agent-one-by-one'),
                      label: 'Escolher um por um',
                      onTap: () =>
                          notifier.set(codexAgentSuggestionKey, 'dismissed'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (cache == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Lista de modelos ainda não lida: atualize em Consumo → Codex. '
              'Até lá, todo agente usa o modelo do tipo de execução.',
              key: ValueKey('codex-agent-no-catalog'),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 700
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: modelsColumn),
                    const SizedBox(width: 20),
                    Expanded(child: effortsColumn),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    modelsColumn,
                    const SizedBox(height: 16),
                    effortsColumn,
                  ],
                ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Os nomes vêm do model/list a cada abertura; o app nunca fixa '
          'modelo do Codex no código. Um esforço que o modelo não oferece cai '
          'no padrão do modelo, com aviso na sessão.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// "sol: ultra · luna: max": one model family per distinct highest
  /// effort.
  static String _highestNote(List<CodexModelInfo> models) {
    final byValue = <String, String>{};
    for (final m in models) {
      final h = codexHighestOf(m.efforts);
      if (h == null) continue;
      byValue.putIfAbsent(h, () => m.id.split('-').last);
    }
    if (byValue.length < 2) return byValue.keys.firstOrNull ?? '';
    return [for (final e in byValue.entries.take(3)) '${e.value}: ${e.key}']
        .join(' · ');
  }
}

class _Head extends StatelessWidget {
  const _Head(this.left, this.right);

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.textMuted,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(left.toUpperCase(), style: style)),
          Expanded(child: Text(right.toUpperCase(), style: style)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.child,
    required this.note,
    required this.noteColor,
  });

  final String label;
  final Widget child;
  final String note;
  final Color noteColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 13,
              color: AppColors.text,
            ),
          ),
        ),
        Expanded(flex: 3, child: child),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: noteColor),
          ),
        ),
      ],
    ),
  );
}

class _Select extends StatelessWidget {
  const _Select({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.highlight = false,
  });

  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  /// A suggestion not confirmed yet (amber border).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final k = key is ValueKey ? (key as ValueKey).value : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('$k-$value-${items.length}'),
      initialValue: items.any((i) => i.$1 == value) ? value : items.first.$1,
      isDense: true,
      isExpanded: true,
      dropdownColor: AppColors.panelSolid,
      style: const TextStyle(
        fontSize: 12,
        fontFamily: AppFonts.mono,
        color: AppColors.text,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: highlight ? SessionColors.approvalBorder : AppColors.border,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      items: [
        for (final (v, l) in items)
          DropdownMenuItem(
            key: ValueKey('$k-item-$v'),
            value: v,
            child: Text(l, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
