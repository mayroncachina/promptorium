import 'package:flutter/material.dart';

import '../../../../ui/theme/tokens.dart';
import '../../../context/context_snapshot.dart' show contextTokens;
import '../../edit_diff.dart';
import '../replay_data.dart';
import '../replay_state.dart';
import '../replay_step.dart';
import 'replay_style.dart';

/// Side of the replay: "Neste ponto" (R6) and "Resultado" (R8).
class ReplaySidePanel extends StatelessWidget {
  const ReplaySidePanel({
    super.key,
    required this.state,
    required this.steps,
    required this.current,
    required this.results,
    required this.tab,
    required this.onTab,
    required this.onFile,
    required this.onSeek,
    this.file,
    this.root,
    this.visibleCount = 0,
  });

  final ReplayState state;
  final List<ReplayStep> steps;
  final int current;
  final List<ReplayResultFile> results;

  /// 0 = "Neste ponto", 1 = "Resultado".
  final int tab;
  final ValueChanged<int> onTab;
  final ValueChanged<String?> onFile;
  final ValueChanged<int> onSeek;
  final String? file;
  final String? root;

  /// Steps that touched [file].
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _Tab(
                key: const ValueKey('replay-side-now'),
                label: 'Neste ponto',
                on: tab == 0,
                onTap: () => onTab(0),
              ),
              _Tab(
                key: const ValueKey('replay-side-result'),
                label: 'Resultado · ${results.length}',
                on: tab == 1,
                onTap: () => onTab(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            children: tab == 0 ? _now() : _result(),
          ),
        ),
      ],
    );
  }

  List<Widget> _now() {
    final s = state;
    final cmd = s.lastCommand;
    final errors = [
      for (final x in steps)
        if (x.isProblem) x,
    ];
    return [
      const _Head('Já leu'),
      if (s.read.isEmpty) const _Muted('nada ainda'),
      for (final f in s.read)
        _Line(
          key: ValueKey('replay-read-${baseName(f.path)}'),
          left: baseName(f.path),
          right: '×${f.reads}',
          tip: relativePath(f.path, root),
        ),
      const _Head('Já editou'),
      if (s.edited.isEmpty) const _Muted('nada ainda'),
      for (final f in s.edited)
        _Line(
          key: ValueKey('replay-edited-${baseName(f.path)}'),
          left: baseName(f.path),
          tip: relativePath(f.path, root),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+${f.added} ',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11.5,
                  color: AppColors.teal,
                ),
              ),
              Text(
                '−${f.removed}',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11.5,
                  color: AppColors.red,
                ),
              ),
              if (f.editedWithoutRead) ...[
                const SizedBox(width: 6),
                Container(
                  key: const ValueKey('replay-blind-edit'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.amber),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'editou sem ler',
                    style: TextStyle(fontSize: 10, color: AppColors.amber),
                  ),
                ),
              ],
            ],
          ),
        ),
      const _Head('Último comando'),
      if (cmd == null)
        const _Muted('nenhum ainda')
      else
        _Line(
          key: const ValueKey('replay-last-command'),
          left:
              '${cmd.outcome == ReplayOutcome.error ? '×' : '✓'} ${cmd.target}',
          leftColor: cmd.outcome == ReplayOutcome.error
              ? AppColors.red
              : AppColors.text,
          right: 'há ${current - cmd.index} passos',
          onTap: () => onSeek(cmd.index),
        ),
      if (errors.isNotEmpty) ...[
        const _Head('Erros da sessão'),
        for (final e in errors.take(30))
          _Line(
            key: ValueKey('replay-error-${e.index}'),
            left:
                '${e.outcome == ReplayOutcome.denied ? '–' : '×'} ${e.index + 1} '
                '${replayStepLabel(e)}',
            leftColor: AppColors.textSecondary,
            onTap: () => onSeek(e.index),
          ),
      ],
      const _Head('Contexto'),
      // SPEC-087 R6: the reading of this point, not the session's now.
      _Line(
        key: const ValueKey('replay-context'),
        left: s.compactedSince
            ? 'compactado · aguardando medição'
            : s.contextTokens == null
            ? '–'
            : s.capacity == null
            ? '${contextTokens(s.contextTokens!)} · limite desconhecido'
            : '${contextTokens(s.contextTokens!)} de '
                  '${contextTokens(s.capacity!)} · '
                  '${(s.contextTokens! * 100 / s.capacity!).round()}%',
        right: s.compactions == 1
            ? '1 compactação'
            : '${s.compactions} compactações',
      ),
    ];
  }

  List<Widget> _result() {
    if (results.isEmpty) {
      return const [_Muted('A sessão não editou nenhum arquivo.')];
    }
    final chosen = file;
    final out = <Widget>[
      const Text(
        'Arquivos alterados pela sessão. Escolha um para ver só os passos que '
        'o tocaram.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      for (final f in results)
        _ResultRow(
          key: ValueKey('replay-result-${baseName(f.path)}'),
          file: f,
          root: root,
          on: f.path == chosen,
          onTap: () => onFile(f.path == chosen ? null : f.path),
        ),
    ];
    if (chosen != null) {
      final key = absolutePath(chosen, root);
      var reads = 0, edits = 0;
      int? first;
      for (final s in flattenSteps(steps)) {
        final p = s.filePath;
        if (p == null || absolutePath(p, root) != key) continue;
        if (s.toolName == 'Read') reads++;
        if (s.isAppliedEdit) {
          edits++;
          first ??= (s.parent ?? s).index;
        }
      }
      out.addAll([
        _Head('${baseName(chosen)} na sessão'),
        _Line(left: 'lido', right: '$reads vezes'),
        _Line(left: 'editado', right: '$edits vezes'),
        if (first != null)
          _Line(left: 'primeira edição', right: 'passo ${first + 1}'),
        const SizedBox(height: 8),
        _Muted(
          '← → andam só pelos $visibleCount passos do arquivo enquanto o '
          'filtro estiver ligado.',
        ),
      ]);
    }
    return out;
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: on ? SessionColors.selectedBg : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? AppColors.text : AppColors.textSecondary,
          ),
        ),
      ),
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 10.5,
        letterSpacing: .6,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
  );
}

class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.left,
    this.right,
    this.trailing,
    this.leftColor = AppColors.text,
    this.onTap,
    this.tip,
  });

  final String left;
  final String? right;
  final Widget? trailing;
  final Color leftColor;
  final VoidCallback? onTap;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11.5,
                color: leftColor,
              ),
            ),
          ),
          if (right != null)
            Text(
              right!,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ?trailing,
        ],
      ),
    );
    if (tip != null) row = Tooltip(message: tip!, child: row);
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.file,
    required this.on,
    required this.onTap,
    this.root,
  });

  final ReplayResultFile file;
  final bool on;
  final VoidCallback onTap;
  final String? root;

  @override
  Widget build(BuildContext context) {
    final rel = relativePath(file.path, root);
    final parts = rel.split('/');
    final short = parts.length > 2
        ? parts.sublist(parts.length - 2).join('/')
        : rel;
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.amberTint : null,
            border: Border.all(
              color: on ? AppColors.amber : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Tooltip(
            message: rel,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    short,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.5,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Text(
                  file.added < 0 ? 'binário ' : '+${file.added} ',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11.5,
                    color: AppColors.teal,
                  ),
                ),
                Text(
                  file.removed < 0 ? '' : '−${file.removed}',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11.5,
                    color: AppColors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
