import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../prompt/conversation_manager.dart';
import '../../sessions/widgets/session_style.dart';
import '../../board/spec_runner.dart' show gateRunningProvider;
import '../../project/project_config.dart';
import '../../specs/spec_service.dart' show nextSpecCode;
import '../vibe_flow.dart';
import '../vibe_guard.dart';
import '../vibe_service.dart';

/// Purple of the VIBE (SPEC-069 R9): the badge, the card's edge.
const vibeColor = AppColors.lilac;

/// App setting: "Entendi; não mostrar este aviso de novo" (R2).
const vibeWarningSeenKey = 'vibe.aviso.entendido';

/// "VIBE" as text, never only colour (R13).
class VibeBadge extends StatelessWidget {
  const VibeBadge({super.key, this.fontSize = 11});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'VIBE',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: vibeColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'VIBE',
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1C1326),
          ),
        ),
      ),
    );
  }
}

/// "Fazer como tarefa" (R1, R2): asks the agent directly, with no spec.
/// [initial] fills "O que fazer" (the text being written in the Prompt).
Future<int?> showVibeStartDialog(
  BuildContext context, {
  required Workspace workspace,
  String initial = '',
}) => showAppDialog<int>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => VibeStartDialog(workspace: workspace, initial: initial),
);

class VibeStartDialog extends ConsumerStatefulWidget {
  const VibeStartDialog({
    super.key,
    required this.workspace,
    this.initial = '',
  });

  final Workspace workspace;
  final String initial;

  @override
  ConsumerState<VibeStartDialog> createState() => _VibeStartDialogState();
}

class _VibeStartDialogState extends ConsumerState<VibeStartDialog> {
  late final _text = TextEditingController(text: widget.initial);
  VibePreview? _preview;
  bool _seen = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final text = _text.text.trim();
      final p = await ref
          .read(vibeServiceProvider)
          .preview(widget.workspace, text.isEmpty ? 'tarefa' : text);
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      debugPrint('vibe: prévia — $e');
    }
  }

  Future<void> _start() async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Diga o que fazer.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_seen) {
        await ref
            .read(appSettingsProvider.notifier)
            .set(vibeWarningSeenKey, '1');
      }
      final d = ref.read(promptDraftProvider);
      final r = await ref
          .read(vibeServiceProvider)
          .start(
            widget.workspace,
            _text.text,
            model: d.model,
            providerId: d.providerId,
          );
      ref.read(selectedConversationProvider.notifier).select(r.conversationId);
      ref.read(navigationProvider.notifier).go(AppSection.prompt);
      if (mounted) Navigator.of(context).pop(r.conversationId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final warned =
        ref.watch(appSettingsProvider.select((m) => m[vibeWarningSeenKey])) ==
        '1';
    final p = _preview;
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    );
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        key: const ValueKey('vibe-start-dialog'),
        color: AppColors.panelSolid,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.bolt, size: 20, color: vibeColor),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Fazer como tarefa',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                SizedBox(width: 8),
                                VibeBadge(),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Pede direto ao agente, sem escrever uma spec. '
                              'Roda num worktree próprio e termina num PR.',
                              style: label,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'O que fazer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        key: const ValueKey('vibe-start-text'),
                        controller: _text,
                        autofocus: true,
                        minLines: 3,
                        maxLines: 6,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Ex.: deixa o botão Comprar verde',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Text.rich(
                            TextSpan(
                              text: 'Número ',
                              style: label,
                              children: [
                                TextSpan(text: p?.code ?? '…', style: mono),
                              ],
                            ),
                            key: const ValueKey('vibe-start-code'),
                          ),
                          Text.rich(
                            TextSpan(
                              text: 'Branch ',
                              style: label,
                              children: [
                                TextSpan(text: p?.branch ?? '…', style: mono),
                              ],
                            ),
                            key: const ValueKey('vibe-start-branch'),
                          ),
                          Text.rich(
                            TextSpan(
                              text: 'A partir de ',
                              style: label,
                              children: [
                                TextSpan(text: p?.base ?? '…', style: mono),
                              ],
                            ),
                            key: const ValueKey('vibe-start-base'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (!warned) ...[
                        const VibeWarning(),
                        const SizedBox(height: 10),
                        InkWell(
                          key: const ValueKey('vibe-start-seen'),
                          onTap: () => setState(() => _seen = !_seen),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _seen,
                                onChanged: (v) =>
                                    setState(() => _seen = v ?? false),
                              ),
                              const Text(
                                'Entendi; não mostrar este aviso de novo',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ] else
                        const Row(
                          key: ValueKey('vibe-start-short-warning'),
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: AppColors.amber,
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Use com cuidado: pula requisitos, canvas e '
                                'critérios; gate, Review, teto e prints '
                                'continuam obrigatórios.',
                                style: label,
                              ),
                            ),
                          ],
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Entra no Quadro em Em execução.',
                          style: label,
                        ),
                      ),
                      SmallButton(
                        label: 'Cancelar',
                        height: 34,
                        onTap: _busy ? null : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      AmberButton(
                        key: const ValueKey('vibe-start-submit'),
                        label: _busy ? 'Começando…' : 'Começar VIBE',
                        height: 34,
                        busy: _busy,
                        onTap: _start,
                      ),
                    ],
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

