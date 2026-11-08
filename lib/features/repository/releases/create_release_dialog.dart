import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../project/project_config.dart';
import '../../sessions/widgets/session_style.dart';
import 'release_dispatcher.dart';
import 'releases_state.dart';
import 'releases_tab.dart' show ChangelogBox, plural;
import 'semver.dart';
import 'unreleased.dart';

/// What the dialog decided: the version and the path, and whether the
/// chosen workflow goes to `.promptorium/config.yml` (R6).
@immutable
class CreateReleaseRequest {
  const CreateReleaseRequest({
    required this.version,
    required this.tag,
    required this.path,
    required this.changelog,
    this.saveChoice = false,
  });

  final String version;
  final String tag;
  final ReleasePath path;
  final String changelog;
  final bool saveChoice;
}

/// "Criar release" (R5; docs/mockups/spec-044/2-criar-release.png). The
/// only button that acts is "Disparar release".
Future<CreateReleaseRequest?> showCreateReleaseDialog(
  BuildContext context, {
  required ReleasesData data,
  required ReleasePath path,
  String? version,
}) => showAppDialog<CreateReleaseRequest>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) =>
      CreateReleaseDialog(data: data, path: path, initialVersion: version),
);

class CreateReleaseDialog extends ConsumerStatefulWidget {
  const CreateReleaseDialog({
    super.key,
    required this.data,
    required this.path,
    this.initialVersion,
  });

  final ReleasesData data;
  final ReleasePath path;

  /// "Disparar de novo" brings the version that failed.
  final String? initialVersion;

  @override
  ConsumerState<CreateReleaseDialog> createState() =>
      _CreateReleaseDialogState();
}

class _CreateReleaseDialogState extends ConsumerState<CreateReleaseDialog> {
  late final _version = TextEditingController(
    text: widget.initialVersion ?? '${widget.data.unreleased.suggested}',
  );
  late ReleasePath _path = widget.path;
  ReleaseWorkflow? _chosen;
  bool _save = true;
  late String _changelog = widget.data.unreleased.changelog;
  int _changelogFor = 0;

  Unreleased get _u => widget.data.unreleased;

  String? get _error => validateNewVersion(
    _version.text,
    last: _u.lastVersion,
    existingTags: widget.data.existingTags,
    lastTag: _u.lastTag,
  );

  String get _tag => tagFor(_version.text, lastTag: _u.lastTag);

  String get _bare => _version.text.trim().replaceFirst(RegExp('^v'), '');

  @override
  void initState() {
    super.initState();
    if (widget.initialVersion != null) _refreshChangelog();
  }

  @override
  void dispose() {
    _version.dispose();
    super.dispose();
  }

  /// The preview for the version typed (R5): git-cliff's when the card's
  /// came from it, else the app's.
  Future<void> _refreshChangelog() async {
    final ticket = ++_changelogFor;
    if (_error != null) return;
    if ('${_u.suggested}' == _bare && widget.initialVersion == null) {
      setState(() => _changelog = _u.changelog);
      return;
    }
    String? text;
    if (_u.byGitCliff) {
      text = await cliffChangelog(
        ref.read(cliRunnerProvider),
        widget.data.repo.path,
        _tag,
      );
    }
    text ??= renderChangelog(_bare, _u.groups, date: DateTime.now());
    if (!mounted || ticket != _changelogFor) return;
    setState(() => _changelog = text!);
  }

