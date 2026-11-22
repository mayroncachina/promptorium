import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/memory/ai_memory_cli.dart';
import '../../../core/memory/ai_memory_state.dart';
import '../../../core/memory/handoff.dart';
import '../../../data/providers.dart';
import '../../../ui/providers/provider_logos.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../sessions/handoff/handoff_from_memory.dart'
    show handoffContinueAction;
import '../../sessions/widgets/session_style.dart';
import '../../settings/ai_memory_view.dart';

/// What the ai-memory section of a project shows (SPEC-098 R8–R12): the
/// handoffs, the briefing, or the error of reading them (R14).
@immutable
class AiMemoryPanelData {
  const AiMemoryPanelData({
    this.handoffs,
    this.briefing,
    this.error,
    this.timedOut = false,
  });

  final HandoffList? handoffs;
  final MemoryBriefing? briefing;
  final String? error;
  final bool timedOut;
}

/// Reads the project's handoffs (`memory_handoff_list`, without claiming)
/// and briefing in the workspace folder. Read when the section opens, on
/// "Atualizar" and when a session of the project ends — never on a timer
/// (R14). Failures become [AiMemoryPanelData.error].
final aiMemoryPanelProvider = FutureProvider.autoDispose
    .family<AiMemoryPanelData, String>((ref, workspacePath) async {
      final cli = await ref.watch(aiMemoryCliProvider.future);
      if (cli == null) {
        return const AiMemoryPanelData(error: 'o ai-memory não foi encontrado');
      }
      try {
        final results = await Future.wait([
          cli.call('memory_handoff_list', const {}, cwd: workspacePath),
          cli.call('memory_briefing', const {}, cwd: workspacePath),
        ]);
        return AiMemoryPanelData(
          handoffs: HandoffList.parse(results[0], workspacePath: workspacePath),
          briefing: MemoryBriefing.parse(results[1]),
        );
      } on AiMemoryException catch (e) {
        return AiMemoryPanelData(error: e.message, timedOut: e.timedOut);
      }
    });

/// "Continuar em…" of a handoff (SPEC-099 R13): opens "Continuar no …" with
/// that handoff chosen. Null hides the button.
@immutable
class HandoffContinueAction {
  const HandoffContinueAction({required this.label, required this.run});

  /// "Continuar no Codex" (by the handoff's origin).
  final String Function(Handoff handoff) label;
  final Future<void> Function(BuildContext context, Handoff handoff) run;
}

final handoffContinueActionProvider = Provider<HandoffContinueAction?>(
  (ref) => handoffContinueAction,
);

/// "hoje 11:41", "ontem 09:15", "18/11 10:00".
String aiMemoryWhen(DateTime? t, {DateTime? now}) {
  if (t == null) return 'sem data';
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'hoje $hm';
  if (diff == 1) return 'ontem $hm';
  return '${two(t.day)}/${two(t.month)} $hm';
}

