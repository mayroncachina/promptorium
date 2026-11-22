import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/run_prefs.dart';
import '../../../core/memory/handoff.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../core/providers/provider_preferences.dart';
import '../../../data/providers.dart';
import '../../../ui/providers/provider_logos.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../settings/settings_sections.dart';
import '../session_manager.dart';
import '../timeline.dart';
import '../timeline_provider.dart';
import '../widgets/session_style.dart';
import 'continue_controller.dart';
import 'continue_link.dart';
import 'handoff_source.dart';
import 'session_summary.dart';

/// Opens "Continuar no Codex" for [origin] (SPEC-099 R3). [handoff] comes
/// chosen when the dialog opens from a handoff of the Memória panel (R13).
/// Returns the id of the new session (null = cancelled).
Future<String?> showContinueDialog(
  BuildContext context,
  Session origin, {
  Handoff? handoff,
}) => showAppDialog<String>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => ContinueDialog(origin: origin, handoff: handoff),
);

/// The dialog (mock 2, mock 4): origin and target, what goes along, the
/// options in the target, what stays behind, the ways to pass the work and
/// the first message, which goes to the field of the new session.
class ContinueDialog extends ConsumerStatefulWidget {
  const ContinueDialog({super.key, required this.origin, this.handoff});

  final Session origin;
  final Handoff? handoff;

  @override
  ConsumerState<ContinueDialog> createState() => _ContinueDialogState();
}

class _ContinueDialogState extends ConsumerState<ContinueDialog> {
  late final String _target = continueTarget(widget.origin.provider)!;
  late final _title = TextEditingController(
    text: continuedTitle(sessionTitle(widget.origin), _target),
  );
  late final _message = TextEditingController();
  late String _model = providerModelFrom(
    ref.read(runPrefsProvider),
    ref.read(appSettingsProvider),
    _target,
    RunKind.session,
  );
  late String _effort = providerEffortFrom(
    ref.read(runPrefsProvider),
    ref.read(appSettingsProvider),
    _target,
    RunKind.session,
  );
  ContinuePath _path = ContinuePath.summary;
  List<String>? _uncommitted;
  double? _budget;
  bool _busy = false;
  String? _error;

  /// The message was edited by hand: changing the path keeps it.
  bool _edited = false;
  String _generated = '';

  /// ai-memory state, kept by [HandoffSource] (T3).
  HandoffSourceState _source = const HandoffSourceState.none();

  Session get _o => widget.origin;

  @override
  void initState() {
    super.initState();
    _message.addListener(() {
      if (_message.text != _generated) _edited = true;
    });
    _load();
  }

