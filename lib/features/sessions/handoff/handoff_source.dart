import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/memory/ai_memory_cli.dart';
import '../../../core/memory/ai_memory_state.dart';
import '../../../core/memory/ai_memory_wiring.dart';
import '../../../core/memory/handoff.dart';
import '../../../core/providers/quota_source.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../project/widgets/ai_memory_view.dart' show aiMemoryWhen;
import '../session_manager.dart';
import '../timeline_provider.dart';
import '../widgets/session_style.dart';
import '../widgets/session_terminal.dart';
import 'continue_controller.dart';
import 'continue_dialog.dart' show PathOption, lastLimit;
import 'continue_link.dart';
import 'handoff_wait.dart';
import 'session_summary.dart' show providerWords;

/// Where the handoff of the dialog stands.
enum HandoffSourceStatus {
  /// Not reported yet.
  none,

  /// ai-memory is not there or not wired in both agents (R7).
  unavailable,

  /// The origin still has a process: ending it writes the handoff (R4.1).
  originAlive,

  /// Asking the origin for a polished handoff (P2).
  polishing,

  /// Ending the origin and waiting up to 10 s (R4.2).
  waiting,

  /// The handoff of the origin (or the one chosen in the Memória, R13).
  found,

  /// Cut without a handoff (R4.3).
  cut,
}

/// What the ai-memory part of the dialog tells it (SPEC-099 R4–R6).
@immutable
class HandoffSourceState {
  const HandoffSourceState({
    required this.status,
    this.installed = false,
    this.reason,
    this.handoff,
    this.owner,
    this.terminalReason,
    this.openTerminal,
    this.polishReason,
    this.polish = false,
    this.onPolish,
    this.targetName = '',
  });

  const HandoffSourceState.none() : this(status: HandoffSourceStatus.none);

  final HandoffSourceStatus status;

  /// ai-memory is connected (else the dialog shows the discreet line).
  final bool installed;

  /// Why the ai-memory handoff is unavailable.
  final String? reason;
  final Handoff? handoff;
  final String? owner;

  /// Why `ai-memory run` is unavailable (null = available).
  final String? terminalReason;

  /// Opens `ai-memory run` in the terminal (R6).
  final Future<void> Function(Session origin)? openTerminal;

  /// P2: why the polished handoff cannot be asked (null = it can).
  final String? polishReason;
  final bool polish;
  final VoidCallback? onPolish;
  final String targetName;

  /// The ai-memory handoff path can be chosen.
  bool get available => installed && reason == null;

  /// "Continuar" can be pressed with the ai-memory path (false while the
  /// origin lives or the wait runs).
  bool get ready =>
      status != HandoffSourceStatus.originAlive &&
      status != HandoffSourceStatus.polishing &&
      status != HandoffSourceStatus.waiting;

  /// The ways to pass the work, in the dialog's order (R3).
  List<PathOption> options({
    required String targetName,
    required String fromName,
  }) => [
    if (installed)
      PathOption(
        title: 'Passagem do ai-memory · recomendado',
        text:
            'O $targetName recebe a passagem ao começar; a mensagem cita o id.',
        path: ContinuePath.aiMemory,
        reason: reason,
      ),
    if (installed)
      PathOption(
        title: 'Terminal com ai-memory run ${targetName.toLowerCase()}',
        text: 'Mais opções · experimental · fora da timeline.',
        path: ContinuePath.terminal,
        reason: terminalReason,
      ),
    PathOption(
      title: 'Resumo do app',
      text: installed
          ? 'Montado pelo app, sem chamar modelo; você edita.'
          : 'Único caminho sem o ai-memory. Montado pelo app, sem chamar '
                'modelo; você edita.',
      path: ContinuePath.summary,
    ),
    if (installed)
      PathOption(
        title: 'Pedir ao ${fromName.split(' ').first} uma passagem caprichada',
        text: '1 turno',
        checkbox: true,
        checked: polish,
        reason: polishReason,
        onToggle: onPolish,
        keyName: 'polish',
      ),
  ];
}

