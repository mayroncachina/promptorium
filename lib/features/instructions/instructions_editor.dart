import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/instructions_files.dart';
import '../../core/providers/workspace_assets.dart';
import '../../core/text/line_diff.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/diff_view.dart';
import '../../ui/widgets/markdown/app_markdown.dart';
import '../project/widgets/project_widgets.dart';
import '../sessions/widgets/session_style.dart';

/// The editor of Projeto › Instruções (SPEC-113 R8, R9): the two root files
/// (`AGENTS.md`, `CLAUDE.md`) as buffers that are saved together (R5), the
/// `CLAUDE.md` split into its import line and the "Só para o Claude Code"
/// part, and the change made outside the app.

// --- Buffers -------------------------------------------------------------------

/// One root file being edited (R8).
class InstructionsBuffer {
  InstructionsBuffer(this.root, this.name);

  final String root;

  /// `AGENTS.md` or `CLAUDE.md`.
  final String name;
  final controller = TextEditingController();

  /// The text on disk the edit started from (null = the file did not
  /// exist): the base of the safe write (R5).
  String? base;

  /// The `CLAUDE.md` import as written (R9); null = the whole file is in
  /// [controller] (the `AGENTS.md`, or a `CLAUDE.md` without the import).
  String? importLine;

  /// What [controller] had when [base] was loaded: [dirty] compares to it.
  String loaded = '';

  /// The [importLine] when [base] was loaded.
  String? loadedImport;

  /// The file on disk changed while there was an edit (R8): its text
  /// (null = deleted) is kept aside until the person chooses.
  ({String? text})? outside;

  String? get external => outside?.text;

  String get path => '$root/$name';
  bool get isClaude => name == claudeMdName;
  bool get dirty => controller.text != loaded || importLine != loadedImport;
  bool get exists => base != null;

  /// The whole file as it would be written.
  String get fullText => importLine == null
      ? controller.text
      : composeClaudeMd(controller.text, importLine: importLine!);

  /// Puts [disk] in the editor (R8: re-read when there is no edit).
  void load(String? disk) {
    base = disk;
    outside = null;
    final text = disk ?? '';
    if (isClaude) {
      final parts = splitClaudeMd(text);
      importLine = parts.importLine;
      loaded = parts.claudeOnly;
    } else {
      importLine = null;
      loaded = text;
    }
    loadedImport = importLine;
    if (controller.text != loaded) controller.text = loaded;
  }

  InstructionsSnapshot get snapshot =>
      InstructionsSnapshot(path: path, text: base);

  void dispose() => controller.dispose();
}

/// An unsaved edit kept while the tab is not on screen (R8: leaving the
/// screen does not lose it).
@immutable
class InstructionsDraft {
  const InstructionsDraft({
    required this.base,
    required this.importLine,
    required this.loadedImport,
    required this.loaded,
    required this.text,
  });

  final String? base;
  final String? importLine;
  final String? loadedImport;
  final String loaded;
  final String text;
}

/// Unsaved edits by absolute path.
class InstructionsDrafts extends Notifier<Map<String, InstructionsDraft>> {
  @override
  Map<String, InstructionsDraft> build() => const {};

  void keep(String path, InstructionsDraft draft) =>
      state = {...state, path: draft};

  void drop(String path) {
    if (!state.containsKey(path)) return;
    state = {...state}..remove(path);
  }
}

final instructionsDraftsProvider =
    NotifierProvider<InstructionsDrafts, Map<String, InstructionsDraft>>(
      InstructionsDrafts.new,
    );

/// The two root buffers of a project and what is done with them (R5, R8,
/// R9). The screen owns it; the buffers survive it through
/// [InstructionsDrafts].
class InstructionsEditing {
  InstructionsEditing(this.root)
    : agents = InstructionsBuffer(root, agentsMdName),
      claude = InstructionsBuffer(root, claudeMdName);

