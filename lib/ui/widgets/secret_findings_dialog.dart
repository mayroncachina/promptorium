import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/secrets/secret_scanner.dart';
import '../../data/repos/secret_waivers_repo.dart' show secretWaiverMinReason;
import '../theme/tokens.dart';
import 'app_dialog.dart';

/// The pieces of the Vigia de segredos shared by the session's card, the
/// app's window and the Código (SPEC-085 R7–R11). Nothing here ever has the
/// value: only [SecretFinding.masked] and the masked line.

/// "Stripe live key em pagamento.ts linha 12, valor oculto" (R10).
String secretFindingLabel(SecretFinding f) => f.line == null
    ? '${f.ruleName}: arquivo ${f.fileName}, valores ocultos'
    : '${f.ruleName} em ${f.fileName} linha ${f.line}, valor oculto';

/// The amber chip with the rule's name.
class SecretRuleChip extends StatelessWidget {
  const SecretRuleChip(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: AppColors.amber.withValues(alpha: .7)),
    ),
    child: Text(
      name,
      style: const TextStyle(fontSize: 11, color: AppColors.amberLight),
    ),
  );
}

/// One action of a finding (a small outlined button, or a text one).
class SecretActionButton extends StatelessWidget {
  const SecretActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.plain = false,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool plain, primary;

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const WidgetStatePropertyAll(text),
    );
    if (primary) {
      return FilledButton(
        style: style.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.disabled)
                ? AppColors.amber.withValues(alpha: .25)
                : AppColors.amber,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.disabled)
                ? AppColors.textMuted
                : AppColors.onAmber,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
    }
    if (plain) {
      return TextButton(
        style: style.copyWith(
          foregroundColor: const WidgetStatePropertyAll(
            AppColors.textSecondary,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return OutlinedButton(
      style: style.copyWith(
        foregroundColor: const WidgetStatePropertyAll(AppColors.text),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.borderHover),
        ),
        backgroundColor: const WidgetStatePropertyAll(
          AppColors.surfaceRaisedSolid,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// The head of a finding: file, line, rule chip and the masked value.
class SecretFindingHeader extends StatelessWidget {
  const SecretFindingHeader(this.finding, {super.key});

  final SecretFinding finding;

  @override
  Widget build(BuildContext context) {
    final f = finding;
    return Row(
      children: [
        const Icon(
          Icons.description_outlined,
          size: 14,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: f.path,
                        style: const TextStyle(color: AppColors.text),
                      ),
                      if (f.line != null)
                        TextSpan(
                          text: ':${f.line}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SecretRuleChip(f.ruleName),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            f.masked,
            key: ValueKey('secret-masked-${f.path}-${f.line}'),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.amberLight,
            ),
          ),
        ),
      ],
    );
  }
}

/// The code line with the value masked.
class SecretMaskedLine extends StatelessWidget {
  const SecretMaskedLine(this.finding, {super.key});

  final SecretFinding finding;

  @override
  Widget build(BuildContext context) {
    final line = finding.maskedLine;
    if (line == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.backgroundSolid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${finding.line}  ',
              style: const TextStyle(color: ReviewColors.lineNumber),
            ),
            TextSpan(text: line),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12,
          color: AppColors.text,
        ),
      ),
    );
  }
}

/// A finding with its actions (R9): "Remover", "Ignorar com
/// justificativa…" (or "Commitar mesmo assim…") and "Abrir o arquivo".
class SecretFindingTile extends StatelessWidget {
  const SecretFindingTile({
    super.key,
    required this.finding,
    this.onRemove,
    this.onIgnore,
    this.onOpen,
    this.ignoreLabel = 'Ignorar com justificativa…',
    this.resolution,
    this.note,
    this.enabled = true,
  });

  final SecretFinding finding;
  final VoidCallback? onRemove, onIgnore, onOpen;

  /// False while an action runs: the buttons stay, disabled.
  final bool enabled;
  final String ignoreLabel;

  /// How it was handled (`removido`, `ignorado`, `pedido`); null = open.
  final String? resolution;

  /// A line under the head ("no commit 4e5f6a7, ainda não enviado").
  final String? note;

