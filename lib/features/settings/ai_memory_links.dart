import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/memory/ai_memory_state.dart';
import '../../core/memory/ai_memory_wiring.dart';
import '../../core/providers/agent_registry.dart' show providerFlowsProvider;
import '../../ui/providers/provider_logos.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../sessions/widgets/session_style.dart';
import 'ai_memory_view.dart';

/// Color of a hook/MCP state pill.
Color aiMemoryLinkColor(AiMemoryLink l) => switch (l) {
  AiMemoryLink.on => AppColors.teal,
  AiMemoryLink.awaitingTrust || AiMemoryLink.outdated => AppColors.amber,
  AiMemoryLink.missing => AppColors.textSecondary,
  AiMemoryLink.unknown => AppColors.textMuted,
};

/// Configurações → Memória: one block per agent with hooks and MCP (R3),
/// "Ligar" with a preview (R4), "Desligar" (R5, P5) and the executions of
/// the app outside the memory (R6, R7). Mock 2.
class AiMemoryLinksView extends ConsumerWidget {
  const AiMemoryLinksView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wiring = ref.watch(aiMemoryWiringProvider);
    final w = wiring.value;
    // R3: the Codex block only with the Codex on in the app (SPEC-096).
    final codexOn = ref.watch(providerFlowsProvider).anyFor('codex');
    final agents = [AiMemoryAgent.claude, if (codexOn) AiMemoryAgent.codex];
    if (w == null) {
      return AiMemoryBox(
        child: Text(
          wiring.isLoading
              ? 'Lendo o estado da ligação com o ai-memory…'
              : 'Não foi possível ler o estado da ligação.',
          key: const ValueKey('ai-memory-wiring-loading'),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }
    final missing = [
      for (final a in agents)
        if (w.of(a).needsLink) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (missing.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: SmallButton(
                key: const ValueKey('ai-memory-link-both'),
                label: 'Ligar nos dois',
                color: AppColors.onAmber,
                background: AppColors.amber,
                border: AppColors.amber,
                onTap: () => showAiMemoryLinkPreview(context, ref, missing),
              ),
            ),
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, a) in agents.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _AgentBlock(wiring: w, agent: a),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _AppRuns(),
      ],
    );
  }
}

class _AgentBlock extends ConsumerWidget {
  const _AgentBlock({required this.wiring, required this.agent});