  final String root;
  final InstructionsBuffer agents;
  final InstructionsBuffer claude;
  bool _synced = false;

  List<InstructionsBuffer> get buffers => [agents, claude];
  List<InstructionsBuffer> get dirtyBuffers =>
      buffers.where((b) => b.dirty).toList();
  bool get dirty => buffers.any((b) => b.dirty);

  InstructionsBuffer? byName(String name) => switch (name) {
    agentsMdName => agents,
    claudeMdName => claude,
    _ => null,
  };

  /// Brings the buffers up to the files read in [inv] (R8): the first time
  /// it restores [drafts]; afterwards a file changed on disk is re-read
  /// when there is no edit, and kept aside in
  /// [InstructionsBuffer.outside] when there is.
  void sync(
    InstructionsInventory inv, {
    Map<String, InstructionsDraft> drafts = const {},
  }) {
    for (final (b, disk) in [
      (agents, inv.agentsText),
      (claude, inv.claudeText),
    ]) {
      if (!_synced) {
        final d = drafts[b.path];
        if (d == null) {
          b.load(disk);
          continue;
        }
        b
          ..base = d.base
          ..importLine = d.importLine
          ..loadedImport = d.loadedImport
          ..loaded = d.loaded
          ..controller.text = d.text;
        if (disk != d.base) b.outside = (text: disk);
        continue;
      }
      if (disk == b.base) {
        b.outside = null;
      } else if (!b.dirty) {
        b.load(disk);
      } else {
        b.outside = (text: disk);
      }
    }
    _synced = true;
  }

  /// The edits to keep while the screen is away.
  Map<String, InstructionsDraft> get drafts => {
    for (final b in dirtyBuffers)
      b.path: InstructionsDraft(
        base: b.base,
        importLine: b.importLine,
        loadedImport: b.loadedImport,
        loaded: b.loaded,
        text: b.controller.text,
      ),
  };

  /// "Salvar" (R5, R8): every changed root file in one safe write. A file
  /// changed on disk since the reading comes back in
  /// [InstructionsBuffer.outside] and nothing is written.
  Future<InstructionsWriteResult> save() async {
    final changed = dirtyBuffers;
    try {
      final result = await writeInstructionFiles([
        for (final b in changed) InstructionsWrite(b.snapshot, b.fullText),
      ]);
      for (final w in result.written) {
        final b = byName(w.name)!;
        // Keeps the cursor: the text in the editor is what was written.
        final text = b.controller.text;
        final selection = b.controller.selection;
        b.load(w.text);
        if (b.controller.text != text) continue;
        b.controller.selection = selection;
      }
      return result;
    } on InstructionsConflict catch (e) {
      final b = buffers.firstWhere((b) => b.path == e.path);
      b.outside = (text: (await readInstructionsSnapshot(b.path)).text);
      rethrow;
    }
  }

  /// "Descartar" (R8): every changed file back to the disk version.
  void discard() {
    for (final b in dirtyBuffers) {
      b.load(b.outside == null ? b.base : b.external);
    }
  }

  /// "Usar o do disco" (R8): the edit of [b] gives way to the file.
  void useDisk(InstructionsBuffer b) => b.load(b.external);

  /// "Manter o meu" (R8): the edit stays and the next save replaces the
  /// file that changed.
  void keepMine(InstructionsBuffer b) {
    if (b.outside == null) return;
    b.base = b.external;
    b.outside = null;
  }

  /// "Mover seleção para o AGENTS.md" (R9): takes the selected text out of
  /// the Claude-only part and puts it at the end of the `AGENTS.md`. Both
  /// stay unsaved until "Salvar", which writes them together (R5). False =
  /// nothing selected.
  bool moveSelectionToAgents() {
    final c = claude.controller;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final moved = sel.textInside(c.text).trim();
    if (moved.isEmpty) return false;
    var rest = sel.textBefore(c.text) + sel.textAfter(c.text);
    rest = rest.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    c.value = TextEditingValue(
      text: rest,
      selection: TextSelection.collapsed(
        offset: sel.start.clamp(0, rest.length),
      ),
    );
    final a = agents.controller;
    final head = a.text.trimRight();
    a.text = head.isEmpty ? '$moved\n' : '$head\n\n$moved\n';
    return true;
  }