/// Project → Memória → ai-memory (R8–R13, mock 1).
class AiMemoryPanel extends ConsumerStatefulWidget {
  const AiMemoryPanel({super.key, required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<AiMemoryPanel> createState() => _AiMemoryPanelState();
}

class _AiMemoryPanelState extends ConsumerState<AiMemoryPanel> {
  bool _history = false;
  final _expanded = <String>{};
  String? _actionError;

  /// The web UI answered (null = not asked yet).
  bool? _web;

  String get _path => widget.workspace.path;

  void _refresh() {
    setState(() => _actionError = null);
    ref.invalidate(aiMemoryPanelProvider(_path));
  }

  Future<void> _discard(Handoff h) async {
    final ok = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelSolid,
        title: const Text(
          'Descartar a passagem?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'A passagem de ${h.agentName} (${aiMemoryWhen(h.createdAt)}) fica '
          'expirada e nenhuma sessão vai recebê-la. A ação não se desfaz.',
          key: const ValueKey('ai-memory-discard-text'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        actions: [
          SmallButton(
            key: const ValueKey('ai-memory-discard-cancel'),
            label: 'Cancelar',
            onTap: () => Navigator.pop(ctx, false),
          ),
          SmallButton(
            key: const ValueKey('ai-memory-discard-confirm'),
            label: 'Descartar',
            color: AppColors.red,
            border: SessionColors.stopBorder,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cli = await ref.read(aiMemoryCliProvider.future);
    if (cli == null) return;
    try {
      final r = await cli.call('memory_handoff_cancel', {
        'handoff_id': h.id,
      }, cwd: _path);
      if (r is Map && r['cancelled'] == false) {
        setState(
          () => _actionError =
              'A passagem já não estava aberta (${r['state'] ?? 'outro estado'}).',
        );
      }
    } on AiMemoryException catch (e) {
      setState(() => _actionError = 'Não deu para descartar: ${e.message}.');
    }
    ref.invalidate(aiMemoryPanelProvider(_path));
  }

  /// R12: the web UI page when the server runs it, else the folder (or
  /// file) inside the wiki.
  Future<void> _openWiki(MemoryBriefing b, {String? page}) async {
    final d = ref.read(aiMemoryDetectionProvider).value;
    final open = ref.read(aiMemoryOpenerProvider);
    final ws = b.workspace, proj = b.project;
    if (d == null || ws == null || proj == null) return;
    final base =
        '${d.serverUrl}/web/w/${Uri.encodeComponent(ws)}/'
        '${Uri.encodeComponent(proj)}';
    if (_web == null) {
      final code = await ref.read(aiMemoryHttpProbeProvider)(
        Uri.parse(base),
        aiMemoryCallTimeout,
      );
      // 2xx/3xx, or a login page: the web UI is there.
      _web = code != null && (code < 400 || code == 401 || code == 403);
    }
    if (_web!) {
      await open(page == null ? base : '$base/p/$page');
      return;
    }
    final cli = await ref.read(aiMemoryCliProvider.future);
    final status = await cli?.status();
    final dataDir = status?['data_dir'];
    if (dataDir is! String) {
      if (mounted) {
        setState(
          () => _actionError =
              'Não deu para achar a pasta do wiki (ai-memory status).',
        );
      }
      return;
    }
    final folder = p.join(dataDir, 'wiki', ws, proj);
    await open(page == null ? folder : p.join(folder, page));
  }

  @override
  Widget build(BuildContext context) {
    final detection = ref.watch(aiMemoryDetectionProvider).value;
    // R14: a session of the project that ends refreshes the section.
    ref.listen(sessionsProvider(widget.workspace.id), (prev, next) {
      final before = {for (final s in prev?.value ?? const []) s.id: s.status};
      final ended = (next.value ?? const []).any(
        (s) =>
            (before[s.id] == SessionStatus.running ||
                before[s.id] == SessionStatus.waitingApproval) &&
            s.status != SessionStatus.running &&
            s.status != SessionStatus.waitingApproval,
      );
      if (ended) ref.invalidate(aiMemoryPanelProvider(_path));
    });
    if (detection == null) return const SizedBox.shrink();
    if (!detection.serverUp) {
      return _StatusOnly(detection: detection);
    }
    final data = ref.watch(aiMemoryPanelProvider(_path));
    final value = data.value;
    final briefing = value?.briefing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusLine(
          detection: detection,
          briefing: briefing,
          loading: data.isLoading,
          onRefresh: _refresh,
        ),
        const SizedBox(height: 12),
        if (value == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Lendo as passagens do ai-memory…',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          )
        else if (value.error != null)
          _ReadError(
            message: value.error!,
            timedOut: value.timedOut,
            onRetry: _refresh,
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final list = _handoffColumn(value.handoffs!);
              final side = _sideColumn(value.handoffs!, briefing!);
              if (c.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [list, const SizedBox(height: 12), side],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 13, child: list),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: side),
                ],
              );
            },
          ),
        if (_actionError != null) ...[
          const SizedBox(height: 8),
          Text(
            _actionError!,
            key: const ValueKey('ai-memory-action-error'),
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
      ],
    );
  }

  Widget _handoffColumn(HandoffList list) {
    final shown = _history ? list.handoffs : list.open;
    final next = list.nextDelivered;
    final action = ref.watch(handoffContinueActionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'PASSAGENS PENDENTES · ${list.open.length}',
              key: const ValueKey('ai-memory-pending-title'),
              style: sectionTitleStyle,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'lidas sem consumir · na ordem de entrega do ai-memory',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
            SizedBox(
              height: 24,
              child: Checkbox(
                key: const ValueKey('ai-memory-history'),
                value: _history,
                onChanged: (v) => setState(() => _history = v ?? false),
              ),
            ),
            const Text(
              'Mostrar aceitas e expiradas',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          const AiMemoryBox(
            child: Text(
              'Nenhuma passagem aberta neste projeto. A próxima sessão começa '
              'sem passagem.',
              key: ValueKey('ai-memory-no-handoffs'),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        for (final h in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HandoffCard(
              handoff: h,
              list: list,
              next: identical(h, next),
              expanded: _expanded.contains(h.id),
              onToggle: () => setState(
                () => _expanded.contains(h.id)
                    ? _expanded.remove(h.id)
                    : _expanded.add(h.id),
              ),
              onDiscard: list.canDiscard(h) ? () => _discard(h) : null,
              continueAction:
                  action != null &&
                      h.isOpen &&
                      list.ownerOf(h) == HandoffOwnerKind.you
                  ? action
                  : null,
            ),
          ),
        if (_history && list.closed.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Esta versão do ai-memory só informa as passagens abertas; o '
              'histórico aparece quando ele passar a listar as aceitas e '
              'expiradas.',
              key: ValueKey('ai-memory-no-history'),
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.push_pin_outlined, size: 13, color: AppColors.textMuted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'A ordem segue a entrega do ai-memory: uma passagem manual '
                'primeiro, depois a automática mais nova do mesmo diretório. '
                'O painel não aceita passagens; quem aceita é a sessão do '
                'agente. Passagens de outro dono aparecem só com os '
                'metadados, sem ações.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sideColumn(HandoffList list, MemoryBriefing b) {
    final u = list.unended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (u != null) ...[
          AiMemoryBox(
            key: const ValueKey('ai-memory-unended'),
            color: SessionColors.approvalBg,
            border: SessionColors.approvalBorder,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sessão do ${u.agentName} terminou sem passagem',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_capitalize(aiMemoryWhen(u.lastActivityAt))} · id '
                        '${u.shortId} · cortada antes do fim (cota ou queda). '
                        'A próxima sessão vai ler direto o que o ai-memory '
                        'capturou dela.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        AiMemoryBox(
          key: const ValueKey('ai-memory-wiki'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('WIKI DO PROJETO', style: sectionTitleStyle),
                  ),
                  SmallButton(
                    key: const ValueKey('ai-memory-open-wiki'),
                    label: 'Abrir wiki',
                    icon: Icons.open_in_new,
                    onTap: () => _openWiki(b),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${b.pages}', style: _strong),
                    const TextSpan(text: ' páginas   '),
                    TextSpan(text: '${b.sessions}', style: _strong),
                    const TextSpan(text: ' sessões   '),
                    TextSpan(text: _thousands(b.observations), style: _strong),
                    const TextSpan(text: ' observações'),
                  ],
                ),
                key: const ValueKey('ai-memory-counts'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (b.recentPages.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('MAIS RECENTES', style: sectionTitleStyle),
                const SizedBox(height: 4),
                for (final pg in b.recentPages)
                  InkWell(
                    key: ValueKey('ai-memory-page-${pg.path}'),
                    onTap: () => _openWiki(b, page: pg.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              pg.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: AppFonts.mono,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          Text(
                            _short(pg.updatedAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Abre a página do projeto na interface web do ai-memory. Sem '
                'ela, abre a pasta do projeto no wiki.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _strong = TextStyle(
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _thousands(int n) {
    final s = '$n';
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
      out.write(s[i]);
    }
    return out.toString();
  }

  /// "11:41" today, "ontem", else "18/11".
  static String _short(DateTime? t) {
    if (t == null) return '';
    final w = aiMemoryWhen(t);
    if (w.startsWith('hoje ')) return w.substring(5);
    if (w.startsWith('ontem')) return 'ontem';
    return w.split(' ').first;
  }
}

/// "ai-memory 3.5.1 conectado · 127.0.0.1:49374 · projeto default/x ·
/// última captura 12:20" (R8).
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.detection,
    required this.briefing,
    required this.loading,
    required this.onRefresh,
  });

  final AiMemoryDetection detection;
  final MemoryBriefing? briefing;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final b = briefing;
    const muted = TextStyle(color: AppColors.textSecondary);
    const strong = TextStyle(
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    );
    return Row(
      children: [
        Dot(aiMemoryStatusColor(detection.status)),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: detection.title, style: strong),
                TextSpan(text: ' ${detection.status.label}', style: muted),
                TextSpan(text: '  ·  ${detection.serverHost}', style: muted),
                if (b?.scope != null) ...[
                  const TextSpan(text: '  ·  projeto ', style: muted),
                  TextSpan(
                    text: b!.scope,
                    style: strong.copyWith(fontFamily: AppFonts.mono),
                  ),
                ],
                if (b?.lastObservationAt != null)
                  TextSpan(
                    text:
                        '  ·  última captura '
                        '${aiMemoryWhen(b!.lastObservationAt).replaceFirst('hoje ', '')}',
                    style: muted,
                  ),
              ],
            ),
            key: const ValueKey('ai-memory-status-line'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SmallButton(
          key: const ValueKey('ai-memory-refresh'),
          label: loading ? 'Atualizando…' : 'Atualizar',
          icon: Icons.refresh,
          onTap: loading ? null : onRefresh,
        ),
      ],
    );
  }
}

/// Server stopped or too old to read: one status line, nothing called.
class _StatusOnly extends StatelessWidget {
  const _StatusOnly({required this.detection});

  final AiMemoryDetection detection;

  @override
  Widget build(BuildContext context) => AiMemoryBox(
    key: const ValueKey('ai-memory-panel-down'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Dot(aiMemoryStatusColor(detection.status)),
            const SizedBox(width: 8),
            Text(
              '${detection.title} · ${detection.status.label}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${detection.message} As sessões e os fatos do projeto continuam '
          'funcionando.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (detection.fixCommand != null) ...[
          const SizedBox(height: 8),
          AiMemoryCommandBox(detection.fixCommand!),
        ],
      ],
    ),
  );
}

/// "Não deu para ler as passagens · tempo esgotado em 5 s" (R14, mock 4).
class _ReadError extends StatelessWidget {
  const _ReadError({
    required this.message,
    required this.timedOut,
    required this.onRetry,
  });

  final String message;
  final bool timedOut;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AiMemoryBox(
        key: const ValueKey('ai-memory-read-error'),
        color: SessionColors.delBg,
        border: SessionColors.stopBorder,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: AppColors.red,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Não deu para ler as passagens',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    TextSpan(text: ' · $message'),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SmallButton(
              key: const ValueKey('ai-memory-retry'),
              label: 'Tentar de novo',
              onTap: onRetry,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'A aba e as sessões continuam funcionando. Os fatos do projeto não '
        'dependem do ai-memory.',
        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
    ],
  );
}

/// One handoff (R9, R11). Its texts are plain [Text]: no markdown, no links,
/// nothing runs (R13).
class _HandoffCard extends StatelessWidget {
  const _HandoffCard({
    required this.handoff,
    required this.list,
    required this.next,
    required this.expanded,
    required this.onToggle,
    required this.onDiscard,
    required this.continueAction,
  });

  final Handoff handoff;
  final HandoffList list;
  final bool next;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onDiscard;
  final HandoffContinueAction? continueAction;

  @override
  Widget build(BuildContext context) {
    final h = handoff;
    final mine = list.ownerOf(h) != HandoffOwnerKind.other;
    final dir = list.directoryLabel(h);
    const meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final known = h.fromAgent == 'claude-code' || h.fromAgent == 'codex';
    return AiMemoryBox(
      key: ValueKey('ai-memory-handoff-${h.id}'),
      border: next ? ReviewColors.acceptBorder : AppColors.border,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('ai-memory-handoff-toggle-${h.id}'),
            onTap: onToggle,
            child: Row(
              children: [
                if (known)
                  ProviderChip(
                    h.fromAgent == 'codex' ? 'codex' : 'claude',
                    name: h.agentName,
                  )
                else
                  Text(
                    h.agentName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: h.origin),
                              TextSpan(
                                text: '  ·  ${aiMemoryWhen(h.createdAt)}',
                              ),
                              const TextSpan(text: '  ·  dono: '),
                              TextSpan(
                                text: list.ownerLabel(h),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                ),
                              ),
                              if (!h.isOpen)
                                TextSpan(text: '  ·  ${h.state.label}'),
                            ],
                          ),
                          key: ValueKey('ai-memory-handoff-meta-${h.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: meta,
                        ),
                      ),
                      if (dir != null) ...[const SizedBox(width: 8), _Tag(dir)],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (next)
                  const AiMemoryPill(
                    'será entregue à próxima sessão',
                    AppColors.teal,
                    key: ValueKey('ai-memory-next-badge'),
                  ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          if (!h.isOpen && h.acceptedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'aceita por ${aiMemoryAgentName(h.acceptedBy)}'
              '${h.acceptedByUser == null ? '' : ' (${h.acceptedByUser})'} · '
              '${aiMemoryWhen(h.acceptedAt)}',
              key: ValueKey('ai-memory-accepted-${h.id}'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
          if (mine && h.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (expanded) ...[
              const Text('RESUMO', style: sectionTitleStyle),
              const SizedBox(height: 4),
            ],
            Text(
              h.summary,
              key: ValueKey('ai-memory-summary-${h.id}'),
              maxLines: expanded ? null : 1,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ],
          if (mine && expanded) ...[
            if (h.openQuestions.isNotEmpty || h.nextSteps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Bullets('PERGUNTAS ABERTAS', h.openQuestions),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _Bullets('PRÓXIMOS PASSOS', h.nextSteps)),
                ],
              ),
            ],
            if (h.filesTouched.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('ARQUIVOS TOCADOS', style: sectionTitleStyle),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final f in h.filesTouched) _Tag(f)],
              ),
            ],
            if (h.isOpen) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (continueAction != null) ...[
                    SmallButton(
                      key: ValueKey('ai-memory-continue-${h.id}'),
                      label: continueAction!.label(h),
                      color: AppColors.teal,
                      border: ReviewColors.acceptBorder,
                      onTap: () => continueAction!.run(context, h),
                    ),
                    const SizedBox(width: 8),
                  ],
                  SmallButton(
                    key: ValueKey('ai-memory-copy-${h.id}'),
                    label: 'Copiar id ${h.shortId}',
                    icon: Icons.copy,
                    onTap: () => copyAiMemoryText(context, h.id),
                  ),
                  const Spacer(),
                  if (onDiscard != null)
                    SmallButton(
                      key: ValueKey('ai-memory-discard-${h.id}'),
                      label: 'Descartar',
                      color: AppColors.red,
                      border: SessionColors.stopBorder,
                      onTap: onDiscard,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.title, this.items);

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: sectionTitleStyle),
      const SizedBox(height: 4),
      if (items.isEmpty)
        const Text(
          '—',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '•  $i',
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
        ),
    ],
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaisedSolid,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11,
        fontFamily: AppFonts.mono,
        color: AppColors.textSecondary,
      ),
    ),
  );
}
