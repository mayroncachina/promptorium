import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../core/claude/claude_cli.dart';
import '../../../core/claude/run_prefs.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/shell_intents.dart';
import '../../../ui/theme/tokens.dart';
import '../session_manager.dart';
import 'session_style.dart';

/// Interactive `claude --resume <id>` in a PTY (xterm + flutter_pty, wiring
/// copied from xterm-4.0.0/example/lib/main.dart).
class SessionTerminal {
  SessionTerminal(this.sessionId);

  /// Session id (Sessões) or worktree path (Código).
  final String sessionId;
  final terminal = Terminal(maxLines: 10000);
  final controller = TerminalController();
  Pty? pty;
  bool running = false;

  void start({
    required String executable,
    required List<String> args,
    required String cwd,
    required VoidCallback onExit,
    Map<String, String>? environment,
  }) {
    final p = Pty.start(
      executable,
      arguments: args,
      workingDirectory: cwd,
      environment: environment,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );
    pty = p;
    running = true;
    p.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(terminal.write);
    p.exitCode.then((code) {
      running = false;
      terminal.write('\r\n[processo encerrado com código $code]\r\n');
      onExit();
    });
    terminal.onOutput = (data) => p.write(const Utf8Encoder().convert(data));
    terminal.onResize = (w, h, pw, ph) => p.resize(h, w);
  }

  void kill() {
    if (running) pty?.kill();
  }
}

/// Terminals by session id (kept while switching tabs / sessions).
class SessionTerminals extends Notifier<Map<String, SessionTerminal>> {
  /// Mirror of [state] (state cannot be read inside `onDispose`).
  final Map<String, SessionTerminal> _all = {};

  @override
  Map<String, SessionTerminal> build() {
    ref.onDispose(() {
      for (final t in _all.values) {
        t.kill();
      }
    });
    return const {};
  }

  @override
  set state(Map<String, SessionTerminal> value) {
    _all
      ..clear()
      ..addAll(value);
    super.state = value;
  }

  bool isRunning(String id) => state[id]?.running ?? false;

  /// Starts `claude --resume <id>` interactively in the session worktree.
  void open(Session s) {
    final existing = state[s.id];
    if (existing != null && existing.running) return;
    final t = SessionTerminal(s.id);
    final model = s.model == 'inherit' || s.model.isEmpty ? null : s.model;
    final prefs = ref.read(runPrefsProvider);
    final effort = effortArg(s.effort ?? prefs.effort(RunKind.session));
    t.start(
      executable: ref.read(claudeExecutableProvider),
      args: [
        '--resume',
        s.id,
        if (model != null) ...['--model', model],
        if (effort != null) ...['--effort', effort],
        '--autocompact',
        prefs.autocompact,
        if (s.agentName != null) ...['--agent', s.agentName!],
        if (s.permissionMode != null) ...[
          '--permission-mode',
          s.permissionMode!,
        ],
      ],
      cwd: s.worktreePath,
      environment: switch (ref.read(worktreeEnvProvider)[s.worktreePath]) {
        final env? => {...Platform.environment, ...env},
        null => null,
      },
      onExit: () {
        if (ref.mounted) state = {...state};
      },
    );
    state = {...state, s.id: t};
  }

  /// App closing: kills every PTY (`claude` interactive processes).
  void killAll() {
    for (final t in _all.values) {
      t.kill();
    }
  }

  void close(String id) {
    state[id]?.kill();
    state = {...state}..remove(id);
  }
}

final sessionTerminalsProvider =
    NotifierProvider<SessionTerminals, Map<String, SessionTerminal>>(
      SessionTerminals.new,
    );

const _terminalTheme = TerminalTheme(
  cursor: AppColors.amber,
  selection: SessionColors.terminalSelection,
  foreground: AppColors.text,
  background: AppColors.background,
  black: AppColors.panel,
  red: AppColors.red,
  green: AppColors.teal,
  yellow: AppColors.amber,
  blue: AppColors.blue,
  magenta: AppColors.lilac,
  cyan: AppColors.bubble,
  white: AppColors.text,
  brightBlack: AppColors.textMuted,
  brightRed: AppColors.red,
  brightGreen: AppColors.teal,
  brightYellow: AppColors.amber,
  brightBlue: AppColors.blue,
  brightMagenta: AppColors.lilac,
  brightCyan: AppColors.glowText,
  brightWhite: Colors.white,
  searchHitBackground: SessionColors.approvalBorder,
  searchHitBackgroundCurrent: AppColors.amber,
  searchHitForeground: AppColors.background,
);

/// "Terminal" tab.
class SessionTerminalView extends ConsumerWidget {
  const SessionTerminalView({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = ref.watch(sessionTerminalsProvider)[session.id];
    final alive = ref.watch(
      sessionManagerProvider.select((s) => s.isAlive(session.id)),
    );
    if (term == null || (!term.running && alive)) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                alive
                    ? 'A sessão está rodando em modo headless. Para usá-la no '
                          'terminal interativo (claude --resume), pare-a antes '
                          '— dois processos na mesma sessão conflitam.'
                    : 'Abre o Claude Code interativo nesta sessão '
                          '(claude --resume) no worktree.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              AmberButton(
                key: const ValueKey('terminal-open'),
                label: alive ? 'Parar e abrir no terminal' : 'Abrir terminal',
                onTap: () async {
                  if (alive) {
                    await ref
                        .read(sessionManagerProvider.notifier)
                        .stop(session.id);
                  }
                  ref.read(sessionTerminalsProvider.notifier).open(session);
                },
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Dot(term.running ? AppColors.teal : AppColors.textMuted, size: 6),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'claude --resume ${session.id} · ${session.worktreePath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (term.running)
                SmallButton(
                  label: 'Encerrar',
                  height: 24,
                  fontSize: 11,
                  onTap: () => ref
                      .read(sessionTerminalsProvider.notifier)
                      .close(session.id),
                )
              else
                SmallButton(
                  label: 'Reabrir',
                  height: 24,
                  fontSize: 11,
                  onTap: () =>
                      ref.read(sessionTerminalsProvider.notifier).open(session),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: AppTerminalView(term: term),
          ),
        ),
      ],
    );
  }
}

/// xterm view of a [SessionTerminal] with the app theme; right click copies
/// the selection or pastes (Sessões and Código, Fase 10).
class AppTerminalView extends StatelessWidget {
  const AppTerminalView({
    super.key,
    required this.term,
    this.autofocus = true,
    this.fontSize = 13,
  });

  final SessionTerminal term;
  final bool autofocus;
  final double fontSize;

  /// F1 opens "Sobre" (R14): xterm would otherwise turn it into an escape
  /// sequence for the PTY. Other function keys still go to the PTY.
  static KeyEventResult _aboutKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.f1 ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final context = node.context;
    if (event is KeyDownEvent && context != null) {
      Actions.maybeInvoke(context, const OpenAboutIntent());
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => TerminalView(
    term.terminal,
    controller: term.controller,
    autofocus: autofocus,
    onKeyEvent: _aboutKey,
    theme: _terminalTheme,
    textStyle: TerminalStyle(fontFamily: AppFonts.mono, fontSize: fontSize),
    onSecondaryTapDown: (details, offset) async {
      final selection = term.controller.selection;
      if (selection != null) {
        final text = term.terminal.buffer.getText(selection);
        term.controller.clearSelection();
        await Clipboard.setData(ClipboardData(text: text));
      } else {
        final data = await Clipboard.getData('text/plain');
        final text = data?.text;
        if (text != null) term.terminal.paste(text);
      }
    },
  );
}
