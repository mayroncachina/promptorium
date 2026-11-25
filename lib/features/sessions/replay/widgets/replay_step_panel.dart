import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/agent_event.dart' show NeutralLimits;
import '../../../../core/providers/provider_availability.dart';
import '../../../../ui/theme/tokens.dart';
import '../../../../ui/widgets/diff_view.dart';
import '../../../../ui/widgets/markdown/app_markdown.dart';
import '../../../../ui/widgets/numbered_text_view.dart';
import '../../edit_diff.dart';
import '../../timeline.dart';
import '../../widgets/session_style.dart';
import '../../widgets/tool_expanded_view.dart' show readLines;
import '../file_at_step.dart';
import '../replay_data.dart';
import '../replay_step.dart';
import 'replay_style.dart';

/// The step under the cursor (SPEC-082 R5), and "Arquivo neste ponto" (R7).
class ReplayStepPanel extends ConsumerStatefulWidget {
  const ReplayStepPanel({
    super.key,
    required this.sessionId,
    required this.step,
    required this.steps,
    required this.diffs,
    required this.onOpenInTimeline,
    required this.onSeek,
    required this.onOpenSubagent,
    this.root,
    this.openFileAt,
  });

  final String sessionId;
  final ReplayStep step;

  /// Every top-level step (the text said before an edit, R5).
  final List<ReplayStep> steps;

  /// Edit diffs of the session by `tool_use_id` (SPEC-026).
  final Map<String, EditDiff> diffs;
  final VoidCallback onOpenInTimeline;

  /// Moves the cursor to a top-level step.
  final ValueChanged<int> onSeek;

  /// Opens the subagent's lane at its step [child] (R5, P7).
  final ValueChanged<int?> onOpenSubagent;
  final String? root;

  /// Step whose "Arquivo neste ponto" opens right away ("Quem escreveu?").
  final ReplayStep? openFileAt;

  @override
  ConsumerState<ReplayStepPanel> createState() => _ReplayStepPanelState();
}

class _ReplayStepPanelState extends ConsumerState<ReplayStepPanel> {
  /// "Arquivo neste ponto" open (per step).
  final _fileAt = <ReplayStep>{};

  /// "Ver tudo" of a command's output (per step).
  final _fullOutput = <ReplayStep>{};

  /// "Buscar a saída completa" (SPEC-110 R4), by `tool_use_id`: what came,
  /// or why not. Nothing is stored.
  final _fetched = <String, String>{};
  final _fetchFailed = <String, String>{};
  final _fetching = <String>{};

  Future<void> _fetch(ReplayStep s) async {
    final id = s.tool!.id;
    if (!_fetching.add(id)) return;
    setState(() => _fetchFailed.remove(id));
    try {
      final text = await fetchReplayOutput(ref, widget.sessionId, s);
      if (mounted) setState(() => _fetched[id] = text);
    } catch (e) {
      if (mounted) setState(() => _fetchFailed[id] = '$e');
    } finally {
      _fetching.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.openFileAt != null) _fileAt.add(widget.openFileAt!);
  }

