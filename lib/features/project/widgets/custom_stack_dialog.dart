import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../sessions/widgets/session_style.dart';
import '../cost_estimate.dart' show callsLabel;
import '../custom_stack.dart';
import '../environment_check.dart' show planLabel;
import 'commands_card.dart';
import 'project_widgets.dart';
import 'stack_step.dart' show DecisionRow;

/// Opens "Definir a stack com o Claude" (SPEC-072 R16–R19). True when the
/// person chose "Usar esta stack"; closing leaves the Começar screen as it
/// was. [chat] keeps the conversation for the pencil.
Future<bool> showCustomStackDialog(
  BuildContext context,
  CustomStackChat chat, {
  String? subscriptionType,
}) async =>
    await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) =>
          CustomStackDialog(chat: chat, subscriptionType: subscriptionType),
    ) ??
    false;

class CustomStackDialog extends StatefulWidget {
  const CustomStackDialog({
    super.key,
    required this.chat,
    this.subscriptionType,
  });

  final CustomStackChat chat;
  final String? subscriptionType;

  @override
  State<CustomStackDialog> createState() => _CustomStackDialogState();
}

class _CustomStackDialogState extends State<CustomStackDialog> {
  final _text = TextEditingController();
  bool _showClaudeMd = false;

  CustomStackChat get chat => widget.chat;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty || chat.busy) return;
    _text.clear();
    if (chat.proposal == null) {
      chat.propose(t);
    } else {
      chat.adjust(t);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.panelSolid,
    insetPadding: const EdgeInsets.all(32),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 940, maxHeight: 680),
      child: ListenableBuilder(
        listenable: chat,
        builder: (context, _) => Column(
          key: const ValueKey('custom-stack-dialog'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _body()),
            _input(),
            const Divider(height: 1, color: AppColors.border),
            _footer(),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 18, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Definir a stack com o Claude',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text(
                'Descreva a stack. O Claude propõe as decisões, os comandos e '
                'um CLAUDE.md base. Ele só lê: nada é gravado até você criar '
                'o projeto.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        SmallButton(
          key: const ValueKey('custom-stack-close'),
          label: 'Fechar',
          onTap: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );

  Widget _body() {
    final p = chat.proposal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      children: [
        for (final m in chat.messages)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6, left: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.amberTint,
                border: Border.all(color: SessionColors.approvalBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                m.adjust ? 'Ajuste: ${m.text}' : m.text,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        if (chat.busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const PlannerBusy('Pensando…'),
                const SizedBox(width: 12),
                SmallButton(
                  key: const ValueKey('custom-stack-cancel-run'),
                  label: 'Cancelar',
                  onTap: chat.cancel,
                ),
              ],
            ),
          ),
        if (chat.error case final e?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: NoticeBox.error(
              text: e,
              action: SmallButton(
                key: const ValueKey('custom-stack-retry'),
                label: 'Tentar de novo',
                onTap: chat.retry,
              ),
            ),
          ),
        if (p != null) ...[const SizedBox(height: 6), _preview()],
      ],
    );
  }

  /// The description, or "Pedir ajuste…" once there is a preview: always
  /// visible under the conversation.
  Widget _input() {
    final p = chat.proposal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              label: p == null ? 'Descrição da stack' : 'Pedido de ajuste',
              textField: true,
              child: TextField(
                key: const ValueKey('custom-stack-text'),
                controller: _text,
                enabled: !chat.busy,
                minLines: p == null ? 3 : 1,
                maxLines: 5,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: p == null
                      ? 'API em Go com Fiber e Postgres, testes com go test'
                      : 'Pedir ajuste… (ex.: trocar o Fiber pelo chi)',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          (p == null ? AmberButton.new : _small)(
            key: const ValueKey('custom-stack-send'),
            label: p == null ? 'Propor stack' : 'Pedir ajuste',
            height: 36,
            onTap: chat.busy || _text.text.trim().isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }

  static Widget _small({
    Key? key,
    required String label,
    required VoidCallback? onTap,
    double height = 30,
  }) => SmallButton(key: key, label: label, onTap: onTap, height: height);

  Widget _preview() {
    final p = chat.proposal!;
    final lines = '\n'.allMatches(p.claudeMd.trimRight()).length + 1;
    final plan = widget.subscriptionType;
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      key: const ValueKey('custom-stack-preview'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: SessionColors.runningToolBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                p.name,
                key: const ValueKey('custom-stack-name'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              const InfoTag('proposta do Claude'),
              const Spacer(),
              Text(
                [
                  callsLabel(chat.calls),
                  if (plan != null) 'plano ${planLabel(plan)}',
                ].join(' · '),
                key: const ValueKey('custom-stack-calls'),
                style: label,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final decisions = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final d in p.decisions)
                    DecisionRow(decision: d, onChoose: null),
                ],
              );
              final commands = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Comandos',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'editáveis · vão para o config.yml',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CommandsCard(
                    commands: p.commands,
                    compact: true,
                    onChanged: chat.busy ? null : chat.editCommand,
                  ),
                ],
              );
              return box.maxWidth > 820
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: decisions),
                        const SizedBox(width: 16),
                        Expanded(child: commands),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [decisions, commands],
                    );
            },
          ),
          const SizedBox(height: 8),
          if (p.scaffold.isNotEmpty)
            Text.rich(
              TextSpan(
                text: 'Scaffold  ',
                children: [
                  TextSpan(
                    text: p.scaffold,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              key: const ValueKey('custom-stack-scaffold'),
              style: label,
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('CLAUDE.md base · $lines linhas', style: label),
              TextButton(
                key: const ValueKey('custom-stack-claudemd'),
                onPressed: () => setState(() => _showClaudeMd = !_showClaudeMd),
                child: Text(_showClaudeMd ? 'Ocultar' : 'Ver'),
              ),
            ],
          ),
          if (_showClaudeMd)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SessionColors.terminalPanel,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                p.claudeMd,
                key: const ValueKey('custom-stack-claudemd-text'),
                style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Cada proposta ou ajuste é uma chamada e conta no custo do '
            'Começar.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        SmallButton(
          key: const ValueKey('custom-stack-cancel'),
          label: 'Cancelar',
          height: 36,
          onTap: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 8),
        AmberButton(
          key: const ValueKey('custom-stack-use'),
          label: 'Usar esta stack',
          height: 36,
          onTap: chat.proposal == null || chat.busy
              ? null
              : () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
}
