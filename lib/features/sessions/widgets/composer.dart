import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../data/providers.dart';
import '../../../core/providers/permission_policy.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../prompt/prompt_actions.dart'
    show
        ComposerTrigger,
        filterFiles,
        mentionedFiles,
        triggerAt,
        workspaceFilesProvider;
import '../../prompt/widgets/prompt_composer.dart'
    show ComposerSuggestions, insertSavedPrompt, replaceComposerRange;
import '../../../core/dev/picked_element.dart';
import '../picked_elements.dart';
import '../session_composer_draft.dart';
import '../session_manager.dart';
import 'session_style.dart';

String permissionLabel(ClaudePermissionMode? m, {String provider = 'claude'}) =>
    permissionModeLabel(m, provider: provider);

/// Modes offered in the UI (plano, Fase 5: default / acceptEdits / plan; the
/// user's opt-in skipPermissions).
const uiPermissionModes = [
  ClaudePermissionMode.defaultMode,
  ClaudePermissionMode.acceptEdits,
  ClaudePermissionMode.plan,
  ClaudePermissionMode.skipPermissions,
];

/// `app_settings` key of the last mode chosen in "Nova sessão".
const lastPermissionModeKey = 'session.permissionMode';

/// Message box under the timeline. Sends with `ClaudeProcess.send`; a
/// session without a live process is resumed first (`--resume`).
class SessionComposer extends ConsumerStatefulWidget {
  const SessionComposer({
    super.key,
    required this.sessionId,
    required this.permissionMode,
    this.canSend,
    this.provider = 'claude',
    this.root,
    this.onPointAnother,
    this.onSentWithElements,
  });

  final String sessionId;
  final String provider;
  final String? permissionMode;

  /// Returns an error message when sending is not allowed right now.
  final String? Function()? canSend;

  /// Worktree of the session: the `@` picker lists its files (UX v2, U4).
  final String? root;

  /// "Apontar outro" beside the pointed elements (SPEC-051 R8; null =
  /// hidden).
  final VoidCallback? onPointAnother;

  /// After a request with pointed elements was sent (R11).
  final VoidCallback? onSentWithElements;

  @override
  ConsumerState<SessionComposer> createState() => _SessionComposerState();
}

/// `@specs/...` mentions of [text] ("Anexar spec" chips).
List<String> attachedSpecs(String text) => [
  for (final f in mentionedFiles([text]))
    if (f.startsWith('specs/')) f,
];

/// [text] with `@path` inserted at [cursor] (a space around it when needed).
({String text, int cursor}) insertMention(
  String text,
  int cursor,
  String path,
) {
  final at = cursor < 0 || cursor > text.length ? text.length : cursor;
  final before = text.substring(0, at);
  final after = text.substring(at);
  final lead = before.isEmpty || before.endsWith(' ') || before.endsWith('\n')
      ? ''
      : ' ';
  final insert = '$lead@$path ';
  final rest = after.startsWith(' ') ? after.substring(1) : after;
  return (text: '$before$insert$rest', cursor: before.length + insert.length);
}

/// [text] without the `@path` mention.
String removeMention(String text, String path) => text
    .replaceAllMapped(
      RegExp('(^|\\s)@${RegExp.escape(path)}(?=\\s|\$)'),
      (m) => m.group(1)!,
    )
    .replaceAll(RegExp(r'  +'), ' ')
    .trimLeft();

/// Says that the text in the field is a draft of the decision modal.
class _DraftNote extends StatelessWidget {
  const _DraftNote();

  @override
  Widget build(BuildContext context) => const Row(
    key: ValueKey('composer-draft-note'),
    children: [
      Icon(Icons.group_outlined, size: 14, color: AppColors.textSecondary),
      SizedBox(width: 6),
      Flexible(
        child: Text.rich(
          TextSpan(
            text: 'Rascunho com as decisões do modal · ',
            children: [
              TextSpan(
                text: 'ainda não enviado',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    ],
  );
}

class _SessionComposerState extends ConsumerState<SessionComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  ComposerTrigger? _trigger;
  int _highlight = 0;
  int? _dismissedAt;

  /// The text came from a draft and was not sent (SPEC-033 R12).
  bool _fromDraft = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
    _takeDraftAfterFrame();
  }

  @override
  void didUpdateWidget(covariant SessionComposer old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId) _takeDraftAfterFrame();
  }

  void _takeDraftAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _takeDraft();
      });

