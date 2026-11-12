import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_info.dart';
import '../../core/update/changelog_section.dart';
import '../../core/update/installer.dart';
import '../../core/update/update_check.dart';
import '../../features/sessions/widgets/session_style.dart';
import '../../features/splash/splash_painter.dart';
import '../../features/splash/splash_stage.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/app_dialog.dart';
import 'about_update_card.dart';
import 'update_flow.dart';

const repositoryUrl = 'https://github.com/mayroncachina/promptorium';
const changelogUrl = '$repositoryUrl/blob/main/CHANGELOG.md';

/// Local `CHANGELOG.md` (bundled asset, so it works offline); read on first
/// use, when the dialog opens.
final changelogProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString('CHANGELOG.md'),
  // A missing asset doesn't come back: say so at once (R6).
  retry: (_, _) => null,
);

/// Diálogo Sobre (F1).
Future<void> showAboutPromptorium(BuildContext context) => showAppDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const AboutPromptoriumDialog(),
);

/// Sobre (SPEC-038): the identity on the left; on the right the update card
/// and the news of the last version, in a single window.
class AboutPromptoriumDialog extends ConsumerStatefulWidget {
  const AboutPromptoriumDialog({super.key});

  @override
  ConsumerState<AboutPromptoriumDialog> createState() =>
      _AboutPromptoriumDialogState();
}

class _AboutPromptoriumDialogState
    extends ConsumerState<AboutPromptoriumDialog> {
  final _actionFocus = FocusNode(debugLabel: 'about-action');
  final _cardFocus = FocusNode(debugLabel: 'about-card', skipTraversal: true);
  final _keepFocus = FocusNode(debugLabel: 'about-keep-downloading');
  bool _askingClose = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(updateFlowProvider, _onFlowChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusAction());
  }

  @override
  void dispose() {
    _actionFocus.dispose();
    _cardFocus.dispose();
    _keepFocus.dispose();
    super.dispose();
  }

  /// The main action of the card or, in a state without one, the card.
  void _focusAction() {
    if (!mounted) return;
    (_actionFocus.parent != null ? _actionFocus : _cardFocus).requestFocus();
  }

  /// A new state may take away the button that had the focus: it stays on
  /// the card, and a focus that is elsewhere doesn't move (R11).
  void _onFlowChanged(UpdateFlowState? previous, UpdateFlowState next) {
    if (previous.runtimeType == next.runtimeType) return;
    if (next is! UpdateDownloading && _askingClose) {
      setState(() => _askingClose = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusAction());
    } else if (_cardFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusAction());
    }
  }

  /// `Esc`, F1, the X and the scrim while [PopScope] holds the screen (R9).
  void _onCloseRefused(UpdateFlowState state) {
    if (state is! UpdateDownloading) return;
    if (_askingClose) return _keepDownloading();
    setState(() => _askingClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keepFocus.requestFocus();
    });
  }

  void _keepDownloading() {
    setState(() => _askingClose = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusAction());
  }

  void _cancelAndClose() {
    ref.read(updateFlowProvider.notifier).cancelDownload();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateFlowProvider);
    final installing = state is UpdateInstalling;
    final holds = installing || state is UpdateDownloading;
    final asking = _askingClose && state is UpdateDownloading;
    // The dialog route is outside AppShell's shortcuts: F1 closes here.
    return PopScope(
      canPop: !holds,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onCloseRefused(state);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f1): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            key: const ValueKey('about-dialog'),
            backgroundColor: AppColors.panel,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: SessionColors.selectedBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 820,
              height: 560,
              child: Stack(
                children: [
                  ExcludeFocus(
                    excluding: asking,
                    // Tab: the right column, the logo, the links (SPEC-066 R6).
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Identity(paused: asking),
                          Expanded(
                            child: FocusTraversalOrder(
                              order: const NumericFocusOrder(1),
                              child: FocusTraversalGroup(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    16,
                                    0,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _Header(installing: installing),
                                      const SizedBox(height: 6),
                                      UpdateCard(
                                        actionFocus: _actionFocus,
                                        cardFocus: _cardFocus,
                                      ),
                                      const SizedBox(height: 16),
                                      const Expanded(child: _News()),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (asking)
                    Positioned.fill(
                      child: _CloseConfirmation(
                        keepFocus: _keepFocus,
                        onKeep: _keepDownloading,
                        onCancel: _cancelAndClose,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.installing});

  final bool installing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Sobre',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: const ValueKey('about-close'),
          tooltip: installing ? 'Aguarde a instalação terminar' : 'Fechar',
          icon: const Icon(Icons.close, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          onPressed: installing ? null : () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );
}

/// Left column: the opening animation, the version and the links (R2, R4).
class _Identity extends ConsumerWidget {
  const _Identity({required this.paused});

  /// The download confirmation is over the screen (SPEC-066 R7).
  final bool paused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    final installer = ref.read(updateInstallerProvider);
    return Container(
      key: const ValueKey('about-identity'),
      width: 300,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AboutLogo(paused: paused),
              ),
            ),
          ),
          Text(
            version == null
                ? AppInfo.platformName
                : 'v$version · ${AppInfo.platformName}',
            key: const ValueKey('about-version'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: FocusTraversalGroup(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                children: [
                  _Link(
                    key: const ValueKey('about-repo'),
                    label: 'Repositório',
                    onTap: () => installer.openReleasePage(repositoryUrl),
                  ),
                  _Link(
                    key: const ValueKey('about-history'),
                    label: 'Histórico completo',
                    onTap: () => installer.openReleasePage(changelogUrl),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The logo of Sobre (SPEC-066): the intro, then the calm rhythm while the
/// screen is open (R2, R3). The mouse agitates it (R4), and a click, Enter or
/// Space plays the intro again (R5, R6). With animations off it is a still
/// icon, outside the Tab order (R8).
class AboutLogo extends StatefulWidget {
  const AboutLogo({super.key, this.paused = false});

  /// Stops the flask where it is (R7).
  final bool paused;

  @override
  State<AboutLogo> createState() => _AboutLogoState();
}

class _AboutLogoState extends State<AboutLogo> {
  final _stage = GlobalKey<SplashStageState>();
  bool _hover = false;
  bool _focused = false;

  void _replay() => _stage.currentState?.replay();

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.animate(context);
    return SplashStage(
      key: _stage,
      ambient: SplashAmbient.calm,
      excited: animate && _hover,
      paused: widget.paused,
      iconSize: 148,
      titleSize: 24,
      subtitleSize: 12.5,
      gap: 6,
      iconBuilder: animate ? _button : null,
    );
  }

  Widget _button(BuildContext context, Widget icon) => MouseRegion(
    key: const ValueKey('about-logo'),
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: _detector(icon),
    ),
  );

  Widget _detector(Widget icon) => FocusableActionDetector(
    onShowFocusHighlight: (v) => setState(() => _focused = v),
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          _replay();
          return null;
        },
      ),
    },
    child: Tooltip(
      message: 'Tocar a abertura de novo',
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: GestureDetector(
        onTap: _replay,
        child: Semantics(
          button: true,
          label: 'Ícone do Promptorium',
          hint: 'Tocar a abertura de novo',
          onTap: _replay,
          excludeSemantics: true,
          child: DecoratedBox(
            key: const ValueKey('about-logo-ring'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _focused ? AppColors.amber : Colors.transparent,
                width: 2,
              ),
            ),
            child: icon,
          ),
        ),
      ),
    ),
  );
}

class _Link extends StatelessWidget {
  const _Link({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.amber),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.open_in_new, size: 12, color: AppColors.amber),
        ],
      ),
    ),
  );
}

