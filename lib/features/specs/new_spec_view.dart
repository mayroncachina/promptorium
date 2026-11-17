import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_cli.dart';
import '../../core/clipboard/clipboard_image.dart';
import '../../core/process/process_runner.dart';
import '../../data/providers.dart';
import '../../ui/shell/footer_stats.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../ideas/widgets/idea_field.dart';
import '../issues/issue_refine.dart';
import '../project/project_config.dart';
import '../project/project_plan.dart' show PlanMessage;
import '../project/widgets/project_widgets.dart';
import '../sessions/widgets/session_style.dart';
import 'new_spec_dialog.dart';
import 'spec_draft.dart';
import 'spec_planner.dart';
import 'spec_prints.dart';
import 'widgets/print_cards.dart';

/// "Nova spec" from anywhere (SPEC-039 R1): the Specs screen, on the idea.
Future<void> openNewSpec(WidgetRef ref) async {
  // Read before waiting: the palette that called this closes in the meantime.
  final flow = ref.read(newSpecFlowProvider.notifier);
  final moved = await ref
      .read(navigationProvider.notifier)
      .request(AppSection.specs);
  if (moved) flow.open();
}

/// A spec came out of "Nova spec"; [plan] = start Planejar on it.
typedef NewSpecCreated = void Function(Spec spec, {required bool plan});

/// "Nova spec" in the main area of the Specs screen (SPEC-039): the idea and
/// the mini planejamento, with the draft beside the conversation.
class NewSpecView extends ConsumerWidget {
  const NewSpecView({
    super.key,
    required this.workspace,
    required this.onCreated,
  });

  final Workspace workspace;
  final NewSpecCreated onCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(specDraftProvider(workspace.id)).value;
    final conversation =
        row != null &&
        ref.watch(newSpecFlowProvider) == NewSpecStage.conversation;
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Trail(
            readOnlyTag: conversation,
            onSpecs: () => ref.read(newSpecFlowProvider.notifier).close(),
          ),
          Expanded(
            child: conversation
                ? _MiniPlanning(
                    workspace: workspace,
                    row: row,
                    onCreated: onCreated,
                  )
                : _Idea(workspace: workspace, row: row, onCreated: onCreated),
          ),
        ],
      ),
    );
  }
}

/// "Specs / Nova spec" (R1).
class _Trail extends StatelessWidget {
  const _Trail({required this.readOnlyTag, required this.onSpecs});

  final bool readOnlyTag;
  final VoidCallback onSpecs;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        TextButton(
          key: const ValueKey('new-spec-trail-specs'),
          onPressed: onSpecs,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 30),
            textStyle: const TextStyle(fontFamily: AppFonts.sans, fontSize: 12),
          ),
          child: const Text('Specs'),
        ),
        const ExcludeSemantics(
          child: Text(
            '/',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Nova spec',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const Spacer(),
        if (readOnlyTag) InfoTag('planner · somente leitura'),
      ],
    ),
  );
}

/// Text field of this flow (R12): the border stands out from the background.
InputDecoration _fieldDecoration({String? hint, bool dense = false}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    isDense: dense,
    filled: true,
    fillColor: AppColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: border(AppColors.inputBorder),
    enabledBorder: border(AppColors.inputBorder),
    focusedBorder: border(AppColors.amber, 2),
  );
}

/// "Conte a ideia" (R1), with the saved draft (R8) or the missing CLI (R9)
/// above it.
class _Idea extends ConsumerStatefulWidget {
  const _Idea({
    required this.workspace,
    required this.row,
    required this.onCreated,
  });

  final Workspace workspace;
  final SpecDraft? row;
  final NewSpecCreated onCreated;

  @override
  ConsumerState<_Idea> createState() => _IdeaState();
}

class _IdeaState extends ConsumerState<_Idea> {
  final _text = TextEditingController();
  bool _checking = false;

  /// "Planejar a spec" ran: the refine target goes on with the draft.
  bool _planning = false;

  /// The prints of the idea (SPEC-083 R4), until "Planejar a spec" hands
  /// them to the draft.
  List<SpecPrint> _prints = const [];

  /// Why the last print was refused (R3).
  String? _printError;

  /// Ctrl V with an image and no `wl-paste` / `xclip` (R2).
  ClipboardToolMissing? _toolMissing;

  /// "Print 1 anexado, 1568 × 980" (R12).
  String? _printStatus;

