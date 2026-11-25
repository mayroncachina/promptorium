import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../debt_service.dart';
import '../debt_table.dart';

/// The form of a new debt or decision (R6, R8, R9, R10, R12): the same for
/// every origin, already filled by the caller. Returns the edited draft, or
/// null when cancelled.
class DebtFormDialog extends StatefulWidget {
  const DebtFormDialog({
    super.key,
    required this.initial,
    this.nextCode,
    this.destination,
    this.saveLabel,
  });

  final DebtDraft initial;

  /// `DT-10` (a preview: the code is reserved on save).
  final String? nextCode;

  /// Where the row goes: `DEBITO_TECNICO.md · branch main` (R18).
  final String? destination;
  final String? saveLabel;

  @override
  State<DebtFormDialog> createState() => _DebtFormDialogState();
}

class _DebtFormDialogState extends State<DebtFormDialog> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _reason = TextEditingController(text: widget.initial.reason);
  late final _where = TextEditingController(text: widget.initial.where);
  late final _toResolve = TextEditingController(text: widget.initial.toResolve);
  late final _origin = TextEditingController(text: widget.initial.origin);
  String? _error;

  bool get _isDebt => widget.initial.kind == DebtKind.debt;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _reason, _where, _toResolve, _origin]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _reason, _where, _toResolve, _origin]) {
      c.dispose();
    }
    super.dispose();
  }

  DebtDraft get _draft => widget.initial.copyWith(
    title: _title.text.trim(),
    reason: _reason.text.trim(),
    where: _where.text.trim(),
    toResolve: _toResolve.text.trim(),
    origin: _origin.text.trim(),
  );

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(
        () => _error = _isDebt ? 'Informe o título.' : 'Informe a pergunta.',
      );
      return;
    }
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.nextCode ?? '${widget.initial.kind.prefix}-NN';
    final preview = DebtTable.formatRow(_draft.cells(code, 'AAAA-MM-DD'));
    return Align(
      alignment: const Alignment(0, -0.3),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        },
        child: Material(
          key: const ValueKey('debt-form'),
          color: AppColors.panelSolid,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        _isDebt ? 'Novo débito' : 'Nova decisão',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        code,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.amber,
                        ),
                      ),
                      const Spacer(),
                      if (widget.destination != null)
                        Flexible(
                          child: Text(
                            widget.destination!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: _isDebt ? 'O quê (título)' : 'Pergunta',
                    controller: _title,
                    fieldKey: 'debt-form-title',
                    autofocus: true,
                    error: _error,
                  ),
                  if (_isDebt)
                    _Field(
                      label: 'Motivo',
                      controller: _reason,
                      fieldKey: 'debt-form-reason',
                      maxLines: 3,
                    ),
                  if (_isDebt)
                    _Field(
                      label: 'Onde (arquivo ou função, sem linha)',
                      controller: _where,
                      fieldKey: 'debt-form-where',
                      mono: true,
                    ),
                  _Field(
                    label: _isDebt ? 'Para resolver' : 'Recomendação',
                    controller: _toResolve,
                    fieldKey: 'debt-form-to-resolve',
                    maxLines: 2,
                  ),
                  _Field(
                    label: 'Origem',
                    controller: _origin,
                    fieldKey: 'debt-form-origin',
                    hint: 'spec 31, Q5',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'LINHA QUE O APP GRAVA',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSolid,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      preview,
                      key: const ValueKey('debt-form-preview'),
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SmallButton(
                        key: const ValueKey('debt-form-cancel'),
                        label: 'Cancelar',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      AmberButton(
                        key: const ValueKey('debt-form-save'),
                        label:
                            widget.saveLabel ??
                            (_isDebt ? 'Salvar débito' : 'Salvar decisão'),
                        onTap: _save,
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.maxLines = 1,
    this.mono = false,
    this.autofocus = false,
    this.hint,
    this.error,
  });

  final String label;
  final TextEditingController controller;
  final String fieldKey;
  final int maxLines;
  final bool mono;
  final bool autofocus;
  final String? hint;
  final String? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey(fieldKey),
      controller: controller,
      autofocus: autofocus,
      minLines: 1,
      maxLines: maxLines,
      style: TextStyle(fontSize: 13, fontFamily: mono ? AppFonts.mono : null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
