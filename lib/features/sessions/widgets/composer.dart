import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../prompt/prompt_actions.dart' show mentionedFiles;
import '../session_manager.dart';
import 'session_style.dart';

String permissionLabel(ClaudePermissionMode? m) => switch (m) {
  null || ClaudePermissionMode.defaultMode => 'perguntar',
  ClaudePermissionMode.acceptEdits => 'aceitar edições',
  ClaudePermissionMode.plan => 'planejar',
  ClaudePermissionMode.auto => 'automático',
  ClaudePermissionMode.dontAsk => 'não perguntar',
  ClaudePermissionMode.skipPermissions => 'sem perguntar nada (perigoso)',
};

/// Modes offered in the UI (plano, Fase 5: default / acceptEdits / plan; the
/// user's opt-in skipPermissions).
const uiPermissionModes = [
  ClaudePermissionMode.defaultMode,
  ClaudePermissionMode.acceptEdits,
  ClaudePermissionMode.plan,
  ClaudePermissionMode.skipPermissions,
];

/// `app_settings` key of the last mode chosen in "Nova sessão".
const lastPermissionModeKey = 'session.permissionMode';

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

/// `@specs/...` mentions of [text] ("Anexar spec" chips).
List<String> attachedSpecs(String text) => [
  for (final f in mentionedFiles([text]))
    if (f.startsWith('specs/')) f,
];

/// [text] with `@path` inserted at [cursor] (a space around it when needed).
({String text, int cursor}) insertMention(
  String text,
  int cursor,
  String path,
) {
  final at = cursor < 0 || cursor > text.length ? text.length : cursor;
  final before = text.substring(0, at);
  final after = text.substring(at);
  final lead = before.isEmpty || before.endsWith(' ') || before.endsWith('\n')
      ? ''
      : ' ';
  final insert = '$lead@$path ';
  final rest = after.startsWith(' ') ? after.substring(1) : after;
  return (text: '$before$insert$rest', cursor: before.length + insert.length);
}

/// [text] without the `@path` mention.
String removeMention(String text, String path) => text
    .replaceAllMapped(
      RegExp('(^|\\s)@${RegExp.escape(path)}(?=\\s|\$)'),
      (m) => m.group(1)!,
    )
    .replaceAll(RegExp(r'  +'), ' ')
    .trimLeft();

class _SessionComposerState extends ConsumerState<SessionComposer> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  void _onText() {
    final specs = attachedSpecs(_text.text);
    if (!_sameList(specs, _chips)) setState(() => _chips = specs);
  }

  List<String> _chips = const [];

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _attach(String path) {
    final sel = _text.selection;
    final r = insertMention(_text.text, sel.isValid ? sel.end : -1, path);
    _text.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.cursor),
    );
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
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
            if (_chips.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _chips)
                    InputChip(
                      key: ValueKey('composer-spec-chip-$p'),
                      label: Text(
                        '@$p',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.text,
                        ),
                      ),
                      backgroundColor: AppColors.surfaceRaised,
                      side: const BorderSide(color: AppColors.border),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () =>
                          _text.text = removeMention(_text.text, p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
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
                const SizedBox(width: 8),
                Flexible(child: _AttachSpecButton(onPick: _attach)),
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

/// "Anexar spec" (pendência da Fase 5): lists the workspace specs and inserts
/// `@specs/<arquivo>` into the message (the CLI attaches `@` mentions).
class _AttachSpecButton extends ConsumerWidget {
  const _AttachSpecButton({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final specs = ws == null
        ? const <Spec>[]
        : ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    return PopupMenuButton<String>(
      key: const ValueKey('composer-attach-spec'),
      tooltip: specs.isEmpty
          ? 'Nenhuma spec registrada (tela Specs)'
          : 'Anexar spec (@specs/…)',
      enabled: specs.isNotEmpty,
      color: AppColors.panel,
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final s in specs)
          PopupMenuItem(
            value: s.path,
            child: Text(
              '${s.code} · ${s.title}',
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
          'Anexar spec',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: specs.isEmpty
                ? AppColors.textMuted
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