  /// A print being read: one at a time keeps the order.
  Future<void> _printQueue = Future.value();

  late final _screenFocus = FocusNode(
    debugLabel: 'new-spec-idea-screen',
    skipTraversal: true,
  );

  /// Read here: the widget's ref is gone in [dispose].
  late final IssueRefine _refine;

  @override
  void initState() {
    super.initState();
    _refine = ref.read(issueRefineProvider.notifier);
    // SPEC-074 R6: the text of the issue, as an imported file.
    final target = ref.read(issueRefineProvider)[widget.workspace.id];
    if (target != null && widget.row == null) _text.text = target.text;
  }

  @override
  void dispose() {
    // Left without planning: the next "Nova spec" is a new spec again.
    if (!_planning && widget.row == null) {
      final refine = _refine;
      final id = widget.workspace.id;
      Future.microtask(() => refine.clear(id));
    }
    // Left without planning: the prints were never kept (R4).
    if (!_planning && _prints.isNotEmpty) {
      unawaited(deletePrintFiles(_prints));
    }
    _text.dispose();
    _screenFocus.dispose();
    super.dispose();
  }

  /// R1: Ctrl V anywhere on the screen also looks for an image; the text
  /// paste goes on as before (the event is not consumed).
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final k = HardwareKeyboard.instance;
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyV &&
        k.isControlPressed &&
        !k.isShiftPressed &&
        !k.isAltPressed) {
      unawaited(_pasteImage());
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pasteImage() async {
    final r = await ref.read(clipboardImageReaderProvider).read();
    if (!mounted) return;
    switch (r) {
      case ClipboardImageFound(:final bytes):
        await _addPrint(() async => bytes);
      case ClipboardToolMissing():
        // Without the tool there is no way to see the image; text in the
        // clipboard means a normal paste, so the notice is only for the
        // rest (R2).
        final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        if (!mounted || (text != null && text.isNotEmpty)) return;
        setState(() => _toolMissing = r);
      case ClipboardNoImage():
        break;
    }
  }

  /// "Anexar print…" (R1).
  Future<void> _pickPrint() async {
    final path = await ref.read(printFilePickerProvider)();
    if (path == null || !mounted) return;
    await _addFiles([path]);
  }

  /// Dropped or picked image files (R1).
  Future<void> _addFiles(List<String> paths) async {
    for (final path in paths) {
      final name = path.split('/').last;
      await _addPrint(() async {
        final f = File(path);
        if (await f.length() > maxPrintBytes) {
          throw PrintException(
            '"$name" tem mais de 20 MB. Reduza a imagem e tente de novo.',
          );
        }
        return f.readAsBytes();
      }, sourceName: name);
    }
  }

  Future<void> _addPrint(
    Future<List<int>> Function() read, {
    String? sourceName,
  }) {
    final job = _printQueue.then((_) async {
      try {
        final bytes = await read();
        final print = await preparePrint(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          workspacePath: _ws.path,
          existing: _prints,
          sourceName: sourceName,
        );
        if (!mounted) {
          await deletePrintFiles([print]);
          return;
        }
        final n = _prints.length + 1;
        final status = 'Print $n anexado, ${print.width} por ${print.height}';
        setState(() {
          _prints = [..._prints, print];
          _printError = null;
          _toolMissing = null;
          _printStatus = 'Print $n anexado, ${print.sizeLabel}';
        });
        if (mounted) {
          unawaited(
            SemanticsService.sendAnnouncement(
              View.of(context),
              status,
              TextDirection.ltr,
            ),
          );
        }
      } on PrintException catch (e) {
        if (mounted) setState(() => _printError = e.message);
      } on FileSystemException catch (e) {
        if (mounted) {
          setState(
            () => _printError =
                'Não foi possível ler ${sourceName ?? 'a imagem'}: '
                '${e.osError?.message ?? e.message}',
          );
        }
      }
    });
    _printQueue = job.catchError((Object _) {});
    return job;
  }

  void _setKind(int index, PrintKind kind) => setState(
    () => _prints = [
      for (final (i, s) in _prints.indexed)
        i == index ? s.copyWith(kind: kind) : s,
    ],
  );

  void _removePrint(int index) {
    final gone = _prints[index];
    setState(() {
      _prints = renumberPrints([..._prints]..removeAt(index));
      _printError = null;
      _printStatus = null;
    });
    unawaited(deletePrintFiles([gone]));
  }

  Workspace get _ws => widget.workspace;

  Future<void> _plan() async {
    final idea = _text.text.trim();
    if (idea.isEmpty && _prints.isEmpty) return;
    if (!printsTyped(_prints)) return;
    _planning = true;
    final planner = ref.read(specPlannerProvider.notifier);
    final started = planner.begin(_ws, idea, prints: _prints);
    ref.read(newSpecFlowProvider.notifier).converse();
    await started;
  }

  Future<void> _blank() async {
    final spec = await showNewSpecDialog(context);
    if (spec != null) widget.onCreated(spec, plan: false);
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final footer = ref.read(footerStatsProvider.notifier);
    final resolved = ref.read(resolvedClaudeCliProvider.notifier);
    try {
      final info = await detectClaudeCli(
        run: ref.read(processRunnerProvider),
        candidates: ref.read(claudeExecutableCandidatesProvider),
      );
      resolved.set(info);
      footer.setCli(CliStatus.connected, version: info.version);
    } on ClaudeCliNotFound {
      resolved.set(null);
      footer.setCli(CliStatus.notFound);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _discard(SpecDraftData data) async {
    if (data.requirements.isNotEmpty && !await _confirmDiscard(data)) return;
    await ref.read(specPlannerProvider.notifier).discard(_ws);
  }

  Future<bool> _confirmDiscard(SpecDraftData data) async {
    final n = data.requirements.length;
    final subject = data.title.isEmpty ? 'O rascunho' : data.title;
    final discard = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('new-spec-discard-dialog'),
        backgroundColor: AppColors.panel,
        title: const Text(
          'Descartar o rascunho?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 380,
          child: Text(
            '$subject tem $n ${n == 1 ? 'requisito' : 'requisitos'} e a '
            'conversa com o planner. Isso não pode ser desfeito.',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
        actions: [
          OutlinedButton(
            key: const ValueKey('new-spec-discard-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: SessionColors.stopBorder),
            ),
            child: const Text('Descartar'),
          ),
          FilledButton(
            key: const ValueKey('new-spec-discard-keep'),
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.onAmber,
            ),
            child: const Text(
              'Manter rascunho',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final data = row == null ? null : SpecDraftData.decode(row.data);
    final noCli = ref.watch(cliStatusProvider).$1 == CliStatus.notFound;
    final busy = ref.watch(specPlannerProvider).contains(_ws.id);
    final untyped = !printsTyped(_prints);
    final hint = data != null
        ? 'Continue ou descarte o rascunho para planejar outra ideia.'
        : untyped
        ? 'Diga se cada print é um bug ou uma referência'
        : noCli
        ? 'Em branco abre o modelo de sempre.'
        : 'Em branco abre o modelo de sempre, sem chamar o planner.';
    final hasIdea = _text.text.trim().isNotEmpty || _prints.isNotEmpty;
    return Focus(
      focusNode: _screenFocus,
      onKeyEvent: _onKey,
      // A click on the empty part of the screen takes the focus off the
      // field (desktop); it lands here so Ctrl V still works (R1).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _screenFocus.requestFocus,
        child: _ideaBody(
          context,
          data,
          row,
          noCli,
          busy,
          untyped,
          hint,
          hasIdea,
        ),
      ),
    );
  }

  Widget _ideaBody(
    BuildContext context,
    SpecDraftData? data,
    SpecDraft? row,
    bool noCli,
    bool busy,
    bool untyped,
    String hint,
    bool hasIdea,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (noCli) ...[
                _NoCliCard(checking: _checking, onVerify: _verify),
                const SizedBox(height: 12),
              ],
              if (data != null) ...[
                _DraftCard(
                  line: draftSummary(data, row!.updatedAt, DateTime.now()),
                  onDiscard: busy ? null : () => _discard(data),
                  onContinue: noCli
                      ? null
                      : ref.read(newSpecFlowProvider.notifier).converse,
                ),
                const SizedBox(height: 12),
              ],
              if (ref.watch(issueRefineProvider)[_ws.id] case final t?) ...[
                IssueRefineCard(target: t),
                const SizedBox(height: 12),
              ],
              const Text(
                'Conte a ideia',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Uma ou duas frases: o que muda e para quem. O planner lê o '
                'repositório, faz poucas perguntas e monta a spec com você. '
                'Já tem um documento? Importe o texto dele. Tem um print? '
                'Cole com Ctrl V.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              IdeaField(
                fieldKey: const ValueKey('new-spec-idea'),
                controller: _text,
                autofocus: true,
                hint:
                    'Avisar o paciente antes da consulta, para reduzir as '
                    'faltas…',
                onChanged: (_) => setState(() {}),
                onImageFiles: _addFiles,
                onAttachPrint: _pickPrint,
                printHint:
                    'ou cole com Ctrl V · até $maxPrints prints · PDF, '
                    'Markdown ou TXT',
              ),
              if (_printStatus case final status?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '✓ $status',
                    key: const ValueKey('print-status'),
                    style: const TextStyle(fontSize: 11, color: AppColors.teal),
                  ),
                ),
              if (_toolMissing case final missing?) ...[
                const SizedBox(height: 10),
                _ToolMissingCard(
                  missing: missing,
                  onClose: () => setState(() => _toolMissing = null),
                ),
              ],
              if (_printError case final error?) ...[
                const SizedBox(height: 10),
                _PrintErrorLine(error),
              ],
              if (_prints.isNotEmpty) ...[
                const SizedBox(height: 12),
                PrintCards(
                  prints: _prints,
                  onKind: _setKind,
                  onRemove: _removePrint,
                ),
                const SizedBox(height: 10),
                const _SensitiveWarning(),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AmberButton(
                    key: const ValueKey('new-spec-plan'),
                    label: 'Planejar a spec',
                    height: 36,
                    fontSize: 13,
                    onTap: !hasIdea || untyped || data != null || noCli || busy
                        ? null
                        : _plan,
                  ),
                  SmallButton(
                    key: const ValueKey('new-spec-blank'),
                    label: 'Criar em branco',
                    height: 36,
                    fontSize: 13,
                    onTap: _blank,
                  ),
                  Text(
                    hint,
                    key: const ValueKey('new-spec-plan-hint'),
                    style: TextStyle(
                      fontSize: 11,
                      color: untyped && data == null
                          ? AppColors.amber
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// R5: the fixed notice under the cards.
class _SensitiveWarning extends StatelessWidget {
  const _SensitiveWarning();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('print-sensitive-warning'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: AppColors.amberTint,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: SessionColors.approvalBorder),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: AppColors.amber,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'O print vai para o repositório quando a spec for criada. Confira '
            'se ele não mostra senha, token, e-mail ou dado de cliente.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.text),
          ),
        ),
      ],
    ),
  );
}

/// R3: why a print was refused.
class _PrintErrorLine extends StatelessWidget {
  const _PrintErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('print-error'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SessionColors.stopBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.red),
      ),
    ),
  );
}

/// R2: Ctrl V with an image and no `wl-paste` / `xclip`.
class _ToolMissingCard extends StatelessWidget {
  const _ToolMissingCard({required this.missing, required this.onClose});

  final ClipboardToolMissing missing;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('print-tool-missing'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaisedSolid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderHover),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  ClipboardToolMissing.message,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('print-tool-missing-close'),
                tooltip: 'Fechar aviso',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            decoration: BoxDecoration(
              color: AppColors.backgroundSolid,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    missing.command,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                    ),
                  ),
                ),
                SmallButton(
                  key: const ValueKey('print-tool-copy'),
                  label: 'Copiar',
                  height: 26,
                  semanticLabel: 'Copiar o comando de instalação',
                  onTap: () =>
                      Clipboard.setData(ClipboardData(text: missing.command)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enquanto isso, arraste o arquivo para o campo ou use "Anexar '
            'print…".',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

/// "Da issue #215" (SPEC-074 R6): the text came from the issue, and saving
/// rewrites the same spec.
class IssueRefineCard extends StatelessWidget {
  const IssueRefineCard({super.key, required this.target});

  final IssueRefineTarget target;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('new-spec-issue-card'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaisedSolid,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.borderHover),
    ),
    child: Row(
      children: [
        const Icon(Icons.adjust, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Da issue #${target.issue}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'O texto da issue está no campo. Criar a spec reescreve a '
                '${target.code}, com o mesmo issue: ${target.issue}; nada é '
                'enviado sozinho.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.line,
    required this.onDiscard,
    required this.onContinue,
  });

  final String line;
  final VoidCallback? onDiscard;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('new-spec-draft-card'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.amberTint,
      border: Border.all(color: SessionColors.approvalBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Você tem um rascunho',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                line,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SmallButton(
          key: const ValueKey('new-spec-discard'),
          label: 'Descartar',
          onTap: onDiscard,
        ),
        const SizedBox(width: 10),
        AmberButton(
          key: const ValueKey('new-spec-continue'),
          label: 'Continuar',
          onTap: onContinue,
        ),
      ],
    ),
  );
}

