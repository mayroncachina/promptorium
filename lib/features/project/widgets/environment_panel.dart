import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/process/process_runner.dart';
import '../../../core/system/worktree_launcher.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../environment_check.dart';

/// The "Ambiente" block of the Começar screen (SPEC-072 R1–R4, R15,
/// R20–R22): the hosting indicator (derived from the "Repositório remoto"
/// radio, never clicked), one line per check and the fix next to each red
/// or amber item.
class EnvironmentPanel extends ConsumerStatefulWidget {
  const EnvironmentPanel({
    super.key,
    required this.checker,
    required this.hosting,
    required this.onRecheck,
    required this.onBrowse,
  });

  final EnvironmentChecker checker;
  final Hosting hosting;

  /// "Verificar de novo": every item again.
  final VoidCallback onRecheck;

  /// "Procurar…" of the Pasta item.
  final VoidCallback onBrowse;

  @override
  ConsumerState<EnvironmentPanel> createState() => _EnvironmentPanelState();
}

class _EnvironmentPanelState extends ConsumerState<EnvironmentPanel> {
  final _gitName = TextEditingController();
  final _gitEmail = TextEditingController();
  bool _saving = false;
  String? _saveError;
  String? _terminalError;

  /// Items whose fix opened a terminal: checked again when the window comes
  /// back to focus (R3).
  final _awaiting = <EnvKind>{};
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _gitName.dispose();
    _gitEmail.dispose();
    super.dispose();
  }

  void _onResume() {
    if (_awaiting.isEmpty) return;
    widget.checker.recheck({..._awaiting});
    _awaiting.clear();
  }

  Future<void> _saveIdentity() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.checker.saveIdentity(_gitName.text, _gitEmail.text);
    } catch (e) {
      if (mounted) setState(() => _saveError = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _terminal(EnvKind kind, String command) async {
    setState(() => _terminalError = null);
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final used = await ref
        .read(worktreeLauncherProvider)
        .terminal(home, command);
    if (!mounted) return;
    if (used == null) {
      setState(
        () => _terminalError =
            'Nenhum terminal encontrado. Rode no terminal: $command',
      );
      return;
    }
    _awaiting.add(kind);
  }

  Future<void> _open(String url) async {
    try {
      await ref.read(processRunnerProvider)('xdg-open', [url]);
    } catch (e) {
      debugPrint('xdg-open $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.checker,
    builder: (context, _) => Column(
      key: const ValueKey('env-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('AMBIENTE', style: sectionTitleStyle)),
            TextButton.icon(
              key: const ValueKey('env-recheck'),
              onPressed: widget.onRecheck,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amber,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text(
                'Verificar de novo',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _HostingIndicator(hosting: widget.hosting),
        if (widget.hosting == Hosting.unknown)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Hospedagem não reconhecida: PR e MR pelo app indisponíveis.',
              key: ValueKey('env-hosting-unknown'),
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        const SizedBox(height: 8),
        for (final item in widget.checker.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ItemCard(item: item, fix: _fix(item)),
          ),
      ],
    ),
  );

  Widget? _fix(EnvItem item) {
    final children = <Widget>[];
    switch (item.problem) {
      case EnvProblem.gitIdentity:
        children.add(_identityFix());
      case EnvProblem.gitMissing:
        children.add(
          const _Hint(
            'Instale o git (sudo apt install git) e verifique de '
            'novo.',
          ),
        );
      case EnvProblem.claudeMissing || EnvProblem.claudeIncompatible:
        children.add(
          SmallButton(
            key: const ValueKey('env-claude-install'),
            label: 'Instalar o Claude Code',
            onTap: () => _open(item.installUrl ?? claudeInstallUrl),
          ),
        );
      case EnvProblem.hostMissing:
        final cli = item.title.contains('glab') ? 'glab' : 'gh';
        children.add(
          SmallButton(
            key: const ValueKey('env-host-install'),
            label: 'Instale o $cli',
            onTap: item.installUrl == null
                ? null
                : () => _open(item.installUrl!),
          ),
        );
      case EnvProblem.claudeLogin || EnvProblem.hostLogin:
        final command = item.command!;
        final short = command.split(' --').first;
        children.add(
          SmallButton(
            key: ValueKey('env-${item.kind.name}-terminal'),
            label: 'Abrir terminal com $short',
            onTap: () => _terminal(item.kind, command),
          ),
        );
        if (_terminalError case final e?) children.add(_Hint(e));
      case EnvProblem.folderMissing ||
          EnvProblem.folderNotWritable ||
          EnvProblem.folderBusy ||
          EnvProblem.folderBadName:
        children.add(
          SmallButton(
            key: const ValueKey('env-folder-browse'),
            label: 'Procurar…',
            onTap: widget.onBrowse,
          ),
        );
      case EnvProblem.hostOther:
        if (item.installUrl case final url?) {
          children.add(
            SmallButton(
              key: const ValueKey('env-host-install'),
              label: 'Ver a instalação',
              onTap: () => _open(url),
            ),
          );
        }
      case EnvProblem.timeout || null:
        break;
    }
    if (item.note case final note?) children.add(_Hint(note));
    if (children.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in children)
          Padding(padding: const EdgeInsets.only(top: 6), child: c),
      ],
    );
  }

  Widget _identityFix() {
    InputDecoration field(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: const OutlineInputBorder(),
    );
    const label = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11,
      color: AppColors.textSecondary,
    );
    final ready =
        !_saving &&
        _gitName.text.trim().isNotEmpty &&
        _gitEmail.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nome', style: label),
                  const SizedBox(height: 4),
                  Semantics(
                    label: 'Nome para o git',
                    textField: true,
                    child: TextField(
                      key: const ValueKey('env-git-name'),
                      controller: _gitName,
                      style: const TextStyle(fontSize: 12),
                      decoration: field('Seu Nome'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('E-mail', style: label),
                  const SizedBox(height: 4),
                  Semantics(
                    label: 'E-mail para o git',
                    textField: true,
                    child: TextField(
                      key: const ValueKey('env-git-email'),
                      controller: _gitEmail,
                      style: const TextStyle(fontSize: 12),
                      decoration: field('voce@exemplo.com'),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (ready) _saveIdentity();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SmallButton(
              key: const ValueKey('env-git-save'),
              label: _saving ? 'Gravando…' : 'Gravar no git',
              onTap: ready ? _saveIdentity : null,
            ),
            const Text('ou, no terminal:', style: label),
          ],
        ),
        const SizedBox(height: 6),
        SelectableText(
          'git config --global user.name "${_gitName.text.trim().isEmpty ? 'Seu Nome' : _gitName.text.trim()}"\n'
          'git config --global user.email "${_gitEmail.text.trim().isEmpty ? 'voce@exemplo.com' : _gitEmail.text.trim()}"',
          key: const ValueKey('env-git-commands'),
          style: mono,
        ),
        if (_saveError case final e?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              e,
              key: const ValueKey('env-git-error'),
              style: const TextStyle(fontSize: 11, color: AppColors.red),
            ),
          ),
      ],
    );
  }
}

/// GitHub · GitLab · Local, marked from the remote (R20). Text, not only
/// color (R15); not clickable.
class _HostingIndicator extends StatelessWidget {
  const _HostingIndicator({required this.hosting});

  final Hosting hosting;

  @override
  Widget build(BuildContext context) {
    final detected = switch (hosting) {
      Hosting.github || Hosting.gitlab || Hosting.local => hosting.label,
      Hosting.unknown => 'não reconhecida',
      Hosting.pending => 'aguardando a URL do remoto',
    };
    return Semantics(
      key: const ValueKey('env-hosting'),
      label: 'Hospedagem detectada pelo remoto: $detected',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text.rich(
                TextSpan(
                  text: 'Hospedagem\n',
                  style: TextStyle(fontSize: 12, color: AppColors.text),
                  children: [
                    TextSpan(
                      text: 'pelo remoto',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    for (final h in const [
                      Hosting.github,
                      Hosting.gitlab,
                      Hosting.local,
                    ])
                      Expanded(
                        child: Container(
                          key: ValueKey('env-hosting-${h.name}'),
                          height: 26,
                          alignment: Alignment.center,
                          decoration: h == hosting
                              ? BoxDecoration(
                                  color: AppColors.amberTint,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.amber),
                                )
                              : null,
                          child: Text(
                            h.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: h == hosting
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: h == hosting
                                  ? AppColors.amber
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.fix});

  final EnvItem item;
  final Widget? fix;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (item.state) {
      EnvState.ok => (AppColors.teal, Icons.check_circle_outline),
      EnvState.blocked => (AppColors.red, Icons.cancel_outlined),
      EnvState.warning => (AppColors.amber, Icons.error_outline),
      EnvState.checking => (AppColors.textMuted, Icons.more_horiz),
    };
    final open =
        item.state == EnvState.blocked || item.state == EnvState.warning;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        item.state.word.toUpperCase(),
        key: ValueKey('env-${item.kind.name}-state'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
    final title = Text(
      item.title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    final line = Text(
      item.line,
      key: ValueKey('env-${item.kind.name}-line'),
      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
    );
    return Semantics(
      key: ValueKey('env-${item.kind.name}'),
      container: true,
      liveRegion: true,
      label: item.semantics,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: open ? color.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: open ? color.withValues(alpha: 0.55) : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: item.state == EnvState.checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      )
                    : Icon(icon, size: 16, color: color),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: open
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [title, line],
                          )
                        : Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [title, line],
                          ),
                  ),
                  ?fix,
                ],
              ),
            ),
            const SizedBox(width: 6),
            ExcludeSemantics(child: badge),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
  );
}
