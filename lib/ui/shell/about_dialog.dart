import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/installer.dart';
import '../../data/providers.dart';
import '../../core/update/update_check.dart';
import '../theme/tokens.dart';

const repositoryUrl = 'https://github.com/mayroncachina/promptorium';

/// Local `CHANGELOG.md` (bundled asset, so it works offline); read on first
/// use, when the dialog opens.
final changelogProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString('CHANGELOG.md'),
);

/// Diálogo Sobre (F1).
Future<void> showAboutPromptorium(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const AboutPromptoriumDialog(),
);

class AboutPromptoriumDialog extends ConsumerWidget {
  const AboutPromptoriumDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    final changelog = ref.watch(changelogProvider);
    final update = ref.watch(updateCheckerProvider);
    final style = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .copyWith(p: const TextStyle(fontSize: 12));
    // The dialog route is outside AppShell's shortcuts: F1 closes here.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          key: const ValueKey('about-dialog'),
          backgroundColor: AppColors.panel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: SessionColors.selectedBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sobre o Promptorium',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Promptorium',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        version == null ? 'Versão …' : 'Versão $version',
                        key: const ValueKey('about-version'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        key: const ValueKey('about-repo'),
                        onTap: () => Process.run('xdg-open', [repositoryUrl]),
                        child: const Text(
                          repositoryUrl,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.amber,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      const _CheckNowButton(),
                      if (update != null) ...[
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('about-update-now'),
                          onPressed: () async {
                            if (await _confirmUpdate(context, update) &&
                                context.mounted) {
                              _startUpdate(context, ref, update);
                            }
                          },
                          child: const Text('Atualizar agora'),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('about-changelog'),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (update != null) ...[
                          Text(
                            'Novidades da ${update.version}',
                            key: const ValueKey('about-update-notes-title'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          MarkdownBody(
                            key: const ValueKey('about-update-notes'),
                            data: update.notes.trim().isEmpty
                                ? '_Sem notas nesta versão._'
                                : update.notes,
                            styleSheet: style,
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                        ],
                        changelog.when(
                          data: (md) => MarkdownBody(
                            key: const ValueKey('about-changelog-body'),
                            data: md,
                            styleSheet: style,
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const Text(
                            'Changelog indisponível.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Verificar agora": forces a lookup of the latest release; the dialog
/// watches [updateCheckerProvider], so the result shows up by itself.
/// Explicit confirmation before anything is downloaded. Returns true only
/// when the user confirms; the download itself arrives in the next steps.
Future<bool> _confirmUpdate(
  BuildContext context,
  AvailableUpdate update,
) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('about-update-confirm'),
      backgroundColor: AppColors.panel,
      title: const Text('Atualizar o Promptorium?'),
      content: Text(
        'A versão ${update.version} será baixada e instalada, e o app '
        'será reiniciado. Nada é baixado antes da sua confirmação.',
      ),
      actions: [
        TextButton(
          key: const ValueKey('about-update-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('about-update-confirm-yes'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Atualizar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// After the confirmation: picks the Linux asset and downloads it,
/// showing the progress in a dialog.
void _startUpdate(BuildContext context, WidgetRef ref, AvailableUpdate update) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppColors.scrim,
    builder: (_) => _DownloadDialog(update: update),
  );
}

class _DownloadDialog extends ConsumerStatefulWidget {
  const _DownloadDialog({required this.update});

  final AvailableUpdate update;

  @override
  ConsumerState<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends ConsumerState<_DownloadDialog> {
  DownloadProgress? _progress;
  File? _file;
  String? _error;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final installer = ref.read(updateInstallerProvider);
    try {
      final asset = pickAsset(
        widget.update.assets,
        preferDeb: await installer.hasPkexec(),
      );
      if (asset == null) {
        throw const FileSystemException(
          'Nenhum pacote compatível com o Linux.',
        );
      }
      await for (final p in installer.download(
        asset,
        releaseAssets: widget.update.assets,
      )) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _file = p.file;
        });
      }
      final file = _file;
      if (file == null || !mounted) return;
      setState(() => _installing = true);
      final db = ref.read(appDatabaseProvider);
      await installer.installAndRestart(file, closeDatabase: db.close);
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = e is FileSystemException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final fraction = p?.fraction;
    return AlertDialog(
      key: const ValueKey('about-download'),
      backgroundColor: AppColors.panel,
      title: Text('Baixando a ${widget.update.version}'),
      content: _error != null
          ? Text(_error!, key: const ValueKey('about-download-error'))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  key: const ValueKey('about-download-progress'),
                  value: _file != null ? 1 : fraction,
                ),
                const SizedBox(height: 8),
                Text(
                  _installing
                      ? 'Instalando e reiniciando…'
                      : _file != null
                      ? 'Download concluído.'
                      : fraction == null
                      ? 'Baixando…'
                      : '${(fraction * 100).round()}%',
                  key: const ValueKey('about-download-label'),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
      actions: [
        if (_error != null) ...[
          TextButton(
            key: const ValueKey('about-open-release'),
            onPressed: () => ref
                .read(updateInstallerProvider)
                .openReleasePage(widget.update.url),
            child: const Text('Abrir página da release'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ],
    );
  }
}

class _CheckNowButton extends ConsumerStatefulWidget {
  const _CheckNowButton();

  @override
  ConsumerState<_CheckNowButton> createState() => _CheckNowButtonState();
}

class _CheckNowButtonState extends ConsumerState<_CheckNowButton> {
  bool _busy = false;
  bool _checked = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await ref.read(updateCheckerProvider.notifier).check(force: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _checked = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateCheckerProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: const ValueKey('about-check-now'),
          onPressed: _busy ? null : _check,
          child: Text(_busy ? 'Verificando…' : 'Verificar agora'),
        ),
        if (_checked && !_busy && update == null)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            key: ValueKey('about-up-to-date'),
            child: Text(
              'Você já está na versão mais recente.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}
