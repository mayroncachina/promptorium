import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/agent_trailer.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/info_tip.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_config.dart';

/// Subject of the example commit shown wherever the marking is explained.
const agentTrailerExampleSubject =
    'SPEC-042 R2: seletor de sprint no cabeçalho';

/// `Promptorium-Agente: sonnet · SPEC-042 R2` (the example line).
final agentTrailerExampleLine = agentTrailerLine('sonnet', 'SPEC-042 R2');

/// The example commit as an [InfoTipCode]: subject, blank line, trailer.
final agentTrailerExampleCode = InfoTipCode(
  [agentTrailerExampleSubject, '', agentTrailerExampleLine],
  highlight: const {2},
);

/// ⓘ of the option (Configuração do projeto, SPEC-048 R1 / R7).
InfoTip agentTrailerInfoTip({Key? key}) => InfoTip(
  key: key ?? const ValueKey('config-mark-agents-info'),
  title: 'O que muda nos commits',
  semanticLabel: 'Sobre marcar commits feitos por agentes',
  text:
      'Quando um agente do Promptorium faz commit, o app acrescenta uma '
      'linha ao fim da mensagem. O autor continua sendo você, e o GitHub '
      'não mostra coautor.',
  code: agentTrailerExampleCode,
  detail: const TextSpan(
    children: [
      TextSpan(text: 'Serve para a '),
      TextSpan(
        text: 'Atividade',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      TextSpan(text: ' separar o que você e os agentes fizeram e para o '),
      TextSpan(
        text: 'Grafo',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      TextSpan(text: ' mostrar o modelo de cada commit.'),
    ],
  ),
  footnote:
      'Só as sessões do app são marcadas: seus commits no terminal saem '
      'como sempre. Nada é instalado no repositório, e commits antigos não '
      'mudam.',
);

/// Confirmation of turning the marking on from where it is used (the
/// "Quem fez os commits" card of the Atividade, SPEC-046; SPEC-048 R6).
///
/// On "Ligar marcação" it writes `git: marcar-commits-de-agente: true` to
/// the workspace's `.promptorium/config.yml` (other keys kept), refreshes
/// [projectConfigProvider] and returns true; false when cancelled.
Future<bool> showAgentTrailerDialog(
  BuildContext context, {
  required Workspace workspace,
}) async =>
    await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => AgentTrailerDialog(workspace: workspace),
    ) ??
    false;

/// Turns the marking on in [workspacePath]'s config (other keys kept).
Future<void> enableAgentTrailer(String workspacePath) async {
  final c = ProjectConfig.loadSync(workspacePath);
  await ProjectConfig.save(
    workspacePath,
    c.copyWith(git: const GitConfig(markAgentCommits: true)),
  );
}

class AgentTrailerDialog extends ConsumerStatefulWidget {
  const AgentTrailerDialog({super.key, required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<AgentTrailerDialog> createState() => _AgentTrailerDialogState();
}

class _AgentTrailerDialogState extends ConsumerState<AgentTrailerDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await enableAgentTrailer(widget.workspace.path);
      ref.invalidate(projectConfigProvider(widget.workspace.path));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Falha ao salvar: $e';
        });
      }
    }
  }

  static const _body = TextStyle(
    fontSize: 13,
    height: 1.5,
    color: AppColors.text,
  );
  static const _mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12.5);

  Widget _bullet(List<InlineSpan> spans) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 10, 0),
          child: Text('•', style: _body),
        ),
        Expanded(
          child: Text.rich(TextSpan(children: spans), style: _body),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final git = ref.watch(gitVersionProvider);
    final tooOld = git.hasValue && !gitSupportsAgentTrailer(git.value);
    final code = agentTrailerExampleCode;
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Material(
        key: const ValueKey('agent-trailer-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Marcar os commits dos agentes?',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vale para ${widget.workspace.name}, a partir das '
                  'próximas sessões.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Os commits das sessões ganham esta linha no fim',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('agent-trailer-example'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < code.lines.length; i++)
                        Text(
                          code.lines[i].isEmpty ? ' ' : code.lines[i],
                          style: _mono.copyWith(
                            height: 1.6,
                            color: code.highlight.contains(i)
                                ? AppColors.amber
                                : AppColors.text,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _bullet(const [
                  TextSpan(
                    text:
                        'O autor continua sendo você, e o GitHub não mostra '
                        'coautor.',
                  ),
                ]),
                _bullet(const [
                  TextSpan(text: '.promptorium/config.yml', style: _mono),
                  TextSpan(text: ' ganha '),
                  TextSpan(
                    text: 'git: marcar-commits-de-agente: true',
                    style: _mono,
                  ),
                  TextSpan(
                    text:
                        ' e entra no próximo commit, como qualquer '
                        'configuração do projeto. Quem clonar com o '
                        'Promptorium herda a marcação.',
                  ),
                ]),
                _bullet(const [
                  TextSpan(
                    text:
                        'Seus commits no terminal não são marcados, e nada é '
                        'instalado em ',
                  ),
                  TextSpan(text: '.git/hooks', style: _mono),
                  TextSpan(text: '.'),
                ]),
                _bullet(const [
                  TextSpan(
                    text:
                        'Commits antigos não mudam. Eles seguem como "sem '
                        'marca".',
                  ),
                ]),
                const SizedBox(height: 14),
                const Text(
                  'Dá para desligar em Configurações › Configuração do '
                  'projeto › Git.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                if (tooOld || _error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error ??
                        'Precisa do git $agentTrailerMinGitLabel ou mais novo '
                            '(este é o ${git.value ?? 'ausente'}).',
                    key: const ValueKey('agent-trailer-error'),
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      key: const ValueKey('agent-trailer-cancel'),
                      label: 'Agora não',
                      height: 38,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: 10),
                    AmberButton(
                      key: const ValueKey('agent-trailer-enable'),
                      label: 'Ligar marcação',
                      height: 38,
                      fontSize: 13,
                      busy: _busy,
                      onTap: tooOld ? null : _enable,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `2.32` (the minimum shown to the user).
final agentTrailerMinGitLabel =
    '${agentTrailerMinGit.major}.${agentTrailerMinGit.minor}';
