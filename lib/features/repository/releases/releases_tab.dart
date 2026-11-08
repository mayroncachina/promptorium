import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/update/changelog_section.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../board/board_screen.dart' show boardSelectedSpecProvider;
import '../../sessions/widgets/session_style.dart';
import '../repository_info.dart';
import '../repository_screen.dart';
import 'release_timeline.dart';
import 'releases_state.dart';
import 'unreleased.dart';

/// The Releases tab (SPEC-044; docs/mockups/spec-044/1-releases.png).
final releasesTab = RepositoryTab(
  id: 'releases',
  label: 'Releases',
  builder: (context, repo) => ReleasesTab(repo: repo),
  headerTrailing: (context, repo) => GhStatusLabel(repo: repo),
);

/// Green of a published version (the mockup's `#5BC88A`).
const _published = Color(0xFF5BC88A);

Color releaseStateColor(ReleaseState s) => switch (s) {
  ReleaseState.published => _published,
  ReleaseState.draft => AppColors.blue,
  ReleaseState.prerelease => AppColors.lilac,
  ReleaseState.tagOnly => AppColors.textSecondary,
};

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// `7 nov 2026`.
String formatReleaseDate(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// `7 nov 2026, 10:41`.
String formatReleaseDateTime(DateTime? d) =>
    d == null ? '' : '${formatReleaseDate(d)}, ${formatClock(d)}';

/// `12,9 MB` (MiB, with a decimal comma).
String formatBytes(int? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = i == 0 ? '$bytes' : v.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${units[i]}';
}

String plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// Opens [url] in the browser (`xdg-open`); errors only log.
Future<void> openExternal(WidgetRef ref, String url) async {
  try {
    await ref.read(cliRunnerProvider)('xdg-open', [url]);
  } catch (e) {
    debugPrint('xdg-open $url: $e');
  }
}

/// `gh conectado como …` on the right of the header (Abas.dc.html), or
/// why the tab is read-only (R9).
class GhStatusLabel extends ConsumerWidget {
  const GhStatusLabel({super.key, required this.repo});

  final RepositoryInfo repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(releasesProvider(repo)).value;
    if (data == null) return const SizedBox.shrink();
    final auth = data.auth;
    final text = !auth.installed
        ? 'gh não instalado · só leitura'
        : !auth.loggedIn
        ? 'gh sem login · só leitura'
        : data.blocker != null
        ? 'só leitura'
        : auth.account == null
        ? 'gh conectado'
        : 'gh conectado como ${auth.account}';
    return Text(
      text,
      key: const ValueKey('repo-gh-status'),
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}

/// The selected version of the timeline (null = the first).
class SelectedReleaseController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? tag) => state = tag;
}

final selectedReleaseProvider =
    NotifierProvider<SelectedReleaseController, String?>(
      SelectedReleaseController.new,
    );

class ReleasesTab extends ConsumerWidget {
  const ReleasesTab({super.key, required this.repo});

  final RepositoryInfo repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(releasesProvider(repo));
    return switch (async) {
      AsyncData(:final value) => ReleasesView(data: value),
      AsyncError(:final error) => Center(
        child: Text(
          'Não foi possível ler as versões: $error',
          style: const TextStyle(color: AppColors.red, fontSize: 13),
        ),
      ),
      _ => const Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    };
  }
}

/// The card, the versions and the open version (R2, R3, R4, R9).
class ReleasesView extends ConsumerWidget {
  const ReleasesView({super.key, required this.data, this.onCreate});

  final ReleasesData data;

  /// "Criar release" (null = not offered yet).
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTag = ref.watch(selectedReleaseProvider);
    final selected =
        data.timeline.where((e) => e.tag == selectedTag).firstOrNull ??
        data.timeline.firstOrNull;
    return LayoutBuilder(
      builder: (context, box) {
        final side = (box.maxWidth * 0.36).clamp(320.0, 500.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  key: const ValueKey('releases-list'),
                  children: [
                    UnreleasedCard(data: data, onCreate: onCreate),
                    if (data.releasesError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'As releases do GitHub não vieram: '
                        '${data.releasesError}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.amber,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text('VERSÕES', style: sectionTitleStyle),
                    const SizedBox(height: 8),
                    if (data.timeline.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Nenhuma versão ainda: a primeira release cria a '
                          'primeira tag.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    for (final e in data.timeline)
                      VersionRow(
                        entry: e,
                        selected: e.tag == selected?.tag,
                        onTap: () => ref
                            .read(selectedReleaseProvider.notifier)
                            .select(e.tag),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: side,
                child: selected == null
                    ? const SizedBox.shrink()
                    : ReleaseDetailPanel(entry: selected),
              ),
            ],
          ),
        );
      },
    );
  }
}

