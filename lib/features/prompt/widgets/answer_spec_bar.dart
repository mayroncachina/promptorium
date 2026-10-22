import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../project/project_config.dart';
import '../../sessions/session_manager.dart' show slugify;
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart';
import '../spec_from_answer.dart';

/// Where a spec of an answer goes (SPEC-016): the spec of the same `id` in
/// the project, its file as read now, and the code a new spec would get.
typedef AnswerSpecTarget = ({
  Workspace ws,
  Spec? target,
  String? current,
  bool stale,
  String nextCode,
});

final answerSpecTargetProvider = FutureProvider.autoDispose
    .family<AnswerSpecTarget, (Conversation, String?)>((ref, key) async {
      final (c, id) = key;
      final ws = await ref.read(workspacesRepoProvider).getById(c.workspaceId);
      if (ws == null) throw const SpecException('Projeto não encontrado.');
      final repo = ref.read(specsRepoProvider);
      final target = id == null ? null : await repo.getByCode(ws.id, id);
      String? current;
      var stale = false;
      if (target != null) {
        final service = ref.read(specServiceProvider);
        current = await service.read(ws, target);
        final f = service.fileOf(ws, target);
        stale =
            current != null &&
            (await f.lastModified()).isAfter(c.createdAt.toLocal());
      }
      return (
        ws: ws,
        target: target,
        current: current,
        stale: stale,
        nextCode: await nextSpecCode(repo, ws),
      );
    });

/// Specs saved from answers in this run: `<conversation>:<hash>` → spec.
class AnswerSpecsSaved extends Notifier<Map<String, Spec>> {
  @override
  Map<String, Spec> build() => const {};

  void set(String key, Spec spec) => state = {...state, key: spec};
}

final answerSpecsSavedProvider =
    NotifierProvider<AnswerSpecsSaved, Map<String, Spec>>(AnswerSpecsSaved.new);

String _savedKey(Conversation c, String markdown) =>
    '${c.id}:${markdown.hashCode}';

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void openSpecInSpecs(WidgetRef ref, Spec spec) {
  ref.read(selectedSpecProvider.notifier).select(spec.id);
  ref.read(navigationProvider.notifier).go(AppSection.specs);
}

/// Saves [markdown] (as a new spec when [asNew] or when the answer's `id` has
/// no spec that accepts a new version; otherwise applies it).
Future<Spec?> saveAnswerSpec(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
  AnswerSpec spec, {
  String? markdown,
  bool asNew = false,
  bool openInSpecs = false,
}) async {
  final text = markdown ?? spec.markdown;
  try {
    final t = await ref.read(answerSpecTargetProvider((c, spec.id)).future);
    final service = ref.read(specServiceProvider);
    final target = t.target;
    final apply =
        !asNew && target != null && applyBlockedReason(target) == null;
    final saved = apply
        ? await applyAnswerSpec(
            service,
            t.ws,
            target,
            text,
            expectedText: t.current,
          )
        : await saveAnswerSpecAsNew(service, t.ws, text);
    ref
        .read(answerSpecsSavedProvider.notifier)
        .set(_savedKey(c, spec.markdown), saved);
    ref.invalidate(answerSpecTargetProvider((c, spec.id)));
    if (context.mounted) {
      _snack(
        context,
        apply
            ? '${saved.code} atualizada em ${saved.path}'
            : '${saved.code} criada em ${saved.path} (rascunho)',
      );
    }
    if (openInSpecs) openSpecInSpecs(ref, saved);
    return saved;
  } catch (e) {
    if (context.mounted) _snack(context, 'Falha ao salvar a spec: $e');
    return null;
  }
}

/// Main action of the bar and of "Transformar em spec" (R5): a stale file
/// opens the preview first; otherwise saves or applies directly.
Future<void> primaryAnswerSpec(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
  AnswerSpec spec,
) async {
  final t = await ref.read(answerSpecTargetProvider((c, spec.id)).future);
  final target = t.target;
  final apply = target != null && applyBlockedReason(target) == null;
  if (!context.mounted) return;
  if (apply && t.stale) {
    await showAnswerSpecPreview(context, ref, c, spec);
    return;
  }
  await saveAnswerSpec(context, ref, c, spec);
}