/// Card of a failure, as in the mockup: red border, title, reason.
class _FailureCard extends StatelessWidget {
  const _FailureCard({
    super.key,
    required this.title,
    required this.text,
    this.action,
    this.trailing,
  });

  final String title;
  final String text;
  final Widget? action;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.panel,
      border: Border.all(color: SessionColors.stopBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline, size: 15, color: AppColors.red),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    ),
  );
}

class _NoCliCard extends StatelessWidget {
  const _NoCliCard({required this.checking, required this.onVerify});

  final bool checking;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) => _FailureCard(
    key: const ValueKey('new-spec-no-cli'),
    title: 'Claude Code CLI não encontrado',
    text:
        'O planner precisa dele para ler o repositório. Conecte o Claude '
        'Code e verifique de novo, ou crie a spec em branco.',
    trailing: SmallButton(
      key: const ValueKey('new-spec-verify'),
      label: 'Verificar de novo',
      onTap: checking ? null : onVerify,
    ),
  );
}

/// The conversation (left) and the draft (right) (R3, R5).
class _MiniPlanning extends ConsumerWidget {
  const _MiniPlanning({
    required this.workspace,
    required this.row,
    required this.onCreated,
  });

  final Workspace workspace;
  final SpecDraft row;
  final NewSpecCreated onCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = SpecDraftData.decode(row.data);
    final busy = ref.watch(specPlannerProvider).contains(workspace.id);
    final planner = ref.read(specPlannerProvider.notifier);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StepHeader(
                title: 'Mini planejamento',
                subtitle:
                    'Converse com o planner. O rascunho à direita é '
                    'preenchido a cada resposta.',
              ),
              Expanded(
                child: _Conversation(
                  messages: data.messages,
                  prints: data.prints,
                  busy: busy,
                  failed: !busy && data.unanswered.isNotEmpty,
                  onSuggestion: (s) => planner.send(workspace, s),
                  onRetry: () => planner.retry(workspace),
                ),
              ),
              _Composer(
                enabled: !busy,
                onSend: (text) => planner.send(workspace, text),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 420,
          child: _DraftPanel(
            workspace: workspace,
            data: data,
            busy: busy,
            onCreated: onCreated,
          ),
        ),
      ],
    );
  }
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.messages,
    this.prints = const [],
    required this.busy,
    required this.failed,
    required this.onSuggestion,
    required this.onRetry,
  });

  final List<PlanMessage> messages;

  /// Shown with the first message of the person (SPEC-083 R6).
  final List<SpecPrint> prints;
  final bool busy;
  final bool failed;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onRetry;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _scroll = ScrollController();

  /// R3: the end of the conversation stays in view.
  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  @override
  void didUpdateWidget(_Conversation old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length ||
        old.busy != widget.busy ||
        old.failed != widget.failed) {
      _toEnd();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    final idle = !widget.busy && !widget.failed;
    final lastPlanner = msgs.lastIndexWhere((m) => !m.fromUser);
    final firstUser = msgs.indexWhere((m) => m.fromUser);
    // Measured, not estimated: a lazy list stops short of the real end.
    return SingleChildScrollView(
      key: const ValueKey('new-spec-conversation'),
      controller: _scroll,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, m) in msgs.indexed) ...[
            _Message(
              message: m,
              prints: i == firstUser ? widget.prints : const [],
              suggestions: idle && i == lastPlanner ? m.suggestions : const [],
              onSuggestion: widget.onSuggestion,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.busy)
            const Align(
              alignment: Alignment.centerLeft,
              child: PlannerBusy('Pensando…'),
            ),
          if (widget.failed)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _FailureCard(
                key: const ValueKey('new-spec-planner-failed'),
                title: 'O planner não respondeu',
                text:
                    'Sua conversa e o rascunho continuam aqui. Tente de novo '
                    'ou crie a spec com o que já tem.',
                action: SmallButton(
                  key: const ValueKey('new-spec-retry'),
                  label: 'Tentar de novo',
                  onTap: widget.onRetry,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.message,
    this.prints = const [],
    required this.suggestions,
    required this.onSuggestion,
  });

  final PlanMessage message;
  final List<SpecPrint> prints;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: SessionColors.selectedBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, s) in prints.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        PrintThumbnail(
                          print: s,
                          index: i,
                          width: 72,
                          height: 46,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${s.name} · ${s.kind == PrintKind.reference ? 'referência de outro app' : 'bug neste projeto'}',
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
                SelectableText(
                  m.text,
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Planner',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              m.text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.text,
              ),
            ),
            if (m.note != null) ...[
              const SizedBox(height: 6),
              Text(
                m.note!,
                style: const TextStyle(fontSize: 11, color: AppColors.teal),
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    ChipButton(
                      key: ValueKey('new-spec-suggestion-$s'),
                      label: s,
                      onTap: () => onSuggestion(s),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Answer field, fixed under the conversation (R12).
class _Composer extends StatefulWidget {
  const _Composer({required this.enabled, required this.onSend});

  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (!widget.enabled || t.isEmpty) return;
    _text.clear();
    widget.onSend(t);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _send,
            },
            child: TextField(
              key: const ValueKey('new-spec-composer'),
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              decoration: _fieldDecoration(
                hint: 'Responda ou descreva mais sobre a ideia…',
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ListenableBuilder(
          listenable: _text,
          builder: (_, _) => SmallButton(
            key: const ValueKey('new-spec-send'),
            label: 'Enviar',
            height: 36,
            onTap: widget.enabled && _text.text.trim().isNotEmpty
                ? _send
                : null,
          ),
        ),
      ],
    ),
  );
}

/// "Rascunho da spec": what the spec will have, with the fixed actions at the
/// bottom (R5–R7, R12).
class _DraftPanel extends ConsumerStatefulWidget {
  const _DraftPanel({
    required this.workspace,
    required this.data,
    required this.busy,
    required this.onCreated,
  });

  final Workspace workspace;
  final SpecDraftData data;
  final bool busy;
  final NewSpecCreated onCreated;

  @override
  ConsumerState<_DraftPanel> createState() => _DraftPanelState();
}

class _DraftPanelState extends ConsumerState<_DraftPanel> {
  late final _title = TextEditingController(text: widget.data.title);
  bool _creating = false;
  bool _createFailed = false;

  @override
  void didUpdateWidget(_DraftPanel old) {
    super.didUpdateWidget(old);
    final d = widget.data;
    if (!d.titleEdited && d.title != _title.text) _title.text = d.title;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _planNext =>
      ref.read(appSettingsProvider.notifier).get(AppSettingKeys.specPlanNext) !=
      '0';

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _createFailed = false;
    });
    try {
      final spec = await ref
          .read(specPlannerProvider.notifier)
          .create(widget.workspace, title: _title.text);
      widget.onCreated(spec, plan: _planNext);
    } catch (e) {
      debugPrint('Criar spec do rascunho: $e');
      if (mounted) setState(() => _createFailed = true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    ref.watch(appSettingsProvider);
    final planNext = _planNext;
    // SPEC-074 R6: refining an issue's spec saves over it.
    final refine = ref.watch(issueRefineProvider)[widget.workspace.id];
    final code =
        refine?.code ?? ref.watch(nextSpecCodeProvider(widget.workspace)).value;
    final specs =
        ref.watch(specsProvider(widget.workspace.id)).value ?? const <Spec>[];
    // SPEC-083 R9: a citation of the reference app blocks "Criar spec".
    final mentions = brandMentions(d);
    final canCreate =
        d.hasReply &&
        !widget.busy &&
        !_creating &&
        _title.text.trim().isNotEmpty &&
        mentions.isEmpty;
    List<(int, int)> marks(String where) => [
      for (final m in mentions)
        if (m.where == where) (m.start, m.end),
    ];
    final planner = ref.read(specPlannerProvider.notifier);
    final folder = ProjectConfig.loadSync(widget.workspace.path).specsDir;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Rascunho da spec',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                if (code != null) ...[
                  Text(
                    code,
                    key: const ValueKey('new-spec-code'),
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                InfoTag('rascunho'),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('new-spec-draft'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                const _Label('Título'),
                TextField(
                  key: const ValueKey('new-spec-draft-title'),
                  controller: _title,
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                  decoration: _fieldDecoration(dense: true),
                  onChanged: (text) {
                    setState(() {});
                    ref
                        .read(specPlannerProvider.notifier)
                        .editTitle(widget.workspace, text);
                  },
                ),
                const SizedBox(height: 14),
                const _Label('Objetivo'),
                d.objective.isEmpty
                    ? const _Empty()
                    : _Body(d.objective, marks: marks('Objetivo')),
                if (d.prints.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const _Label('Referência visual'),
                  for (final (i, s) in d.prints.indexed)
                    _DraftPrint(
                      key: ValueKey('draft-print-$i'),
                      index: i,
                      print: s,
                      onDescription: (text) => planner.editPrintDescription(
                        widget.workspace,
                        i,
                        text,
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                _Label(
                  'Requisitos',
                  trailing: d.requirements.isEmpty
                      ? null
                      : '${d.requirements.length} · máximo '
                            '${SpecDraftData.maxRequirements}',
                ),
                if (d.requirements.isEmpty) const _Empty(),
                for (final (i, r) in d.requirements.indexed)
                  _Item(
                    id: 'R${i + 1}',
                    text: r,
                    isNew: d.newRequirements.contains(r),
                    marks: marks('R${i + 1}'),
                  ),
                for (final brand in {for (final m in mentions) m.brand})
                  _BrandWarning(
                    key: ValueKey('brand-warning-$brand'),
                    brand: brand,
                    where: {
                      for (final m in mentions)
                        if (m.brand == brand) m.where,
                    }.toList(),
                    onRewrite: widget.busy
                        ? null
                        : () => planner.rewriteBrands(
                            widget.workspace,
                            {for (final m in mentions) m.brand}.toList(),
                          ),
                  ),
                const SizedBox(height: 14),
                const _Label('Fora do escopo'),
                if (d.outOfScope.isEmpty) const _Empty(),
                for (final o in d.outOfScope)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _Body(
                      o,
                      marks: [
                        for (final m in mentions)
                          if (m.where == 'Fora do escopo' && m.text == o)
                            (m.start, m.end),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                const _Label('Depende de'),
                if (d.dependsOn.isEmpty) const _Empty(),
                for (final c in d.dependsOn)
                  _Item(
                    id: c,
                    text:
                        specs.where((s) => s.code == c).firstOrNull?.title ??
                        '',
                  ),
                const SizedBox(height: 14),
                const _Label('Perguntas em aberto'),
                if (d.openQuestions.isEmpty) const _Empty(),
                for (final (i, q) in d.openQuestions.indexed)
                  _Item(
                    id: 'P${i + 1}',
                    text: q.text,
                    detail: q.suggestion.isEmpty
                        ? null
                        : 'Sugestão: ${q.suggestion}',
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_createFailed) ...[
                  _FailureCard(
                    key: const ValueKey('new-spec-create-failed'),
                    title: 'Não foi possível criar a spec',
                    text:
                        'A pasta $folder/ não aceitou o arquivo. A conversa e '
                        'o rascunho continuam aqui. Corrija a pasta e crie de '
                        'novo.',
                  ),
                  const SizedBox(height: 10),
                ],
                _PlanNextOption(
                  value: planNext,
                  onChanged: (v) => ref
                      .read(appSettingsProvider.notifier)
                      .set(AppSettingKeys.specPlanNext, v ? '1' : '0'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SmallButton(
                      key: const ValueKey('new-spec-leave'),
                      label: 'Sair e guardar',
                      height: 36,
                      fontSize: 13,
                      onTap: ref.read(newSpecFlowProvider.notifier).close,
                    ),
                    AmberButton(
                      key: const ValueKey('new-spec-create'),
                      label: planNext ? 'Criar e planejar' : 'Criar spec',
                      height: 36,
                      fontSize: 13,
                      busy: _creating,
                      onTap: canCreate ? _create : null,
                    ),
                  ],
                ),
                if (mentions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tire as citações ao app de referência '
                    '(${mentions.length})',
                    key: const ValueKey('brand-block-hint'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.amber,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanNextOption extends StatelessWidget {
  const _PlanNextOption({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            key: const ValueKey('new-spec-plan-next'),
            value: value,
            activeColor: AppColors.amber,
            checkColor: AppColors.onAmber,
            side: const BorderSide(color: AppColors.inputBorder),
            onChanged: (v) => onChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Escrever o Plano em seguida',
                  style: TextStyle(fontSize: 13, color: AppColors.text),
                ),
                SizedBox(height: 2),
                Text(
                  'Depois de criar, lê o código e grava ## Plano e ## Etapas.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Text(
    'Ainda vazio',
    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text, {this.marks = const []});

  final String text;

  /// Citations of the reference app, highlighted (SPEC-083 R9).
  final List<(int, int)> marks;

  static const _style = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) return Text(text, style: _style);
    final sorted = [...marks]..sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in sorted) {
      if (start < at) continue;
      spans
        ..add(TextSpan(text: text.substring(at, start)))
        ..add(
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              backgroundColor: SessionColors.approvalBg,
              color: AppColors.amberLight,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.amber,
            ),
          ),
        );
      at = end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: _style, children: spans));
  }
}

/// One print of "Referência visual" (SPEC-083 R8): the thumbnail, the kind
/// and the description written by the planner, which the person may edit.
class _DraftPrint extends StatefulWidget {
  const _DraftPrint({
    super.key,
    required this.index,
    required this.print,
    required this.onDescription,
  });

  final int index;
  final SpecPrint print;
  final ValueChanged<String> onDescription;

  @override
  State<_DraftPrint> createState() => _DraftPrintState();
}

class _DraftPrintState extends State<_DraftPrint> {
  late final _text = TextEditingController(text: widget.print.description);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_DraftPrint old) {
    super.didUpdateWidget(old);
    final d = widget.print.description;
    if (!_focus.hasFocus && d != _text.text) _text.text = d;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.print;
    final n = widget.index + 1;
    final reference = s.kind == PrintKind.reference;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrintThumbnail(print: s, index: widget.index, width: 112, height: 70),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      s.name,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                      ),
                    ),
                    InfoTag(s.kind?.short ?? 'sem tipo'),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  key: ValueKey('draft-print-description-${widget.index}'),
                  controller: _text,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                  decoration: _fieldDecoration(
                    dense: true,
                    hint: 'O que o print $n mostra',
                  ),
                  onChanged: widget.onDescription,
                ),
                if (reference) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Só referência: a spec não copia a marca, o nome, os '
                    'textos nem os ícones do app de referência.',
                    key: ValueKey('draft-print-reference-note'),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.lilac,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "A spec cita “Nimbo” do app de referência" (SPEC-083 R9).
class _BrandWarning extends StatelessWidget {
  const _BrandWarning({
    super.key,
    required this.brand,
    required this.where,
    required this.onRewrite,
  });

  final String brand;
  final List<String> where;
  final VoidCallback? onRewrite;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.approvalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'A spec cita “$brand” do app de referência',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.amberLight,
                        ),
                      ),
                      TextSpan(
                        text: '  ${where.join(', ')}',
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SmallButton(
                key: const ValueKey('brand-rewrite'),
                label: 'Pedir ao planner para reescrever',
                onTap: onRewrite,
              ),
              const Text(
                'ou responda na conversa',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// `R1 texto [novo]`, `SPEC-005 título`, `P1 pergunta` + sugestão.
class _Item extends StatelessWidget {
  const _Item({
    required this.id,
    required this.text,
    this.detail,
    this.isNew = false,
    this.marks = const [],
  });

  final String id;
  final String text;
  final String? detail;
  final bool isNew;
  final List<(int, int)> marks;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            id,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Body(text, marks: marks),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    detail!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (isNew) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: SessionColors.runningToolBorder),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'novo',
              style: TextStyle(fontSize: 10, color: AppColors.teal),
            ),
          ),
        ],
      ],
    ),
  );
}

/// "Rascunho guardado" above the list of specs (R8): opens "Nova spec".
class SavedDraftCard extends ConsumerWidget {
  const SavedDraftCard({super.key, required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(specDraftProvider(workspace.id)).value;
    if (row == null) return const SizedBox.shrink();
    final data = SpecDraftData.decode(row.data);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Material(
        color: AppColors.amberTint,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: SessionColors.approvalBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('specs-saved-draft'),
          onTap: ref.read(newSpecFlowProvider.notifier).open,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rascunho guardado',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  draftSummary(data, row.updatedAt, DateTime.now()),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