  /// "Recolocar o import" (R9). Without an edit it writes the `CLAUDE.md`
  /// with the import on top and returns the write (for "Desfazer"); with an
  /// edit the import goes into the buffer, saved with the rest.
  Future<InstructionsWriteResult?> restoreImport() async {
    if (claude.importLine != null) return null;
    if (claude.dirty || claude.base == null) {
      claude.importLine = claudeImportLine;
      return null;
    }
    final result = await writeInstructionFiles([
      InstructionsWrite(claude.snapshot, restoreAgentsImport(claude.base!)),
    ]);
    claude.load(result.written.single.text);
    return result;
  }

  void dispose() {
    agents.dispose();
    claude.dispose();
  }
}

// --- Editor --------------------------------------------------------------------

enum InstructionsEditorMode { text, preview }

/// The center column of Projeto › Instruções for a root file (mocks
/// `1-editar-agents.png`, `2-claude-importa.png`): name and state, Texto /
/// Prévia, "Abrir no editor", the change made outside the app, the text and
/// Salvar / Descartar. [readOnly] (a generated `AGENTS.md`) shows the text
/// without the write actions.
class InstructionsEditor extends StatelessWidget {
  const InstructionsEditor({
    super.key,
    required this.editing,
    required this.buffer,
    required this.mode,
    required this.onMode,
    required this.onOpenExternal,
    required this.onSave,
    required this.onDiscard,
    required this.onUndo,
    required this.onChanged,
    required this.onOpenAgents,
    required this.onRestoreImport,
    this.busy = false,
    this.readOnly = false,
    this.saved = false,
    this.comparing = false,
    this.onCompare,
    this.focusNode,
  });

  final InstructionsEditing editing;
  final InstructionsBuffer buffer;
  final InstructionsEditorMode mode;
  final ValueChanged<InstructionsEditorMode> onMode;
  final VoidCallback onOpenExternal;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  /// Null = nothing to undo.
  final VoidCallback? onUndo;

  /// After a choice on the change made outside (re-render).
  final VoidCallback onChanged;
  final VoidCallback onOpenAgents;
  final VoidCallback onRestoreImport;
  final bool busy;
  final bool readOnly;

  /// The last action was a save (the footer says it, with "Desfazer").
  final bool saved;
  final bool comparing;
  final VoidCallback? onCompare;
  final FocusNode? focusNode;

  bool get _split => buffer.isClaude && buffer.importLine != null;

