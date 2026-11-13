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
