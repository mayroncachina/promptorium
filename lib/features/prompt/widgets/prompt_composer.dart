import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/agent_registry.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../sessions/widgets/session_style.dart';
import '../attachments.dart' show imageMediaType;
import '../conversation_manager.dart' show modelLabel;
import '../prompt_actions.dart';

/// Replaces `[start, end)` of [c] with [text] and puts the cursor after it.
void replaceComposerRange(
  TextEditingController c,
  int start,
  int end,
  String text,
) {
  final v = c.text;
  final s = start.clamp(0, v.length), e = end.clamp(s, v.length);
  c.value = TextEditingValue(
    text: v.replaceRange(s, e, text),
    selection: TextSelection.collapsed(offset: s + text.length),
  );
}

/// Inserts a saved prompt's body: replaces the `/query` being typed, else
/// goes at the cursor (or the end). Increments `uses`.
Future<void> insertSavedPrompt(
  WidgetRef ref,
  TextEditingController c,
  SavedPrompt p, {
  ComposerTrigger? trigger,
}) async {
  final sel = c.selection;
  final cursor = sel.isValid ? sel.extentOffset : c.text.length;
  if (trigger != null) {
    replaceComposerRange(c, trigger.start, cursor, p.body);
  } else {
    final start = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    replaceComposerRange(c, start, end, p.body);
  }
  await ref.read(savedPromptsRepoProvider).incrementUses(p.command);
}

/// Big message box of the Prompt screen: `@` file picker, `/` saved prompts,
/// provider / model / mode selectors and Enviar (Ctrl+Enter).
class PromptComposer extends ConsumerStatefulWidget {
  const PromptComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.workspaceRoot,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    this.files = const [],
    this.onPickFiles,
    this.onRemoveFile,
    this.dropping = false,
    required this.provider,
    required this.model,
    required this.mode,
    required this.onProvider,
    required this.onModel,
    required this.onMode,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Root for `git ls-files` (null = no workspace).
  final String? workspaceRoot;
  final List<String> attachments;
  final ValueChanged<String> onAttach;
  final ValueChanged<String> onRemoveAttachment;

  /// Absolute paths picked or dropped (images, PDFs, anything): they go with
  /// the next message.
  final List<String> files;
  final VoidCallback? onPickFiles;
  final ValueChanged<String>? onRemoveFile;

  /// A file is being dragged over the window.
  final bool dropping;
  final AgentProvider provider;
  final String model;
  final PromptMode mode;
  final ValueChanged<AgentProvider> onProvider;
  final ValueChanged<String> onModel;
  final ValueChanged<PromptMode> onMode;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  ConsumerState<PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends ConsumerState<PromptComposer> {
  ComposerTrigger? _trigger;
  int _highlight = 0;

  /// Trigger the user closed with Esc (not reopened until it changes).
  int? _dismissedAt;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(PromptComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final c = widget.controller;
    final cursor = c.selection.isValid ? c.selection.extentOffset : -1;
    var t = triggerAt(c.text, cursor);
    if (t != null && t.start == _dismissedAt) t = null;
    if (t?.start != _trigger?.start || t?.char != _trigger?.char) {
      _highlight = 0;
    }
    if (t == null && _trigger == null) return;
    setState(() => _trigger = t);
  }

  List<String> _files() {
    final root = widget.workspaceRoot;
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
    final c = widget.controller;
    final cursor = c.selection.isValid ? c.selection.extentOffset : t.start;
    replaceComposerRange(c, t.start, cursor, '@$path ');
    widget.onAttach(path);
    setState(() => _trigger = null);
    widget.focusNode.requestFocus();
  }

  Future<void> _pickPrompt(SavedPrompt p) async {
    final t = _trigger;
    setState(() => _trigger = null);
    await insertSavedPrompt(ref, widget.controller, p, trigger: t);
    widget.focusNode.requestFocus();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _highlight = (_highlight + delta) % count);
  }