/// The ai-memory part of the dialog (R4–R6, mock 2 and mock 4): finds the
/// handoff of the origin, warns about a concurrent manual one and says when
/// the origin was cut without one. Without ai-memory it shows nothing.
class HandoffSource extends ConsumerStatefulWidget {
  const HandoffSource({
    super.key,
    required this.origin,
    required this.target,
    required this.selected,
    required this.onChanged,
    this.chosen,
  });

  final Session origin;
  final String target;
  final Handoff? chosen;
  final bool selected;
  final ValueChanged<HandoffSourceState> onChanged;

  @override
  ConsumerState<HandoffSource> createState() => _HandoffSourceState();
}

class _HandoffSourceState extends ConsumerState<HandoffSource> {
  HandoffSourceStatus _status = HandoffSourceStatus.none;
  String? _reason;
  String? _terminalReason;
  Handoff? _handoff;
  HandoffList? _list;
  bool _polish = false;
  bool _manualDismissed = false;
  String? _error;
  bool _started = false;

  Session get _o => widget.origin;
  String get _nativeId => _o.externalId ?? _o.id;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<AiMemoryCli?> _cli() => ref.read(aiMemoryCliProvider.future);

  Future<void> _init() async {
    AiMemoryDetection? d;
    try {
      d = await ref.read(aiMemoryDetectionProvider.future);
    } catch (_) {
      d = null;
    }
    if (!mounted) return;
    if (d == null || !d.serverUp) {
      _set(HandoffSourceStatus.unavailable, reason: 'ai-memory não conectado');
      return;
    }
    // R6, SPEC-098 P7: `run` from the minimum version, target installed.
    _terminalReason = d.status == AiMemoryStatus.connected
        ? null
        : 'indisponível: ai-memory abaixo de $aiMemoryMinVersion';
    // R4: hooks in both agents.
    AiMemoryWiring? w;
    try {
      w = await ref.read(aiMemoryWiringProvider.future);
    } catch (_) {
      w = null;
    }
    if (!mounted) return;
    final both =
        w != null &&
        w.claude.hooks == AiMemoryLink.on &&
        w.codex.hooks == AiMemoryLink.on;
    if (!both) {
      _set(
        HandoffSourceStatus.unavailable,
        reason: 'indisponível: hooks do ai-memory não ligados nos dois agentes',
      );
      return;
    }
    if (widget.chosen != null) {
      _handoff = widget.chosen;
      await _read();
      _set(HandoffSourceStatus.found);
      return;
    }
    final alive = ref.read(sessionManagerProvider).isAlive(_o.id);
    if (alive) {
      _set(HandoffSourceStatus.originAlive);
      return;
    }
    await _wait();
  }

  Future<void> _read() async {
    final cli = await _cli();
    if (cli == null) return;
    try {
      _list = HandoffList.parse(
        await cli.call('memory_handoff_list', const {}, cwd: _o.worktreePath),
        workspacePath: ref.read(activeWorkspaceProvider)?.path,
      );
    } on AiMemoryException catch (e) {
      _error = e.message;
    }
  }

