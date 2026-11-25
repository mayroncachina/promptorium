import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../debt_item.dart';
import '../debt_payment.dart';
import 'decision_panel.dart' show DebtTag;

/// "Pagar · N" (SPEC-112 R15): opens the dialog for [items] (open debts of
/// [ws]) and, on confirm, creates the VIBE or the spec. Returns the spec.
Future<Spec?> openPayDebtsDialog(
  BuildContext context,
  WidgetRef ref, {
  required Workspace ws,
  required List<DebtItem> items,
  required String file,
}) async {
  if (items.isEmpty) return null;
  final spec = await showAppDialog<Spec>(
    context: context,
    builder: (_) => PayDebtsDialog(ws: ws, items: items, file: file),
  );
  if (spec != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showAppToast(
      SnackBar(
        content: Text(
          '${spec.code} criada: '
          '${debtCodesText([for (final d in items) d.code])} '
          '${items.length == 1 ? 'fica' : 'ficam'} em pagamento.',
        ),
      ),
    );
  }
  return spec;
}

class PayDebtsDialog extends ConsumerStatefulWidget {
  const PayDebtsDialog({
    super.key,
    required this.ws,
    required this.items,
    required this.file,
  });

  final Workspace ws;
  final List<DebtItem> items;

  /// `DEBITO_TECNICO.md`.
  final String file;

  @override
  ConsumerState<PayDebtsDialog> createState() => _PayDebtsDialogState();
}

class _PayDebtsDialogState extends ConsumerState<PayDebtsDialog> {
  late DebtPayMode _mode = suggestedPayMode(widget.items.length);
  bool _busy = false;
  String? _error;

  int get _n => widget.items.length;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final spec = await ref
          .read(debtPaymentProvider)
          .pay(widget.ws, widget.items, _mode, file: widget.file);
      if (mounted) Navigator.of(context).pop(spec);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  String get _preview => _mode == DebtPayMode.vibe
      ? vibePaymentPrompt(widget.items, file: widget.file)
      : [
          '# ${paymentSpecTitle(widget.items)}',
          '',
          '## Objetivo',
          '',
          paymentSpecObjective(widget.items, file: widget.file),
          '',
          '## Requisitos',
          '',
          for (final (i, d) in widget.items.indexed)
            '- R${i + 1} · ${paymentRequirement(d)}',
        ].join('\n');

  @override
  Widget build(BuildContext context) {
    final vibe = _mode == DebtPayMode.vibe;
    final both = _n == 1 ? 'o débito' : (_n == 2 ? 'os dois' : 'os $_n');
    final task = vibe ? 'a tarefa' : 'a spec';
    final first = widget.items.first.code;
    return Align(
      alignment: const Alignment(0, -0.3),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _confirm,
        },
        child: Material(
          key: const ValueKey('pay-debts-dialog'),
          color: AppColors.panelSolid,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Pagar $_n ${_n == 1 ? 'débito' : 'débitos'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Esc fecha',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ItemsBox(items: widget.items),
                  const SizedBox(height: 16),
                  const _Label('COMO PAGAR'),
                  const SizedBox(height: 8),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ModeCard(
                            key: const ValueKey('pay-mode-vibe'),
                            title: 'Tarefa VIBE',
                            tag: 'até 2 débitos',
                            suggested: suggestedPayMode(_n) == DebtPayMode.vibe,
                            selected: vibe,
                            body:
                                'Um prompt só, numa worktree, com Revisão e '
                                'merge no fim. Bom para débitos pequenos e já '
                                'descritos.',
                            onTap: _busy
                                ? null
                                : () =>
                                      setState(() => _mode = DebtPayMode.vibe),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ModeCard(
                            key: const ValueKey('pay-mode-spec'),
                            title: 'Spec',
                            tag: 'a partir de 3',
                            suggested: suggestedPayMode(_n) == DebtPayMode.spec,
                            selected: !vibe,
                            body:
                                '“${paymentSpecTitle(widget.items)}”, com os '
                                'débitos no Objetivo e um requisito por '
                                'débito. Passa pela entrevista e pelo plano.',
                            onTap: _busy
                                ? null
                                : () =>
                                      setState(() => _mode = DebtPayMode.spec),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Label(vibe ? 'PROMPT DA VIBE' : 'TEXTO DA SPEC'),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: SessionColors.terminalPanel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _preview,
                        key: const ValueKey('pay-preview'),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _Label('O QUE ACONTECE'),
                  const SizedBox(height: 8),
                  _Step(
                    n: 1,
                    children: [
                      TextSpan(
                        text: 'Agora ${_n == 1 ? 'ele fica' : '$both ficam'} ',
                      ),
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: DebtTag(
                          'em pagamento',
                          color: AppColors.amber,
                          filled: true,
                        ),
                      ),
                      TextSpan(text: ', com o link d$task.'),
                    ],
                  ),
                  _Step(
                    n: 2,
                    children: [
                      const TextSpan(text: 'No merge, o app risca as linhas: '),
                      TextSpan(
                        text:
                            '~~$first~~ … — **resolvido** pela '
                            '${vibe ? 'VIBE' : 'spec N'}',
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11.5,
                        ),
                      ),
                      const TextSpan(text: ', e “Para resolver” vira “—”.'),
                    ],
                  ),
                  _Step(
                    n: 3,
                    children: [
                      TextSpan(
                        text:
                            'Se $task for descartada, '
                            '${_n == 1 ? 'ele volta' : '$both voltam'} a ',
                      ),
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: DebtTag('aberto'),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      key: const ValueKey('pay-error'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SmallButton(
                        key: const ValueKey('pay-cancel'),
                        label: 'Cancelar',
                        height: 34,
                        fontSize: 13,
                        onTap: _busy
                            ? () {}
                            : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      AmberButton(
                        key: const ValueKey('pay-confirm'),
                        label: vibe ? 'Criar VIBE' : 'Criar spec',
                        height: 34,
                        fontSize: 13,
                        busy: _busy,
                        onTap: _busy ? null : _confirm,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10.5,
      letterSpacing: .8,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    ),
  );
}

class _ItemsBox extends StatelessWidget {
  const _ItemsBox({required this.items});

  final List<DebtItem> items;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        for (final (i, d) in items.indexed)
          Container(
            key: ValueKey('pay-item-${d.code}'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : const Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Text(
                  d.code,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12.5,
                    color: AppColors.amber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    d.whereRefs.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.title,
    required this.tag,
    required this.suggested,
    required this.selected,
    required this.body,
    required this.onTap,
  });

  final String title;
  final String tag;
  final bool suggested;
  final bool selected;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.amberTint : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppColors.amber : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: selected ? AppColors.amber : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Spacer(),
                  Flexible(
                    flex: 100,
                    child: suggested
                        ? DebtTag(
                            'sugerido · $tag',
                            key: ValueKey('pay-suggested-$title'),
                            color: AppColors.teal,
                            filled: true,
                          )
                        : Text(
                            tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.children});

  final int n;
  final List<InlineSpan> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderHover),
          ),
          child: Text(
            '$n',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(children: children),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ),
      ],
    ),
  );
}