BoxDecoration _cardDecoration({Color border = AppColors.border}) =>
    BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border),
    );

/// "Não lançado" (R3): commits after the last tag, by type, the merged
/// specs and the suggested version, with "Ver changelog" and "Criar
/// release" (disabled with the reason when read-only, R9).
class UnreleasedCard extends ConsumerWidget {
  const UnreleasedCard({super.key, required this.data, this.onCreate});

  final ReleasesData data;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = data.unreleased;
    final last = u.lastTag;
    final title = u.isEmpty
        ? (last == null ? 'Nenhum commit ainda' : 'Nada novo desde $last')
        : last == null
        ? '${plural(u.commitCount, 'commit', 'commits')} na ${u.branch} desde '
              'o primeiro commit'
        : '${plural(u.commitCount, 'commit', 'commits')} na ${u.branch} desde '
              '$last';
    final canCreate = !u.isEmpty && data.blocker == null;
    return Container(
      key: const ValueKey('unreleased-card'),
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Não lançado',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.amber,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      key: const ValueKey('unreleased-title'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!u.isEmpty) ...[
                      const SizedBox(height: 4),
                      Text.rich(
                        key: const ValueKey('unreleased-suggested'),
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          children: [
                            TextSpan(
                              text: u.byGitCliff
                                  ? 'Versão sugerida pelo git-cliff: '
                                  : 'Versão sugerida pelos commits: ',
                            ),
                            TextSpan(
                              text: u.suggestedTag,
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                            TextSpan(text: ' · ${u.reason.label}'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SmallButton(
                key: const ValueKey('releases-changelog'),
                label: 'Ver changelog',
                height: 40,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                onTap: u.isEmpty
                    ? null
                    : () => showChangelogPreview(context, u.changelog),
              ),
              const SizedBox(width: 12),
              Semantics(
                hint: data.blocker?.reason,
                child: AmberButton(
                  key: const ValueKey('releases-create'),
                  label: 'Criar release',
                  height: 40,
                  fontSize: 14,
                  onTap: canCreate ? onCreate : null,
                ),
              ),
            ],
          ),
          if (data.blocker case final b?) ...[
            const SizedBox(height: 14),
            BlockerNote(blocker: b),
          ],
          if (u.specs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'SPECS MERGEADAS · ${u.specs.length}',
              style: sectionTitleStyle.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 10),
            _SpecChips(specs: u.specs),
          ],
          if (u.groups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('POR TIPO', style: sectionTitleStyle.copyWith(fontSize: 11)),
            const SizedBox(height: 6),
            for (final g in u.groups) _GroupRow(group: g),
          ],
        ],
      ),
    );
  }
}

/// Why Criar release is off and the command that solves it (R9).
class BlockerNote extends StatelessWidget {
  const BlockerNote({super.key, required this.blocker});

