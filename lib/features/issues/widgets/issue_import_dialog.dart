import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/gh_issues.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_planner.dart' show nextSpecCodeProvider;
import '../../specs/spec_service.dart';
import '../issue_availability.dart';
import '../issue_import.dart';

/// "Importar issues" (SPEC-074 R3, R4, R12): the issues of the GitHub
/// repository with search and filters; each one checked becomes a draft
/// spec in the Bandeja.

/// Opens the dialog and, after an import, the notice "3 issues viraram
/// SPEC-024 a SPEC-026, na Bandeja" with "Abrir a primeira" (R5).
Future<void> showIssueImportDialog(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showAppDialog<IssueImportResult>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => IssueImportDialog(workspace: workspace),
  );
  if (result == null) return;
  final first = result.created.firstOrNull;
  messenger
    ?..hideCurrentSnackBar()
    ..showAppToast(
      SnackBar(
        key: const ValueKey('issue-import-done'),
        content: Semantics(liveRegion: true, child: Text(result.message)),
        action: first == null
            ? null
            : SnackBarAction(
                key: const ValueKey('issue-import-open-first'),
                label: 'Abrir a primeira',
                onPressed: () {
                  ref.read(selectedSpecProvider.notifier).select(first.id);
                  ref.read(navigationProvider.notifier).go(AppSection.specs);
                },
              ),
      ),
    );
}

/// The button of the Bandeja's header (R3): off without GitHub, with the
/// reason as the tooltip (R2).
class IssueImportButton extends ConsumerWidget {
  const IssueImportButton({super.key, required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(issueAvailabilityProvider(workspace.path));
    final reason = a.value?.available == false ? a.value?.reason : null;
    // Off with a reason; the dialog still opens to show it with "Conferir
    // de novo" (the mockup of R2).
    return Tooltip(
      message: reason ?? 'Cada issue marcada vira uma spec em rascunho',
      child: SmallButton(
        key: const ValueKey('issue-import-button'),
        label: 'Importar issues',
        icon: Icons.download_outlined,
        height: 30,
        fontSize: 12,
        color: reason == null ? AppColors.text : AppColors.textMuted,
        onTap: () => unawaited(showIssueImportDialog(context, ref, workspace)),
      ),
    );
  }
}

class IssueImportDialog extends ConsumerStatefulWidget {
  const IssueImportDialog({super.key, required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<IssueImportDialog> createState() => _IssueImportDialogState();
}

class _IssueImportDialogState extends ConsumerState<IssueImportDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  GhIssues? _client;
  IssueStateFilter _state = IssueStateFilter.open;
  final _labels = <String>[];
  String? _milestone;
  IssueAssigneeFilter _assignee = IssueAssigneeFilter.any;

  List<GhLabel> _labelOptions = const [];
  List<String> _milestoneOptions = const [];
  List<String> _assigneeOptions = const [];

  final _issues = <GhIssue>[];
  GhIssuePage? _page;
  bool _loading = false;
  bool _importing = false;
  String? _error;

  /// Checked issues, in the order they were checked.
  final _checked = <int>[];

  /// Increases at each new query: an answer of an old one is dropped.
  int _query = 0;

  String get _root => widget.workspace.path;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _reload);
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final a = await ref.read(issueAvailabilityProvider(_root).future);
    if (!mounted || !a.available || a.repo == null) return;
    final client = GhIssues(
      ref.read(ghCliFactoryProvider)(_root),
      repo: a.repo!,
    );
    setState(() => _client = client);
    unawaited(_reload());
    // The options of the filters come from the repository.
    unawaited(
      client.labels().then(
        (v) => mounted ? setState(() => _labelOptions = v) : null,
        onError: (Object _) {},
      ),
    );
    unawaited(
      client.milestones().then(
        (v) => mounted ? setState(() => _milestoneOptions = v) : null,
        onError: (Object _) {},
      ),
    );
    unawaited(
      client.assignees().then(
        (v) => mounted ? setState(() => _assigneeOptions = v) : null,
        onError: (Object _) {},
      ),
    );
  }

  Future<void> _recheck() async {
    ref.invalidate(issueAvailabilityProvider(_root));
    setState(() {
      _client = null;
      _issues.clear();
      _page = null;
    });
    await _start();
  }

  Future<void> _reload() => _fetch(page: 1);

  Future<void> _more() => _fetch(page: (_page?.page ?? 0) + 1);

