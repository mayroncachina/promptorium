import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/diff_parser.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../session_changes.dart';

const _mono = TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 12,
  color: AppColors.text,
  height: 1.4,
);

/// "Diff" tab: `git diff HEAD` of the worktree (simple; Review is Fase 9).
class SessionDiffView extends ConsumerWidget {
  const SessionDiffView({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changes = ref.watch(sessionChangesProvider(sessionId));
    return changes.when(
      loading: () => const Center(child: Text('Carregando diff…')),
      error: (e, _) => Center(child: Text('$e')),
      data: (c) {
        if (c.error != null) return Center(child: Text(c.error!, style: _mono));
        final untracked = c.entries.where((e) => e.isUntracked).toList();
        final rows = <Widget Function()>[];
        for (final f in c.files) {
          rows.add(() => _FileHeader(f));
          if (f.isBinary) {
            rows.add(
              () => const Padding(
                padding: EdgeInsets.all(8),
                child: Text('(binário)', style: _mono),
              ),
            );
          }
          for (final h in f.hunks) {
            rows.add(
              () => Container(
                color: AppColors.surfaceRaised,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  h.header,
                  style: _mono.copyWith(color: AppColors.blue),
                ),
              ),
            );
            for (final l in h.lines) {
              rows.add(() => _Line(l));
            }
          }
        }
        for (final u in untracked) {
          rows.add(
            () => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${u.path}  (novo, não rastreado)',
                style: _mono.copyWith(color: AppColors.teal),
              ),
            ),
          );
        }
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'Nenhuma alteração no worktree.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Row(
                children: [
                  Text(
                    '${c.count} arquivo(s) alterado(s) · git diff HEAD',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(sessionChangesProvider(sessionId)),
                    child: const Text(
                      'Atualizar',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: rows.length,
                itemBuilder: (_, i) => rows[i](),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FileHeader extends StatelessWidget {
  const _FileHeader(this.file);

  final DiffFile file;

  @override
  Widget build(BuildContext context) {
    final add = file.hunks.fold(0, (n, h) => n + h.additions);
    final del = file.hunks.fold(0, (n, h) => n + h.deletions);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              file.path,
              style: _mono.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Text('+$add', style: _mono.copyWith(color: AppColors.teal)),
          const SizedBox(width: 8),
          Text('−$del', style: _mono.copyWith(color: AppColors.red)),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.line);

  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    final (bg, sign, color) = switch (line.kind) {
      DiffLineKind.add => (SessionColors.addBg, '+', AppColors.teal),
      DiffLineKind.del => (SessionColors.delBg, '-', AppColors.red),
      DiffLineKind.context => (
        Colors.transparent,
        ' ',
        AppColors.textSecondary,
      ),
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '$sign ${line.text}',
        softWrap: false,
        overflow: TextOverflow.fade,
        style: _mono.copyWith(color: color),
      ),
    );
  }
}

/// "Log bruto" tab: `session_events` rows (raw stream-json).
class RawLogView extends ConsumerWidget {
  const RawLogView({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(sessionEventsProvider(sessionId)).value ?? const [];
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum evento gravado.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      key: ValueKey('raw-log-$sessionId'),
      reverse: true,
      padding: const EdgeInsets.all(20),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[rows.length - 1 - i];
        return _RawRow(seq: r.seq, type: r.type, json: r.json);
      },
    );
  }
}

class _RawRow extends StatefulWidget {
  const _RawRow({required this.seq, required this.type, required this.json});

  final int seq;
  final String type;
  final String json;

  @override
  State<_RawRow> createState() => _RawRowState();
}

class _RawRowState extends State<_RawRow> {
  bool _open = false;

  String get _pretty {
    try {
      return const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(widget.json));
    } catch (_) {
      return widget.json;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _open
            ? SelectableText(
                '#${widget.seq} ${widget.type}\n$_pretty',
                style: _mono.copyWith(fontSize: 11),
              )
            : Text(
                '#${widget.seq.toString().padRight(4)} '
                '${widget.type.padRight(22)} ${widget.json}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
      ),
    );
  }
}