  final GhBlocker blocker;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('releases-blocker'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${blocker.reason} A aba fica só leitura: as tags, o que não foi '
          'lançado e a prévia continuam aqui.',
          style: const TextStyle(fontSize: 13),
        ),
        if (blocker.fix case final fix?) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: SelectableText(
                  fix,
                  key: const ValueKey('releases-blocker-fix'),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.amber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SmallButton(
                label: 'Copiar',
                height: 26,
                fontSize: 11,
                onTap: () => Clipboard.setData(ClipboardData(text: fix)),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

const _specDots = [
  Color(0xFF8EC5FF),
  Color(0xFFC59BFF),
  _published,
  AppColors.amber,
];

class _SpecChips extends ConsumerWidget {
  const _SpecChips({required this.specs});

  final List<MergedSpec> specs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final all = ws == null
        ? const <Spec>[]
        : ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final byCode = {for (final s in all) s.code: s};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, m) in specs.indexed)
          () {
            final spec = byCode[m.code];
            final title = spec?.title ?? m.title;
            return InkWell(
              key: ValueKey('merged-spec-${m.code}'),
              borderRadius: BorderRadius.circular(6),
              // Opens the spec on the Quadro (R3).
              onTap: spec == null
                  ? null
                  : () {
                      ref
                          .read(boardSelectedSpecProvider.notifier)
                          .select(spec.id);
                      ref
                          .read(navigationProvider.notifier)
                          .request(AppSection.tasks);
                    },
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Dot(_specDots[i % _specDots.length], size: 7),
                    const SizedBox(width: 8),
                    Text(
                      m.code,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (title != null) ...[
                      const SizedBox(width: 8),
                      Text(title, style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
            );
          }(),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final CommitGroup group;

  @override
  Widget build(BuildContext context) => Container(
    height: 37,
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 170,
          child: Text(group.title, style: const TextStyle(fontSize: 14)),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${group.commits.length}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            group.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A pill with the state of a version (`Publicada · mais recente`).
class ReleaseStatePill extends StatelessWidget {
  const ReleaseStatePill({super.key, required this.entry, this.latest = false});

  final ReleaseEntry entry;

  /// Adds "· mais recente" when the entry is the latest.
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final color = releaseStateColor(entry.state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        latest && entry.isLatest
            ? '${entry.state.label} · mais recente'
            : entry.state.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// A version of the timeline (R2).
class VersionRow extends StatelessWidget {
  const VersionRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final ReleaseEntry entry;
  final bool selected;
  final VoidCallback onTap;

  /// Only the tag, the state and the date (the side list while a run is
  /// followed).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = releaseStateColor(entry.state);
    const muted = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.surfaceRaised : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.borderHover : Colors.transparent,
          ),
        ),
        child: InkWell(
          key: ValueKey('version-${entry.tag}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: compact ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: compact ? null : BorderRadius.circular(4),
                    color: selected ? color : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 94,
                  child: Text(
                    entry.tag,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: compact ? 110 : 134,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ReleaseStatePill(entry: entry),
                  ),
                ),
                if (compact) ...[
                  const Spacer(),
                  Text(formatReleaseDate(entry.date), style: muted),
                  const SizedBox(width: 14),
                ] else ...[
                  SizedBox(
                    width: 130,
                    child: Text(formatReleaseDate(entry.date), style: muted),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 124,
                    child: Text(
                      entry.commits == null
                          ? ''
                          : plural(entry.commits!, 'commit', 'commits'),
                      style: muted,
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      entry.state == ReleaseState.tagOnly
                          ? ''
                          : plural(entry.assets.length, 'pacote', 'pacotes'),
                      style: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The open version (R2): notes, files with their size and "Abrir no
/// GitHub".
class ReleaseDetailPanel extends ConsumerWidget {
  const ReleaseDetailPanel({super.key, required this.entry});

  final ReleaseEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = entry.section;
    final meta = [
      if (entry.date != null) formatReleaseDateTime(entry.date),
      if (entry.commits != null)
        entry.previousTag == null
            ? plural(entry.commits!, 'commit', 'commits')
            : '${plural(entry.commits!, 'commit', 'commits')} desde '
                  '${entry.previousTag}',
    ].join(' · ');
    return Container(
      key: const ValueKey('release-detail'),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      entry.tag,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ReleaseStatePill(entry: entry, latest: true),
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (entry.state == ReleaseState.tagOnly)
                  const Text(
                    'Só a tag: não há release no GitHub para esta versão.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                else if (section.isEmpty)
                  const Text(
                    'A release não tem notas.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                else if (section.rawText != null)
                  SelectableText(
                    section.rawText!,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  )
                else
                  for (final g in section.groups) _NotesGroup(group: g),
                if (entry.assets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Pacotes · ${entry.assets.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final a in entry.assets) _AssetRow(asset: a),
                ],
              ],
            ),
          ),
          if (entry.url != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SmallButton(
                  key: const ValueKey('release-open-github'),
                  label: 'Abrir no GitHub',
                  height: 40,
                  fontSize: 14,
                  onTap: () => openExternal(ref, entry.url!),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotesGroup extends StatelessWidget {
  const _NotesGroup({required this.group});

  final ChangelogGroup group;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (final item in group.items)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Text(item, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _AssetRow extends ConsumerWidget {
  const _AssetRow({required this.asset});

  final GhAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
    onTap: asset.url == null ? null : () => openExternal(ref, asset.url!),
    child: Container(
      height: 47,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.download_outlined,
            size: 15,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              asset.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 13),
            ),
          ),
          Text(
            formatBytes(asset.size),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The changelog the version will get (R4): read-only, with "Copiar".
Future<void> showChangelogPreview(BuildContext context, String text) =>
    showAppDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => AlertDialog(
        key: const ValueKey('changelog-preview'),
        backgroundColor: AppColors.panel,
        title: const Text(
          'Prévia do changelog',
          style: TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: 640,
          child: ChangelogBox(text: text, maxHeight: 460),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );

/// Mono, read-only text of a changelog with "Copiar" on top.
class ChangelogBox extends StatelessWidget {
  const ChangelogBox({super.key, required this.text, this.maxHeight = 220});

  final String text;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: SmallButton(
          key: const ValueKey('changelog-copy'),
          label: 'Copiar',
          height: 26,
          fontSize: 11,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showAppToast(
              const SnackBar(
                content: Text('Changelog copiado.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: SelectableText(
            text,
            key: const ValueKey('changelog-text'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ),
      ),
    ],
  );
}
