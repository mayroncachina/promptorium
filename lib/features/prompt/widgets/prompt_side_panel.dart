import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/agent_provider.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/footer_stats.dart' show formatTokens;
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../refine_changes.dart' show RefineSpecPanel;
import '../refine_origin.dart' show refineOriginOf;
import 'prompt_composer.dart' show FileChip;
import 'prompt_dialogs.dart';

/// Shortcut of "Recolher painel" / "Mostrar painel" (SPEC-056 R8).
const sidePanelShortcut = SingleActivator(
  LogicalKeyboardKey.keyB,
  control: true,
  alt: true,
);

/// Width of the collapsed panel (R8) and of a section balloon (R9).
const sideStripWidth = 48.0;
const sideBalloonWidth = 260.0;

/// Below this width of the Prompt screen the panel starts collapsed (R10).
const sidePanelNarrowWidth = 1100.0;

/// Whether the panel is collapsed (R8, R10): below [sidePanelNarrowWidth]
/// it starts collapsed and the button holds until the band changes
/// ([override]); above it the stored choice ([stored]) counts.
bool sidePanelCollapsed({
  required bool narrow,
  required bool stored,
  bool? override,
}) => override ?? (narrow || stored);

const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
const _value = TextStyle(fontSize: 12, color: AppColors.text);
final _mono = _value.copyWith(fontFamily: AppFonts.mono);

/// Folder, access and tokens of the conversation (+ the cited files when
/// [withFiles]).
class PromptContextSection extends StatelessWidget {
  const PromptContextSection({
    super.key,
    required this.workspace,
    required this.conversation,
    required this.mode,
    required this.files,
    this.withFiles = true,
    this.trailing,
  });

  final Workspace? workspace;
  final Conversation? conversation;
  final PromptMode mode;
  final List<String> files;
  final bool withFiles;

  /// Next to the title ("Recolher painel").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    Widget row(String k, String v, TextStyle style, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(k, style: _label),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v,
              key: key,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              const Expanded(child: Text('CONTEXTO', style: sectionTitleStyle)),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 4),
        row('Pasta', workspace == null ? '—' : '${workspace!.name}/', _mono),
        row(
          'Acesso',
          mode.access,
          _value,
          key: const ValueKey('context-access'),
        ),
        row(
          'Tokens',
          c == null ? '—' : formatTokens(c.tokensIn + c.tokensOut),
          _mono,
          key: const ValueKey('context-tokens'),
        ),
        if (withFiles && files.isNotEmpty) ...[
          const SizedBox(height: 4),
          PromptFilesSection(files: files),
        ],
      ],
    );
  }
}

/// `@files` of the conversation as chips.
class PromptFilesSection extends StatelessWidget {
  const PromptFilesSection({super.key, required this.files, this.title});

  final List<String> files;

  /// Shown above the chips (the balloon has no other heading).
  final String? title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (title != null) ...[
        Text(title!, style: sectionTitleStyle),
        const SizedBox(height: 8),
      ],
      if (files.isEmpty)
        const Text('Nenhum arquivo citado.', style: _label)
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final f in files) FileChip(path: f)],
        ),
    ],
  );
}

/// The saved prompts (click inserts the body in the composer).
class SavedPromptsSection extends ConsumerWidget {
  const SavedPromptsSection({super.key, required this.onInsert});

  final ValueChanged<SavedPrompt> onInsert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompts = ref.watch(savedPromptsProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('PROMPTS SALVOS', style: sectionTitleStyle),
            ),
            InkWell(
              key: const ValueKey('saved-prompt-new'),
              onTap: () => showSavePromptDialog(context),
              child: const Text(
                'Novo',
                style: TextStyle(fontSize: 12, color: AppColors.amber),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (prompts.isEmpty)
          const Text(
            'Nenhum prompt salvo.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        for (final p in prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: AppColors.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                key: ValueKey('saved-prompt-${p.command}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onInsert(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '/${p.command}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 12,
                                color: AppColors.amber,
                              ),
                            ),
                          ),
                          Text(
                            p.uses == 1 ? '1 uso' : '${p.uses} usos',
                            key: ValueKey('saved-prompt-uses-${p.command}'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (p.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          p.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Right column of the Prompt screen: context of the conversation and the
/// saved prompts. [onCollapse] = "Recolher painel" (SPEC-056 R8).
class PromptSidePanel extends StatelessWidget {
  const PromptSidePanel({
    super.key,
    required this.workspace,
    required this.conversation,
    required this.mode,
    required this.files,
    required this.onInsert,
    this.onCollapse,
  });

  final Workspace? workspace;
  final Conversation? conversation;
  final PromptMode mode;

  /// `@files` of the conversation (sent + attached in the composer).
  final List<String> files;
  final ValueChanged<SavedPrompt> onInsert;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return ColoredBox(
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // SPEC-026 R5: refine conversations with a stored origin.
          if (c != null && refineOriginOf(c) != null)
            RefineSpecPanel(conversation: c),
          PromptContextSection(
            workspace: workspace,
            conversation: c,
            mode: mode,
            files: files,
            trailing: onCollapse == null
                ? null
                : _StripButton(
                    key: const ValueKey('side-panel-collapse'),
                    icon: Icons.view_sidebar_outlined,
                    tooltip: 'Recolher painel (Ctrl+Alt+B)',
                    onPressed: onCollapse!,
                  ),
          ),
          const SizedBox(height: 18),
          SavedPromptsSection(onInsert: onInsert),
        ],
      ),
    );
  }
}

/// A section of the collapsed panel (R8, R9).
enum SideSection {
  context('Contexto', Icons.info_outline),
  files('Arquivos citados', Icons.insert_drive_file_outlined),
  prompts('Prompts salvos', Icons.bookmark_border);

  const SideSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The panel collapsed in a [sideStripWidth] strip (R8): Mostrar painel, one
/// button per section (each opens its balloon over the conversation, R9) and
/// the tokens, written vertically.
class PromptSideStrip extends StatefulWidget {
  const PromptSideStrip({
    super.key,
    required this.workspace,
    required this.conversation,
    required this.mode,
    required this.files,
    required this.onInsert,
    required this.onExpand,
  });

  final Workspace? workspace;
  final Conversation? conversation;
  final PromptMode mode;
  final List<String> files;
  final ValueChanged<SavedPrompt> onInsert;
  final VoidCallback onExpand;

  @override
  State<PromptSideStrip> createState() => _PromptSideStripState();
}

class _PromptSideStripState extends State<PromptSideStrip> {
  final _portal = OverlayPortalController();
  final _links = {for (final s in SideSection.values) s: LayerLink()};
  final _balloonFocus = FocusNode(debugLabel: 'side-balloon');
  SideSection? _open;

  /// The strip and the balloon: a click on either is not "outside".
  final _region = Object();

  @override
  void dispose() {
    _balloonFocus.dispose();
    super.dispose();
  }

  void _toggle(SideSection s) {
    if (_open == s) return _close();
    setState(() => _open = s);
    _portal.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open != null) _balloonFocus.requestFocus();
    });
  }

