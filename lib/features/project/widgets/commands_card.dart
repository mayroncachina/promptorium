import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_config.dart';
import '../project_plan.dart';
import '../stack_commands.dart';

/// The "Comandos" block (SPEC-072 R12): one line per command of the stack,
/// with the config.yml key next to it. A command the config.yml already has
/// shows that value, read-only ("já existe"); the others are editable,
/// marked "novo" or, when empty, "não se aplica".
class CommandsCard extends StatefulWidget {
  const CommandsCard({
    super.key,
    required this.commands,
    this.existing = const ProjectConfig(),
    this.onChanged,
    this.onDetect,
    this.detectLabel,
    this.compact = false,
  });

  final StackCommands commands;

  /// The config.yml of the workspace (nothing in the "Outro…" modal).
  final ProjectConfig existing;

  /// An edit; null = read-only.
  final void Function(String key, String value)? onChanged;

  /// "Detectar do repositório" (R14): null hides it. Returns the file read
  /// ("pubspec.yaml"), or null when nothing was found.
  final Future<String?> Function()? onDetect;

  /// The manifest found, shown on the button's tooltip.
  final String? detectLabel;

  /// Without the title row and the footnote (inside the modal's preview).
  final bool compact;

  @override
  State<CommandsCard> createState() => _CommandsCardState();
}

class _CommandsCardState extends State<CommandsCard> {
  final _controllers = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  String? _readFrom;

  @override
  void initState() {
    super.initState();
    for (final k in StackCommands.keys) {
      _controllers[k] = TextEditingController(text: widget.commands[k]);
      _focus[k] = FocusNode();
    }
  }

  @override
  void didUpdateWidget(CommandsCard old) {
    super.didUpdateWidget(old);
    for (final k in StackCommands.keys) {
      final c = _controllers[k]!;
      // An outside change (a new proposal, the detection) replaces the text
      // unless the field is being edited.
      if (!_focus[k]!.hasFocus && c.text != widget.commands[k]) {
        c.text = widget.commands[k];
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _detect() async {
    final from = await widget.onDetect!();
    if (mounted) setState(() => _readFrom = from);
  }

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.textSecondary,
    );
    final rows = [for (final k in StackCommands.keys) _row(k, mono)];
    if (widget.compact) {
      return Column(
        key: const ValueKey('commands-card'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }
    return Container(
      key: const ValueKey('commands-card'),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: SessionColors.approvalBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Comandos',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'vão para o ',
                    children: [
                      TextSpan(
                        text: '.promptorium/config.yml',
                        style: TextStyle(fontFamily: AppFonts.mono),
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              if (widget.onDetect != null)
                Tooltip(
                  message: widget.detectLabel == null
                      ? 'Lê o manifesto da pasta e preenche só as linhas vazias'
                      : 'Lê o ${widget.detectLabel} e preenche só as linhas '
                            'vazias',
                  child: SmallButton(
                    key: const ValueKey('commands-detect'),
                    label: 'Detectar do repositório',
                    onTap: widget.onChanged == null ? null : _detect,
                  ),
                ),
            ],
          ),
          if (_readFrom != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'lido de $_readFrom: só as linhas vazias foram preenchidas',
                key: const ValueKey('commands-detected'),
                style: const TextStyle(fontSize: 11, color: AppColors.teal),
              ),
            ),
          const SizedBox(height: 10),
          ...rows,
          const SizedBox(height: 4),
          const Text(
            '"já existe": o config.yml já tem a chave, e ela fica como está. '
            'Só as chaves vazias são preenchidas.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, TextStyle mono) {
    final existing = configCommand(widget.existing, k);
    final locked = existing != null;
    final value = locked ? existing : widget.commands[k];
    final (badge, color, lock) = locked
        ? ('já existe', AppColors.textSecondary, true)
        : value.trim().isEmpty
        ? ('não se aplica', AppColors.textMuted, false)
        : ('novo', AppColors.teal, false);
    final label = StackCommands.labels[k]!;
    final key = StackCommands.configKeys[k]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          SizedBox(width: 130, child: Text(key, style: mono)),
          Expanded(
            child: Semantics(
              label: '$label ($key)',
              textField: true,
              child: locked
                  ? Container(
                      key: ValueKey('commands-$k'),
                      height: 34,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono,
                      ),
                    )
                  : TextField(
                      key: ValueKey('commands-$k'),
                      controller: _controllers[k],
                      focusNode: _focus[k],
                      enabled: widget.onChanged != null,
                      style: mono.copyWith(color: AppColors.text),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'vazio: não entra no config.yml',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => widget.onChanged?.call(k, v),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (lock) ...[
                        Icon(Icons.lock_outline, size: 10, color: color),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        badge,
                        key: ValueKey('commands-$k-badge'),
                        style: TextStyle(fontSize: 10, color: color),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
