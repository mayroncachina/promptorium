import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../ui/theme/tokens.dart';
import '../session_manager.dart';
import 'session_style.dart';

String permissionLabel(ClaudePermissionMode? m) => switch (m) {
  null || ClaudePermissionMode.defaultMode => 'perguntar',
  ClaudePermissionMode.acceptEdits => 'aceitar edições',
  ClaudePermissionMode.plan => 'planejar',
  ClaudePermissionMode.auto => 'automático',
  ClaudePermissionMode.dontAsk => 'não perguntar',
};

/// Modes offered in the UI (plano, Fase 5: default / acceptEdits / plan).
const uiPermissionModes = [
  ClaudePermissionMode.defaultMode,
  ClaudePermissionMode.acceptEdits,
  ClaudePermissionMode.plan,
];

/// Message box under the timeline. Sends with `ClaudeProcess.send`; a
/// session without a live process is resumed first (`--resume`).
class SessionComposer extends ConsumerStatefulWidget {
  const SessionComposer({
    super.key,
    required this.sessionId,
    required this.permissionMode,
    this.canSend,
  });

  final String sessionId;
  final String? permissionMode;

  /// Returns an error message when sending is not allowed right now.
  final String? Function()? canSend;

  @override
  ConsumerState<SessionComposer> createState() => _SessionComposerState();
}

class _SessionComposerState extends ConsumerState<SessionComposer> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final msg = _text.text.trim();
    if (msg.isEmpty || _busy) return;
    final blocked = widget.canSend?.call();
    if (blocked != null) {
      _snack(blocked);
      return;
    }
    setState(() => _busy = true);
    try {
      _text.clear();
      await ref
          .read(sessionManagerProvider.notifier)
          .send(widget.sessionId, msg);
    } catch (e) {
      if (_text.text.isEmpty) _text.text = msg;
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ClaudePermissionMode.fromCli(widget.permissionMode);
    final alive = ref.watch(
      sessionManagerProvider.select((s) => s.isAlive(widget.sessionId)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SessionColors.selectedBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _send,
              },
              child: TextField(
                key: const ValueKey('composer-field'),
                controller: _text,
                minLines: 2,
                maxLines: 6,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                decoration: const InputDecoration.collapsed(
                  hintText:
                      'Envie uma mensagem para a sessão…  (Ctrl+Enter envia)',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: PopupMenuButton<ClaudePermissionMode>(
                    tooltip: alive
                        ? 'Vale na próxima vez que a sessão for retomada'
                        : 'Modo de permissão ao retomar',
                    color: AppColors.panel,
                    onSelected: (m) => ref
                        .read(sessionManagerProvider.notifier)
                        .setPermissionMode(widget.sessionId, m),
                    itemBuilder: (_) => [
                      for (final m in uiPermissionModes)
                        PopupMenuItem(
                          value: m,
                          child: Text(
                            permissionLabel(m),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Permissão: ${permissionLabel(mode)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: alive
                      ? const SizedBox()
                      : const Text(
                          'retoma a sessão ao enviar',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                AmberButton(
                  key: const ValueKey('composer-send'),
                  label: _busy ? 'Enviando…' : 'Enviar',
                  onTap: _busy ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
