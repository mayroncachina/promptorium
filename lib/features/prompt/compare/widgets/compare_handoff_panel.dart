import 'package:flutter/material.dart';

import '../../../../ui/theme/tokens.dart';
import '../../../sessions/handoff/session_summary.dart' show providerWords;
import '../../../sessions/widgets/session_style.dart';
import '../compare_handoff.dart';
import '../compare_weight.dart' show compareTokens;

/// "Ver o que o B recebe" (SPEC-108 R4): the package of the side that
/// starts without the conversation's session, reviewed and edited before
/// sending.
class CompareHandoffPanel extends StatefulWidget {
  const CompareHandoffPanel({
    super.key,
    required this.handoff,
    required this.letters,
    required this.provider,
    required this.onClose,
    required this.onEdit,
    required this.onReset,
  });

  final CompareHandoff handoff;

  /// The sides that receive it.
  final List<String> letters;

  /// Provider of the conversation (whose session stays out).
  final String provider;
  final VoidCallback onClose;
  final ValueChanged<String> onEdit;

  /// Back to the summary built by the app.
  final VoidCallback onReset;

  @override
  State<CompareHandoffPanel> createState() => _CompareHandoffPanelState();
}

class _CompareHandoffPanelState extends State<CompareHandoffPanel> {
  TextEditingController? _edit;

  @override
  void dispose() {
    _edit?.dispose();
    super.dispose();
  }

  void _stop() => setState(() {
    _edit?.dispose();
    _edit = null;
  });

  @override
  Widget build(BuildContext context) {
    final h = widget.handoff;
    final who = widget.letters.length > 1
        ? 'os lados recebem'
        : 'o ${widget.letters.single} recebe';
    const muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    Widget card(String title, Widget child, {Key? key}) => Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
    final edit = _edit;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'O que $who',
      child: ColoredBox(
        key: const ValueKey('compare-handoff-panel'),
        color: AppColors.panel,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'O QUE ${who.toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('compare-handoff-close'),
                  tooltip: 'Fechar',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: AppColors.textSecondary,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              h.edited
                  ? 'Pacote revisado por você. Vai junto com a pergunta.'
                  : 'Montado pelo app, sem chamar modelo. Revise antes de '
                        'enviar.',
              style: muted,
            ),
            const SizedBox(height: 12),
            if (edit == null) ...[
              card(
                'Conversa',
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: h.messages == 1
                            ? '1 mensagem resumida'
                            : '${h.messages} mensagens resumidas',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text,
                        ),
                      ),
                      const TextSpan(text: '\npergunta atual enviada inteira'),
                    ],
                  ),
                  style: muted,
                ),
              ),
              if (h.hasPlan)
                card(
                  'Plano vigente',
                  const Text('vai no pacote', style: muted),
                ),
              if (h.files.isNotEmpty)
                card(
                  'Arquivos citados · ${h.files.length}',
                  Text(
                    h.files.join('\n'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppFonts.mono,
                      color: AppColors.text,
                    ),
                  ),
                ),
              if (h.git case final git?)
                card(
                  'Estado do git',
                  Text(
                    git,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppFonts.mono,
                      color: AppColors.text,
                    ),
                  ),
                ),
              card(
                'Fora do pacote',
                Text(
                  'a sessão do ${providerWords(widget.provider)} · segredos · '
                  'conteúdo dos arquivos',
                  style: muted,
                ),
              ),
              card(
                'Texto enviado',
                SelectableText(
                  h.text,
                  key: const ValueKey('compare-handoff-text'),
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    fontFamily: AppFonts.mono,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ] else ...[
              TextField(
                key: const ValueKey('compare-handoff-field'),
                controller: edit,
                autofocus: true,
                minLines: 12,
                maxLines: 24,
                style: const TextStyle(fontSize: 12, fontFamily: AppFonts.mono),
              ),
              const SizedBox(height: 6),
              const Text(
                'Os segredos do texto são mascarados ao salvar.',
                style: muted,
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '≈ ${compareTokens(h.tokens)} tokens',
                  key: const ValueKey('compare-handoff-tokens'),
                  style: muted,
                ),
                if (edit == null) ...[
                  SmallButton(
                    key: const ValueKey('compare-handoff-edit'),
                    label: 'Editar o resumo',
                    height: 28,
                    onTap: () => setState(
                      () => _edit = TextEditingController(text: h.text),
                    ),
                  ),
                  if (h.edited)
                    SmallButton(
                      key: const ValueKey('compare-handoff-reset'),
                      label: 'Voltar ao resumo do app',
                      height: 28,
                      onTap: widget.onReset,
                    ),
                ] else ...[
                  SmallButton(
                    key: const ValueKey('compare-handoff-cancel'),
                    label: 'Cancelar',
                    height: 28,
                    onTap: _stop,
                  ),
                  AmberButton(
                    key: const ValueKey('compare-handoff-save'),
                    label: 'Salvar',
                    height: 28,
                    onTap: () {
                      final text = edit.text.trim();
                      _stop();
                      if (text.isNotEmpty) widget.onEdit(text);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
