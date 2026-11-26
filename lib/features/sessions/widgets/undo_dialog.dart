import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_service.dart' show TreeChangeKind;
import '../../../data/providers.dart';
import '../../../ui/providers/provider_logos.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../conversation_events.dart';
import '../restore/restore_service.dart';
import '../session_changes.dart';
import '../session_manager.dart';
import 'session_style.dart';

/// What the person chose in the [UndoDialog].
typedef UndoChoice = ({
  Set<String> paths,
  bool filesOnly,

  /// The agent's conversation goes back too (SPEC-110 R7).
  bool revertConversation,
});

/// The window of "Desfazer o último turno" / "Voltar a antes deste turno…"
/// / "Refazer" (SPEC-084 R6, R7, R12, R16): what goes back, what the person
/// changed after the turn (unchecked), the commits thrown away and what
/// does not come back. Nothing changes until the main button.
class UndoDialog extends StatefulWidget {
  const UndoDialog({
    super.key,
    required this.point,
    required this.plan,
    required this.onConfirm,
    this.redo = false,
    this.latest = true,
    this.busy = false,
    this.onStop,
    this.onDiff,
  });

  final RestorePoint point;

  /// Worked out by [RestoreService.plan] / [RestoreService.redoPlan].
  final Future<UndoPlan> plan;

  /// Applies the choice; an error is shown in the window.
  final Future<void> Function(UndoChoice choice) onConfirm;
  final bool redo;

  /// [point] is the newest turn ("Desfazer o turno 4?"); otherwise the
  /// window goes back to before it and every turn after it.
  final bool latest;

  /// The session is in a turn (P3): only "Parar e desfazer".
  final bool busy;
  final Future<UndoPlan> Function()? onStop;

  /// Diff of one file of the turn ("Ver diff", P7).
  final Future<String> Function(String path)? onDiff;

  @override
  State<UndoDialog> createState() => _UndoDialogState();
}

class _UndoDialogState extends State<UndoDialog> {
  late Future<UndoPlan> _plan = widget.plan;
  UndoPlan? _loaded;
  Set<String>? _selected;
  late bool _busy = widget.busy;
  bool _working = false;
  bool _showAll = false;
  bool _showDiff = false;
  String? _error;

  /// "Voltar também a conversa" (SPEC-110 R7, P2: checked).
  bool _conversation = true;

  bool _revertsConversation(UndoPlan plan) =>
      !widget.redo && _conversation && (plan.conversation?.available ?? false);

  @override
  void initState() {
    super.initState();
    _watch(_plan);
  }