  Future<void> _load() async {
    final c = ref.read(continueControllerProvider);
    final files = await c.uncommitted(_o.worktreePath);
    if (!mounted) return;
    setState(() => _uncommitted = files);
    _regenerate();
    final ws = await ref.read(workspacesRepoProvider).getById(_o.workspaceId);
    final budget = await ref
        .read(sessionManagerProvider.notifier)
        .agentBudget(_o.agentName, ws?.path);
    if (!mounted) return;
    setState(() => _budget = budget);
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  String _summary() => sessionSummary(
    title: sessionTitle(_o),
    provider: _o.provider,
    items: ref.read(sessionTimelineProvider(_o.id)).timeline.items,
    root: _o.worktreePath,
    uncommitted: _uncommitted ?? const [],
  );

  void _regenerate() {
    if (_edited) return;
    final text = continueMessage(
      originTitle: sessionTitle(_o),
      originProvider: _o.provider,
      path: _path,
      handoff: _source.handoff,
      summary: _path == ContinuePath.summary ? _summary() : null,
    );
    _generated = text;
    _message.text = text;
    _edited = false;
  }

  void _pick(ContinuePath p) {
    if (_path == p) return;
    setState(() => _path = p);
    _regenerate();
  }

  void _onSource(HandoffSourceState s) {
    if (!mounted) return;
    final first = _source.status == HandoffSourceStatus.none;
    setState(() {
      _source = s;
      // R4: the ai-memory handoff is the recommended path when available.
      if (first && s.available) _path = ContinuePath.aiMemory;
      if (!s.available && _path == ContinuePath.aiMemory) {
        _path = ContinuePath.summary;
      }
    });
    _regenerate();
  }

  Future<String?> _workspacePath() async =>
      (await ref.read(workspacesRepoProvider).getById(_o.workspaceId))?.path;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final root = await _workspacePath();
      final noSandbox =
          ref
              .read(providerAvailabilityProvider(_target))
              .value
              ?.sandboxWarning !=
          null;
      final mode = convertAccess(
        _o.permissionMode,
        target: _target,
        worktree: _o.worktreePath != root,
        noSandbox: noSandbox,
      );
      if (mode == null) throw const SessionException(ContinueReasons.noSandboxRoot);
      if (_path == ContinuePath.terminal) {
        await _source.openTerminal?.call(_o);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final id = await ref
          .read(continueControllerProvider)
          .start(
            ContinueRequest(
              origin: _o,
              target: _target,
              title: _title.text.trim().isEmpty
                  ? continuedTitle(sessionTitle(_o), _target)
                  : _title.text.trim(),
              model: _model,
              effort: _effort,
              mode: mode,
              path: _path,
              message: _message.text.trim(),
              handoff: _path == ContinuePath.aiMemory ? _source.handoff : null,
              handoffOwner: _source.owner,
            ),
          );
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openMemorySettings() {
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(context).pop();
    container
        .read(selectedSettingsSectionProvider.notifier)
        .select(SettingsSection.aiMemory);
    container.read(navigationProvider.notifier).go(AppSection.settings);
  }

  static const _section = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );
  static const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
  static const _value = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    color: AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final alive = ref.watch(
      sessionManagerProvider.select((m) => m.isAlive(_o.id)),
    );
    final look = SessionLook.of(_o.status, alive: alive);
    final limited = ref.watch(
      sessionTimelineProvider(
        _o.id,
      ).select((t) => lastLimit(t.timeline.items) != null),
    );
    final targetName = providerWords(_target);
    final fromName = providerWords(_o.provider);
    final behind = leftBehind(_o, target: _target, budgetUsd: _budget);
    final ws = ref.watch(activeWorkspaceProvider);
    final inWorktree = ws == null || _o.worktreePath != ws.path;
    final noSandbox =
        ref
            .watch(providerAvailabilityProvider(_target))
            .value
            ?.sandboxWarning !=
        null;
    final mode = convertAccess(
      _o.permissionMode,
      target: _target,
      worktree: inWorktree,
      noSandbox: noSandbox,
    );
    final codexCache = _target == 'codex'
        ? codexModelsCache(ref.watch(appSettingsProvider))
        : null;
    final models = <String>{
      'inherit',
      if (codexCache != null)
        for (final m in codexCache.models) m.id
      else if (_target != 'codex')
        ...sessionModels.where((m) => m != 'inherit'),
      _model,
    };
    final efforts = <String>{
      ...(codexCache == null
          ? effortChoices
          : ['default', ...?codexCache.byId(_model)?.efforts]),
      _effort,
    };
    final files = _uncommitted;
    final hasAiMemory = _source.installed;

    Widget box({required Widget child, Color? border, Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border ?? AppColors.border),
      ),
      child: child,
    );
    Widget kv(String k, Widget v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: _label)),
          const SizedBox(width: 8),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: v),
          ),
        ],
      ),
    );
    Widget select<T>(
      Key key,
      T value,
      List<(T, String)> items,
      ValueChanged<T> onChanged,
    ) => SizedBox(
      width: 170,
      child: DropdownButtonFormField<T>(
        key: key,
        initialValue: value,
        isDense: true,
        isExpanded: true,
        dropdownColor: AppColors.panelSolid,
        style: const TextStyle(fontSize: 12, color: AppColors.text),
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final (v, l) in items)
            DropdownMenuItem(
              value: v,
              child: Text(l, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );

    return Align(
      alignment: const Alignment(0, -0.4),
      child: Material(
        key: const ValueKey('continue-dialog'),
        color: AppColors.panelSolid,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        continueLabel(_target),
                        key: const ValueKey('continue-dialog-title'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('continue-dialog-close'),
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Origin → target.
                      Row(
                        children: [
                          Expanded(
                            child: box(
                              key: const ValueKey('continue-origin'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Origem', style: _label),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      ProviderChip(_o.provider),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          sessionTitle(_o),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '· ${look.label.toLowerCase()}'
                                        '${limited ? ' (limite)' : ''}',
                                        key: const ValueKey(
                                          'continue-origin-state',
                                        ),
                                        style: _label,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: box(
                              key: const ValueKey('continue-target'),
                              border: ReviewColors.acceptBorder,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Destino · sessão nova',
                                    style: _label,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      ProviderChip(_target),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          key: const ValueKey(
                                            'continue-title',
                                          ),
                                          controller: _title,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: InputBorder.none,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // R4, R5: the handoff of ai-memory (T3).
                      HandoffSource(
                        origin: _o,
                        target: _target,
                        chosen: widget.handoff,
                        selected: _path == ContinuePath.aiMemory,
                        onChanged: _onSource,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('O QUE VAI JUNTO', style: _section),
                                const SizedBox(height: 8),
                                kv(
                                  inWorktree ? 'Worktree e branch' : 'Pasta',
                                  Text(
                                    inWorktree
                                        ? '${_basename(_o.worktreePath)} · ${_o.branch}'
                                        : 'raiz do workspace · ${_o.branch}',
                                    key: const ValueKey('continue-worktree'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _value,
                                  ),
                                ),
                                kv(
                                  'Não commitados',
                                  Text(
                                    files == null
                                        ? 'lendo…'
                                        : files.isEmpty
                                        ? 'nenhum'
                                        : '${files.length} '
                                              '${files.length == 1 ? 'arquivo, fica' : 'arquivos, ficam'} '
                                              'no worktree',
                                    key: const ValueKey('continue-uncommitted'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (behind.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  const Text('FICA PARA TRÁS', style: _section),
                                  const SizedBox(height: 6),
                                  for (final b in behind)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        key: ValueKey(
                                          'continue-behind-${b.kind}',
                                        ),
                                        children: [
                                          Text(b.kind, style: _label),
                                          const SizedBox(width: 6),
                                          Text(b.value, style: _value),
                                          const SizedBox(width: 6),
                                          _Tag(b.tag),
                                        ],
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'NO ${targetName.toUpperCase()}',
                                  style: _section,
                                ),
                                const SizedBox(height: 8),
                                kv(
                                  'Modelo',
                                  select<String>(
                                    const ValueKey('continue-model'),
                                    _model,
                                    [
                                      for (final m in models)
                                        (
                                          m,
                                          m == 'inherit'
                                              ? 'padrão do ${providerBrandName(_target)}'
                                              : m,
                                        ),
                                    ],
                                    (v) => setState(() => _model = v),
                                  ),
                                ),
                                kv(
                                  'Esforço',
                                  select<String>(
                                    const ValueKey('continue-effort'),
                                    _effort,
                                    [for (final e in efforts) (e, effortLabel(e))],
                                    (v) => setState(() => _effort = v),
                                  ),
                                ),
                                kv(
                                  'Acesso',
                                  Text(
                                    mode == null
                                        ? 'indisponível na raiz'
                                        : accessWords(mode),
                                    key: const ValueKey('continue-access'),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (noSandbox && _target == 'codex')
                                  const Text(
                                    'Sandbox do Codex indisponível: acesso '
                                    'total, só no worktree.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.amber,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('COMO PASSAR O TRABALHO', style: _section),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          for (final opt in _source.options(
                            targetName: targetName,
                            fromName: fromName,
                          ))
                            SizedBox(
                              width: 370,
                              child: _PathOption(
                                option: opt,
                                selected: _path == opt.path,
                                onTap: opt.reason == null && opt.path != null
                                    ? () => _pick(opt.path!)
                                    : opt.onToggle,
                              ),
                            ),
                        ],
                      ),
                      if (!hasAiMemory) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          key: const ValueKey('continue-no-ai-memory'),
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Com o ai-memory ligado, a passagem traz o que '
                              'falhou e as perguntas abertas. ',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            InkWell(
                              key: const ValueKey('continue-memory-settings'),
                              onTap: _openMemorySettings,
                              child: const Text(
                                'Configurações → Memória',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.text,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_path != ContinuePath.terminal) ...[
                        const SizedBox(height: 12),
                        Text(
                          _path == ContinuePath.summary
                              ? 'RESUMO DO APP · VAI PARA O COMPOSER, VOCÊ ENVIA'
                              : 'MENSAGEM INICIAL · VAI PARA O COMPOSER, VOCÊ ENVIA',
                          style: _section,
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const ValueKey('continue-message'),
                          controller: _message,
                          minLines: 3,
                          maxLines: 9,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(isDense: true),
                        ),
                        if (_path == ContinuePath.summary)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Montado pelo app, sem chamar modelo. Edite à '
                              'vontade: vai para o composer da sessão nova.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          key: const ValueKey('continue-error'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'O ${providerBrandName(_o.provider)} não troca no meio '
                        'de um turno: a sessão de origem fica concluída e '
                        'ligada à nova.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    SmallButton(
                      key: const ValueKey('continue-cancel'),
                      label: 'Cancelar',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    SmallButton(
                      key: const ValueKey('continue-go'),
                      label: _busy
                          ? 'Abrindo…'
                          : _path == ContinuePath.terminal
                          ? 'Abrir no terminal'
                          : continueLabel(_target),
                      color: AppColors.background,
                      background: AppColors.amber,
                      border: AppColors.amber,
                      fontWeight: FontWeight.w600,
                      // Waiting for the handoff only holds its own path.
                      onTap:
                          _busy ||
                              mode == null ||
                              (_path == ContinuePath.aiMemory &&
                                  !_source.ready)
                          ? null
                          : _go,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _basename(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
}

/// One way to pass the work, as the dialog lists it.
@immutable
class PathOption {
  const PathOption({
    required this.title,
    required this.text,
    this.path,
    this.reason,
    this.checkbox = false,
    this.checked = false,
    this.onToggle,
    this.keyName,
  });

  final String title;
  final String text;

  /// Null = a checkbox (the polished handoff, P2).
  final ContinuePath? path;

  /// Why it is unavailable (null = available).
  final String? reason;
  final bool checkbox;
  final bool checked;
  final VoidCallback? onToggle;
  final String? keyName;
}

class _PathOption extends StatelessWidget {
  const _PathOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final PathOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final enabled = o.reason == null;
    final on = o.checkbox ? o.checked : selected;
    final icon = o.checkbox
        ? (on ? Icons.check_box : Icons.check_box_outline_blank)
        : (on ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return InkWell(
      key: ValueKey('continue-path-${o.keyName ?? o.path?.wire ?? 'extra'}'),
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 16,
                color: on ? AppColors.amber : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      o.reason == null ? o.text : '${o.text} · ${o.reason}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.providerClaude),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: AppColors.providerClaude),
    ),
  );
}

/// The last usage limit of a timeline, while nothing was sent after it
/// (R2): what makes the origin "parada (limite)" and shows the banner.
LimitItem? lastLimit(List<TimelineItem> items) {
  for (final i in items.reversed) {
    if (i is UserItem) return null;
    if (i is LimitItem) return i;
  }
  return null;
}

/// Opens the dialog from a button (snack on failure).
Future<void> openContinue(
  BuildContext context,
  WidgetRef ref,
  Session s,
) async {
  try {
    await showContinueDialog(context, s);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text('$e')));
  }
}