  final AiMemoryWiring wiring;
  final AiMemoryAgent agent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = wiring.of(agent);
    Widget row(String label, AiMemoryLink l, String key, {bool mono = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: label),
                      if (mono)
                        const TextSpan(
                          text: ' ai-memory',
                          style: TextStyle(fontFamily: AppFonts.mono),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
              AiMemoryPill(
                l.label,
                aiMemoryLinkColor(l),
                key: ValueKey('ai-memory-${agent.cliName}-$key'),
              ),
            ],
          ),
        );
    final note = switch (agent) {
      AiMemoryAgent.claude =>
        'Onze eventos, entre eles SessionStart (entrega a passagem) e '
            'SessionEnd (grava a próxima).',
      AiMemoryAgent.codex =>
        wiring.codexAppWithoutMemory == null
            ? 'As sessões do Codex no app carregam os mesmos hooks e MCP do '
                  '~/.codex.'
            : null,
    };
    final codexReason = agent == AiMemoryAgent.codex
        ? wiring.codexAppWithoutMemory
        : null;
    return AiMemoryBox(
      key: ValueKey('ai-memory-block-${agent.cliName}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProviderChip(agent.providerId, name: agent.label),
              const Spacer(),
              if (a.anyOn)
                SmallButton(
                  key: ValueKey('ai-memory-unlink-${agent.cliName}'),
                  label: 'Desligar',
                  onTap: () => showAiMemoryUnlink(context, ref, agent),
                ),
              if (a.needsLink) ...[
                const SizedBox(width: 6),
                SmallButton(
                  key: ValueKey('ai-memory-link-${agent.cliName}'),
                  label: 'Ligar no ${agent.label}',
                  color: AppColors.onAmber,
                  background: AppColors.amber,
                  border: AppColors.amber,
                  onTap: () => showAiMemoryLinkPreview(context, ref, [agent]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          row('Hooks de ciclo de vida', a.hooks, 'hooks'),
          row('MCP', a.mcp, 'mcp', mono: true),
          if (a.plugin)
            const Text(
              'Ligado pelo plugin do ai-memory (hooks e MCP vêm dentro dele).',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (codexReason != null) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Codex no app sem memória: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.amber,
                    ),
                  ),
                  TextSpan(text: codexReason),
                ],
              ),
              key: const ValueKey('ai-memory-codex-no-memory'),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// R6: how each kind of execution of the app meets ai-memory.
class _AppRuns extends StatelessWidget {
  const _AppRuns();

  @override
  Widget build(BuildContext context) {
    Widget line(String what, String how) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              what,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          Text(
            how,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
    return AiMemoryBox(
      key: const ValueKey('ai-memory-app-runs'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Text('EXECUÇÕES DO APP', style: sectionTitleStyle),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'vale também para hooks instalados fora do app',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          line(
            'Auxiliares: planner, verificador, revisor, títulos, decisões de '
                'etapa',
            'sem captura · sem passagem',
          ),
          line('Sessões de etapa do Quadro', 'captura · sem passagem no fim'),
          line(
            'Sessões livres e conversas do Prompt',
            'captura · passagem no fim e no começo',
          ),
        ],
      ),
    );
  }
}

/// R4: the preview of "Ligar": commands, files ai-memory will change and
/// the backups; runs the installers only after the confirmation, then shows
/// their output. The app never writes in those files itself.
Future<void> showAiMemoryLinkPreview(
  BuildContext context,
  WidgetRef ref,
  List<AiMemoryAgent> agents,
) => showAppDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => AiMemoryLinkDialog(agents: agents),
);

class AiMemoryLinkDialog extends ConsumerStatefulWidget {
  const AiMemoryLinkDialog({super.key, required this.agents});

  final List<AiMemoryAgent> agents;

  @override
  ConsumerState<AiMemoryLinkDialog> createState() => _AiMemoryLinkDialogState();
}

class _AiMemoryLinkDialogState extends ConsumerState<AiMemoryLinkDialog> {
  bool _running = false;
  List<({String command, int exitCode, String output})>? _results;

  List<List<String>> get _commands => [
    for (final a in widget.agents) ...a.installCommands,
  ];

  String get _title => widget.agents.length == 1
      ? widget.agents.single.label
      : widget.agents.map((a) => a.label).join(' e ');

  Future<void> _apply() async {
    final cli = await ref.read(aiMemoryCliProvider.future);
    if (cli == null) return;
    setState(() => _running = true);
    final results = <({String command, int exitCode, String output})>[];
    for (final c in _commands) {
      final r = await cli.runConfirmed(c);
      results.add((
        command: 'ai-memory ${c.join(' ')}',
        exitCode: r.exitCode,
        output: r.output,
      ));
      if (r.exitCode != 0) break;
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _results = results;
    });
    ref.invalidate(aiMemoryWiringProvider);
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(aiMemoryEnvironmentProvider);
    final dataDir = ref.watch(aiMemoryWiringProvider).value?.dataDir;
    final results = _results;
    final codex = widget.agents.contains(AiMemoryAgent.codex);
    final agentArgs = widget.agents
        .map((a) => '--agent ${a.cliName}')
        .join(' ');
    return Dialog(
      backgroundColor: AppColors.panelSolid,
      child: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 0),
              child: Row(
                children: [
                  for (final a in widget.agents) ...[
                    ProviderChip(a.providerId, name: a.label),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      'Ligar o ai-memory no $_title',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    iconSize: 16,
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: _running ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Prévia do '),
                          TextSpan(
                            text: 'ai-memory setup --plan $agentArgs',
                            style: const TextStyle(fontFamily: AppFonts.mono),
                          ),
                          const TextSpan(
                            text: '. Nada muda até você confirmar.',
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'COMANDOS QUE VÃO RODAR',
                      style: sectionTitleStyle,
                    ),
                    const SizedBox(height: 6),
                    AiMemoryCommandBox(
                      [for (final c in _commands) 'ai-memory ${c.join(' ')}']
                          .join('\n'),
                      key: const ValueKey('ai-memory-link-commands'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'O QUE O AI-MEMORY VAI ALTERAR',
                      style: sectionTitleStyle,
                    ),
                    const SizedBox(height: 4),
                    for (final a in widget.agents)
                      for (final (path, what) in aiMemoryFilesFor(
                        a,
                        env: env,
                        dataDir: dataDir,
                      ))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Icon(
                                path.endsWith('/')
                                    ? Icons.folder_outlined
                                    : Icons.description_outlined,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  path,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: AppFonts.mono,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              Text(
                                what,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 6),
                    const Text(
                      'O ai-memory guarda uma cópia com data ao lado de cada '
                      'arquivo que altera e só mexe nas entradas dele. Rodar '
                      'de novo não muda nada.',
                      key: ValueKey('ai-memory-backup-note'),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (codex) ...[
                      const SizedBox(height: 10),
                      AiMemoryBox(
                        color: SessionColors.approvalBg,
                        border: SessionColors.approvalBorder,
                        padding: const EdgeInsets.all(10),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: AppColors.amber,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Na próxima abertura, o Codex pede para '
                                'confiar nos hooks (/hooks). Até lá, o estado '
                                'fica "aguardando confiança".',
                                key: ValueKey('ai-memory-trust-note'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.amberLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (results != null) ...[
                      const SizedBox(height: 14),
                      const Text('SAÍDA', style: sectionTitleStyle),
                      const SizedBox(height: 6),
                      for (final r in results)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${r.exitCode == 0 ? '✓' : '✗'} ${r.command}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: AppFonts.mono,
                                  color: r.exitCode == 0
                                      ? AppColors.teal
                                      : AppColors.red,
                                ),
                              ),
                              if (r.output.isNotEmpty)
                                AiMemoryCommandBox(r.output),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'O app não escreve nesses arquivos.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (results == null) ...[
                    SmallButton(
                      key: const ValueKey('ai-memory-link-cancel'),
                      label: 'Cancelar',
                      onTap: _running ? null : () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    SmallButton(
                      key: const ValueKey('ai-memory-link-confirm'),
                      label: _running ? 'Ligando…' : 'Ligar no $_title',
                      color: AppColors.onAmber,
                      background: AppColors.amber,
                      border: AppColors.amber,
                      onTap: _running ? null : _apply,
                    ),
                  ] else
                    SmallButton(
                      key: const ValueKey('ai-memory-link-close'),
                      label: 'Fechar',
                      onTap: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// R5 + P5: ai-memory 3.5.1 cannot uninstall one agent only, so
/// "Desligar" shows the commands to copy with "remove de todos os agentes"
/// and what they would remove (from the dry-run). Nothing runs.
Future<void> showAiMemoryUnlink(
  BuildContext context,
  WidgetRef ref,
  AiMemoryAgent agent,
) => showAppDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (ctx) {
    final removal = ref.read(aiMemoryWiringProvider).value?.removal ?? [];
    final commands = aiMemoryUninstallCommands.join('\n');
    return Dialog(
      backgroundColor: AppColors.panelSolid,
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Desligar o ai-memory no ${agent.label}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A versão instalada do ai-memory não desinstala por agente: '
                'estes comandos removem os hooks e o MCP dele de todos os '
                'agentes. O app não roda; copie e rode no terminal se quiser.',
                key: ValueKey('ai-memory-unlink-warning'),
                style: TextStyle(fontSize: 12, color: AppColors.amberLight),
              ),
              const SizedBox(height: 10),
              AiMemoryCommandBox(
                commands,
                key: const ValueKey('ai-memory-unlink-commands'),
              ),
              if (removal.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('O QUE ELES REMOVEM', style: sectionTitleStyle),
                const SizedBox(height: 4),
                for (final line in removal)
                  Text(
                    line,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: AppFonts.mono,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              const Text(
                'O ai-memory guarda uma cópia com data de cada arquivo antes '
                'de mudar. Os dados (wiki) continuam.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallButton(
                    key: const ValueKey('ai-memory-unlink-copy'),
                    label: 'Copiar comandos',
                    icon: Icons.copy,
                    onTap: () => copyAiMemoryText(ctx, commands),
                  ),
                  const SizedBox(width: 8),
                  SmallButton(
                    key: const ValueKey('ai-memory-unlink-close'),
                    label: 'Fechar',
                    onTap: () {
                      // The person may have run them meanwhile.
                      ref.invalidate(aiMemoryWiringProvider);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  },
);