  void _dismiss() => setState(() {
    _dismissedAt = _trigger?.start;
    _trigger = null;
  });

  @override
  Widget build(BuildContext context) {
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
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
        if (!widget.busy) widget.onSend();
      },
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showing)
                _Suggestions(
                  trigger: trigger,
                  files: files,
                  prompts: prompts,
                  highlight: hi,
                  hasWorkspace: widget.workspaceRoot != null,
                  onFile: _pickFile,
                  onPrompt: _pickPrompt,
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.dropping
                        ? AppColors.amber
                        : SessionColors.selectedBorder,
                    width: widget.dropping ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.dropping)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Solte os arquivos aqui para anexar',
                          key: ValueKey('prompt-drop-hint'),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.amber,
                          ),
                        ),
                      ),
                    if (widget.attachments.isNotEmpty ||
                        widget.files.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final a in widget.attachments)
                            FileChip(
                              path: a,
                              onRemove: () => widget.onRemoveAttachment(a),
                            ),
                          for (final f in widget.files)
                            AttachedFileChip(
                              path: f,
                              onRemove: widget.onRemoveFile == null
                                  ? null
                                  : () => widget.onRemoveFile!(f),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    CallbackShortcuts(
                      bindings: bindings,
                      child: TextField(
                        key: const ValueKey('prompt-field'),
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        minLines: 3,
                        maxLines: 10,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.text,
                        ),
                        decoration: const InputDecoration.collapsed(
                          hintText:
                              'Pergunte qualquer coisa…  @ anexa arquivo  '
                              '/ usa um prompt salvo',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.onPickFiles != null)
                                IconButton(
                                  key: const ValueKey('prompt-attach'),
                                  tooltip:
                                      'Anexar arquivos (ou arraste para cá)',
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  color: AppColors.textSecondary,
                                  onPressed: widget.onPickFiles,
                                  icon: const Icon(Icons.attach_file),
                                ),
                              _ProviderButton(
                                active: widget.provider,
                                onSelected: widget.onProvider,
                              ),
                              _ModelButton(
                                models: widget.provider.models,
                                model: widget.model,
                                onSelected: widget.onModel,
                              ),
                              _ModeSwitch(
                                mode: widget.mode,
                                onSelected: widget.onMode,
                              ),
                              Text(
                                widget.mode.hint,
                                key: const ValueKey('prompt-mode-hint'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.busy) ...[
                          SmallButton(
                            key: const ValueKey('prompt-stop'),
                            label: 'Parar',
                            color: AppColors.red,
                            border: SessionColors.stopBorder,
                            height: 32,
                            onTap: widget.onStop,
                          ),
                          const SizedBox(width: 6),
                        ],
                        AmberButton(
                          key: const ValueKey('prompt-send'),
                          label: widget.busy ? 'Respondendo…' : 'Enviar',
                          height: 32,
                          onTap: widget.busy ? null : widget.onSend,
                        ),
                      ],
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
}

/// Chip of a picked / dropped file (name + remove), with an image mark.
class AttachedFileChip extends StatelessWidget {
  const AttachedFileChip({super.key, required this.path, this.onRemove});

  final String path;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final image = imageMediaType(path) != null;
    return Tooltip(
      message: path,
      child: Container(
        key: ValueKey('attached-chip-$path'),
        height: 26,
        padding: EdgeInsets.only(left: 8, right: onRemove == null ? 8 : 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.amber),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              image ? Icons.image_outlined : Icons.attach_file,
              size: 13,
              color: AppColors.amber,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.text),
              ),
            ),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: AppIcon(
                    AppIcons.close,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `@file` chip (composer and context panel).
class FileChip extends StatelessWidget {
  const FileChip({super.key, required this.path, this.onRemove});

  final String path;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final name = path.split('/').last;
    return Tooltip(
      message: path,
      child: Container(
        key: ValueKey('file-chip-$path'),
        height: 26,
        padding: EdgeInsets.only(left: 8, right: onRemove == null ? 8 : 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '@$name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.text,
                ),
              ),
            ),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: AppIcon(
                    AppIcons.close,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.trigger,
    required this.files,
    required this.prompts,
    required this.highlight,
    required this.hasWorkspace,
    required this.onFile,
    required this.onPrompt,
  });

  final ComposerTrigger trigger;
  final List<String> files;
  final List<SavedPrompt> prompts;
  final int highlight;
  final bool hasWorkspace;
  final ValueChanged<String> onFile;
  final ValueChanged<SavedPrompt> onPrompt;

  @override
  Widget build(BuildContext context) {
    final isFile = trigger.char == '@';
    final empty = isFile
        ? (hasWorkspace ? 'Nenhum arquivo encontrado.' : 'Sem workspace.')
        : 'Nenhum prompt salvo com esse nome.';
    final n = isFile ? files.length : prompts.length;
    Widget row(int i) {
      final on = i == highlight;
      final Widget child;
      final VoidCallback tap;
      if (isFile) {
        final f = files[i];
        tap = () => onFile(f);
        child = Text(
          f,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            color: AppColors.text,
          ),
        );
      } else {
        final p = prompts[i];
        tap = () => onPrompt(p);
        child = Row(
          children: [
            Text(
              '/${p.command}',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                p.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      }
      return Material(
        color: on ? AppColors.amberTint : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey(
            isFile
                ? 'suggest-file-${files[i]}'
                : 'suggest-prompt-'
                      '${prompts[i].command}',
          ),
          borderRadius: BorderRadius.circular(6),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: child,
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('prompt-suggestions'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SessionColors.selectedBorder),
      ),
      child: n == 0
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                empty,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: n,
              itemBuilder: (_, i) => row(i),
            ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({required this.active, required this.onSelected});

  final AgentProvider active;
  final ValueChanged<AgentProvider> onSelected;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final all = ref.watch(agentProvidersProvider);
        return PopupMenuButton<String>(
          key: const ValueKey('prompt-provider'),
          tooltip: 'Provedor',
          color: AppColors.surfaceRaised,
          position: PopupMenuPosition.over,
          onSelected: (id) => onSelected(all.firstWhere((p) => p.id == id)),
          itemBuilder: (_) => [
            for (final p in all)
              PopupMenuItem<String>(
                key: ValueKey('provider-${p.id}'),
                value: p.id,
                enabled: p.enabled,
                height: 36,
                child: Row(
                  children: [
                    Dot(p.enabled ? AppColors.amber : AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          color: p.enabled
                              ? AppColors.text
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      p.id == active.id
                          ? 'ativo'
                          : (p.enabled ? '' : 'em breve'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: SessionColors.approvalBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: SessionColors.approvalBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(active.icon, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Text(
                  active.displayName,
                  style: const TextStyle(fontSize: 12, color: AppColors.amber),
                ),
                const SizedBox(width: 6),
                AppIcon(AppIcons.chevronUp, size: 12, color: AppColors.amber),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModelButton extends StatelessWidget {
  const _ModelButton({
    required this.models,
    required this.model,
    required this.onSelected,
  });

  final List<String> models;
  final String model;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey('prompt-model'),
      tooltip: 'Modelo (vale a partir da próxima mensagem)',
      color: AppColors.surfaceRaised,
      position: PopupMenuPosition.over,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final m in models)
          PopupMenuItem(
            value: m,
            height: 34,
            child: Text(modelLabel(m), style: const TextStyle(fontSize: 12)),
          ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          modelLabel(model),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onSelected});

  final PromptMode mode;
  final ValueChanged<PromptMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in [
            ...PromptMode.selectable,
            if (!PromptMode.selectable.contains(mode)) mode,
          ])
            Material(
              color: m == mode ? AppColors.amberTint : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                key: ValueKey('mode-${m.name}'),
                borderRadius: BorderRadius.circular(4),
                onTap: () => onSelected(m),
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  child: Text(
                    m.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: m == mode
                          ? AppColors.amber
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
