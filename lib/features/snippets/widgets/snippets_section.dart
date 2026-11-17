import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../snippet_actions.dart';
import '../snippet_naming.dart';
import 'snippets_dialog.dart';

/// How many snippets the section of the Prompt panel shows (R13).
const snippetsSectionSize = 5;

/// SNIPPETS of the Prompt panel (R13): the five used last; a click inserts
/// in the composer, Copiar and Editar on hover, "Ver todos (N)" opens the
/// dialog. [onDone] runs before an action (the balloon of the strip closes).
class SnippetsSection extends ConsumerWidget {
  const SnippetsSection({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final all = ws == null
        ? const <Snippet>[]
        : ref.watch(snippetsProvider(ws.id)).value ?? const <Snippet>[];
    return Column(
      key: const ValueKey('snippets-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: Text('SNIPPETS', style: sectionTitleStyle)),
            if (all.isNotEmpty)
              Semantics(
                button: true,
                label: 'Ver todos os snippets, ${all.length}',
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('snippets-see-all'),
                  onTap: () {
                    onDone?.call();
                    unawaited(showSnippetsDialog(context, ref));
                  },
                  child: Text(
                    'Ver todos (${all.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.amber,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (all.isEmpty)
          const Text(
            'Salve um bloco de código pelo botão Salvar da resposta.',
            key: ValueKey('snippets-section-empty'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        for (final s in all.take(snippetsSectionSize))
          _SnippetTile(snippet: s, onDone: onDone),
      ],
    );
  }
}

class _SnippetTile extends ConsumerStatefulWidget {
  const _SnippetTile({required this.snippet, this.onDone});

  final Snippet snippet;
  final VoidCallback? onDone;

  @override
  ConsumerState<_SnippetTile> createState() => _SnippetTileState();
}

class _SnippetTileState extends ConsumerState<_SnippetTile> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.snippet;
    final name = shortName(s.name);
    final meta = snippetMeta(s.language, s.body);
    Widget iconButton(
      String key,
      IconData icon,
      String label,
      VoidCallback f,
    ) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: 26,
          child: IconButton(
            key: ValueKey('$key-${s.id}'),
            padding: EdgeInsets.zero,
            iconSize: 14,
            color: AppColors.textSecondary,
            onPressed: f,
            icon: Icon(icon),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (v) => setState(() => _focus = v),
          child: Material(
            color: AppColors.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: _hover ? AppColors.borderHover : AppColors.border,
              ),
            ),
            child: InkWell(
              key: ValueKey('snippet-tile-${s.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                widget.onDone?.call();
                unawaited(
                  insertSnippet(
                    ref,
                    s,
                    messenger: ScaffoldMessenger.maybeOf(context),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Inserir snippet ${s.name}, $meta',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              meta,
                              maxLines: 1,
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // In the tree (and the Tab order) while hidden: focusing
                    // one shows them.
                    Opacity(
                      opacity: _hover || _focus ? 1 : 0,
                      alwaysIncludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          iconButton(
                            'snippet-tile-copy',
                            Icons.copy_outlined,
                            'Copiar snippet $name',
                            () => copySnippet(
                              ref,
                              s,
                              messenger: ScaffoldMessenger.maybeOf(context),
                            ),
                          ),
                          iconButton(
                            'snippet-tile-edit',
                            Icons.edit_outlined,
                            'Editar snippet $name',
                            () {
                              widget.onDone?.call();
                              unawaited(
                                showSnippetsDialog(
                                  context,
                                  ref,
                                  selectId: s.id,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