  Future<void> _fetch({required int page}) async {
    final client = _client;
    if (client == null) return;
    final q = ++_query;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await client.list(
        state: _state,
        labels: _labels,
        milestone: _milestone,
        assignee: _assignee,
        search: _search.text,
        page: page,
      );
      if (!mounted || q != _query) return;
      setState(() {
        if (page == 1) _issues.clear();
        final seen = {for (final i in _issues) i.number};
        _issues.addAll(p.issues.where((i) => !seen.contains(i.number)));
        _page = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || q != _query) return;
      setState(() {
        _error = 'Não deu para ler as issues: $e';
        _loading = false;
      });
    }
  }

  void _toggle(GhIssue i) => setState(() {
    _checked.contains(i.number)
        ? _checked.remove(i.number)
        : _checked.add(i.number);
  });

  Future<void> _import() async {
    if (_checked.isEmpty || _importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    final byNumber = {for (final i in _issues) i.number: i};
    final chosen = [for (final n in _checked) ?byNumber[n]];
    try {
      final r = await importIssues(
        ref.read(specServiceProvider),
        ref.read(specsRepoProvider),
        widget.workspace,
        chosen,
      );
      if (!mounted) return;
      Navigator.of(context).pop(r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não deu para importar: $e';
          _importing = false;
        });
      }
    }
  }

  void _openSpec(Spec s) {
    ref.read(selectedSpecProvider.notifier).select(s.id);
    ref.read(navigationProvider.notifier).go(AppSection.specs);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(issueAvailabilityProvider(_root));
    final avail = a.value;
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Material(
        key: const ValueKey('issue-import-dialog'),
        color: AppColors.panelSolid,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 820,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(avail),
              const Divider(height: 1),
              if (a.isLoading && avail == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Conferindo o GitHub…',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else if (avail != null && !avail.available)
                _unavailable(avail)
              else
                ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(IssueAvailability? a) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Importar issues',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${a?.repo ?? widget.workspace.name} no GitHub · cada issue '
                'marcada vira uma spec em rascunho na Bandeja',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('issue-import-close'),
          tooltip: 'Fechar',
          iconSize: 18,
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  /// R2: the reason, with "Conferir de novo" and what helps.
  Widget _unavailable(IssueAvailability a) => Column(
    key: const ValueKey('issue-import-unavailable'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (a.problem) {
                IssueProblem.ghLoggedOut => Icons.lock_outline,
                IssueProblem.issuesDisabled => Icons.block,
                IssueProblem.gitlab ||
                IssueProblem.otherHost => Icons.info_outline,
                _ => Icons.warning_amber_rounded,
              },
              size: 20,
              color: AppColors.amber,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    key: const ValueKey('issue-import-problem'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    a.reason ?? '',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (a.installUrl != null) ...[
              SmallButton(
                key: const ValueKey('issue-import-install'),
                label: 'Como instalar',
                height: 34,
                onTap: () => unawaited(
                  ref
                      .read(cliRunnerProvider)('xdg-open', [a.installUrl!])
                      .then((_) {}, onError: (Object _) {}),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (a.problem == IssueProblem.ghLoggedOut) ...[
              SmallButton(
                key: const ValueKey('issue-import-copy'),
                label: 'Copiar comando',
                height: 34,
                onTap: () => Clipboard.setData(
                  const ClipboardData(text: 'gh auth login'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (a.problem == IssueProblem.issuesDisabled && a.repo != null) ...[
              SmallButton(
                key: const ValueKey('issue-import-repo'),
                label: 'Abrir o repositório',
                height: 34,
                onTap: () => unawaited(
                  ref
                      .read(cliRunnerProvider)('xdg-open', [
                        'https://github.com/${a.repo}/settings',
                      ])
                      .then((_) {}, onError: (Object _) {}),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (a.problem == IssueProblem.gitlab ||
                a.problem == IssueProblem.otherHost)
              AmberButton(
                key: const ValueKey('issue-import-ok'),
                label: 'Entendi',
                height: 34,
                onTap: () => Navigator.of(context).pop(),
              )
            else
              AmberButton(
                key: const ValueKey('issue-import-recheck'),
                label: 'Conferir de novo',
                height: 34,
                onTap: _recheck,
              ),
          ],
        ),
      ),
    ],
  );

  List<Widget> _body() {
    final specs =
        ref.watch(specsProvider(widget.workspace.id)).value ?? const <Spec>[];
    final imported = specsByIssue(specs);
    final next = ref.watch(nextSpecCodeProvider(widget.workspace)).value;
    final nextNumber = next == null ? null : int.tryParse(next.substring(5));
    final checkable = [
      for (final n in _checked)
        if (!imported.containsKey(n)) n,
    ];
    final predicted = nextNumber == null
        ? const <int, String>{}
        : predictedCodes(checkable, nextNumber);
    final n = checkable.length;
    final page = _page;
    final stateWord = switch (_state) {
      IssueStateFilter.open => 'abertas',
      IssueStateFilter.closed => 'fechadas',
      IssueStateFilter.all => '',
    };
    final total = page?.total ?? 0;
    final countLine = page == null
        ? 'Lendo as issues…'
        : '$total ${total == 1 ? 'issue' : 'issues'}'
              '${stateWord.isEmpty ? '' : ' ${total == 1 ? stateWord.replaceFirst(RegExp(r's$'), '') : stateWord}'}'
              ' com estes filtros · mostrando ${_issues.length}';
    final selectable = [
      for (final i in _issues)
        if (!imported.containsKey(i.number)) i.number,
    ];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                key: const ValueKey('issue-import-search'),
                controller: _search,
                autofocus: true,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 16),
                  prefixIconConstraints: BoxConstraints(minWidth: 32),
                  hintText: 'Buscar no título e no texto…',
                ),
              ),
            ),
            _filter<IssueStateFilter>(
              key: 'state',
              label: 'Estado',
              value: switch (_state) {
                IssueStateFilter.open => 'Abertas',
                IssueStateFilter.closed => 'Fechadas',
                IssueStateFilter.all => 'Todas',
              },
              items: const [
                (IssueStateFilter.open, 'Abertas', false),
                (IssueStateFilter.closed, 'Fechadas', false),
                (IssueStateFilter.all, 'Todas', false),
              ],
              onSelected: (v) {
                _state = v;
                unawaited(_reload());
              },
            ),
            _filter<String>(
              key: 'label',
              label: 'Label',
              value: _labels.isEmpty ? 'qualquer' : _labels.join(', '),
              items: [
                for (final l in _labelOptions)
                  (l.name, l.name, _labels.contains(l.name)),
              ],
              onSelected: (v) {
                _labels.contains(v) ? _labels.remove(v) : _labels.add(v);
                unawaited(_reload());
              },
            ),
            _filter<String>(
              key: 'milestone',
              label: 'Milestone',
              value: _milestone ?? 'qualquer',
              items: [
                ('', 'qualquer', _milestone == null),
                for (final m in _milestoneOptions) (m, m, _milestone == m),
              ],
              onSelected: (v) {
                _milestone = v.isEmpty ? null : v;
                unawaited(_reload());
              },
            ),
            _filter<IssueAssigneeFilter>(
              key: 'assignee',
              label: 'Responsável',
              value: switch (_assignee.kind) {
                'me' => 'eu',
                'none' => 'sem responsável',
                'person' => '@${_assignee.login}',
                _ => 'qualquer',
              },
              items: [
                (IssueAssigneeFilter.any, 'qualquer', false),
                (IssueAssigneeFilter.me, 'eu', false),
                (IssueAssigneeFilter.none, 'sem responsável', false),
                for (final p in _assigneeOptions)
                  (IssueAssigneeFilter.person(p), '@$p', false),
              ],
              onSelected: (v) {
                _assignee = v;
                unawaited(_reload());
              },
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  countLine,
                  key: const ValueKey('issue-import-count'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (selectable.isNotEmpty)
              TextButton(
                key: const ValueKey('issue-import-all'),
                onPressed: () => setState(() {
                  final all = selectable.every(_checked.contains);
                  if (all) {
                    _checked.removeWhere(selectable.contains);
                  } else {
                    for (final s in selectable) {
                      if (!_checked.contains(s)) _checked.add(s);
                    }
                  }
                }),
                child: Text(
                  selectable.every(_checked.contains)
                      ? 'Desmarcar todas'
                      : 'Marcar todas',
                  style: const TextStyle(fontSize: 12, color: AppColors.amber),
                ),
              ),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            _error!,
            key: const ValueKey('issue-import-error'),
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ),
      Flexible(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): _import,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): _import,
          },
          child: Semantics(
            container: true,
            label: 'Issues para importar',
            explicitChildNodes: true,
            child: FocusTraversalGroup(
              child: ListView(
                key: const ValueKey('issue-import-list'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  for (final i in _issues)
                    _row(i, imported[i.number], predicted[i.number]),
                  if (page != null && _issues.isEmpty && !_loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Nenhuma issue com estes filtros.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (page != null && page.hasMore)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      child: SmallButton(
                        key: const ValueKey('issue-import-more'),
                        label: 'Carregar mais ${page.nextCount}',
                        icon: Icons.expand_more,
                        height: 34,
                        expand: true,
                        onTap: _more,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Entram como rascunho na Bandeja, com issue: N no '
                'frontmatter. Nada muda no GitHub.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            SmallButton(
              key: const ValueKey('issue-import-cancel'),
              label: 'Cancelar',
              height: 36,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            AmberButton(
              key: const ValueKey('issue-import-confirm'),
              label: _importing
                  ? 'Importando…'
                  : n == 0
                  ? 'Importar issues'
                  : n == 1
                  ? 'Importar 1 issue'
                  : 'Importar $n issues',
              height: 36,
              onTap: n == 0 || _importing ? null : _import,
            ),
          ],
        ),
      ),
    ];
  }

  Widget _filter<T>({
    required String key,
    required String label,
    required String value,
    required List<(T, String, bool)> items,
    required ValueChanged<T> onSelected,
  }) => PopupMenuButton<T>(
    key: ValueKey('issue-import-filter-$key'),
    tooltip: label,
    color: AppColors.panelSolid,
    onSelected: (v) => setState(() => onSelected(v)),
    itemBuilder: (_) => [
      if (items.isEmpty)
        const PopupMenuItem(
          enabled: false,
          child: Text('Nenhuma opção', style: TextStyle(fontSize: 12)),
        ),
      for (final (v, text, on) in items)
        CheckedPopupMenuItem<T>(
          value: v,
          checked: on,
          child: Text(text, style: const TextStyle(fontSize: 12)),
        ),
    ],
    child: Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderHover),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _row(GhIssue i, Spec? imported, String? code) {
    final checked = imported == null && _checked.contains(i.number);
    final hints = [
      i.milestone ?? 'sem milestone',
      if (i.assignees.isEmpty)
        'sem responsável'
      else
        i.assignees.map((a) => '@$a').join(', '),
      if (i.checklistItems > 0)
        'checklist · ${i.checklistItems} ${i.checklistItems == 1 ? 'item' : 'itens'}',
      if (i.images > 0) '${i.images} ${i.images == 1 ? 'imagem' : 'imagens'}',
      if (i.closed) 'fechada',
    ];
    final locked = imported != null;
    final muted = locked ? AppColors.textMuted : AppColors.text;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          height: 28,
          child: locked
              ? const ExcludeFocus(
                  child: Center(
                    child: Icon(
                      Icons.check_box_outline_blank,
                      size: 16,
                      color: AppColors.border,
                    ),
                  ),
                )
              : Checkbox(
                  key: ValueKey('issue-import-check-${i.number}'),
                  value: checked,
                  activeColor: AppColors.amber,
                  checkColor: AppColors.onAmber,
                  side: const BorderSide(color: AppColors.borderHover),
                  semanticLabel: 'Issue ${i.number}, ${i.title}',
                  onChanged: (_) => _toggle(i),
                ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 48,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '#${i.number}',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: locked ? AppColors.textMuted : CanvasColors.agent,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      i.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    for (final l in i.labels) _LabelChip(l, muted: locked),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  hints.join('  ·  '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (locked) ...[
          Container(
            key: ValueKey('issue-import-done-${i.number}'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: SessionColors.runningToolBorder),
            ),
            child: Text(
              'já importada · ${imported.code}',
              style: const TextStyle(fontSize: 11, color: AppColors.teal),
            ),
          ),
          TextButton(
            key: ValueKey('issue-import-open-${i.number}'),
            onPressed: () => _openSpec(imported),
            child: const Text(
              'Abrir',
              style: TextStyle(fontSize: 12, color: AppColors.amber),
            ),
          ),
        ] else if (code != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'vira '),
                  TextSpan(
                    text: code,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.amber,
                    ),
                  ),
                ],
              ),
              key: ValueKey('issue-import-code-${i.number}'),
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        key: ValueKey('issue-import-row-${i.number}'),
        color: checked ? AppColors.amberTint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: checked
                ? AppColors.amber.withValues(alpha: .5)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          canRequestFocus: false,
          onTap: locked ? null : () => _toggle(i),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
            child: locked
                ? Semantics(
                    label:
                        'Issue ${i.number}, ${i.title}, já importada como '
                        '${imported.code}',
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip(this.label, {this.muted = false});

  final GhLabel label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final hex = int.tryParse(label.color, radix: 16);
    final color = muted || hex == null
        ? AppColors.textSecondary
        : Color(0xFF000000 | hex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Text(
        label.name,
        style: TextStyle(
          fontSize: 10.5,
          color: Color.lerp(color, Colors.white, .35),
        ),
      ),
    );
  }
}