  /// R4.1, P2: asks for the polished handoff (optional), ends the origin
  /// and waits for its handoff.
  Future<void> _endAndWait() async {
    if (_started) return;
    _started = true;
    final manager = ref.read(sessionManagerProvider.notifier);
    if (_polish) {
      _set(HandoffSourceStatus.polishing);
      try {
        await manager.send(_o.id, polishedHandoffRequest);
        // The turn ends with its `result` (busy goes back to false).
        final end = DateTime.now().add(const Duration(minutes: 3));
        while (mounted &&
            DateTime.now().isBefore(end) &&
            (ref.read(sessionManagerProvider).live[_o.id]?.busy ?? false)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        _error = '$e';
      }
    }
    if (!mounted) return;
    await ref.read(continueControllerProvider).endOrigin(_o.id);
    await _wait();
  }

  Future<void> _wait() async {
    _set(HandoffSourceStatus.waiting);
    final cli = await _cli();
    if (cli == null || !mounted) return;
    final ws = ref.read(activeWorkspaceProvider)?.path;
    final r = await waitForHandoff(
      nativeId: _nativeId,
      list: () async => HandoffList.parse(
        await cli.call('memory_handoff_list', const {}, cwd: _o.worktreePath),
        workspacePath: ws,
      ),
      finalize: () => cli.finalizeSession(
        agent: aiMemoryAgentKind(_o.provider),
        sessionId: _nativeId,
        cwd: _o.worktreePath,
      ),
    );
    if (!mounted) return;
    _list = r.list;
    _handoff = r.handoff;
    _error = r.error;
    _set(r.handoff != null ? HandoffSourceStatus.found : HandoffSourceStatus.cut);
  }

  Future<void> _discardManual(Handoff h) async {
    final ok = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelSolid,
        title: const Text(
          'Descartar a passagem manual?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'A passagem manual de ${h.agentName} (${aiMemoryWhen(h.createdAt)}) '
          'fica expirada e nenhuma sessão vai recebê-la. A ação não se desfaz.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        actions: [
          SmallButton(
            key: const ValueKey('continue-manual-discard-cancel'),
            label: 'Cancelar',
            onTap: () => Navigator.pop(ctx, false),
          ),
          SmallButton(
            key: const ValueKey('continue-manual-discard-confirm'),
            label: 'Descartar',
            color: AppColors.red,
            border: SessionColors.stopBorder,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cli = await _cli();
    try {
      await cli?.call('memory_handoff_cancel', {
        'handoff_id': h.id,
      }, cwd: _o.worktreePath);
    } on AiMemoryException catch (e) {
      _error = 'Não deu para descartar: ${e.message}.';
    }
    await _read();
    if (mounted) setState(() => _manualDismissed = true);
  }

  Future<void> _openTerminal(Session s) async {
    final ws = ref.read(activeWorkspaceProvider);
    await ref.read(continueControllerProvider).endOrigin(s.id);
    await ref
        .read(sessionTerminalsProvider.notifier)
        .openAiMemoryRun(
          s,
          target: widget.target,
          yolo:
              s.permissionMode == 'bypassPermissions' &&
              ws != null &&
              s.worktreePath != ws.path,
        );
    ref.read(selectedSessionProvider.notifier).select(s.id);
  }

  String? _polishReason() {
    if (_status != HandoffSourceStatus.originAlive) {
      return 'indisponível: a sessão já terminou';
    }
    final limited = lastLimit(
      ref.read(sessionTimelineProvider(_o.id)).timeline.items,
    );
    final quota = ref
        .read(quotaSnapshotProvider(_o.provider))
        ?.limit(DateTime.now());
    if (limited != null || quota != null) return 'indisponível: cota esgotada';
    return null;
  }

  void _set(HandoffSourceStatus status, {String? reason}) {
    if (!mounted) return;
    setState(() {
      _status = status;
      if (reason != null) _reason = reason;
    });
    final installed = status != HandoffSourceStatus.unavailable ||
        (_reason != null && _reason != 'ai-memory não conectado');
    widget.onChanged(
      HandoffSourceState(
        status: status,
        installed: installed,
        reason: status == HandoffSourceStatus.unavailable ? _reason : null,
        handoff: _handoff,
        owner: _handoff == null ? null : _list?.ownerLabel(_handoff!),
        terminalReason: _terminalReason,
        openTerminal: _terminalReason == null ? _openTerminal : null,
        polishReason: _polishReason(),
        polish: _polish,
        onPolish: () {
          setState(() => _polish = !_polish);
          _set(_status);
        },
      ),
    );
  }

  static const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
  static const _section = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    final from = providerWords(_o.provider).split(' ').first;
    final to = providerWords(widget.target);
    Widget line(Widget icon, String bold, String text, {Key? key}) => Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: bold,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: _label,
            ),
          ),
        ],
      ),
    );
    final manual = _manualDismissed
        ? null
        : HandoffWaitResult(handoff: _handoff, list: _list).manualBefore;
    final children = <Widget>[];
    switch (_status) {
      case HandoffSourceStatus.none:
      case HandoffSourceStatus.unavailable:
        break;
      case HandoffSourceStatus.originAlive:
        children.add(
          Container(
            key: const ValueKey('continue-origin-alive'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ReviewColors.acceptBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.call_split, size: 14, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A sessão do $from ainda está aberta. Encerrá-la grava a '
                    'passagem automática, sem chamar modelo.',
                    style: _label,
                  ),
                ),
                SmallButton(
                  key: const ValueKey('continue-end-origin'),
                  label: 'Encerrar e buscar a passagem',
                  color: AppColors.teal,
                  border: ReviewColors.acceptBorder,
                  onTap: _endAndWait,
                ),
              ],
            ),
          ),
        );
      case HandoffSourceStatus.polishing:
        children.add(
          line(
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            'Pedindo a passagem caprichada',
            ' · 1 turno do $from antes de encerrar',
            key: const ValueKey('continue-polishing'),
          ),
        );
      case HandoffSourceStatus.waiting:
        children.add(
          line(
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            'Esperando a passagem',
            ' · encerrando a sessão do $from · até 10 s',
            key: const ValueKey('continue-waiting'),
          ),
        );
      case HandoffSourceStatus.cut:
        children.add(
          line(
            const Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
            'Sem passagem:',
            ' a sessão foi cortada. O $to vai ler o que o ai-memory capturou '
                'dela.',
            key: const ValueKey('continue-cut'),
          ),
        );
      case HandoffSourceStatus.found:
        if (_handoff case final h?) children.add(_handoffBox(h));
    }
    if (manual != null &&
        (_status == HandoffSourceStatus.found ||
            _status == HandoffSourceStatus.cut)) {
      children.add(
        Container(
          key: const ValueKey('continue-manual'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.amber),
            color: AppColors.amber.withValues(alpha: 0.06),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    size: 15,
                    color: AppColors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Há uma passagem manual de '
                      '${aiMemoryWhen(manual.createdAt)} que o ai-memory '
                      'entrega antes desta',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '"${manual.summary}" · ${manual.agentName} · '
                '${_list?.ownerLabel(manual) ?? 'você'}. A mensagem inicial '
                'cita o id certo nos dois casos.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _label,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_list?.canDiscard(manual) ?? true)
                    SmallButton(
                      key: const ValueKey('continue-manual-discard'),
                      label: 'Descartar a manual',
                      color: AppColors.red,
                      border: SessionColors.stopBorder,
                      onTap: () => _discardManual(manual),
                    ),
                  const SizedBox(width: 8),
                  SmallButton(
                    key: const ValueKey('continue-manual-keep'),
                    label: 'Seguir assim',
                    onTap: () => setState(() => _manualDismissed = true),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null &&
        _status != HandoffSourceStatus.unavailable &&
        _status != HandoffSourceStatus.none) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'ai-memory: $_error',
            key: const ValueKey('continue-ai-memory-error'),
            style: const TextStyle(fontSize: 11, color: AppColors.red),
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// The handoff, as plain text (SPEC-098 R13).
  Widget _handoffBox(Handoff h) {
    Widget bullets(String title, List<String> items) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _section),
          const SizedBox(height: 4),
          for (final i in items.take(4))
            Text(
              '• $i',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          if (items.isEmpty)
            const Text('—', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
    return Container(
      key: const ValueKey('continue-handoff'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.selected ? ReviewColors.acceptBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.call_split, size: 14, color: AppColors.teal),
                const SizedBox(width: 8),
                const Text(
                  'Passagem do ai-memory',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${h.manual ? 'manual' : 'automática'} · gravada '
                    '${aiMemoryWhen(h.createdAt)} · dono: '
                    '${_list?.ownerLabel(h) ?? 'você'}',
                    key: const ValueKey('continue-handoff-meta'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _label,
                  ),
                ),
                Tooltip(
                  message: h.id,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      h.shortId,
                      key: const ValueKey('continue-handoff-id'),
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  h.summary.trim().isEmpty ? '(sem resumo)' : h.summary.trim(),
                  key: const ValueKey('continue-handoff-summary'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bullets('PERGUNTAS ABERTAS', h.openQuestions),
                    const SizedBox(width: 12),
                    bullets('PRÓXIMOS PASSOS', h.nextSteps),
                    const SizedBox(width: 12),
                    bullets('ARQUIVOS TOCADOS', h.filesTouched),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// P2: the extra turn of the origin before it ends.
const polishedHandoffRequest =
    'Vamos passar este trabalho para outro agente. Antes de encerrar, grave '
    'uma passagem manual com memory_handoff_begin: um resumo curto (2 a 3 '
    'frases), o que falhou e por quê, as perguntas abertas e os próximos '
    'passos. Não altere arquivos nem rode mais nada.';