  void _watch(Future<UndoPlan> f) {
    f.then(
      (p) {
        if (!mounted) return;
        setState(() {
          _loaded = p;
          _selected = p.defaultSelection;
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      },
    );
  }

  Future<void> _stop() async {
    final stop = widget.onStop;
    if (stop == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final next = stop();
      setState(() {
        _plan = next;
        _loaded = null;
      });
      _watch(next);
      await next;
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirm(UndoPlan plan) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.onConfirm((
        paths: {...?_selected},
        filesOnly: plan.filesOnly,
        revertConversation: _revertsConversation(plan),
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _working = false;
        });
      }
    }
  }

  String get _title {
    final t = widget.point.turn;
    if (widget.redo) return 'Refazer o turno $t?';
    return widget.latest
        ? 'Desfazer o turno $t?'
        : 'Voltar a antes do turno $t?';
  }

  String get _subtitle {
    final p = widget.point;
    final prompt = p.prompt.isEmpty
        ? ''
        : ', antes de “${p.prompt.length > 48 ? '${p.prompt.substring(0, 48)}…' : p.prompt}”';
    if (widget.redo) {
      return 'Os arquivos voltam ao que eram antes de você desfazer o turno '
          '${p.turn}.';
    }
    return 'Os arquivos voltam ao que eram às ${formatClock(p.startedAt)}$prompt.';
  }

  @override
  Widget build(BuildContext context) {
    final plan = _loaded;
    return Dialog(
      key: const ValueKey('undo-dialog'),
      backgroundColor: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: plan == null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: _error == null
                              ? const Text(
                                  'Calculando o que volta…',
                                  key: ValueKey('undo-loading'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : Text(
                                  _error!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.red,
                                  ),
                                ),
                        ),
                      )
                    : SingleChildScrollView(child: _body(plan)),
              ),
              if (plan != null && _error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const ValueKey('undo-error'),
                  style: const TextStyle(fontSize: 12, color: AppColors.red),
                ),
              ],
              const SizedBox(height: 14),
              _actions(plan),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(UndoPlan? plan) {
    final n = _selected?.length ?? 0;
    final commits = plan == null || plan.filesOnly ? 0 : plan.commits.length;
    // SPEC-110 R7: what the agent forgets is in the button.
    final back = plan != null && _revertsConversation(plan);
    final c = plan?.conversation;
    final turns = c == null
        ? ''
        : '${c.lastTurn > c.firstTurn ? 'os' : 'o'} '
              '${turnsLabel(c.firstTurn, c.lastTurn)} da conversa';
    final String label;
    if (plan != null && plan.filesOnly && !widget.redo) {
      label = back
          ? 'Desfazer os arquivos e $turns'
          : 'Desfazer só os arquivos';
    } else {
      final verb = widget.redo ? 'Refazer' : 'Desfazer';
      final files = '$n arquivo${n == 1 ? '' : 's'}';
      final parts = [
        if (n > 0 || (commits == 0 && !back)) files,
        if (commits > 0) '$commits commit${commits == 1 ? '' : 's'}',
        if (back) turns,
      ];
      label = parts.length == 1
          ? '$verb ${parts.single}'
          : '$verb ${parts.sublist(0, parts.length - 1).join(', ')} e '
                '${parts.last}';
    }
    final canGo =
        plan != null &&
        !_working &&
        !_busy &&
        (n > 0 || commits > 0 || back || (widget.redo && c?.copyAt != null));
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SmallButton(
          key: const ValueKey('undo-cancel'),
          label: 'Cancelar',
          height: 34,
          onTap: _working ? null : () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 8),
        if (_busy && widget.onStop != null)
          SmallButton(
            key: const ValueKey('undo-stop'),
            label: 'Parar e desfazer',
            icon: Icons.stop_rounded,
            height: 34,
            color: AppColors.onAmber,
            border: AppColors.amber,
            background: AppColors.amber,
            fontWeight: FontWeight.w600,
            onTap: _working ? null : _stop,
          )
        else
          // A long label (files, commits and turns) shrinks before it overflows.
          Flexible(
            child: SmallButton(
              key: const ValueKey('undo-confirm'),
              label: _working ? 'Aplicando…' : label,
              icon: widget.redo ? Icons.redo_rounded : Icons.undo_rounded,
              height: 34,
              color: AppColors.onAmber,
              border: AppColors.amber,
              background: AppColors.amber,
              fontWeight: FontWeight.w600,
              onTap: canGo ? () => _confirm(plan) : null,
            ),
          ),
      ],
    );
  }

  Widget _body(UndoPlan plan) {
    const max = 8;
    // Created and deleted files first: they are the surprises.
    int rank(UndoFile f) => f.kind == TreeChangeKind.modified ? 1 : 0;
    final restore = [...plan.restore]
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    final shown = _showAll || restore.length <= max
        ? restore
        : restore.take(max - 1).toList();
    final hidden = restore.length - shown.length;
    final lostEdits = [
      for (final f in plan.changedAfter)
        if (_selected?.contains(f.path) ?? false) f.path,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.filesOnly && !widget.redo) ...[
          _Callout(
            key: const ValueKey('undo-pushed'),
            color: AppColors.amber,
            icon: Icons.warning_amber_rounded,
            text: _pushedText(plan),
          ),
          const SizedBox(height: 12),
        ],
        if (_busy) ...[
          const _Callout(
            key: ValueKey('undo-busy'),
            color: AppColors.amber,
            icon: Icons.hourglass_top_rounded,
            text:
                'A sessão está no meio de um turno: o agente estaria escrevendo '
                'nos mesmos arquivos. Pare a sessão para desfazer.',
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                'ARQUIVOS QUE VOLTAM · ${restore.length}',
                style: sectionTitleStyle,
              ),
            ),
            if (widget.onDiff != null && restore.isNotEmpty)
              InkWell(
                key: const ValueKey('undo-diff-toggle'),
                onTap: () => setState(() => _showDiff = !_showDiff),
                child: Text(
                  _showDiff ? 'Ocultar diff' : 'Ver diff',
                  style: const TextStyle(fontSize: 12, color: AppColors.teal),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (restore.isEmpty)
          const Text(
            'Nenhum arquivo mudou neste turno.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else
          _Box(
            children: [
              for (final f in shown) _fileRow(f),
              if (hidden > 0)
                InkWell(
                  key: const ValueKey('undo-show-all'),
                  onTap: () => setState(() => _showAll = true),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(36, 6, 0, 4),
                    child: Text(
                      '+ $hidden arquivo${hidden == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (plan.changedAfter.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'VOCÊ MUDOU DEPOIS DO TURNO · ${plan.changedAfter.length}',
            style: sectionTitleStyle,
          ),
          const SizedBox(height: 8),
          _Box(
            highlight: true,
            children: [for (final f in plan.changedAfter) _fileRow(f)],
          ),
          if (lostEdits.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'A sua edição em ${lostEdits.join(', ')} se perde.',
              key: const ValueKey('undo-lost-edit'),
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ],
        ],
        if (plan.commits.isNotEmpty || plan.notRestored.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (plan.commits.isNotEmpty) Expanded(child: _commits(plan)),
              if (plan.commits.isNotEmpty && plan.notRestored.isNotEmpty)
                const SizedBox(width: 16),
              if (plan.notRestored.isNotEmpty)
                Expanded(child: _notRestored(plan)),
            ],
          ),
        ],
        for (final o in plan.others)
          if (o.files.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Callout(
              key: ValueKey('undo-other-${o.title}'),
              color: AppColors.amber,
              icon: Icons.warning_amber_rounded,
              text:
                  'A sessão ${o.title} também está mexendo neste diretório; '
                  'os arquivos dela podem voltar junto: ${o.files.join(', ')}.',
            ),
          ],
        if (plan.conversation case final c?) ...[
          const SizedBox(height: 14),
          _conversationSection(c),
        ],
        if (!widget.redo) ...[
          const SizedBox(height: 12),
          _Callout(
            key: const ValueKey('undo-kept'),
            color: AppColors.teal,
            icon: Icons.history_rounded,
            text: _keptText(plan),
          ),
        ],
      ],
    );
  }

  /// "Conversa do agente" (SPEC-110 R7, R9).
  Widget _conversationSection(ConversationPlan c) {
    final on = c.available;
    const muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final head = Row(
      children: [
        const Expanded(
          child: Text('CONVERSA DO AGENTE', style: sectionTitleStyle),
        ),
        ProviderChip(
          c.provider,
          key: const ValueKey('undo-conversation-agent'),
          dense: true,
        ),
      ],
    );
    if (widget.redo) {
      return Column(
        key: const ValueKey('undo-conversation'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          const SizedBox(height: 8),
          Text(
            c.copyAt == null
                ? (c.reason ?? '')
                : 'A sessão volta para a cópia da conversa de '
                      '${formatClock(c.copyAt)}: o ${c.agent} lembra de novo '
                      '${c.lastTurn > c.firstTurn ? 'dos' : 'do'} '
                      '${turnsLabel(c.firstTurn, c.lastTurn)}.',
            key: const ValueKey('undo-conversation-redo'),
            style: muted,
          ),
        ],
      );
    }
    final label = on
        ? 'Voltar também a conversa do ${c.agent} para antes do turno '
              '${c.firstTurn}'
        : 'Voltar também a conversa';
    final many = c.lastTurn > c.firstTurn;
    final effect =
        'O ${c.agent} esquece ${many ? 'os' : 'o'} '
        '${turnsLabel(c.firstTurn, c.lastTurn)}. A timeline do app continua '
        'mostrando ${many ? 'os turnos, marcados como revertidos' : 'o turno, marcado como revertido'}.';
    final why = c.onlyCodex ? 'Só Codex: ${c.reason}' : (c.reason ?? '');
    final checked = on && _conversation;
    final toggle = on && !_working
        ? () => setState(() => _conversation = !_conversation)
        : null;
    Widget box = Semantics(
      key: const ValueKey('undo-conversation-box'),
      container: true,
      checked: checked,
      enabled: on,
      label: on ? '$label. $effect' : '$label. $why',
      onTap: toggle,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('undo-conversation-toggle'),
        onTap: toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  key: const ValueKey('undo-conversation-check'),
                  value: checked,
                  activeColor: AppColors.amber,
                  checkColor: AppColors.onAmber,
                  side: const BorderSide(color: AppColors.inputBorder),
                  onChanged: toggle == null ? null : (_) => toggle(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: on ? AppColors.text : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      on ? effect : why,
                      key: const ValueKey('undo-conversation-text'),
                      style: muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!on) box = Tooltip(message: why, child: box);
    return Column(
      key: const ValueKey('undo-conversation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        const SizedBox(height: 8),
        _Box(
          children: [
            box,
            if (checked)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 2, 4, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 14,
                      color: AppColors.teal,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Antes de reverter, o app guarda uma cópia da '
                        'conversa (thread/fork) para o Refazer. Não chama o '
                        'modelo.',
                        key: ValueKey('undo-conversation-copy'),
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _pushedText(UndoPlan plan) {
    final n = plan.pushedCommits.length;
    final where = plan.remotes.isEmpty ? 'o remoto' : plan.remotes.first;
    final keep = plan.commits.map((c) => c.shortSha).join(', ');
    return '$n commit${n == 1 ? ' já foi enviado' : 's já foram enviados'} '
        'para $where. Desfazer reescreveria a branch, e o próximo push '
        'precisaria de --force. ${plan.commits.length == 1 ? 'O commit' : 'Os commits'} '
        '$keep ${plan.commits.length == 1 ? 'fica' : 'ficam'}; os arquivos '
        'marcados voltam ao que eram antes do turno, como alterações não '
        'commitadas.';
  }

  String _keptText(UndoPlan plan) {
    final kept = plan.kept;
    final head = kept.isEmpty
        ? ''
        : kept.length == 1
        ? '${kept.first} não mudou neste turno e fica como está. '
        : '${kept.first} e mais ${kept.length - 1} não mudaram neste turno e '
              'ficam como estão. ';
    return '${head}Antes de desfazer, o app grava o estado atual: dá para '
        'refazer.';
  }

  Widget _commits(UndoPlan plan) {
    final title = widget.redo
        ? 'COMMITS QUE VOLTAM · ${plan.commits.length}'
        : plan.filesOnly
        ? 'COMMITS QUE FICAM · ${plan.commits.length}'
        : 'COMMIT${plan.commits.length == 1 ? '' : 'S'} DESCARTADO${plan.commits.length == 1 ? '' : 'S'} · ${plan.commits.length}';
    final local = plan.commits.every((c) => !c.pushed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: sectionTitleStyle),
        const SizedBox(height: 8),
        for (final c in plan.commits.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: c.shortSha,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      color: AppColors.amber,
                    ),
                  ),
                  TextSpan(text: '  ${c.subject}'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
        if (plan.commits.length > 5)
          Text(
            '+ ${plan.commits.length - 5}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        if (!widget.redo && !plan.filesOnly)
          Text(
            [
              if (local) 'só local',
              '${plan.startBranch ?? 'HEAD'} volta para '
                  '${plan.startHead.length > 7 ? plan.startHead.substring(0, 7) : plan.startHead}',
              if (plan.branchChanged)
                'a branch ${plan.currentBranch ?? '(destacada)'} fica onde está',
            ].join(' · '),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _notRestored(UndoPlan plan) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('NÃO VOLTA', style: sectionTitleStyle),
      const SizedBox(height: 8),
      for (final n in plan.notRestored)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: n.path,
                  style: const TextStyle(fontFamily: AppFonts.mono),
                ),
                TextSpan(
                  text: ' · ${n.reason}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
        ),
    ],
  );

  Widget _fileRow(UndoFile f) {
    final checked = _selected?.contains(f.path) ?? false;
    final (letter, color) = switch (f.kind) {
      TreeChangeKind.modified => ('M', AppColors.amber),
      TreeChangeKind.created => ('A', AppColors.teal),
      TreeChangeKind.deleted => ('D', AppColors.red),
    };
    final String detail;
    if (f.userAfter) {
      detail = f.editedAt == null
          ? 'editado por você depois · fica'
          : 'editado por você às ${formatClock(f.editedAt)} · fica';
    } else if (f.kind == TreeChangeKind.created) {
      detail = widget.redo ? 'volta' : 'criado no turno · será apagado';
    } else if (f.kind == TreeChangeKind.deleted) {
      detail = widget.redo ? 'será apagado' : 'apagado no turno · volta';
    } else if (f.added == null) {
      detail = 'binário';
    } else {
      detail = '+${f.added} −${f.removed}';
    }
    final row = InkWell(
      key: ValueKey('undo-file-${f.path}'),
      onTap: _working
          ? null
          : () => setState(() {
              final s = {...?_selected};
              checked ? s.remove(f.path) : s.add(f.path);
              _selected = s;
            }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                key: ValueKey('undo-check-${f.path}'),
                value: checked,
                activeColor: AppColors.amber,
                checkColor: AppColors.onAmber,
                side: const BorderSide(color: AppColors.inputBorder),
                onChanged: _working
                    ? null
                    : (v) => setState(() {
                        final s = {...?_selected};
                        v == true ? s.add(f.path) : s.remove(f.path);
                        _selected = s;
                      }),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 14,
              child: Text(
                letter,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                f.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.text,
                ),
              ),
            ),
            if (f.userDuring) ...[
              const SizedBox(width: 8),
              const _Badge('você também editou durante o turno'),
            ],
            if (f.otherSessions.isNotEmpty) ...[
              const SizedBox(width: 8),
              _Badge('também de ${f.otherSessions.first}'),
            ],
            const SizedBox(width: 10),
            Text(
              detail,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
    if (!_showDiff || widget.onDiff == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        _FileDiff(load: () => widget.onDiff!(f.path)),
      ],
    );
  }
}

class _FileDiff extends StatefulWidget {
  const _FileDiff({required this.load});

  final Future<String> Function() load;

  @override
  State<_FileDiff> createState() => _FileDiffState();
}

class _FileDiffState extends State<_FileDiff> {
  late final Future<String> _diff = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _diff,
    builder: (context, snap) {
      final text = snap.hasError ? '${snap.error}' : (snap.data ?? '…').trim();
      final lines = text.split('\n').take(40).toList();
      return Container(
        margin: const EdgeInsets.fromLTRB(36, 2, 4, 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: SessionColors.terminalPanel,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Text(
                l,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: l.startsWith('+') && !l.startsWith('+++')
                      ? AppColors.teal
                      : l.startsWith('-') && !l.startsWith('---')
                      ? AppColors.red
                      : AppColors.textSecondary,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.children, this.highlight = false});

  final List<Widget> children;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: highlight ? SessionColors.approvalBg : AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: highlight ? SessionColors.approvalBorder : AppColors.border,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.lilac),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: AppColors.lilac),
    ),
  );
}

class _Callout extends StatelessWidget {
  const _Callout({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
        ),
      ],
    ),
  );
}

// --- wiring -------------------------------------------------------------------

/// Opens the [UndoDialog] for [point] of [session] and applies the choice
/// (R5, R8, R9, R10, R11). [redo] = "Refazer".
Future<void> openUndoDialog(
  BuildContext context,
  WidgetRef ref, {
  required Session session,
  required RestorePoint point,
  bool redo = false,
}) async {
  final restore = ref.read(restoreServiceProvider);
  final manager = ref.read(sessionManagerProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final points = ref.read(sessionRestorePointsProvider(session.id)).value;
  final latest =
      points == null ||
      points
          .where((p) => p.state != RestoreState.undone)
          .every((p) => p.turn <= point.turn);
  // R16: other live sessions in the same folder.
  final live = ref.read(sessionManagerProvider).live;
  final all = ref.read(sessionsProvider(session.workspaceId)).value ?? const [];
  final others = <String, String>{
    for (final s in all)
      if (s.id != session.id &&
          s.worktreePath == session.worktreePath &&
          (live[s.id]?.alive ?? false))
        s.id: sessionTitle(s),
  };
  bool busy() =>
      ref.read(sessionManagerProvider).live[session.id]?.busy ?? false;
  final current = await ref.read(restorePointsRepoProvider).byId(point.id);
  if (current == null || !context.mounted) return;
  final start = current.endSha ?? current.startSha;
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (_) => UndoDialog(
      point: current,
      redo: redo,
      latest: latest,
      busy: !redo && busy(),
      plan: redo
          ? restore.redoPlan(current)
          : restore.plan(current, otherLive: others),
      onStop: () async {
        await manager.stop(session.id);
        final until = DateTime.now().add(const Duration(seconds: 15));
        while (busy() && DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final fresh = await ref.read(restorePointsRepoProvider).byId(point.id);
        return restore.plan(fresh ?? current, otherLive: others);
      },
      onDiff: (path) => redo
          ? restore.diff(
              current.worktreePath,
              current.undoneSha ?? start,
              current.undoSha ?? start,
              path,
            )
          : restore.diff(current.worktreePath, current.startSha, start, path),
      onConfirm: (choice) async {
        final fresh =
            await ref.read(restorePointsRepoProvider).byId(point.id) ?? current;
        if (redo) {
          await restore.redoTurn(fresh, choice.paths);
        } else {
          await restore.undoTurn(
            fresh,
            choice.paths,
            filesOnly: choice.filesOnly,
            revertConversation: choice.revertConversation,
          );
        }
        ref.invalidate(sessionChangesProvider(session.id));
      },
    ),
  );
  if (ok != true || redo || messenger == null) return;
  // R11: "Turno 4 desfeito. Refazer" for 10 s.
  messenger
    ..hideCurrentSnackBar()
    ..showAppToast(
      SnackBar(
        key: const ValueKey('undo-toast'),
        duration: const Duration(seconds: 10),
        // With an action a SnackBar stays by default; this one leaves (R11).
        persist: false,
        content: Text('Turno ${current.turn} desfeito.'),
        action: SnackBarAction(
          label: 'Refazer',
          textColor: AppColors.amber,
          onPressed: () {
            if (!context.mounted) return;
            unawaited(
              openUndoDialog(
                context,
                ref,
                session: session,
                point: current,
                redo: true,
              ),
            );
          },
        ),
      ),
    );
}

/// The newest point of [points] that can be undone (R5): not undone.
RestorePoint? lastUndoable(List<RestorePoint> points) =>
    points.where((p) => p.state != RestoreState.undone).firstOrNull;

/// "Desfazer o último turno" in the session header (R5, P2, P3).
class UndoLastTurnButton extends ConsumerWidget {
  const UndoLastTurnButton({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points =
        ref.watch(sessionRestorePointsProvider(session.id)).value ??
        const <RestorePoint>[];
    final target = lastUndoable(points);
    if (target == null) return const SizedBox.shrink();
    final busy = ref.watch(
      sessionManagerProvider.select((s) => s.live[session.id]?.busy ?? false),
    );
    return Tooltip(
      message: busy
          ? 'Espere o turno terminar ou pare a sessão'
          : 'Volta os arquivos e commits ao que eram antes do turno '
                '${target.turn} (${formatClock(target.startedAt)})',
      child: SmallButton(
        key: const ValueKey('session-undo-turn'),
        label: 'Desfazer o último turno',
        icon: Icons.undo_rounded,
        color: AppColors.amber,
        border: SessionColors.approvalBorder,
        background: AppColors.amberTint,
        onTap: busy
            ? null
            : () =>
                  openUndoDialog(context, ref, session: session, point: target),
      ),
    );
  }
}
