import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/gh_issues.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart';
import '../issue_availability.dart';
import '../issue_create.dart';

/// "Criar issue no GitHub" (SPEC-074 R11): the title and the text already
/// put together from the spec, with optional labels, milestone and
/// assignee. The spec gets `issue: N` only after the issue exists.

/// Opens the dialog for [spec]; a notice says the number at the end.
Future<int?> showCreateIssueDialog(
  BuildContext context,
  WidgetRef ref,
  Spec spec,
) async {
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null || !context.mounted) return null;
  final text = await ref.read(specServiceProvider).read(ws, spec);
  if (!context.mounted) return null;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final n = await showAppDialog<int>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => CreateIssueDialog(
      workspace: ws,
      spec: spec,
      title: SpecDocument.parse(text ?? '').title ?? spec.title,
      body: issueBodyFromSpec(text ?? '', path: spec.path),
    ),
  );
  if (n != null) {
    messenger?.showAppToast(
      SnackBar(
        key: const ValueKey('create-issue-done'),
        content: Semantics(
          liveRegion: true,
          child: Text('Issue #$n criada e ligada à ${spec.code}.'),
        ),
      ),
    );
  }
  return n;
}

class CreateIssueDialog extends ConsumerStatefulWidget {
  const CreateIssueDialog({
    super.key,
    required this.workspace,
    required this.spec,
    required this.title,
    required this.body,
  });

  final Workspace workspace;
  final Spec spec;
  final String title;
  final String body;

  @override
  ConsumerState<CreateIssueDialog> createState() => _CreateIssueDialogState();
}

class _CreateIssueDialogState extends ConsumerState<CreateIssueDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _body = TextEditingController(text: widget.body);
  final _labels = <String>[];
  String? _milestone;

  /// `@me` = "eu".
  String? _assignee;
  List<GhLabel> _labelOptions = const [];
  List<String> _milestoneOptions = const [];
  List<String> _people = const [];
  GhIssues? _client;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final root = widget.workspace.path;
    final a = await ref.read(issueAvailabilityProvider(root).future);
    if (!mounted || !a.available || a.repo == null) return;
    final client = GhIssues(
      ref.read(ghCliFactoryProvider)(root),
      repo: a.repo!,
    );
    setState(() => _client = client);
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
        (v) => mounted ? setState(() => _people = v) : null,
        onError: (Object _) {},
      ),
    );
  }

  Future<void> _create() async {
    final client = _client;
    if (client == null || _creating || _title.text.trim().isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final n = await createIssueForSpec(
        client: client,
        service: ref.read(specServiceProvider),
        repo: ref.read(specsRepoProvider),
        ws: widget.workspace,
        spec: widget.spec,
        title: _title.text,
        body: _body.text,
        labels: _labels,
        milestone: _milestone,
        assignee: _assignee,
      );
      if (mounted) Navigator.of(context).pop(n);
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = 'Não deu para criar a issue: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(issueAvailabilityProvider(widget.workspace.path)).value;
    final unavailable = a != null && !a.available;
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Material(
        key: const ValueKey('create-issue-dialog'),
        color: AppColors.panelSolid,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
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
                              'Criar issue no GitHub',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${a?.repo ?? widget.workspace.name} · a issue '
                            'nasce ligada à ${widget.spec.code}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('create-issue-close'),
                      tooltip: 'Fechar',
                      iconSize: 18,
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (unavailable) ...[
                        Text(
                          a.reason ?? 'GitHub indisponível.',
                          key: const ValueKey('create-issue-unavailable'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.amber,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const _Label('Título'),
                      TextField(
                        key: const ValueKey('create-issue-title'),
                        controller: _title,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(isDense: true),
                      ),
                      const SizedBox(height: 12),
                      const _Label('Texto da issue'),
                      TextField(
                        key: const ValueKey('create-issue-body'),
                        controller: _body,
                        minLines: 6,
                        maxLines: 12,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(isDense: true),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          _picker(
                            key: 'labels',
                            label: 'Labels',
                            value: _labels.isEmpty
                                ? 'nenhuma'
                                : _labels.join(', '),
                            items: [
                              for (final l in _labelOptions)
                                (l.name, l.name, _labels.contains(l.name)),
                            ],
                            onSelected: (v) => _labels.contains(v)
                                ? _labels.remove(v)
                                : _labels.add(v),
                          ),
                          _picker(
                            key: 'milestone',
                            label: 'Milestone',
                            value: _milestone ?? 'nenhuma',
                            items: [
                              ('', 'nenhuma', _milestone == null),
                              for (final m in _milestoneOptions)
                                (m, m, _milestone == m),
                            ],
                            onSelected: (v) =>
                                _milestone = v.isEmpty ? null : v,
                          ),
                          _picker(
                            key: 'assignee',
                            label: 'Responsável',
                            value: switch (_assignee) {
                              null => 'ninguém',
                              '@me' =>
                                a?.account == null
                                    ? 'eu'
                                    : 'eu (${a!.account})',
                              final p => '@$p',
                            },
                            items: [
                              ('', 'ninguém', _assignee == null),
                              ('@me', 'eu', _assignee == '@me'),
                              for (final p in _people)
                                (p, '@$p', _assignee == p),
                            ],
                            onSelected: (v) => _assignee = v.isEmpty ? null : v,
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const ValueKey('create-issue-error'),
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
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'A spec ganha issue: N no frontmatter e o selo #N.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    SmallButton(
                      key: const ValueKey('create-issue-cancel'),
                      label: 'Cancelar',
                      height: 36,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AmberButton(
                      key: const ValueKey('create-issue-confirm'),
                      label: _creating ? 'Criando…' : 'Criar issue',
                      height: 36,
                      onTap:
                          _client == null ||
                              _creating ||
                              _title.text.trim().isEmpty
                          ? null
                          : _create,
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

  Widget _picker({
    required String key,
    required String label,
    required String value,
    required List<(String, String, bool)> items,
    required void Function(String) onSelected,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _Label(label),
      PopupMenuButton<String>(
        key: ValueKey('create-issue-$key'),
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
            CheckedPopupMenuItem<String>(
              value: v,
              checked: on,
              child: Text(text, style: const TextStyle(fontSize: 12)),
            ),
        ],
        child: Container(
          width: 200,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderHover),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    ),
  );
}
