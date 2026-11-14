import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mcp/app_mcp_config.dart';
import '../../core/mcp/app_mcp_server.dart';
import '../../core/mcp/app_mcp_tools.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';

/// "Servidor MCP do Promptorium" of Configurações › Execução de specs
/// (SPEC-052 R10): on / off, the state, the tools and the R9 limit.
class AppMcpServerCard extends ConsumerStatefulWidget {
  const AppMcpServerCard({super.key});

  @override
  ConsumerState<AppMcpServerCard> createState() => _AppMcpServerCardState();
}

class _AppMcpServerCardState extends ConsumerState<AppMcpServerCard> {
  final _limit = TextEditingController();
  final _limitFocus = FocusNode();

  @override
  void dispose() {
    _limit.dispose();
    _limitFocus.dispose();
    super.dispose();
  }

  Future<void> _saveLimit() async {
    final n = int.tryParse(_limit.text.trim());
    final settings = ref.read(appSettingsProvider.notifier);
    if (n == null || n < 1) {
      _limit.text = '${appMcpCreationLimit(ref.read(appSettingsProvider))}';
      return;
    }
    if (n == McpGrant.defaultCreationLimit) {
      await settings.remove(AppSettingKeys.mcpCreationLimit);
    } else {
      await settings.set(AppSettingKeys.mcpCreationLimit, '$n');
    }
  }

  @override
  Widget build(BuildContext context) {
    final values = ref.watch(appSettingsProvider);
    final on = appMcpEnabled(values);
    final limit = appMcpCreationLimit(values);
    if (!_limitFocus.hasFocus && _limit.text != '$limit') {
      _limit.text = '$limit';
    }
    final server = ref.watch(appMcpServerProvider);
    const sub = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    Widget status() {
      if (!on) {
        return const Text(
          'Desligado: as próximas execuções não recebem o servidor.',
          key: ValueKey('settings-app-mcp-status'),
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        );
      }
      return ListenableBuilder(
        listenable: server ?? ValueNotifier(0),
        builder: (context, _) {
          final port = server?.port;
          final n = server?.grants.length ?? 0;
          final text = port == null
              ? 'Sobe com a próxima sessão ou conversa'
              : 'Ouvindo em 127.0.0.1:$port · '
                    '${n == 1 ? '1 execução conectada' : '$n execuções conectadas'}';
          return Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: port == null ? AppColors.textMuted : AppColors.teal,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  key: const ValueKey('settings-app-mcp-status'),
                  style: TextStyle(
                    fontSize: 12,
                    color: port == null ? AppColors.textMuted : AppColors.teal,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    TableRow row(List<Widget> cells, {bool header = false}) => TableRow(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      children: [
        for (final c in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: c,
          ),
      ],
    );
    const head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );

    return AgentCard(
      key: const ValueKey('settings-app-mcp'),
      title: 'Servidor MCP do Promptorium',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            key: const ValueKey('settings-app-mcp-on'),
            value: on,
            onChanged: (v) => v ?? true
                ? ref
                      .read(appSettingsProvider.notifier)
                      .remove(AppSettingKeys.mcpServer)
                : ref
                      .read(appSettingsProvider.notifier)
                      .set(AppSettingKeys.mcpServer, '0'),
          ),
          const Text('Ligado', style: TextStyle(fontSize: 13)),
        ],
      ),
      children: [
        const Text(
          'Deixa o agente consultar as specs e o Quadro, criar rascunhos e '
          'anotar o andamento. Vale só para as sessões e conversas que o app '
          'abre. Cada uma recebe um arquivo próprio em ~/.promptorium/run, '
          'com um token que some quando ela termina. Nada vai para '
          '~/.claude.json nem para .mcp.json.',
          style: sub,
        ),
        const SizedBox(height: 8),
        status(),
        const SizedBox(height: 12),
        Table(
          key: const ValueKey('settings-app-mcp-tools'),
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
            2: IntrinsicColumnWidth(),
            3: IntrinsicColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            row(const [
              Text('Ferramenta', style: head),
              Text('O que faz', style: head),
              Text('Modos', style: head),
              Text('Aprovação', style: head),
            ], header: true),
            for (final t in appMcpCatalog)
              row([
                Text(t.name, style: mono),
                Text(t.summary, style: const TextStyle(fontSize: 12)),
                Text(t.write ? 'Planejar, Editar' : 'todos', style: sub),
                Text(
                  t.write ? 'Sempre pede' : 'Liberada',
                  key: ValueKey('settings-app-mcp-approval-${t.name}'),
                  style: TextStyle(
                    fontSize: 12,
                    color: t.write ? AppColors.amber : AppColors.teal,
                  ),
                ),
              ]),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Specs que uma execução pode criar',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(
              width: 72,
              child: Focus(
                onFocusChange: (f) {
                  if (!f) _saveLimit();
                },
                child: TextField(
                  key: const ValueKey('settings-app-mcp-limit'),
                  controller: _limit,
                  focusNode: _limitFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _saveLimit(),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ),
            const Text(
              'Acima disso, o agente recebe um erro que explica o motivo e '
              'nada é gravado.',
              style: sub,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'O servidor nunca muda status, coluna ou etapas, não sobrescreve '
          'specs e não aprova, executa nem faz merge. Em "sem perguntar", a '
          'escrita grava sem aprovação e a timeline marca o que foi criado.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