  void _close() {
    if (_open == null) return;
    setState(() => _open = null);
    _portal.hide();
  }

  Widget _balloon(BuildContext context) {
    final s = _open;
    if (s == null) return const SizedBox.shrink();
    final content = switch (s) {
      SideSection.context => PromptContextSection(
        workspace: widget.workspace,
        conversation: widget.conversation,
        mode: widget.mode,
        files: widget.files,
        withFiles: false,
      ),
      SideSection.files => PromptFilesSection(
        files: widget.files,
        title: 'ARQUIVOS CITADOS',
      ),
      SideSection.prompts => SavedPromptsSection(
        onInsert: (p) {
          _close();
          widget.onInsert(p);
        },
      ),
    };
    return CompositedTransformFollower(
      link: _links[s]!,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.topRight,
      offset: const Offset(-10, -6),
      child: Align(
        alignment: Alignment.topRight,
        child: TapRegion(
          groupId: _region,
          onTapOutside: (_) => _close(),
          child: Focus(
            focusNode: _balloonFocus,
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.escape) {
                _close();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: s.label,
              child: Material(
                key: ValueKey('side-balloon-${s.name}'),
                color: AppColors.panelSolid,
                elevation: 6,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: sideBalloonWidth,
                    maxWidth: sideBalloonWidth,
                    maxHeight: 420,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final tokens = c == null
        ? null
        : '${formatTokens(c.tokensIn + c.tokensOut)} tokens';
    Widget section(SideSection s) {
      final count = s == SideSection.files ? widget.files.length : 0;
      return CompositedTransformTarget(
        link: _links[s]!,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            backgroundColor: AppColors.amber,
            textColor: AppColors.background,
            smallSize: 8,
            offset: const Offset(2, -2),
            child: _StripButton(
              key: ValueKey('side-strip-${s.name}'),
              icon: s.icon,
              tooltip: s.label,
              semanticLabel: count > 0 ? '${s.label}, $count' : s.label,
              selected: _open == s,
              onPressed: () => _toggle(s),
            ),
          ),
        ),
      );
    }

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _balloon,
      child: TapRegion(
        groupId: _region,
        child: ColoredBox(
          color: AppColors.panel,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                _StripButton(
                  key: const ValueKey('side-panel-expand'),
                  icon: Icons.view_sidebar_outlined,
                  tooltip: 'Mostrar painel (Ctrl+Alt+B)',
                  highlighted: true,
                  onPressed: widget.onExpand,
                ),
                const SizedBox(height: 10),
                const SizedBox(
                  width: 24,
                  child: Divider(height: 1, color: AppColors.border),
                ),
                const SizedBox(height: 10),
                for (final s in SideSection.values) section(s),
                const Spacer(),
                if (tokens != null)
                  RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      tokens,
                      key: const ValueKey('side-strip-tokens'),
                      maxLines: 1,
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
        ),
      ),
    );
  }
}

/// 32 px icon button of the strip and of the panel header (R11: tooltip
/// and label).
class _StripButton extends StatelessWidget {
  const _StripButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.semanticLabel,
    this.selected = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final String? semanticLabel;
  final VoidCallback onPressed;
  final bool selected;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final active = selected || highlighted;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: SizedBox.square(
          dimension: 32,
          child: IconButton(
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            iconSize: 17,
            color: active ? AppColors.amber : AppColors.textSecondary,
            focusColor: AppColors.amber.withValues(alpha: .25),
            style: IconButton.styleFrom(
              backgroundColor: selected
                  ? AppColors.amber.withValues(alpha: .1)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: highlighted
                    ? BorderSide(color: AppColors.amber.withValues(alpha: .6))
                    : BorderSide.none,
              ),
            ),
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}