/// Only the news of the last version (R5, R6): the notes of the update when
/// there is one, or else the section of the installed version.
class _News extends ConsumerWidget {
  const _News();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateCheckerProvider);
    if (update != null) {
      return _NewsBody(
        version: update.version,
        date: update.publishedAt?.toLocal(),
        section: latestChanges(update.notes, version: update.version),
      );
    }
    final installed = ref.watch(appVersionProvider).value;
    return ref
        .watch(changelogProvider)
        .when(
          data: (md) {
            final section = latestChanges(md, version: installed);
            return section.version == null
                ? const _NewsBody()
                : _NewsBody(
                    version: section.version,
                    date: section.date,
                    section: section,
                  );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const _NewsBody(),
        );
  }
}

class _NewsBody extends StatelessWidget {
  const _NewsBody({this.version, this.date, this.section});

  final String? version;
  final DateTime? date;

  /// Null when the changelog can't be read.
  final ChangelogSection? section;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    final section = this.section;
    const muted = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              version == null ? 'Novidades' : 'Novidades da $version',
              key: const ValueKey('about-news-title'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (date != null) ...[
              const SizedBox(width: 8),
              Text(
                formatDate(date),
                key: const ValueKey('about-news-date'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('about-changelog'),
            padding: const EdgeInsets.fromLTRB(0, 12, 4, 16),
            child: section == null
                ? const Text('Novidades indisponíveis.', style: muted)
                : section.isEmpty
                ? const Text(
                    'Sem novidades para mostrar nesta versão.',
                    style: muted,
                  )
                : MarkdownBody(
                    key: const ValueKey('about-changelog-body'),
                    data: section.markdown,
                    styleSheet: _newsStyle(context),
                  ),
          ),
        ),
      ],
    );
  }

  static MarkdownStyleSheet _newsStyle(BuildContext context) =>
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.text),
        h3: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        listBullet: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        listIndent: 12,
        blockSpacing: 6,
      );
}

/// Closing in the middle of a download, over the screen and inside the same
/// window (R9): the main action keeps downloading.
class _CloseConfirmation extends StatelessWidget {
  const _CloseConfirmation({
    required this.keepFocus,
    required this.onKeep,
    required this.onCancel,
  });

  final FocusNode keepFocus;
  final VoidCallback onKeep;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: ColoredBox(
      color: AppColors.scrim,
      child: Center(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          scopesRoute: true,
          namesRoute: true,
          label: 'Cancelar o download',
          child: Container(
            key: const ValueKey('about-close-confirm'),
            width: 400,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border.all(color: SessionColors.selectedBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cancelar o download?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'O que já foi baixado será descartado.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: UpdateActionRow([
                    SmallButton(
                      key: const ValueKey('about-close-cancel'),
                      label: 'Cancelar e fechar',
                      onTap: onCancel,
                      height: 32,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      background: AppColors.surfaceRaised,
                      border: SessionColors.selectedBorder,
                    ),
                    AmberButton(
                      key: const ValueKey('about-close-keep'),
                      label: 'Continuar baixando',
                      onTap: onKeep,
                      focusNode: keepFocus,
                      height: 32,
                      fontSize: 13,
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
