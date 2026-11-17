import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../data/repos/snippets_repo.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../../ui/widgets/code_editor/app_code_editor.dart';
import '../../code/worktree_files.dart' show fuzzyScore;
import '../../prompt/conversation_manager.dart'
    show selectedConversationProvider;
import '../../review/widgets/review_dialogs.dart' show ReviewDialogFrame;
import '../../sessions/session_manager.dart' show selectedSessionProvider;
import '../../sessions/widgets/session_style.dart';
import '../snippet_actions.dart';
import '../snippet_naming.dart';

/// Order of the list of the dialog (R9).
enum SnippetOrder {
  lastUsed('Usados por último'),
  name('Nome'),
  created('Criados por último');

  const SnippetOrder(this.label);

  final String label;
}

/// [list] filtered by [query] (name and description, [fuzzyScore]) and in
/// [order]. With a query the best match comes first.
List<Snippet> filterSnippets(
  List<Snippet> list,
  String query, {
  SnippetOrder order = SnippetOrder.lastUsed,
}) {
  final sorted = [...list];
  switch (order) {
    case SnippetOrder.lastUsed:
      sorted.sort((a, b) {
        final c = (b.lastUsedAt ?? b.createdAt).compareTo(
          a.lastUsedAt ?? a.createdAt,
        );
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    case SnippetOrder.name:
      sorted.sort((a, b) => a.nameKey.compareTo(b.nameKey));
    case SnippetOrder.created:
      sorted.sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
  }
  final q = query.trim();
  if (q.isEmpty) return sorted;
  final scored = <(Snippet, int)>[];
  for (final s in sorted) {
    final score = fuzzyScore('${s.name} ${s.description}', q);
    if (score != null) scored.add((s, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (s, _) in scored) s];
}

/// Opens the Snippets dialog of the active workspace (R9), on [selectId]
/// when given.
Future<void> showSnippetsDialog(
  BuildContext context,
  WidgetRef ref, {
  int? selectId,
}) async {
  final ws = ref.read(activeWorkspaceProvider);
  if (ws == null) return;
  await showAppDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => SnippetsDialog(
      workspace: ws,
      initialId: selectId,
      messenger: ScaffoldMessenger.maybeOf(context),
    ),
  );
}

/// The Snippets dialog (R9–R12): the list with the search on the left, the
/// open snippet on the right.
class SnippetsDialog extends ConsumerStatefulWidget {
  const SnippetsDialog({
    super.key,
    required this.workspace,
    this.initialId,
    this.messenger,
  });

  final Workspace workspace;
  final int? initialId;

  /// The screen's messenger: "Snippet inserido" shows there, after the
  /// dialog closes.
  final ScaffoldMessengerState? messenger;

  @override
  ConsumerState<SnippetsDialog> createState() => _SnippetsDialogState();
}

enum _Unsaved { save, discard, cancel }

class _SnippetsDialogState extends ConsumerState<SnippetsDialog> {
  final _query = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _code = CodeLineEditingController();
  final _listFocus = FocusNode(debugLabel: 'snippets-list');
  final _nameFocus = FocusNode(debugLabel: 'snippet-name');
  final _listScroll = ScrollController();

  /// The dialog's own messenger (its toasts show over the scrim).
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  SnippetOrder _order = SnippetOrder.lastUsed;

  /// The snippet open on the right, as last loaded or saved.
  Snippet? _open;
  String? _language;

  /// Row highlighted by ↑/↓ (Enter opens it).
  int _highlight = 0;
  String? _nameError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _description.addListener(_changed);
    _code.addListener(_changed);
    // The first list of the stream opens the snippet asked for (or the
    // first one).
    ref.listenManual(snippetsProvider(widget.workspace.id), (_, next) {
      // The list may arrive while a frame is being built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onList(next.value));
    }, fireImmediately: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listFocus.requestFocus();
    });
  }

  void _onList(List<Snippet>? list) {
    if (list == null || !mounted) return;
    final open = _open;
    if (open == null) {
      final first =
          list.where((s) => s.id == widget.initialId).firstOrNull ??
          filterSnippets(list, '', order: _order).firstOrNull;
      if (first != null) _load(first);
    } else if (!list.any((s) => s.id == open.id)) {
      // Deleted (here or elsewhere): nothing open.
      setState(() => _open = null);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _name.dispose();
    _description.dispose();
    _code.dispose();
    _listFocus.dispose();
    _nameFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // The code editor notifies while it is being built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  bool get _dirty {
    final s = _open;
    if (s == null) return false;
    return _name.text != s.name ||
        _description.text != s.description ||
        _code.text != s.body ||
        _language != s.language;
  }

  void _load(Snippet s) {
    setState(() {
      _open = s;
      _language = s.language;
      _nameError = null;
      _name.text = s.name;
      _description.text = s.description;
      _code.text = s.body;
    });
  }

  List<Snippet> _visible() => filterSnippets(
    ref.read(snippetsProvider(widget.workspace.id)).value ?? const [],
    _query.text,
    order: _order,
  );

  /// Asks before losing the changes of the open snippet (R10). True = go
  /// on (saved or discarded).
  Future<bool> _settle() async {
    if (!_dirty) return true;
    final name = shortName(_open!.name);
    final choice =
        await showAppDialog<_Unsaved>(
          context: context,
          barrierColor: AppColors.scrim,
          builder: (context) => ReviewDialogFrame(
            key: const ValueKey('snippet-unsaved-dialog'),
            title: "Salvar as mudanças em '$name'?",
            width: 460,
            content: const [
              Text(
                'O snippet tem mudanças que não foram salvas.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
            actions: [
              SmallButton(
                key: const ValueKey('snippet-unsaved-cancel'),
                label: 'Cancelar',
                onTap: () => Navigator.of(context).pop(_Unsaved.cancel),
              ),
              SmallButton(
                key: const ValueKey('snippet-unsaved-discard'),
                label: 'Descartar',
                color: AppColors.red,
                border: SessionColors.stopBorder,
                onTap: () => Navigator.of(context).pop(_Unsaved.discard),
              ),
              AmberButton(
                key: const ValueKey('snippet-unsaved-save'),
                label: 'Salvar',
                onTap: () => Navigator.of(context).pop(_Unsaved.save),
              ),
            ],
          ),
        ) ??
        _Unsaved.cancel;
    switch (choice) {
      case _Unsaved.cancel:
        return false;
      case _Unsaved.discard:
        _load(_open!);
        return true;
      case _Unsaved.save:
        return _save();
    }
  }

  Future<void> _select(Snippet s) async {
    if (s.id == _open?.id) return;
    if (!await _settle() || !mounted) return;
    _load(s);
  }

  Future<void> _close() async {
    if (!await _settle() || !mounted) return;
    Navigator.of(context).pop();
  }

  /// Writes the open snippet (R10). False = it could not (name).
  Future<bool> _save() async {
    final s = _open;
    if (s == null || _saving) return false;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'O nome não pode ficar vazio.');
      return false;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(snippetsRepoProvider)
          .update(
            s.id,
            name: name,
            body: _code.text,
            language: _language,
            description: _description.text,
          );
      if (mounted) _load(saved);
      return true;
    } on SnippetNameTaken catch (e) {
      if (mounted) setState(() => _nameError = e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The open snippet as it is in the fields (copy and insert take what is
  /// on screen).
  Snippet _current() => _open!.copyWith(
    name: _name.text.trim().isEmpty ? _open!.name : _name.text.trim(),
    body: _code.text,
    language: Value(_language),
  );

  Future<void> _delete() async {
    final s = _open;
    if (s == null) return;
    final messenger = _messenger.currentState;
    final repo = ref.read(snippetsRepoProvider);
    final next = _neighbour(s);
    await repo.delete(s.id);
    if (!mounted) return;
    setState(() => _open = null);
    if (next != null) _load(next);
    messenger
      ?..hideCurrentSnackBar()
      ..showAppToast(
        SnackBar(
          key: const ValueKey('snippet-deleted-toast'),
          content: const Text('Snippet excluído'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () => unawaited(repo.restore(s)),
          ),
        ),
      );
  }

  Snippet? _neighbour(Snippet s) {
    final list = _visible();
    final i = list.indexWhere((x) => x.id == s.id);
    if (i < 0) return null;
    if (i + 1 < list.length) return list[i + 1];
    if (i > 0) return list[i - 1];
    return null;
  }

  Future<void> _openOrigin() async {
    final s = _open;
    if (s == null || !await _settle() || !mounted) return;
    final nav = ref.read(navigationProvider.notifier);
    Navigator.of(context).pop();
    if (s.originConversationId case final id?) {
      ref.read(selectedConversationProvider.notifier).select(id);
      await nav.request(AppSection.prompt);
    } else if (s.originSessionId case final id?) {
      ref.read(selectedSessionProvider.notifier).select(id);
      await nav.request(AppSection.sessions);
    }
  }

  KeyEventResult _onListKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final list = _visible();
    if (list.isEmpty) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      setState(() {
        final d = k == LogicalKeyboardKey.arrowDown ? 1 : -1;
        _highlight = (_highlight + d + list.length) % list.length;
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      final s = list[_highlight.clamp(0, list.length - 1)];
      unawaited(
        _select(s).then((_) {
          if (mounted && _open?.id == s.id) _nameFocus.requestFocus();
        }),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final all =
        ref.watch(snippetsProvider(widget.workspace.id)).value ?? const [];
    final list = filterSnippets(all, _query.text, order: _order);
    if (_highlight >= list.length) {
      _highlight = list.isEmpty ? 0 : list.length - 1;
    }
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_save()),
        },
        // Its own messenger: "Snippet excluído · Desfazer" shows over the
        // scrim and can be clicked (R12). A click outside closes, asking
        // first when there are changes.
        child: ScaffoldMessenger(
          key: _messenger,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_close()),
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    key: const ValueKey('snippets-dialog'),
                    color: AppColors.panelSolid,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: (size.width - 48).clamp(640, 1140).toDouble(),
                      height: (size.height - 48).clamp(420, 640).toDouble(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(all.length),
                          const Divider(height: 1),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(width: 330, child: _listColumn(list)),
                                const VerticalDivider(width: 1),
                                Expanded(child: _editor()),
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
          ),
        ),
      ),
    );
  }

  Widget _header(int count) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
    child: Row(
      children: [
        const Icon(Icons.bookmark_border, size: 18, color: AppColors.amber),
        const SizedBox(width: 8),
        const Text(
          'Snippets',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${widget.workspace.name} · $count',
          key: const ValueKey('snippets-count'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        IconButton(
          key: const ValueKey('snippets-close'),
          tooltip: 'Fechar (Esc)',
          iconSize: 18,
          color: AppColors.textSecondary,
          onPressed: _close,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _listColumn(List<Snippet> list) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('snippets-search'),
          controller: _query,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: _input('Buscar snippets', icon: Icons.search),
          onChanged: (_) => setState(() => _highlight = 0),
          onSubmitted: (_) {
            if (list.isNotEmpty) unawaited(_select(list[_highlight]));
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text(
              'Ordem',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Spacer(),
            PopupMenuButton<SnippetOrder>(
              key: const ValueKey('snippets-order'),
              tooltip: 'Ordem da lista',
              initialValue: _order,
              color: AppColors.panelSolid,
              onSelected: (o) => setState(() {
                _order = o;
                _highlight = 0;
              }),
              itemBuilder: (_) => [
                for (final o in SnippetOrder.values)
                  PopupMenuItem(
                    key: ValueKey('snippets-order-${o.name}'),
                    value: o,
                    height: 34,
                    child: Text(o.label, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _order.label,
                    style: const TextStyle(fontSize: 12, color: AppColors.text),
                  ),
                  const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Focus(
            focusNode: _listFocus,
            onKeyEvent: _onListKey,
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _query.text.trim().isEmpty
                          ? 'Nenhum snippet ainda. Salve um bloco de código '
                                'pelo botão Salvar da resposta.'
                          : 'Nenhum snippet encontrado.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _listScroll,
                  itemCount: list.length,
                  itemBuilder: (context, i) =>
                      _row(list[i], highlighted: focused && i == _highlight),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(Snippet s, {required bool highlighted}) {
    final open = s.id == _open?.id;
    final dirty = open && _dirty;
    final meta = snippetMeta(s.language, s.body);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: open,
        label: 'Snippet ${s.name}, $meta${dirty ? ', não salvo' : ''}',
        excludeSemantics: true,
        child: Material(
          color: open ? SessionColors.selectedBg : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: highlighted
                  ? AppColors.amberLight
                  : (open ? SessionColors.selectedBorder : Colors.transparent),
            ),
          ),
          child: InkWell(
            key: ValueKey('snippet-row-${s.id}'),
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(8),
            onTap: () => _select(s),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (dirty) ...[
                        const SizedBox(width: 6),
                        const Dot(AppColors.amber, size: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      Text(
                        snippetWhen(s.lastUsedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor() {
    final s = _open;
    if (s == null) {
      return const Center(
        child: Text(
          'Escolha um snippet na lista.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    final options = snippetLanguageOptions(_language);
    final word = snippetLanguageWord(_language);
    final lang = CodeLanguage.forFence(_language) ?? CodeLanguage.plaintext;
    const label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Nome', style: label),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('snippet-name'),
                      controller: _name,
                      focusNode: _nameFocus,
                      maxLength: snippetNameMax,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text,
                      ),
                      decoration: _input(null)
                          .copyWith(errorText: _nameError, counterText: ''),
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Linguagem', style: label),
                    const SizedBox(height: 6),
                    SnippetLanguagePicker(
                      key: const ValueKey('snippet-language'),
                      value: word,
                      options: options,
                      onChanged: (w) =>
                          setState(() => _language = snippetLanguageOf(w)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Descrição', style: label),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('snippet-description'),
            controller: _description,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            decoration: _input('Para que serve (opcional)'),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AppCodeEditor(
                  key: const ValueKey('snippet-code'),
                  controller: _code,
                  editorKey: 'snippets',
                  language: lang,
                  baseFontSize: 12,
                  onSave: () => unawaited(_save()),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _origin(s)),
              Text(
                snippetUsage(s.uses, s.lastUsedAt),
                key: const ValueKey('snippet-usage'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SmallButton(
                key: const ValueKey('snippet-delete'),
                label: 'Excluir',
                icon: Icons.delete_outline,
                color: AppColors.red,
                border: SessionColors.stopBorder,
                background: Colors.transparent,
                semanticLabel: 'Excluir snippet ${shortName(s.name)}',
                onTap: _delete,
              ),
              const SizedBox(width: 12),
              if (_dirty)
                const Row(
                  key: ValueKey('snippet-dirty'),
                  children: [
                    Dot(AppColors.amber, size: 6),
                    SizedBox(width: 6),
                    Text(
                      'não salvo',
                      style: TextStyle(fontSize: 12, color: AppColors.amber),
                    ),
                  ],
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    SmallButton(
                      key: const ValueKey('snippet-copy'),
                      label: 'Copiar',
                      icon: Icons.copy_outlined,
                      semanticLabel: 'Copiar snippet ${shortName(s.name)}',
                      onTap: () => copySnippet(
                        ref,
                        _current(),
                        messenger: _messenger.currentState,
                      ),
                    ),
                    SmallButton(
                      key: const ValueKey('snippet-insert'),
                      label: 'Inserir no composer',
                      icon: Icons.download_outlined,
                      semanticLabel:
                          'Inserir snippet ${shortName(s.name)} no composer',
                      onTap: () async {
                        final current = _current();
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        if (!await _settle() || !mounted) return;
                        Navigator.of(context).pop();
                        await insertSnippet(ref, current, messenger: messenger);
                      },
                    ),
                    _SaveButton(enabled: _dirty && !_saving, onTap: _save),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _origin(Snippet s) {
    final label = s.originLabel;
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    final conv = s.originConversationId;
    final session = s.originSessionId;
    final kind = conv != null
        ? 'da conversa '
        : (session != null ? 'da sessão ' : 'de ');
    const muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final date = ' · ${snippetDate(s.createdAt)}';
    final gone = conv == null && session == null;
    return Row(
      key: const ValueKey('snippet-origin'),
      children: [
        const Icon(Icons.link, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(kind, style: muted),
        Flexible(
          child: gone
              ? Text(
                  '$label (apagada)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted.copyWith(fontStyle: FontStyle.italic),
                )
              : Semantics(
                  link: true,
                  label: 'Abrir ${kind.trim()} $label',
                  excludeSemantics: true,
                  child: InkWell(
                    key: const ValueKey('snippet-origin-link'),
                    onTap: _openOrigin,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
        ),
        Text(date, style: muted),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.enabled, required this.onTap});

  final bool enabled;
  final Future<bool> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Salvar snippet (Ctrl+S)',
        excludeSemantics: true,
        child: Material(
          color: AppColors.amber,
          shape: RoundedRectangleBorder(borderRadius: radius),
          child: InkWell(
            key: const ValueKey('snippet-save'),
            borderRadius: radius,
            onTap: enabled ? onTap : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 30,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Salvar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onAmber,
                      ),
                    ),
                    SizedBox(width: 8),
                    _DarkKbd('Ctrl S'),
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

/// Key chip on an amber button.
class _DarkKbd extends StatelessWidget {
  const _DarkKbd(this.keys);

  final String keys;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.onAmber.withValues(alpha: .35)),
    ),
    child: Text(
      keys,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 10.5,
        color: AppColors.onAmber,
      ),
    ),
  );
}

/// Dense field of the snippet dialogs.
InputDecoration _input(String? hint, {IconData? icon}) =>
    snippetInput(hint, icon: icon);

/// Dense field of the snippet dialogs and of the "Salvar snippet" balloon.
InputDecoration snippetInput(String? hint, {IconData? icon}) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
  isDense: true,
  filled: true,
  fillColor: AppColors.background,
  prefixIcon: icon == null
      ? null
      : Icon(icon, size: 16, color: AppColors.textSecondary),
  prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AppColors.amber),
  ),
);

/// The language of a snippet (R2, R9): the fence word and the highlighted
/// languages.
class SnippetLanguagePicker extends StatelessWidget {
  const SnippetLanguagePicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Linguagem: $value',
    initialValue: value,
    color: AppColors.panelSolid,
    constraints: const BoxConstraints(maxHeight: 320, minWidth: 130),
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final o in options)
        PopupMenuItem(
          key: ValueKey('snippet-language-$o'),
          value: o,
          height: 30,
          child: Text(
            o,
            style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
          ),
        ),
    ],
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.text,
              ),
            ),
          ),
          const Icon(
            Icons.expand_more,
            size: 16,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    ),
  );
}