  @override
  void didUpdateWidget(ReplayStepPanel old) {
    super.didUpdateWidget(old);
    final open = widget.openFileAt;
    if (open != null && !identical(open, old.openFileAt)) _fileAt.add(open);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final path = s.filePath;
    final isEdit = s.kind == ReplayKind.edit && path != null;
    final showFile = isEdit && _fileAt.contains(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              ReplayKindBadge(s),
              const SizedBox(width: 8),
              Expanded(child: _title(s)),
              const SizedBox(width: 8),
              if (s.kind == ReplayKind.run) ...[
                _ExitBadge(step: s),
                const SizedBox(width: 6),
              ],
              if (isEdit) ...[
                SmallButton(
                  key: const ValueKey('replay-file-at'),
                  label: showFile
                      ? 'Ver o diff do passo'
                      : 'Arquivo neste ponto',
                  height: 28,
                  onTap: () => setState(
                    () => showFile ? _fileAt.remove(s) : _fileAt.add(s),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              SmallButton(
                key: const ValueKey('replay-open-timeline'),
                label: 'Abrir na Timeline',
                height: 28,
                onTap: widget.onOpenInTimeline,
              ),
            ],
          ),
        ),
        Expanded(
          child: showFile
              ? _FileAtView(
                  key: ValueKey('replay-file-at-${s.tool!.id}'),
                  sessionId: widget.sessionId,
                  step: s,
                  diff: widget.diffs[s.tool!.id],
                )
              : _body(s),
        ),
      ],
    );
  }

  Widget _title(ReplayStep s) {
    final t = s.tool;
    final path = s.filePath;
    final what = s.verb;
    final target = path == null || s.reads.isNotEmpty
        ? (t == null ? '' : s.target)
        : relativePath(path, widget.root);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$what ',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          TextSpan(
            text: target,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (s.added != null)
            TextSpan(
              text: '  ${s.statsLabel}',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          // SPEC-110 R1: what happened to the file; where the read came
          // from.
          if (s.changeLabel ?? s.via case final String extra
              when extra.isNotEmpty)
            TextSpan(
              text: '  · $extra',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
        ],
      ),
      key: const ValueKey('replay-panel-title'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _body(ReplayStep s) {
    final t = s.tool;
    switch (s.kind) {
      case ReplayKind.edit:
        final d = t == null ? null : widget.diffs[t.id];
        return _scroll([
          if (s.outcome == ReplayOutcome.denied)
            const _Note('Edição negada: o arquivo não mudou.')
          else if (s.outcome == ReplayOutcome.error)
            _Note('A edição falhou: ${t?.result ?? ''}', error: true),
          if (d?.section != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Seção: ${d!.section}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          if (d?.unknownBefore ?? false)
            const _Note('Conteúdo anterior desconhecido'),
          if (d != null)
            DiffView(
              key: const ValueKey('replay-edit-diff'),
              rows: d.rows,
              muted: s.outcome == ReplayOutcome.denied,
              collapseSame: 8,
            ),
          ..._saidBefore(s),
        ]);
      case ReplayKind.read:
        return _readBody(s, t!);
      case ReplayKind.run:
        return _runBody(s, t!);
      case ReplayKind.user:
      case ReplayKind.assistant:
        final text = switch (s.item) {
          UserItem(:final text) => text,
          AssistantTextItem(:final text) => text,
          _ => '',
        };
        return _scroll([
          AppMarkdown(key: const ValueKey('replay-text'), data: text),
        ]);
      case ReplayKind.thinking:
        return _scroll([
          SelectableText(
            (s.item as ThinkingItem).text,
            key: const ValueKey('replay-text'),
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          ),
        ]);
      case ReplayKind.subagent:
        return _subagentBody(s, t!);
      case ReplayKind.mark:
        return _scroll([
          SelectableText(
            (s.item as NoticeItem).text,
            key: const ValueKey('replay-text'),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: s.isProblem ? AppColors.red : AppColors.text,
            ),
          ),
        ]);
      case ReplayKind.web:
      case ReplayKind.plan:
      case ReplayKind.other:
        if (t!.other case final o? when (o.text ?? '').isNotEmpty) {
          return _scroll([
            AppMarkdown(key: const ValueKey('replay-text'), data: o.text!),
          ]);
        }
        return _scroll([
          _Label('Entrada'),
          _Mono(const JsonEncoder.withIndent('  ').convert(t.input)),
          const SizedBox(height: 12),
          _Label('Resultado'),
          _Mono(t.result ?? 'sem resposta', error: t.isError),
        ]);
    }
  }

  /// "Antes deste passo o agente disse: …" (the last text before the step).
  List<Widget> _saidBefore(ReplayStep s) {
    if (s.parent != null) return const [];
    for (var i = s.index - 1; i >= 0 && i >= s.index - 8; i--) {
      final p = widget.steps[i];
      if (p.kind == ReplayKind.assistant) {
        return [
          const SizedBox(height: 10),
          Text(
            'Antes deste passo o agente disse: "${p.target}" '
            '(passo ${p.index + 1})',
            key: const ValueKey('replay-said-before'),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ];
      }
      if (p.kind == ReplayKind.user) break;
    }
    return const [];
  }

  Widget _readBody(ReplayStep s, ToolItem t) {
    final input = t.input;
    final result = t.result;
    // SPEC-110 R1: the command that read, and its output.
    if (t.commandEvent != null) return _runBody(s, t);
    if (t.name == 'Read') {
      final offset = input['offset'];
      final limit = input['limit'];
      final range = offset is num || limit is num
          ? 'linhas ${offset ?? 1}–${(offset is num ? offset : 1) + (limit is num ? limit : 0)}'
          : 'arquivo inteiro';
      final lines = result == null ? null : readLines(result);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              range,
              key: const ValueKey('replay-read-range'),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: lines == null
                ? _scroll([_Mono(result ?? 'sem resposta', error: t.isError)])
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: NumberedTextView(
                      key: const ValueKey('replay-read-lines'),
                      lines: lines.lines,
                      numbers: lines.numbers,
                    ),
                  ),
          ),
        ],
      );
    }
    final pattern = input['pattern'] ?? input['path'] ?? '';
    return _scroll([
      _Label('Padrão'),
      _Mono('$pattern'),
      const SizedBox(height: 12),
      _Label('Resultados'),
      _Mono(result ?? 'sem resposta', error: t.isError),
    ]);
  }

  static final _failLine = RegExp(
    r'(FAIL|Error|ERROR|error:|\[E\]|Expected:|Actual:|failed|✗|Some tests failed|Exception)',
  );

  Widget _runBody(ReplayStep s, ToolItem t) {
    final desc = t.input['description'];
    final fetched = _fetched[t.id];
    final out = (fetched ?? t.result ?? '').trimRight();
    final lines = out.isEmpty ? const <String>[] : out.split('\n');
    final full = _fullOutput.contains(s);
    final shown = full || lines.length <= 200
        ? lines
        : lines.sublist(lines.length - 200);
    return _scroll([
      if (desc is String && desc.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Descrição do agente: "$desc"',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      _Mono('\$ ${t.input['command'] ?? ''}'),
      const SizedBox(height: 8),
      // SPEC-110 R1: what the command read (the only thing it does, or
      // along with the rest).
      if (s.reads.isNotEmpty) ...[
        _Label(s.kind == ReplayKind.read ? 'Lido pelo comando' : 'Também leu'),
        for (final (i, r) in s.reads.indexed)
          Padding(
            key: ValueKey('replay-command-read-$i'),
            padding: const EdgeInsets.only(bottom: 2),
            child: _Mono(
              [
                if (r.isFile)
                  [relativePath(r.path, widget.root), ?r.range].join(' ')
                else
                  r.label(widget.root),
                if (r.via.isNotEmpty) r.via,
              ].join(' · '),
            ),
          ),
        const SizedBox(height: 8),
      ],
      Container(
        key: const ValueKey('replay-run-output'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: SessionColors.terminalPanel,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: shown.isEmpty
            ? Text(
                t.done ? '(sem saída)' : 'sem resposta',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              )
            : SelectableText.rich(
                TextSpan(
                  children: [
                    for (final l in shown)
                      TextSpan(
                        text: '$l\n',
                        style: TextStyle(
                          color:
                              s.outcome == ReplayOutcome.error &&
                                  _failLine.hasMatch(l)
                              ? AppColors.red
                              : AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
      ),
      ..._fetchMore(s, t),
      if (lines.length > 200)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SmallButton(
              key: const ValueKey('replay-run-all'),
              label: full
                  ? 'Ver só as últimas 200'
                  : 'Ver as ${lines.length} linhas',
              height: 28,
              onTap: () => setState(
                () => full ? _fullOutput.remove(s) : _fullOutput.add(s),
              ),
            ),
          ),
        ),
    ]);
  }

  /// R4: the stored output is cut or was not stored at all.
  List<Widget> _fetchMore(ReplayStep s, ToolItem t) {
    if (_fetched.containsKey(t.id)) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Saída completa buscada no Codex (não fica guardada).',
            key: ValueKey('replay-output-fetched'),
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ];
    }
    final c = t.commandEvent;
    if (c == null || !replayOutputMissing(c)) return const [];
    final reason = replayFetchBlock(
      s,
      ref.watch(providerAvailabilityProvider('codex')).value,
    );
    final busy = _fetching.contains(t.id);
    final failed = _fetchFailed[t.id];
    final button = SmallButton(
      key: const ValueKey('replay-fetch-output'),
      label: busy ? 'Buscando…' : 'Buscar a saída completa',
      height: 28,
      onTap: reason != null || busy ? null : () => _fetch(s),
    );
    return [
      const SizedBox(height: 8),
      if (c.outputCutLines > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '… ${NeutralLimits.cutLabel(c.outputCutLines, what: 'saída')}',
            key: const ValueKey('replay-output-cut'),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (reason == null)
            button
          else
            Tooltip(message: reason, child: button),
          Text(
            reason ?? 'thread/items/list · sem chamar o modelo',
            key: const ValueKey('replay-fetch-hint'),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
      if (failed != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Não deu para buscar a saída: $failed',
            key: const ValueKey('replay-fetch-failed'),
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ),
    ];
  }

  Widget _subagentBody(ReplayStep s, ToolItem t) {
    final prompt = t.input['prompt'] ?? t.input['description'] ?? '';
    return _scroll([
      _Label('Pedido'),
      AppMarkdown(data: '$prompt'),
      const SizedBox(height: 12),
      _Label('Resultado'),
      AppMarkdown(data: t.result ?? 'sem resposta'),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _Label('${s.children.length} passos do subagente')),
          SmallButton(
            key: const ValueKey('replay-subagent-open'),
            label: 'Abrir na faixa',
            height: 26,
            onTap: () => widget.onOpenSubagent(null),
          ),
        ],
      ),
      const SizedBox(height: 4),
      for (final c in s.children.take(200))
        InkWell(
          key: ValueKey('replay-subagent-step-${c.index}'),
          onTap: () => widget.onOpenSubagent(c.index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    '${s.index + 1}.${c.index + 1}',
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                ReplayKindBadge(c, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    replayStepLabel(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ]);
  }
}

class _ExitBadge extends StatelessWidget {
  const _ExitBadge({required this.step});

  final ReplayStep step;

  static final _exit = RegExp(r'^Exit code (\d+)');

  @override
  Widget build(BuildContext context) {
    final t = step.tool!;
    // SPEC-095 R2: a neutral command brings its exit code.
    final neutral = t.commandEvent?.exitCode;
    final code = neutral != null
        ? '$neutral'
        : _exit.firstMatch(t.result ?? '')?.group(1);
    final error = step.outcome == ReplayOutcome.error;
    final label = !t.done
        ? 'sem resposta'
        : error
        ? 'saída ${code ?? '≠ 0'} · ${formatDurationShort(step.duration)}'
        : 'saída 0 · ${formatDurationShort(step.duration)}';
    final color = error ? AppColors.red : AppColors.teal;
    return Container(
      key: const ValueKey('replay-exit'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: .6,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
    ),
  );
}

class _Mono extends StatelessWidget {
  const _Mono(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => SelectableText(
    text,
    style: TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      height: 1.45,
      color: error ? AppColors.red : AppColors.text,
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key, this.error = false, this.title});

  final String text;
  final String? title;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.red : AppColors.amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        border: Border.all(color: color.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

/// "Arquivo neste ponto" (R7): the whole file right after the step, its
/// lines highlighted; or why it cannot be rebuilt, with the step's diff.
class _FileAtView extends ConsumerWidget {
  const _FileAtView({
    super.key,
    required this.sessionId,
    required this.step,
    required this.diff,
  });

  final String sessionId;
  final ReplayStep step;
  final EditDiff? diff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = ref.watch(replayFileAtProvider((sessionId, step.tool!.id)));
    return at.when(
      loading: () => const Center(
        child: Text(
          'Reconstruindo o arquivo…',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
      error: (e, _) => _failed('$e'),
      data: (r) {
        if (!r.ok) return _failed(r.reason ?? '');
        final lines = displayLines(r.text!);
        final hl = {for (final l in r.highlighted) l - 1};
        final first = hl.isEmpty ? null : hl.reduce((a, b) => a < b ? a : b);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Text(
                'Como estava logo depois do passo ${step.index + 1} · '
                '${lines.length} linhas · base: ${r.base?.label ?? 'o próprio passo'}',
                key: const ValueKey('replay-file-at-info'),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: NumberedTextView(
                  key: const ValueKey('replay-file-at-text'),
                  lines: lines,
                  highlighted: hl,
                  matches: first == null
                      ? const []
                      : [(line: first, start: 0, end: 0)],
                  current: first == null ? null : 0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _failed(String reason) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Note(
          reason,
          title: 'Não dá para reconstruir o arquivo neste ponto.',
          key: const ValueKey('replay-file-at-failed'),
        ),
        if (diff != null) DiffView(rows: diff!.rows, collapseSame: 8),
      ],
    ),
  );
}

/// "Diff final" of a file chosen in "Resultado", with "Quem escreveu?" on
/// each added line (R8, P5).
class ReplayFinalDiffView extends ConsumerStatefulWidget {
  const ReplayFinalDiffView({
    super.key,
    required this.sessionId,
    required this.path,
    required this.steps,
    required this.onGoTo,
    this.root,
  });

  final String sessionId;
  final String path;
  final List<ReplayStep> steps;

  /// Moves the cursor to [step] (top level or inside a subagent);
  /// [showFile] opens "Arquivo neste ponto".
  final void Function(ReplayStep step, {bool showFile}) onGoTo;
  final String? root;

  @override
  ConsumerState<ReplayFinalDiffView> createState() =>
      _ReplayFinalDiffViewState();
}

class _ReplayFinalDiffViewState extends ConsumerState<ReplayFinalDiffView> {
  int? _asked;

  @override
  void didUpdateWidget(ReplayFinalDiffView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _asked = null;
  }

  @override
  Widget build(BuildContext context) {
    final diff = ref.watch(
      replayFinalDiffProvider((widget.sessionId, widget.path)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Diff final  ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                TextSpan(
                  text: relativePath(widget.path, widget.root),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (diff.value != null && diff.value!.error == null)
                  TextSpan(
                    text:
                        '  +${diff.value!.added} −${diff.value!.removed} '
                        '${diff.value!.against ?? ''}',
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
            key: const ValueKey('replay-final-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: diff.when(
            loading: () => const Center(
              child: Text(
                'Carregando o diff…',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            error: (e, _) => Center(child: Text('$e')),
            data: (d) {
              if (d.error != null || d.rows.isEmpty) {
                return Center(
                  child: Text(
                    d.error ?? 'Sem mudanças contra a base.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }
              return ListView.builder(
                key: const ValueKey('replay-final-diff'),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                itemCount: d.rows.length,
                itemBuilder: (context, i) {
                  final r = d.rows[i];
                  final line = _DiffLineRow(
                    key: ValueKey('replay-final-row-$i'),
                    row: r,
                    onAsk: r.op == DiffOp.add
                        ? () => setState(() => _asked = _asked == i ? null : i)
                        : null,
                  );
                  if (_asked != i) return line;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [line, _whoCard(r)],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _whoCard(ReplayDiffRow r) {
    final who = whoWroteLine(
      widget.steps,
      widget.path,
      r.text,
      root: widget.root,
    );
    String label(ReplayStep s) {
      final no = s.parent == null
          ? '${s.index + 1}'
          : '${s.parent!.index + 1}.${s.index + 1}';
      return 'Passo $no · ${replayStepLabel(s)} · T${s.turn} · ${clock(s.at)}';
    }

    final edit = who?.edit;
    final cmd = who?.command;
    String? said;
    if (edit != null && edit.parent == null) {
      for (var i = edit.index - 1; i >= 0 && i >= edit.index - 8; i--) {
        final p = widget.steps[i];
        if (p.kind == ReplayKind.assistant) {
          said = 'Antes, no passo ${p.index + 1}: "${p.target}"';
          break;
        }
      }
    }
    return Container(
      key: const ValueKey('replay-who-card'),
      margin: const EdgeInsets.fromLTRB(40, 4, 0, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SessionColors.selectedBg,
        border: Border.all(color: AppColors.borderHover),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quem escreveu a linha ${r.newNo ?? ''}?',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          if (who == null)
            const Text(
              'Linha em branco: não dá para dizer.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else if (edit != null) ...[
            Text(
              label(edit),
              key: const ValueKey('replay-who-edit'),
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
            if (said != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  said,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                AmberButton(
                  key: const ValueKey('replay-who-go'),
                  label: 'Ir para o passo',
                  onTap: () => widget.onGoTo(edit),
                ),
                SmallButton(
                  key: const ValueKey('replay-who-file'),
                  label: 'Arquivo neste ponto',
                  onTap: () => widget.onGoTo(edit, showFile: true),
                ),
              ],
            ),
          ] else ...[
            Text(
              cmd == null
                  ? 'Nenhuma edição da sessão escreveu esta linha: veio de um '
                        'comando.'
                  : 'Nenhuma edição da sessão escreveu esta linha: veio de um '
                        'comando (${label(cmd)}).',
              key: const ValueKey('replay-who-command'),
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
            if (cmd != null) ...[
              const SizedBox(height: 8),
              AmberButton(
                key: const ValueKey('replay-who-go'),
                label: 'Ir para o comando',
                onTap: () => widget.onGoTo(cmd),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DiffLineRow extends StatefulWidget {
  const _DiffLineRow({super.key, required this.row, this.onAsk});

  final ReplayDiffRow row;
  final VoidCallback? onAsk;

  @override
  State<_DiffLineRow> createState() => _DiffLineRowState();
}

class _DiffLineRowState extends State<_DiffLineRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final (bg, sign, color) = switch (r.op) {
      DiffOp.add => (SessionColors.addBg, '+', AppColors.teal),
      DiffOp.del => (SessionColors.delBg, '-', AppColors.red),
      DiffOp.same => (Colors.transparent, ' ', AppColors.textMuted),
    };
    final row = Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${r.newNo ?? r.oldNo ?? ''}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: ReviewColors.lineNumber,
              ),
            ),
          ),
          SizedBox(
            width: 18,
            child: Text(
              sign,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              r.text,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                height: 1.45,
                color: AppColors.text,
              ),
            ),
          ),
          if (widget.onAsk != null && _hover)
            const Text(
              'Quem escreveu?',
              style: TextStyle(fontSize: 11, color: AppColors.amber),
            ),
        ],
      ),
    );
    if (widget.onAsk == null) return row;
    return Semantics(
      button: true,
      label: 'Quem escreveu a linha ${r.newNo ?? ''}?',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(onTap: widget.onAsk, child: row),
      ),
    );
  }
}