  void _submit() {
    if (_error != null ||
        !_path.isWorkflow && _path.kind != ReleasePathKind.draft) {
      return;
    }
    Navigator.of(context).pop(
      CreateReleaseRequest(
        version: _bare,
        tag: _tag,
        path: _path,
        changelog: _changelog,
        saveChoice: _chosen != null && _save,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final ready =
        error == null &&
        (_path.isWorkflow || _path.kind == ReleasePathKind.draft);
    final branch = widget.data.repo.defaultBranch;
    final specs = _u.specs.length;
    return Dialog(
      key: const ValueKey('create-release'),
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Criar release',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                        plural(_u.commitCount, 'commit', 'commits'),
                        if (specs > 0) plural(specs, 'spec', 'specs'),
                      ].join(' e ') +
                      (_u.lastTag == null
                          ? ' desde o primeiro commit.'
                          : ' desde ${_u.lastTag}.'),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                const _Label('Versão'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 200,
                      child: TextField(
                        key: const ValueKey('release-version'),
                        controller: _version,
                        autofocus: true,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: error == null
                                  ? AppColors.amber
                                  : AppColors.red,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: error == null
                                  ? AppColors.amber
                                  : AppColors.red,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          unawaited(_refreshChangelog());
                        },
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _VersionNote(state: this, error: error),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _Label('Como a release vai ser feita'),
                _PathBox(
                  path: _path,
                  candidates: widget.path.kind == ReleasePathKind.ambiguous
                      ? widget.path.candidates
                      : const [],
                  chosen: _chosen,
                  save: _save,
                  branch: branch,
                  version: _bare,
                  onChoose: (w) => setState(() {
                    _chosen = w;
                    _path = widget.path.choose(w);
                  }),
                  onSave: (v) => setState(() => _save = v),
                ),
                const SizedBox(height: 22),
                ChangelogBox(
                  label: 'Prévia do changelog',
                  text: _changelog,
                  maxHeight: 200,
                ),
                const SizedBox(height: 16),
                Container(
                  key: const ValueKey('release-what-happens'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _whatHappens(),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      key: const ValueKey('release-cancel'),
                      label: 'Cancelar',
                      height: 40,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    AmberButton(
                      key: const ValueKey('release-dispatch'),
                      label: 'Disparar release',
                      height: 40,
                      fontSize: 14,
                      onTap: ready ? _submit : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One line on what happens on GitHub (R5).
  String _whatHappens() {
    final tag = _error == null ? _tag : 'da versão';
    final branch = widget.data.repo.defaultBranch;
    final w = _path.workflow;
    if (_path.kind == ReleasePathKind.draft) {
      return 'No GitHub: cria a release $tag em rascunho, apontando para a '
          '$branch, com esta prévia como notas. A tag nasce quando você '
          'publicar o rascunho no GitHub. A release não se desfaz pelo app.';
    }
    if (w == null) {
      return 'Escolha o workflow que faz a release deste repositório.';
    }
    return 'No GitHub: o workflow ${w.label} roda na $branch e cria a tag '
        '$tag e a release (e o PR da versão, se ele abrir um). Tag e release '
        'não se desfazem pelo app.';
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

class _VersionNote extends StatelessWidget {
  const _VersionNote({required this.state, required this.error});

  final _CreateReleaseDialogState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final u = state._u;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          error!,
          key: const ValueKey('release-version-error'),
          style: const TextStyle(fontSize: 13, color: AppColors.red),
        ),
      );
    }
    final suggested = '${u.suggested}' == state._bare;
    return Column(
      key: const ValueKey('release-version-ok'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check, size: 16, color: AppColors.teal),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                suggested
                    ? '${u.byGitCliff ? 'Sugerida pelo git-cliff' : 'Sugerida pelos commits'}: '
                          '${u.reason.label}'
                    : 'Versão válida',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${u.lastTag == null ? 'Primeira versão' : 'Última versão: ${u.lastTag}'}'
          ' · a tag ${state._tag} ainda não existe',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _PathBox extends StatelessWidget {
  const _PathBox({
    required this.path,
    required this.candidates,
    required this.chosen,
    required this.save,
    required this.branch,
    required this.version,
    required this.onChoose,
    required this.onSave,
  });

  final ReleasePath path;

  /// The workflows to pick from (R6: two candidates, nothing configured).
  final List<ReleaseWorkflow> candidates;
  final ReleaseWorkflow? chosen;
  final bool save;
  final String branch;
  final String version;
  final ValueChanged<ReleaseWorkflow> onChoose;
  final ValueChanged<bool> onSave;

  @override
  Widget build(BuildContext context) {
    final w = path.workflow;
    // A Material, not a coloured box: the radio tiles paint on it.
    return Material(
      key: const ValueKey('release-path'),
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (candidates.isNotEmpty) ...[
              const Text(
                'Há mais de um workflow de release e nenhum configurado. '
                'Qual roda a release?',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              RadioGroup<ReleaseWorkflow>(
                groupValue: chosen,
                onChanged: (v) {
                  if (v != null) onChoose(v);
                },
                child: Column(
                  children: [
                    for (final c in candidates)
                      RadioListTile<ReleaseWorkflow>(
                        key: ValueKey('release-candidate-${c.file}'),
                        value: c,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          c.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          c.file,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('release-save-choice'),
                value: save,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Salvar a escolha em ${ProjectConfig.filePath}',
                  style: const TextStyle(fontSize: 13),
                ),
                onChanged: (v) => onSave(v ?? false),
              ),
              if (w != null) const Divider(height: 16),
            ],
            if (w != null || path.kind == ReleasePathKind.draft)
              Row(
                children: [
                  const Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 14),
                            children: w == null
                                ? [
                                    const TextSpan(
                                      text: 'Rascunho de release na ',
                                    ),
                                    TextSpan(
                                      text: branch,
                                      style: const TextStyle(
                                        fontFamily: AppFonts.mono,
                                      ),
                                    ),
                                  ]
                                : [
                                    const TextSpan(text: 'Workflow '),
                                    TextSpan(
                                      text: w.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const TextSpan(text: ' na '),
                                    TextSpan(
                                      text: branch,
                                      style: const TextStyle(
                                        fontFamily: AppFonts.mono,
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          path.command(branch: branch, version: version),
                          key: const ValueKey('release-command'),
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    chosen != null ? 'escolhido agora' : path.origin,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