/// "Use com cuidado" (R2): what the VIBE skips and what stays mandatory.
class VibeWarning extends StatelessWidget {
  const VibeWarning({super.key});

  static const skips = [
    'Requisitos revisados antes',
    'Canvas validado antes de mexer em tela',
    'Critérios de aceite escritos por você',
  ];
  static const keeps = [
    'Gate (testes e lint)',
    'Review antes do merge',
    'Teto: 15 arquivos ou 400 linhas',
    'Prints de antes e depois se mexer em tela',
  ];

  @override
  Widget build(BuildContext context) {
    Widget column(String title, List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('•  $i', style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
    return Container(
      key: const ValueKey('vibe-warning'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        border: Border.all(color: SessionColors.approvalBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: AppColors.amber,
              ),
              SizedBox(width: 8),
              Text(
                'Use com cuidado',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: column('O QUE A VIBE PULA', skips)),
              const SizedBox(width: 16),
              Expanded(child: column('O QUE CONTINUA OBRIGATÓRIO', keeps)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The bar of a VIBE's conversation (R6, R7, R10): code, title, branch,
/// what the VIBE has changed and "Enviar para Review". [meter] and
/// [discard] come with the protections and the Quadro.
class VibeBar extends ConsumerWidget {
  const VibeBar({
    super.key,
    required this.spec,
    required this.busy,
    this.meter,
    this.discard,
  });

  final Spec spec;

  /// The agent is answering.
  final bool busy;
  final Widget? meter;
  final Widget? discard;

  Future<void> _review(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final view = View.of(context);
    void toast(String m) => messenger
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(m)));
    try {
      final r = await ref.read(vibeServiceProvider).sendToReview(spec.id);
      final msg = r.ok
          ? '${spec.code} foi para o Review.'
          : 'O gate de ${spec.code} falhou: veja o relatório na conversa.';
      toast(msg);
      SemanticsService.sendAnnouncement(view, msg, TextDirection.ltr);
    } catch (e) {
      toast('$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(
      gateRunningProvider.select((g) => g.contains(spec.id)),
    );
    final inReview = spec.stage == SpecStage.review;
    final done = spec.stage == SpecStage.done;
    return Container(
      key: ValueKey('vibe-bar-${spec.code}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (spec.kind == SpecKind.vibe) ...[
            const VibeBadge(),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              '${spec.code} · ${spec.title}',
              key: const ValueKey('vibe-bar-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          if (spec.branch case final b?) ...[
            const SizedBox(width: 12),
            const Icon(Icons.call_split, size: 14, color: AppColors.teal),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                b,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.teal,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (meter != null) ...[meter!, const SizedBox(width: 12)],
          if (discard != null) ...[discard!, const SizedBox(width: 8)],
          AmberButton(
            key: const ValueKey('vibe-send-review'),
            label: gate
                ? 'Verificando…'
                : done
                ? 'Mergeada'
                : inReview
                ? 'No Review'
                : 'Enviar para Review',
            height: 34,
            busy: gate,
            onTap: busy || gate || inReview || done
                ? null
                : () => _review(context, ref),
          ),
        ],
      ),
    );
  }
}

/// The size of the VIBE, always in view (R6, R13): a meter with the whole
/// text, red past the cap. [tick] changes when the agent answers.
class VibeMeter extends ConsumerWidget {
  const VibeMeter({
    super.key,
    required this.spec,
    required this.workspacePath,
    required this.tick,
    this.conversationId,
  });

  final Spec spec;
  final String workspacePath;
  final int tick;
  final int? conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(vibeSizeProvider((spec.id, tick))).value;
    final cap =
        ref.watch(projectConfigProvider(workspacePath)).value?.vibe ??
        const VibeConfig();
    if (size == null) return const SizedBox.shrink();
    final threshold = ref.read(vibeFlowProvider.notifier).threshold(spec.id);
    final over = size.over(cap);
    if (conversationId case final id?
        when spec.kind == SpecKind.vibe &&
            size.over(cap, threshold: threshold)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(vibeFlowProvider.notifier).capReached(id, size);
        }
      });
    }
    final color = over ? AppColors.red : AppColors.textSecondary;
    final text = size.label(cap);
    return Semantics(
      key: ValueKey('vibe-meter-${spec.code}'),
      label: 'Tamanho da VIBE',
      value: over ? '$text, passou do teto' : text,
      excludeSemantics: true,
      child: SizedBox(
        width: 150,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${size.files}/${cap.maxFiles} arquivos',
                  style: TextStyle(fontSize: 11, color: color),
                ),
                const Spacer(),
                Text(
                  '${size.lines}/${cap.maxLines} linhas',
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: size.ratio(cap).clamp(0, 1).toDouble(),
                minHeight: 4,
                color: over ? AppColors.red : AppColors.teal,
                backgroundColor: AppColors.border,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The question held before a request runs (R5, R8), as an alert in the
/// conversation with the focus on its main button (R13).
class VibeQuestion extends ConsumerStatefulWidget {
  const VibeQuestion({
    super.key,
    required this.conversationId,
    required this.spec,
    required this.pending,
    required this.workspace,
  });

  final int conversationId;
  final Spec spec;
  final VibePending pending;
  final Workspace workspace;

  @override
  ConsumerState<VibeQuestion> createState() => _VibeQuestionState();
}

class _VibeQuestionState extends ConsumerState<VibeQuestion> {
  final _primary = FocusNode();
  bool _busy = false;
  String? _nextSpec;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _primary.requestFocus();
    });
    if (widget.pending.ask == VibeAsk.cap) {
      nextSpecCode(ref.read(specsRepoProvider), widget.workspace).then((c) {
        if (mounted) setState(() => _nextSpec = c);
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _primary.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showAppToast(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(vibeFlowProvider.notifier);
    final p = widget.pending;
    final c = widget.conversationId;
    final spec = widget.spec;
    if (p.ask == VibeAsk.unrelated) {
      return _card(
        key: const ValueKey('vibe-unrelated'),
        border: vibeColor.withValues(alpha: .6),
        icon: const Icon(Icons.add, size: 16, color: vibeColor),
        title: 'Isso parece outro assunto',
        body:
            '“${p.text}” não tem a ver com ${spec.title}'
            '${p.reason.isEmpty ? '' : ' (${p.reason})'}. Numa VIBE própria, '
            'vira um PR separado e pode ser mergeado sozinho.',
        actions: [
          AmberButton(
            key: const ValueKey('vibe-unrelated-new'),
            label: 'Abrir VIBE nova',
            height: 34,
            focusNode: _primary,
            busy: _busy,
            onTap: () => _run(() async {
              final id = await flow.openNew(c, widget.workspace);
              if (id != null) {
                ref.read(selectedConversationProvider.notifier).select(id);
              }
            }),
          ),
          SmallButton(
            key: const ValueKey('vibe-unrelated-continue'),
            label: 'Continuar nesta',
            height: 34,
            onTap: _busy
                ? null
                : () => _run(() => flow.continueHere(c, spec.id)),
          ),
        ],
      );
    }
    final size = p.size;
    final next = _nextSpec ?? 'SPEC-…';
    Widget option(String title, String text, {required bool main}) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: main ? SessionColors.approvalBg : AppColors.panelSolid,
          border: Border.all(
            color: main ? SessionColors.approvalBorder : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
    return _card(
      key: const ValueKey('vibe-cap'),
      border: SessionColors.stopBorder,
      icon: const Icon(
        Icons.warning_amber_rounded,
        size: 16,
        color: AppColors.red,
      ),
      title:
          'Esta VIBE passou do teto'
          '${size == null ? '' : ': ${size.files} arquivos · ${size.lines} linhas'}',
      body:
          'O agente parou antes de continuar. Uma tarefa deste tamanho '
          'costuma pedir requisitos e critérios.',
      extra: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(
              'Virar spec',
              'O app escreve a $next a partir da conversa. Ela assume o '
                  'código já feito e o trabalho continua na hora; fica '
                  'marcada origem: ${spec.code}.',
              main: true,
            ),
            const SizedBox(width: 10),
            option(
              'Continuar como VIBE',
              'Segue sem spec. O teto volta a perguntar a cada 50% a mais.',
              main: false,
            ),
          ],
        ),
      ),
      actions: [
        SmallButton(
          key: const ValueKey('vibe-cap-continue'),
          label: 'Continuar como VIBE',
          height: 34,
          onTap: _busy
              ? null
              : () => _run(() => flow.continueAsVibe(c, spec.id)),
        ),
        AmberButton(
          key: const ValueKey('vibe-cap-promote'),
          label: 'Virar spec',
          height: 34,
          focusNode: _primary,
          busy: _busy,
          onTap: () => _run(() => flow.promote(c, spec.id)),
        ),
      ],
      actionsAtEnd: true,
    );
  }

  Widget _card({
    required Key key,
    required Color border,
    required Widget icon,
    required String title,
    required String body,
    required List<Widget> actions,
    Widget? extra,
    bool actionsAtEnd = false,
  }) {
    return Semantics(
      key: key,
      container: true,
      liveRegion: true,
      label: title,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaisedSolid,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (extra != null) ...[const SizedBox(height: 10), extra],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: actionsAtEnd
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  a,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