  @override
  Widget build(BuildContext context) {
    final done = resolution != null;
    return Semantics(
      container: true,
      label: secretFindingLabel(finding),
      child: Opacity(
        opacity: done ? .6 : 1,
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.panelSolid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: SecretFindingHeader(finding)),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    note!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ExcludeSemantics(child: SecretMaskedLine(finding)),
              const SizedBox(height: 10),
              if (done)
                Row(
                  children: [
                    const Icon(Icons.check, size: 14, color: AppColors.teal),
                    const SizedBox(width: 6),
                    Text(
                      switch (resolution) {
                        'removido' => 'Removido do commit',
                        'ignorado' => 'Ignorado com justificativa',
                        'pedido' => 'Pedido ao agente',
                        _ => 'Resolvido',
                      },
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (onRemove != null)
                      SecretActionButton(
                        key: ValueKey('secret-remove-${finding.path}'),
                        label: 'Remover',
                        onPressed: enabled ? onRemove : null,
                      ),
                    if (onIgnore != null)
                      SecretActionButton(
                        key: ValueKey('secret-ignore-${finding.path}'),
                        label: ignoreLabel,
                        onPressed: enabled ? onIgnore : null,
                      ),
                    if (onOpen != null)
                      SecretActionButton(
                        key: ValueKey('secret-open-${finding.path}'),
                        label: 'Abrir o arquivo',
                        plain: true,
                        onPressed: onOpen,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What "Ignorar com justificativa…" returns (R11).
typedef SecretWaiverChoice = ({String reason, bool byValue});

/// The window of the reason (R11): at least 10 characters, and the scope
/// (only this value, or this rule in this file).
Future<SecretWaiverChoice?> showSecretWaiverDialog(
  BuildContext context, {
  required SecretFinding finding,
  required String workspaceName,
  bool manual = false,
  String confirmLabel = 'Ignorar e avisar o agente',
}) => showAppDialog<SecretWaiverChoice>(
  context: context,
  builder: (_) => SecretWaiverDialog(
    finding: finding,
    workspaceName: workspaceName,
    manual: manual,
    confirmLabel: manual ? 'Commitar mesmo assim' : confirmLabel,
  ),
);

class SecretWaiverDialog extends StatefulWidget {
  const SecretWaiverDialog({
    super.key,
    required this.finding,
    required this.workspaceName,
    this.manual = false,
    this.confirmLabel = 'Ignorar e avisar o agente',
  });

  final SecretFinding finding;
  final String workspaceName;
  final bool manual;
  final String confirmLabel;

  @override
  State<SecretWaiverDialog> createState() => _SecretWaiverDialogState();
}

class _SecretWaiverDialogState extends State<SecretWaiverDialog> {
  final _reason = TextEditingController();
  bool _byValue = true;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => _reason.text.trim().length >= secretWaiverMinReason;

  void _confirm() {
    if (!_ok) return;
    Navigator.of(context).pop((reason: _reason.text.trim(), byValue: _byValue));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.finding;
    final n = _reason.text.trim().length;
    Widget radio(bool value, Widget title, String? sub, String key) =>
        RadioListTile<bool>(
          key: ValueKey(key),
          value: value,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.amber,
          title: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            child: title,
          ),
          subtitle: sub == null
              ? null
              : Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
        );
    return Dialog(
      backgroundColor: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _confirm,
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.manual
                      ? 'Commitar mesmo assim?'
                      : 'Ignorar este achado?',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'O commit segue com o valor. Se ele for um segredo de '
                  'verdade, vai parar no histórico do git.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSolid,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SecretFindingHeader(f),
                ),
                const SizedBox(height: 16),
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Por que ignorar? ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '(mínimo 10 caracteres)',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 13, color: AppColors.text),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const ValueKey('secret-waiver-reason'),
                  controller: _reason,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText:
                        'Ex.: chave de teste revogada, usada só no fixture',
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: _ok ? AppColors.amber : AppColors.inputBorder,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _ok
                          ? '$n caracteres'
                          : 'faltam ${secretWaiverMinReason - n} caracteres',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _ok ? AppColors.textMuted : AppColors.amber,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vale para',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                RadioGroup<bool>(
                  groupValue: _byValue,
                  onChanged: (v) => setState(() => _byValue = v ?? true),
                  child: Column(
                    children: [
                      radio(
                        true,
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Só este valor, em qualquer arquivo de ',
                              ),
                              TextSpan(
                                text: widget.workspaceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        'o app guarda uma impressão do valor, nunca o valor',
                        'secret-waiver-value',
                      ),
                      radio(
                        false,
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: 'Qualquer “${f.ruleName}” em '),
                              TextSpan(
                                text: f.path,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                ),
                              ),
                            ],
                          ),
                        ),
                        null,
                        'secret-waiver-file',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaisedSolid,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Fica em Configurações › Vigia de segredos, onde dá para '
                    'remover. Sai sozinho depois de 90 dias sem uso.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SecretActionButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    SecretActionButton(
                      key: const ValueKey('secret-waiver-confirm'),
                      label: widget.confirmLabel,
                      primary: true,
                      onPressed: _ok ? _confirm : null,
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

/// The window of a commit / push of the app or of the Código stopped by
/// the Vigia de segredos (R5, R6, R9). The actions come from the caller;
/// it closes with `true` once nothing is left (the caller redoes the
/// action), `false` / null otherwise.
class SecretFindingsDialog extends StatefulWidget {
  const SecretFindingsDialog({
    super.key,
    required this.findings,
    required this.onRemove,
    required this.onIgnore,
    required this.onOpen,
    this.manual = false,
    this.push = false,
    this.title,
  });

  final List<SecretFinding> findings;

  /// "Remover": true when the finding is gone (a file left the index); a
  /// secret in the code opens the file and stays (the app does not
  /// rewrite code).
  final Future<bool> Function(SecretFinding f) onRemove;

  /// "Ignorar com justificativa…" / "Commitar mesmo assim…": true once
  /// recorded.
  final Future<bool> Function(SecretFinding f) onIgnore;
  final Future<void> Function(SecretFinding f) onOpen;

  /// The Código's commit (R6): "Commitar mesmo assim…".
  final bool manual;

  /// A push (the secret is in a commit not sent yet).
  final bool push;
  final String? title;

  @override
  State<SecretFindingsDialog> createState() => _SecretFindingsDialogState();
}

class _SecretFindingsDialogState extends State<SecretFindingsDialog> {
  late final List<SecretFinding> _open = [...widget.findings];
  bool _busy = false;

  Future<void> _act(
    SecretFinding f,
    Future<bool> Function(SecretFinding) job,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await job(f)) _open.remove(f);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_open.isEmpty && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _removeFiles() async {
    for (final f in [..._open]) {
      if (f.isFile) await _act(f, widget.onRemove);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.findings.length;
    final onlyFiles = _open.isNotEmpty && _open.every((f) => f.isFile);
    final title =
        widget.title ??
        (widget.manual
            ? (n == 1 && widget.findings.single.isFile
                  ? 'Este commit leva um arquivo de ambiente'
                  : 'Este commit leva $n ${n == 1 ? 'segredo' : 'segredos'}')
            : 'O app parou: $n ${n == 1 ? 'segredo' : 'segredos'} no que ia '
                  '${widget.push ? 'subir' : 'para o commit'}');
    return Dialog(
      backgroundColor: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: AppColors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.manual
                    ? 'Remover tira o arquivo do commit e põe no .gitignore. '
                          'O arquivo fica no disco.'
                    : 'O app parou antes do commit dos arquivos pendentes e do '
                          'push. Nada saiu da sua máquina.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              for (final f in widget.findings)
                SecretFindingTile(
                  key: ValueKey('secret-dialog-${f.path}-${f.line}'),
                  finding: f,
                  resolution: _open.contains(f) ? null : 'removido',
                  note: widget.push ? 'em um commit ainda não enviado' : null,
                  ignoreLabel: widget.manual
                      ? 'Commitar mesmo assim…'
                      : 'Ignorar com justificativa…',
                  enabled: !_busy,
                  onRemove: () => _act(f, widget.onRemove),
                  onIgnore: () => _act(f, widget.onIgnore),
                  onOpen: () => widget.onOpen(f),
                ),
              const SizedBox(height: 12),
              Text(
                widget.manual
                    ? 'Se o segredo já foi enviado, troque-o no provedor.'
                    : 'No Autopilot e no Corrigir CI automático, a spec para '
                          'aqui em “precisa de você”. Se o segredo já foi '
                          'enviado, troque-o no provedor.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SecretActionButton(
                    key: const ValueKey('secret-dialog-close'),
                    label: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  if (widget.manual && onlyFiles) ...[
                    const SizedBox(width: 8),
                    SecretActionButton(
                      key: const ValueKey('secret-dialog-remove-commit'),
                      label: 'Remover e commitar',
                      primary: true,
                      onPressed: _busy ? null : _removeFiles,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