/// "Spec detectada" under an answer (SPEC-016 R1–R3).
class AnswerSpecBar extends ConsumerWidget {
  const AnswerSpecBar({
    super.key,
    required this.conversation,
    required this.spec,
  });

  final Conversation conversation;
  final AnswerSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final saved = ref.watch(
      answerSpecsSavedProvider.select((m) => m[_savedKey(c, spec.markdown)]),
    );
    final info = ref.watch(answerSpecTargetProvider((c, spec.id))).value;
    final target = info?.target;
    final blocked = target == null ? null : applyBlockedReason(target);
    final apply = target != null && blocked == null;
    final accent = saved != null || apply ? AppColors.teal : AppColors.amber;
    final border = saved != null || apply
        ? SessionColors.runningToolBorder
        : SessionColors.approvalBorder;
    final bg = saved != null || apply
        ? SessionColors.runningToolBg
        : SessionColors.approvalBg;

    final counts =
        '${spec.requirements} ${spec.requirements == 1 ? 'requisito' : 'requisitos'}'
        ' · ${spec.criteria.length} '
        '${spec.criteria.length == 1 ? 'critério' : 'critérios'} de aceite';
    final String title;
    final String subtitle;
    if (saved != null) {
      title = '${saved.code} salva';
      subtitle = '${saved.path} · ${specStatusLabel(saved.status)}';
    } else if (apply) {
      final diff = info!.current == null
          ? null
          : lineDiff(
              info.current!,
              appliedSpecText(spec.markdown, target, info.current),
            );
      final add = diff?.where((l) => l.op == DiffOp.add).length ?? 0;
      final del = diff?.where((l) => l.op == DiffOp.del).length ?? 0;
      title = 'Nova versão da ${target.code}';
      subtitle =
          'Mesmo id do frontmatter · +$add −$del linhas · status mantido';
    } else {
      title = 'Spec detectada nesta resposta';
      subtitle = [
        'nova · ${info?.nextCode ?? '…'}',
        counts,
        ?blocked,
      ].join(' · ');
    }