  @override
  Widget build(BuildContext context) {
    final dirtyNames = [for (final b in editing.dirtyBuffers) b.name];
    final noImport =
        buffer.isClaude &&
        buffer.importLine == null &&
        buffer.exists &&
        editing.agents.exists;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 10),
          if (buffer.outside != null) ...[
            _external(),
            const SizedBox(height: 10),
          ],
          if (noImport) ...[
            NoticeBox.warning(
              key: const ValueKey('instructions-no-import'),
              text:
                  'O CLAUDE.md não importa o AGENTS.md: o Claude Code não lê '
                  'as instruções do AGENTS.md.',
              action: SmallButton(
                key: const ValueKey('instructions-restore-import'),
                label: 'Recolocar o import',
                onTap: busy ? null : onRestoreImport,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_split) ..._importPart(),
          Expanded(child: _body()),
          const SizedBox(height: 10),
          _footer(dirtyNames),
        ],
      ),
    );
  }

  Widget _header() {
    final dirty = buffer.dirty;
    return Row(
      children: [
        Text(
          buffer.name,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(width: 8),
        if (readOnly)
          const InstructionsTag('só leitura')
        else if (!buffer.exists && !dirty)
          const InstructionsTag('novo')
        else
          InstructionsTag(
            dirty ? 'não salvo' : 'salvo',
            key: ValueKey('instructions-state-${dirty ? 'dirty' : 'saved'}'),
            warning: dirty,
          ),
        const Spacer(),
        _ModeButton(
          key: const ValueKey('instructions-mode-text'),
          label: 'Texto',
          on: mode == InstructionsEditorMode.text,
          onTap: () => onMode(InstructionsEditorMode.text),
        ),
        const SizedBox(width: 6),
        _ModeButton(
          key: const ValueKey('instructions-mode-preview'),
          label: 'Prévia',
          on: mode == InstructionsEditorMode.preview,
          onTap: () => onMode(InstructionsEditorMode.preview),
        ),
        const SizedBox(width: 6),
        SmallButton(
          key: const ValueKey('instructions-open-editor'),
          label: 'Abrir no editor',
          onTap: buffer.exists ? onOpenExternal : null,
        ),
      ],
    );
  }

  /// R8: the file changed outside while there is an edit; neither side is
  /// lost before the person chooses.
  Widget _external() {
    final ext = buffer.external;
    return Container(
      key: const ValueKey('instructions-external'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        border: Border.all(color: SessionColors.approvalBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ext == null
                ? 'O ${buffer.name} foi apagado fora do app, e a sua edição '
                      'não foi salva. Escolha o que fica.'
                : 'O ${buffer.name} mudou fora do app, e a sua edição não foi '
                      'salva. Escolha o que fica: nada se perde até você '
                      'escolher.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.amberLight,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SmallButton(
                key: const ValueKey('instructions-keep-mine'),
                label: 'Manter a minha edição',
                onTap: () {
                  editing.keepMine(buffer);
                  onChanged();
                },
              ),
              SmallButton(
                key: const ValueKey('instructions-use-disk'),
                label: 'Usar a versão do disco',
                onTap: () {
                  editing.useDisk(buffer);
                  onChanged();
                },
              ),
              if (onCompare != null)
                SmallButton(
                  key: const ValueKey('instructions-compare'),
                  label: comparing ? 'Esconder a diferença' : 'Comparar',
                  onTap: onCompare,
                ),
            ],
          ),
          if (comparing) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Container(
                  key: const ValueKey('instructions-external-diff'),
                  decoration: BoxDecoration(
                    color: SessionColors.terminalPanel,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DiffView(
                    rows: instructionsDiffRows(ext ?? '', buffer.fullText),
                    collapseSame: 2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// R9: the import line apart from the Claude-only part.
  List<Widget> _importPart() => [
    Container(
      key: const ValueKey('instructions-import-line'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: SessionColors.terminalPanel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        color: projectLilacBg,
        child: Text(
          buffer.importLine!,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            color: projectLilac,
          ),
        ),
      ),
    ),
    const SizedBox(height: 6),
    Row(
      children: [
        const Expanded(
          child: Text(
            'Linha do import. O Claude Code lê aqui o AGENTS.md inteiro.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        SmallButton(
          key: const ValueKey('instructions-open-agents'),
          label: 'Abrir o AGENTS.md',
          onTap: onOpenAgents,
        ),
      ],
    ),
    const SizedBox(height: 14),
    const Row(
      children: [
        Text('SÓ PARA O CLAUDE CODE', style: sectionTitleStyle),
        SizedBox(width: 8),
        InstructionsTag('opcional'),
      ],
    ),
    const SizedBox(height: 8),
  ];

  Widget _body() {
    final box = BoxDecoration(
      color: SessionColors.terminalPanel,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    );
    if (mode == InstructionsEditorMode.preview) {
      return Container(
        key: const ValueKey('instructions-markdown'),
        decoration: box,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: AppMarkdown(data: buffer.controller.text),
        ),
      );
    }
    return Container(
      decoration: box,
      child: TextField(
        key: const ValueKey('instructions-text'),
        controller: buffer.controller,
        focusNode: focusNode,
        readOnly: readOnly,
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12.5,
          height: 1.55,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
          hintText: _split
              ? 'Nada só para o Claude Code. O que vale para os dois agentes '
                    'fica no AGENTS.md.'
              : null,
          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _footer(List<String> dirtyNames) {
    final String status;
    if (readOnly) {
      status = 'Gerado pelo app: edite o CLAUDE.md.';
    } else if (saved && dirtyNames.isEmpty) {
      status = 'Salvo.';
    } else if (dirtyNames.length > 1) {
      status = '${dirtyNames.join(' e ')} não salvos · salvos juntos';
    } else if (dirtyNames.length == 1 && dirtyNames.single != buffer.name) {
      status = '${dirtyNames.single} não salvo';
    } else if (_split) {
      status = 'O Codex não lê este trecho.';
    } else {
      final n = buffer.dirty
          ? changedLines(buffer.loaded, buffer.controller.text)
          : 0;
      status = n > 0
          ? '$n ${n == 1 ? 'linha alterada' : 'linhas alteradas'} · o arquivo '
                'é relido se mudar fora do app'
          : 'O arquivo é relido se mudar fora do app.';
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            status,
            key: const ValueKey('instructions-status'),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (onUndo != null) ...[
          SmallButton(
            key: const ValueKey('instructions-undo'),
            label: 'Desfazer',
            onTap: busy ? null : onUndo,
          ),
          const SizedBox(width: 8),
        ],
        if (!readOnly) ...[
          SmallButton(
            key: const ValueKey('instructions-discard'),
            label: 'Descartar',
            height: 34,
            onTap: busy || dirtyNames.isEmpty ? null : onDiscard,
          ),
          const SizedBox(width: 8),
          AmberButton(
            key: const ValueKey('instructions-save'),
            label: busy ? 'Salvando…' : 'Salvar',
            height: 34,
            onTap: busy || dirtyNames.isEmpty ? null : onSave,
          ),
        ],
      ],
    );
  }
}

/// How many lines differ between [before] and [after] (the footer, mock 1).
int changedLines(String before, String after) {
  var adds = 0, dels = 0;
  for (final d in lineDiff(before, after)) {
    if (d.op == DiffOp.add) adds++;
    if (d.op == DiffOp.del) dels++;
  }
  return adds > dels ? adds : dels;
}

/// The rows of a [DiffView] from [before] to [after].
List<DiffRow> instructionsDiffRows(String before, String after) {
  var oldLine = 1, newLine = 1;
  final lines = lineDiff(before, after);
  if (lines.lastOrNull case (op: DiffOp.same, text: '')) lines.removeLast();
  return [
    for (final d in lines)
      switch (d.op) {
        DiffOp.same => () {
          oldLine++;
          return (op: d.op, text: d.text, line: newLine++);
        }(),
        DiffOp.del => (op: d.op, text: d.text, line: oldLine++),
        DiffOp.add => (op: d.op, text: d.text, line: newLine++),
      },
  ];
}

/// A small tag (`fonte`, `importa`, `não salvo`, `só leitura`).
class InstructionsTag extends StatelessWidget {
  const InstructionsTag(
    this.text, {
    super.key,
    this.warning = false,
    this.lilac = false,
  });

  final String text;
  final bool warning;
  final bool lilac;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = warning
        ? (
            AppColors.amber,
            SessionColors.approvalBg,
            SessionColors.approvalBorder,
          )
        : lilac
        ? (projectLilac, projectLilacBg, projectLilacBorder)
        : (AppColors.textSecondary, AppColors.surfaceRaised, AppColors.border);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    child: SmallButton(
      label: label,
      onTap: onTap,
      background: on ? AppColors.surfaceRaised : AppColors.panel,
      border: on ? AppColors.borderHover : AppColors.border,
    ),
  );
}