  /// Fills the field with the draft of this session, after what is already
  /// there. Nothing is sent.
  void _takeDraft() {
    final draft = ref
        .read(sessionComposerDraftProvider.notifier)
        .take(widget.sessionId);
    if (draft == null) return;
    final typed = _text.text.trimRight();
    final text = typed.isEmpty ? draft : '$typed\n\n$draft';
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _fromDraft = true);
    _focus.requestFocus();
  }

  void _onText() {
    if (_fromDraft && _text.text.isEmpty) setState(() => _fromDraft = false);
    final specs = attachedSpecs(_text.text);
    final cursor = _text.selection.isValid ? _text.selection.extentOffset : -1;
    var t = triggerAt(_text.text, cursor);
    if (t != null && t.start == _dismissedAt) t = null;
    if (t?.start != _trigger?.start || t?.char != _trigger?.char) {
      _highlight = 0;
    }
    if (!_sameList(specs, _chips) || t != null || _trigger != null) {
      setState(() {
        _chips = specs;
        _trigger = t;
      });
    }
  }

  List<String> _files() {
    final root = widget.root;
    final t = _trigger;
    if (root == null || t == null || t.char != '@') return const [];
    final all = ref.watch(workspaceFilesProvider(root)).value ?? const [];
    return filterFiles(all, t.query);
  }

  List<SavedPrompt> _prompts() {
    final t = _trigger;
    if (t == null || t.char != '/') return const [];
    final q = t.query.toLowerCase();
    final all = ref.watch(savedPromptsProvider).value ?? const [];
    return [
      for (final p in all)
        if (p.command.contains(q) || p.description.toLowerCase().contains(q)) p,
    ];
  }

  void _pickFile(String path) {
    final t = _trigger;
    if (t == null) return;
    final cursor = _text.selection.isValid
        ? _text.selection.extentOffset
        : t.start;
    replaceComposerRange(_text, t.start, cursor, '@$path ');
    setState(() => _trigger = null);
    _focus.requestFocus();
  }

  Future<void> _pickPrompt(SavedPrompt p) async {
    final t = _trigger;
    setState(() => _trigger = null);
    await insertSavedPrompt(ref, _text, p, trigger: t);
    _focus.requestFocus();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _highlight = (_highlight + delta) % count);
  }

  void _dismiss() => setState(() {
    _dismissedAt = _trigger?.start;
    _trigger = null;
  });

  List<String> _chips = const [];

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _attach(String path) {
    final sel = _text.selection;
    final r = insertMention(_text.text, sel.isValid ? sel.end : -1, path);
    _text.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.cursor),
    );
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final msg = _text.text.trim();
    final pickedNotifier = ref.read(
      pickedElementsProvider(widget.sessionId).notifier,
    );
    final picked = ref.read(pickedElementsProvider(widget.sessionId));
    if ((msg.isEmpty && picked.isEmpty) || _busy) return;
    final blocked = widget.canSend?.call();
    if (blocked != null) {
      _snack(blocked);
      return;
    }
    setState(() => _busy = true);
    final manager = ref.read(sessionManagerProvider.notifier);
    try {
      _text.clear();
      if (picked.isEmpty) {
        await manager.send(widget.sessionId, msg);
      } else {
        pickedNotifier.clear();
        // Codex without the `image` modality: the PNGs go as files (R8).
        final images = sendsImages(
          widget.provider,
          alive: ref.read(sessionManagerProvider).isAlive(widget.sessionId),
          accepts: manager.acceptsImages(widget.sessionId),
        );
        final m = await buildPickedMessage(
          msg,
          picked,
          images: images,
          root: widget.root ?? Directory.systemTemp.path,
        );
        await manager.send(widget.sessionId, m.text, images: m.images);
        widget.onSentWithElements?.call();
      }
    } catch (e) {
      if (_text.text.isEmpty) _text.text = msg;
      if (picked.isNotEmpty &&
          ref.read(pickedElementsProvider(widget.sessionId)).isEmpty) {
        picked.forEach(pickedNotifier.add);
      }
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      sessionComposerDraftProvider.select((d) => d[widget.sessionId]),
      (_, draft) {
        if (draft != null) _takeDraft();
      },
    );
    final mode = ClaudePermissionMode.fromCli(widget.permissionMode);
    final alive = ref.watch(
      sessionManagerProvider.select((s) => s.isAlive(widget.sessionId)),
    );
    final picked = ref.watch(pickedElementsProvider(widget.sessionId));
    final files = _files();
    final prompts = _prompts();
    final trigger = _trigger;
    final showing = trigger != null;
    final count = trigger?.char == '@' ? files.length : prompts.length;
    final hi = count == 0 ? 0 : _highlight.clamp(0, count - 1);
    void choose() {
      if (count == 0) return;
      if (trigger!.char == '@') {
        _pickFile(files[hi]);
      } else {
        _pickPrompt(prompts[hi]);
      }
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
      if (showing) ...{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, count),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, count),
        const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
        if (count > 0) ...{
          const SingleActivator(LogicalKeyboardKey.enter): choose,
          const SingleActivator(LogicalKeyboardKey.tab): choose,
        },
      },
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SessionColors.selectedBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showing)
              ComposerSuggestions(
                trigger: trigger,
                files: files,
                prompts: prompts,
                highlight: hi,
                hasWorkspace: widget.root != null,
                onFile: _pickFile,
                onPrompt: _pickPrompt,
              ),
            if (_chips.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _chips)
                    InputChip(
                      key: ValueKey('composer-spec-chip-$p'),
                      label: Text(
                        '@$p',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.text,
                        ),
                      ),
                      backgroundColor: AppColors.surfaceRaised,
                      side: const BorderSide(color: AppColors.border),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () =>
                          _text.text = removeMention(_text.text, p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (_fromDraft) ...[const _DraftNote(), const SizedBox(height: 8)],
            if (picked.isNotEmpty) ...[
              SingleChildScrollView(
                key: const ValueKey('composer-picked'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, e) in picked.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      PickedElementCard(
                        key: ValueKey('composer-picked-$i'),
                        element: e,
                        initiallyOpen: i == 0,
                        onRemove: () => ref
                            .read(
                              pickedElementsProvider(widget.sessionId).notifier,
                            )
                            .removeAt(i),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Pedido',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
            ],
            CallbackShortcuts(
              bindings: bindings,
              child: TextField(
                key: const ValueKey('composer-field'),
                controller: _text,
                focusNode: _focus,
                minLines: 2,
                maxLines: 6,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                decoration: const InputDecoration.collapsed(
                  hintText:
                      'Envie uma mensagem para a sessão…  @ arquivo  '
                      '/ prompt salvo  (Ctrl+Enter envia)',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: PopupMenuButton<ClaudePermissionMode>(
                    tooltip: widget.provider == 'codex'
                        ? 'Aplica ao retomar a sessão'
                        : alive
                        ? 'Muda já na sessão em andamento'
                        : 'Modo de permissão ao retomar',
                    color: AppColors.panelSolid,
                    onSelected: (m) async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      try {
                        await ref
                            .read(sessionManagerProvider.notifier)
                            .setPermissionMode(widget.sessionId, m);
                      } on SessionException catch (e) {
                        messenger?.showAppToast(
                          SnackBar(content: Text(e.message)),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      for (final m in uiPermissionModes)
                        PopupMenuItem(
                          value: m,
                          child: Text(
                            permissionLabel(m, provider: widget.provider),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Permissão: ${permissionLabel(mode, provider: widget.provider)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: _AttachSpecButton(onPick: _attach)),
                const SizedBox(width: 10),
                Expanded(
                  child: picked.isNotEmpty
                      ? Text(
                          '${picked.length == 1 ? '1 elemento anexado' : '${picked.length} elementos anexados'}'
                          ' · o seletor, o HTML, os estilos e os prints vão '
                          'junto com o pedido',
                          key: const ValueKey('composer-picked-note'),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        )
                      : alive
                      ? const SizedBox()
                      : const Text(
                          'retoma a sessão ao enviar',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                ),
                if (picked.isNotEmpty && widget.onPointAnother != null) ...[
                  const SizedBox(width: 10),
                  SmallButton(
                    key: const ValueKey('composer-point-another'),
                    label: 'Apontar outro',
                    onTap: widget.onPointAnother,
                  ),
                ],
                const SizedBox(width: 10),
                AmberButton(
                  key: const ValueKey('composer-send'),
                  label: _busy ? 'Enviando…' : 'Enviar',
                  onTap: _busy ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Anexar spec" (pendência da Fase 5): lists the workspace specs and inserts
/// `@specs/<arquivo>` into the message (the CLI attaches `@` mentions).
class _AttachSpecButton extends ConsumerWidget {
  const _AttachSpecButton({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final specs = ws == null
        ? const <Spec>[]
        : ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    return PopupMenuButton<String>(
      key: const ValueKey('composer-attach-spec'),
      tooltip: specs.isEmpty
          ? 'Nenhuma spec registrada (tela Specs)'
          : 'Anexar spec (@specs/…)',
      enabled: specs.isNotEmpty,
      color: AppColors.panelSolid,
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final s in specs)
          PopupMenuItem(
            value: s.path,
            child: Text(
              '${s.code} · ${s.title}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'Anexar spec',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: specs.isEmpty
                ? AppColors.textMuted
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Whether the PNGs of pointed elements go as images (R8): not to a Codex
/// session whose model lacks the `image` modality (or that is not running,
/// so the model is unknown).
bool sendsImages(
  String provider, {
  required bool alive,
  required bool accepts,
}) => provider != 'codex' || (alive && accepts);

/// An element pointed in the preview, in the composer (R8): thumbnail,
/// selector, URL and size; it opens to show the HTML and the styles.
class PickedElementCard extends StatefulWidget {
  const PickedElementCard({
    super.key,
    required this.element,
    required this.onRemove,
    this.initiallyOpen = false,
  });

  final PickedElement element;
  final VoidCallback onRemove;
  final bool initiallyOpen;

  @override
  State<PickedElementCard> createState() => _PickedElementCardState();
}

class _PickedElementCardState extends State<PickedElementCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final e = widget.element;
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11,
      color: AppColors.textSecondary,
    );
    final thumb = e.elementPng == null
        ? const SizedBox(width: 72, height: 48)
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              e.elementPng!,
              width: _open ? 160 : 72,
              height: _open ? 90 : 48,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  SizedBox(width: _open ? 160 : 72, height: _open ? 90 : 48),
            ),
          );
    return Container(
      constraints: BoxConstraints(maxWidth: _open ? 760 : 300),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _open ? AppColors.amber : AppColors.border,
                width: _open ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: thumb,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.selector,
                  maxLines: _open ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                if (_open) ...[
                  Text(
                    '${e.shortUrl} · ${e.width.round()} × ${e.height.round()} · '
                    '${e.imageCount == 1 ? '1 imagem' : '${e.imageCount} imagens'}',
                    style: mono,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    key: const ValueKey('picked-details'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SessionColors.terminalPanel,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      [
                        e.html,
                        if (e.styleLine.isNotEmpty) e.styleLine,
                      ].join('\n'),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: mono.copyWith(color: AppColors.text),
                    ),
                  ),
                ] else
                  InkWell(
                    key: const ValueKey('picked-open'),
                    onTap: () => setState(() => _open = true),
                    child: const Text(
                      'Mostrar detalhes',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            key: const ValueKey('picked-remove'),
            onTap: widget.onRemove,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