    final buttons = <Widget>[
      if (saved != null)
        SmallButton(
          key: const ValueKey('answer-spec-open'),
          label: 'Abrir em Specs',
          height: 30,
          color: AppColors.teal,
          border: border,
          background: Colors.transparent,
          onTap: () => openSpecInSpecs(ref, saved),
        )
      else ...[
        SmallButton(
          key: const ValueKey('answer-spec-save'),
          label: info == null
              ? 'Salvar spec'
              : apply
              ? 'Aplicar na ${target.code}'
              : 'Salvar como ${info.nextCode}',
          height: 30,
          color: AppColors.onAmber,
          border: accent,
          background: accent,
          onTap: info == null
              ? null
              : () => primaryAnswerSpec(context, ref, c, spec),
        ),
        if (apply)
          SmallButton(
            key: const ValueKey('answer-spec-save-new'),
            label: 'Salvar como nova',
            height: 30,
            border: border,
            background: Colors.transparent,
            onTap: () => saveAnswerSpec(context, ref, c, spec, asNew: true),
          ),
        SmallButton(
          key: const ValueKey('answer-spec-preview'),
          label: 'Prévia',
          height: 30,
          border: border,
          background: Colors.transparent,
          onTap: info == null
              ? null
              : () => showAnswerSpecPreview(context, ref, c, spec),
        ),
      ],
      Tooltip(
        message: 'Copiar markdown',
        child: SmallButton(
          key: const ValueKey('answer-spec-copy'),
          label: 'Copiar',
          height: 30,
          color: AppColors.textSecondary,
          border: border,
          background: Colors.transparent,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: spec.markdown));
            if (context.mounted) _snack(context, 'Spec copiada');
          },
        ),
      ),
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          key: const ValueKey('answer-spec-bar'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(AppIcons.specs, size: 16, color: accent),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                key: const ValueKey('answer-spec-title'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                              Text(
                                subtitle,
                                key: const ValueKey('answer-spec-subtitle'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ...buttons,
                  ],
                ),
              ),
              if (saved == null && apply && info!.stale)
                Container(
                  key: const ValueKey('answer-spec-stale'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: SessionColors.approvalBg,
                  child: const Text(
                    'O arquivo mudou depois que a conversa começou. Aplicar '
                    'substitui também essa alteração; confira o diff na prévia.',
                    style: TextStyle(fontSize: 11, color: AppColors.amber),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Prévia" (R4): editable title and Markdown, checks, diff when applying.
Future<void> showAnswerSpecPreview(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
  AnswerSpec spec,
) async {
  final t = await ref.read(answerSpecTargetProvider((c, spec.id)).future);
  if (!context.mounted) return;
  final r = await showDialog<_PreviewResult>(
    context: context,
    builder: (_) => _AnswerSpecPreview(spec: spec, info: t),
  );
  if (r == null || !context.mounted) return;
  await saveAnswerSpec(
    context,
    ref,
    c,
    spec,
    markdown: r.markdown,
    asNew: r.asNew,
    openInSpecs: r.openInSpecs,
  );
}

typedef _PreviewResult = ({String markdown, bool asNew, bool openInSpecs});

enum _Tab { rendered, markdown, diff }

class _AnswerSpecPreview extends StatefulWidget {
  const _AnswerSpecPreview({required this.spec, required this.info});

  final AnswerSpec spec;
  final AnswerSpecTarget info;

  @override
  State<_AnswerSpecPreview> createState() => _AnswerSpecPreviewState();
}

class _AnswerSpecPreviewState extends State<_AnswerSpecPreview> {
  late final _title = TextEditingController(text: widget.spec.title ?? '');
  late final _markdown = TextEditingController(text: widget.spec.markdown);
  late _Tab _tab = _apply ? _Tab.diff : _Tab.rendered;
  bool _open = true;

  bool get _apply {
    final t = widget.info.target;
    return t != null && applyBlockedReason(t) == null;
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() {
      final next = withSpecTitle(_markdown.text, _title.text);
      if (next != _markdown.text) _markdown.text = next;
      setState(() {});
    });
    _markdown.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _markdown.dispose();
    super.dispose();
  }

  String get _finalText => _apply
      ? appliedSpecText(
          _markdown.text,
          widget.info.target!,
          widget.info.current,
        )
      : newSpecTextFromAnswer(_markdown.text, widget.info.nextCode);

  String get _path {
    if (_apply) return widget.info.target!.path;
    final dir = ProjectConfig.loadSync(widget.info.ws.path).specsDir;
    final slug = slugify(_title.text.trim(), maxLength: 40);
    return '$dir/${widget.info.nextCode}${slug.isEmpty ? '' : '-$slug'}.md';
  }

  Widget _box(Color color, Color bg, Color border, String head, String body) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              head,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );

  Widget _tabButton(_Tab tab, String label) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: SmallButton(
      key: ValueKey('answer-spec-tab-${tab.name}'),
      label: label,
      height: 26,
      fontSize: 11,
      color: _tab == tab ? AppColors.text : AppColors.textSecondary,
      border: _tab == tab ? SessionColors.selectedBorder : Colors.transparent,
      background: _tab == tab ? SessionColors.selectedBg : Colors.transparent,
      onTap: () => setState(() => _tab = tab),
    ),
  );

  Widget _content() {
    switch (_tab) {
      case _Tab.rendered:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: MarkdownBody(
            data: SpecDocument.parse(_markdown.text).body,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
          ),
        );
      case _Tab.markdown:
        return TextField(
          key: const ValueKey('answer-spec-markdown'),
          controller: _markdown,
          maxLines: null,
          expands: true,
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(14),
          ),
        );
      case _Tab.diff:
        final lines = lineDiff(widget.info.current ?? '', _finalText);
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final l in lines)
              Container(
                color: switch (l.op) {
                  DiffOp.add => SessionColors.addBg,
                  DiffOp.del => SessionColors.delBg,
                  DiffOp.same => Colors.transparent,
                },
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${switch (l.op) {
                    DiffOp.add => '+',
                    DiffOp.del => '-',
                    DiffOp.same => ' ',
                  }} ${l.text}',
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: switch (l.op) {
                      DiffOp.add => AppColors.teal,
                      DiffOp.del => AppColors.red,
                      DiffOp.same => AppColors.textSecondary,
                    },
                  ),
                ),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = SpecDocument.parse(_markdown.text);
    final reqs = doc.requirements;
    final criteria = parseCriteria(_markdown.text);
    final linked = criteria.where((c) => c.requirements.isNotEmpty).length;
    final target = widget.info.target;
    final code = _apply ? target!.code : widget.info.nextCode;
    final checks = [
      doc.hasFrontmatter
          ? 'Frontmatter${doc.id == null ? '' : ' com id'}'
                '${doc.rawStatus == null ? '' : ' e status'}'
          : 'Sem frontmatter: será criado',
      reqs.isEmpty
          ? 'Nenhum requisito R1, R2…'
          : '${reqs.length} ${reqs.length == 1 ? 'requisito' : 'requisitos'}'
                ' (${reqs.first.id}–${reqs.last.id})',
      '${criteria.length} ${criteria.length == 1 ? 'critério' : 'critérios'}'
          ', $linked ligados a requisitos',
    ].join(' · ');
    final adjust = [
      if (widget.spec.leftover)
        'O texto do agente antes e depois da spec fica de fora.',
      _apply
          ? 'id e status atuais da ${target!.code} são mantidos.'
          : 'id vira $code e o status, rascunho.',
    ].join(' ');
    final blocked = target == null ? null : applyBlockedReason(target);

    return Dialog(
      backgroundColor: AppColors.panel,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _apply
                          ? 'Aplicar na ${target!.code}'
                          : 'Salvar spec da resposta',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const ValueKey('answer-spec-title-field'),
                          controller: _title,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Título',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Arquivo',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          _path,
                          key: const ValueKey('answer-spec-path'),
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: AppColors.lilac,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _box(
                          AppColors.teal,
                          SessionColors.runningToolBg,
                          SessionColors.runningToolBorder,
                          'Conferido',
                          checks,
                        ),
                        const SizedBox(height: 8),
                        _box(
                          AppColors.amber,
                          SessionColors.approvalBg,
                          SessionColors.approvalBorder,
                          'Ajustado ao salvar',
                          adjust,
                        ),
                        if (blocked != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '$blocked Será salva como nova spec.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.amber,
                            ),
                          ),
                        ],
                        if (_apply && widget.info.stale) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'O arquivo mudou depois que a conversa começou. '
                            'Aplicar substitui também essa alteração.',
                            key: ValueKey('answer-spec-preview-stale'),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.amber,
                            ),
                          ),
                        ],
                        CheckboxListTile(
                          key: const ValueKey('answer-spec-open-after'),
                          value: _open,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'Abrir na tela Specs depois de salvar',
                            style: TextStyle(fontSize: 12),
                          ),
                          onChanged: (v) => setState(() => _open = v ?? false),
                        ),
                      ],
                    ),
                  );
                  final preview = Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          color: AppColors.surfaceRaised,
                          child: Wrap(
                            children: [
                              if (_apply) _tabButton(_Tab.diff, 'Diff'),
                              _tabButton(_Tab.rendered, 'Renderizado'),
                              _tabButton(_Tab.markdown, 'Markdown'),
                            ],
                          ),
                        ),
                        Expanded(child: _content()),
                      ],
                    ),
                  );
                  if (box.maxWidth < 640) {
                    return Column(
                      children: [
                        SizedBox(height: box.maxHeight * 0.45, child: side),
                        Expanded(child: preview),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 300, child: side),
                      Expanded(child: preview),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  SmallButton(
                    label: 'Cancelar',
                    onTap: () => Navigator.pop(context),
                  ),
                  if (_apply)
                    SmallButton(
                      key: const ValueKey('answer-spec-preview-new'),
                      label: 'Salvar como ${widget.info.nextCode}',
                      onTap: () => Navigator.pop(context, (
                        markdown: _markdown.text,
                        asNew: true,
                        openInSpecs: _open,
                      )),
                    ),
                  SmallButton(
                    key: const ValueKey('answer-spec-preview-save'),
                    label: _apply ? 'Aplicar na $code' : 'Salvar $code',
                    color: AppColors.onAmber,
                    border: AppColors.amber,
                    background: AppColors.amber,
                    onTap: () => Navigator.pop(context, (
                      markdown: _markdown.text,
                      asNew: !_apply,
                      openInSpecs: _open,
                    )),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
