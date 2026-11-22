import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/claude/run_prefs.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../compaction_controller.dart';
import '../context_snapshot.dart';

const _label = TextStyle(fontSize: 11.5, color: AppColors.textSecondary);
const _title = TextStyle(
  fontSize: 12.5,
  fontWeight: FontWeight.w600,
  color: AppColors.text,
);

/// `200k` → `200 mil tokens`; `auto` → `padrão do agente`.
String autocompactChoiceLabel(String v) =>
    v == 'auto' ? 'padrão do agente' : '${autocompactLabel(v)} tokens';

/// "Auto compactar em [valor]" (SPEC-087 R7): edits the global preference
/// (`RunPrefs.autocompact`, the same `--autocompact` of Configurações) and
/// says it only reaches the next executions; the current one keeps the
/// value it was started with.
class AutocompactControl extends ConsumerWidget {
  const AutocompactControl({super.key, required this.snapshot});

  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final global = ref.watch(runPrefsProvider).autocompact;
    final effective = snapshot.configuredAutocompact;
    final settings = ref.read(appSettingsProvider.notifier);
    final threshold = snapshot.threshold;
    final String note;
    if (effective == null) {
      note =
          'Vale para as próximas execuções. Esta execução não informou o '
          'valor que recebeu.';
    } else if (effective != global) {
      note =
          '${autocompactLabel(global)} vale para as próximas execuções. Esta '
          'execução segue em ${autocompactLabel(effective)} '
          '(--autocompact $effective).';
    } else {
      note =
          'Esta execução usa este valor (--autocompact $effective). '
          'Mudanças valem para as próximas.';
    }
    return Container(
      key: const ValueKey('context-autocompact'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const Text('Auto compactar', style: _title),
                    const Text('em', style: _label),
                    PopupMenuButton<String>(
                      key: const ValueKey('context-autocompact-menu'),
                      tooltip: 'Mudar a compactação automática',
                      initialValue: global,
                      onSelected: (v) =>
                          settings.set(AppSettingKeys.autocompact, v),
                      itemBuilder: (_) => [
                        for (final c in autocompactChoices)
                          PopupMenuItem(
                            key: ValueKey('context-autocompact-$c'),
                            value: c,
                            child: Text(autocompactChoiceLabel(c)),
                          ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderHover),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              autocompactChoiceLabel(global),
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 12,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.expand_more,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Voltar ao padrão do app',
                child: InkWell(
                  key: const ValueKey('context-autocompact-default'),
                  onTap: global == RunPrefs.defaultAutocompact
                      ? null
                      : () => settings.remove(AppSettingKeys.autocompact),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Padrão: ${autocompactLabel(RunPrefs.defaultAutocompact)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: TextStyle(
              fontSize: 11.5,
              color: effective != null && effective != global
                  ? AppColors.amber
                  : AppColors.textSecondary,
            ),
          ),
          if (threshold != null) ...[
            const SizedBox(height: 4),
            Text(
              'O agente informa que compacta em ${contextTokens(threshold)}'
              '${snapshot.autocompactWindow == null ? '' : ' (janela de ${contextTokens(snapshot.autocompactWindow!)} menos a reserva do resumo)'}'
              ', diferente da capacidade da janela.',
              style: _label,
            ),
          ],
        ],
      ),
    );
  }
}

/// The compaction state as the agent reported it (R8), for the meter and
/// the panel. Null when there is nothing to say (configured, no event).
Widget? compactionStatusRow(ContextSnapshot s, {bool alive = true}) {
  final since = s.phaseSince;
  final last = s.last;
  switch (s.phase) {
    case CompactionPhase.compacting:
      return _StatusRow(
        key: const ValueKey('compaction-compacting'),
        icon: const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.teal,
          ),
        ),
        title: 'Compactando…',
        text: since == null
            ? 'evento do agente'
            : 'iniciada às ${contextTime(since)} · evento do agente',
        color: AppColors.borderHover,
      );
    case CompactionPhase.failed:
      return _StatusRow(
        key: const ValueKey('compaction-failed'),
        icon: const Icon(Icons.close, size: 13, color: AppColors.red),
        title: 'Compactação falhou',
        text:
            'a conversa segue utilizável e o histórico fica'
            '${s.compactError == null ? '' : ' · ${s.compactError}'}',
        color: AppColors.red.withValues(alpha: .5),
      );
    case CompactionPhase.done when s.pendingAfterCompaction:
      return _StatusRow(
        key: const ValueKey('compaction-pending'),
        icon: const Icon(Icons.check, size: 13, color: AppColors.teal),
        title: 'Compactação concluída',
        text: [
          if (since != null) contextTime(since),
          if (last != null)
            'última leitura antes: ${contextTokens(last.tokens)} '
                '(turno ${last.turn}) · aguardando medição',
        ].join(' · '),
        color: AppColors.teal.withValues(alpha: .5),
      );
    default:
      return null;
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final Widget icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '$title. $text',
    excludeSemantics: true,
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Text(title, style: _title),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _label,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Text of the 85% warning (R10): which limit, how much is left, and that
/// sending is not blocked.
String contextWarningText(ContextSnapshot s) {
  final w = s.warning!;
  final tokens = contextTokens(w.tokens);
  final ref = contextTokens(w.reference);
  final left = contextTokens(w.remaining);
  if (w.kind == ContextReference.threshold) {
    final cap = s.capacity == null
        ? ''
        : ', não da janela (${contextTokens(s.capacity!)})';
    final rest = w.remaining == 0
        ? 'Passou do limiar: o agente compacta antes do próximo envio.'
        : 'Faltam $left tokens.';
    return '$tokens = ${w.percent}% do limiar de compactação ($ref)$cap. '
        '$rest O envio segue liberado.';
  }
  return '$tokens = ${w.percent}% da capacidade da janela ($ref); o limiar '
      'de compactação não foi informado. Faltam $left tokens. O envio segue '
      'liberado.';
}

/// The local warning above the meter (R10): reason + a way to act. Never
/// blocks sending nor compacts by itself.
class ContextWarningBanner extends StatelessWidget {
  const ContextWarningBanner({
    super.key,
    required this.snapshot,
    required this.onOpenPanel,
    required this.onDismiss,
    this.attachments = 0,
    this.onReviewAttachments,
  });

  final ContextSnapshot snapshot;
  final VoidCallback onOpenPanel;
  final VoidCallback onDismiss;
  final int attachments;
  final VoidCallback? onReviewAttachments;

  @override
  Widget build(BuildContext context) {
    final w = snapshot.warning!;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('context-warning'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: SessionColors.approvalBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SessionColors.approvalBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.kind == ContextReference.threshold
                            ? 'Contexto perto da compactação automática'
                            : 'Contexto perto do limite da janela',
                        style: _title,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contextWarningText(snapshot),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Button(
                  key: const ValueKey('context-warning-open'),
                  label: 'Abrir painel Contexto',
                  primary: true,
                  onTap: onOpenPanel,
                ),
                if (attachments > 0 && onReviewAttachments != null)
                  _Button(
                    key: const ValueKey('context-warning-attachments'),
                    label: 'Revisar próximos anexos ($attachments)',
                    onTap: onReviewAttachments!,
                  ),
                _Button(
                  key: const ValueKey('context-warning-dismiss'),
                  label: 'Dispensar',
                  onTap: onDismiss,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Material(
    color: primary && enabled ? AppColors.amber : Colors.transparent,
    borderRadius: BorderRadius.circular(6),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: primary && enabled
                ? AppColors.amber
                : enabled
                ? AppColors.borderHover
                : AppColors.border,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary && enabled
                  ? AppColors.onAmber
                  : enabled
                  ? AppColors.text
                  : AppColors.textDisabled,
            ),
          ),
        ),
      ),
    ),
  );
}

/// How a new conversation starts (R9).
/// How a new conversation starts (R9; the ai-memory handoff, SPEC-099 R12).
enum NewConversationStart { empty, summary, handoff }

/// The actions of the panel (R9): adjust the auto compaction, review the
/// next attachments, a new conversation (Prompt) and "Compactar agora".
class ContextActions extends StatefulWidget {
  const ContextActions({
    super.key,
    required this.snapshot,
    required this.availability,
    required this.onCompact,
    required this.onAdjust,
    this.attachments = 0,
    this.onReviewAttachments,
    this.onNewConversation,
    this.summary,
    this.providers = const [],
    this.provider,
    this.onProvider,
    this.handoff,
  });

  final ContextSnapshot snapshot;
  final CompactAvailability availability;

  /// Sends the native command with an optional focus.
  final Future<void> Function(String? focus) onCompact;
  final VoidCallback onAdjust;
  final int attachments;
  final VoidCallback? onReviewAttachments;

  /// Prompt only: starts a draft, empty or with the reviewed [summary].
  final void Function(String? summary)? onNewConversation;

  /// The summary built by the app (no model call) for a new conversation.
  final String Function()? summary;

  /// SPEC-099 R12: the providers the new conversation can run in (more
  /// than one only where the Codex runs in the Prompt), the current one and
  /// the choice.
  final List<String> providers;
  final String? provider;
  final ValueChanged<String>? onProvider;

  /// SPEC-099 R12: the message that delivers the next ai-memory handoff
  /// (null result = none); null = ai-memory off.
  final Future<String?> Function()? handoff;

  @override
  State<ContextActions> createState() => _ContextActionsState();
}

class _ContextActionsState extends State<ContextActions> {
  NewConversationStart _start = NewConversationStart.summary;
  bool _sending = false;
  String? _error;
  final _focus = TextEditingController();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _compact() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onCompact(_focus.text);
      _focus.clear();
    } catch (e) {
      // R9: a failure keeps the conversation and its history.
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  late String? _provider = widget.provider;

  Future<void> _newConversation() async {
    final go = widget.onNewConversation!;
    if (_provider != null && _provider != widget.provider) {
      widget.onProvider?.call(_provider!);
    }
    if (_start == NewConversationStart.empty ||
        (_start == NewConversationStart.summary && widget.summary == null)) {
      go(null);
      return;
    }
    String? initial;
    if (_start == NewConversationStart.handoff) {
      initial = await widget.handoff?.call();
      if (initial == null) {
        if (mounted) setState(() => _error = 'Nenhuma passagem aberta.');
        return;
      }
    }
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) =>
          _SummaryDialog(initial: initial ?? widget.summary!()),
    );
    if (text != null) go(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final effective = s.configuredAutocompact;
    final a = widget.availability;
    final c = s.current;
    return Column(
      key: const ValueKey('context-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Contexto atual', style: _label),
                    Text(
                      c == null
                          ? 'Aguardando medição'
                          : '${contextTokens(c.tokens)} medidos',
                      style: _title,
                    ),
                    if (c == null && s.last != null)
                      Text(
                        'Última leitura: ${contextTokens(s.last!.tokens)} no '
                        'turno ${s.last!.turn}'
                        '${s.pendingAfterCompaction ? ', antes de compactar' : ''}',
                        style: _label,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Auto compactar', style: _label),
                  Text(
                    effective == null
                        ? 'não informado'
                        : effective == 'auto'
                        ? 'padrão do agente'
                        : 'em ${autocompactLabel(effective)} tokens',
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const Text('valor desta execução', style: _label),
                ],
              ),
            ],
          ),
        ),
        if (compactionStatusRow(s) case final row?) ...[
          const SizedBox(height: 8),
          row,
        ],
        const SizedBox(height: 8),
        _ActionRow(
          key: const ValueKey('context-action-adjust'),
          icon: Icons.tune,
          title: 'Ajustar compactação automática',
          text: effective == null
              ? 'Muda o limiar global. Vale para as próximas execuções.'
              : 'Muda o limiar global. Vale para as próximas execuções; '
                    'esta segue em ${autocompactLabel(effective)}.',
          onTap: widget.onAdjust,
        ),
        if (widget.onReviewAttachments != null) ...[
          const SizedBox(height: 8),
          _ActionRow(
            key: const ValueKey('context-action-attachments'),
            icon: Icons.attach_file,
            title: 'Revisar próximos anexos',
            badge: widget.attachments > 0 ? '${widget.attachments}' : null,
            text:
                'Tirar um anexo pendente afeta só o próximo envio. O que já '
                'foi lido continua no histórico.',
            onTap: widget.onReviewAttachments!,
          ),
        ],
        if (widget.onNewConversation != null) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('context-action-new'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.add, size: 16, color: AppColors.amber),
                    SizedBox(width: 10),
                    Text('Nova conversa', style: _title),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 26, top: 2),
                  child: Text(
                    'Escolha como ela começa. O resumo é montado pelo app, '
                    'sem chamar o modelo, e pode ser revisado antes do envio.',
                    style: _label,
                  ),
                ),
                if (widget.providers.length > 1) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Nova conversa em', style: _label),
                        for (final p in widget.providers)
                          ChoiceChip(
                            key: ValueKey('context-new-provider-$p'),
                            label: Text(
                              p == 'codex' ? 'Codex' : 'Claude Code',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _provider == p,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => _provider = p),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    for (final (v, label) in [
                      (NewConversationStart.empty, 'Começar vazia'),
                      (
                        NewConversationStart.summary,
                        'Levar um resumo desta conversa',
                      ),
                      if (widget.handoff != null)
                        (
                          NewConversationStart.handoff,
                          'Com a passagem do ai-memory',
                        ),
                    ])
                      InkWell(
                        key: ValueKey('context-new-${v.name}'),
                        onTap: () => setState(() => _start = v),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _start == v
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 14,
                                color: _start == v
                                    ? AppColors.amber
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _Button(
                    key: const ValueKey('context-new-go'),
                    label: switch (_start) {
                      NewConversationStart.summary => 'Revisar resumo',
                      NewConversationStart.handoff => 'Revisar mensagem',
                      NewConversationStart.empty => 'Começar vazia',
                    },
                    onTap: _newConversation,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('context-action-compact'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: a.ok ? AppColors.border : AppColors.borderHover,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    a.ok ? Icons.compress : Icons.lock_outline,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Compactar agora',
                      style: _title.copyWith(
                        color: a.ok ? AppColors.text : AppColors.textDisabled,
                      ),
                    ),
                  ),
                  _Button(
                    key: const ValueKey('context-compact-now'),
                    label: _sending ? 'Pedindo…' : 'Compactar agora',
                    enabled: a.ok && !_sending,
                    onTap: _compact,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 4),
                child: Text(
                  a.reason ??
                      'Usa o comando nativo do agente (/compact) com o agente '
                          'ocioso, um pedido por vez, sem mudar o acesso.',
                  key: const ValueKey('context-compact-reason'),
                  style: _label,
                ),
              ),
              if (a.ok) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: TextField(
                    key: const ValueKey('context-compact-focus'),
                    controller: _focus,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText:
                          'Foco do resumo (opcional): o que manter em detalhe',
                    ),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(left: 26, top: 6),
                  child: Text(
                    'Não foi possível pedir: $_error. A conversa segue como '
                    'estava.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.red,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Compactar não devolve cota do plano nem garante guardar cada '
          'detalhe. O app não cria resumo por turno nem pede ao modelo que '
          'compacte em laço.',
          style: _label,
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: _title),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderHover),
                          ),
                          child: Text(badge!, style: _label),
                        ),
                      ],
                    ],
                  ),
                  Text(text, style: _label),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SummaryDialog extends StatefulWidget {
  const _SummaryDialog({required this.initial});

  final String initial;

  @override
  State<_SummaryDialog> createState() => _SummaryDialogState();
}

class _SummaryDialogState extends State<_SummaryDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Resumo para a nova conversa'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Montado pelo app a partir desta conversa, sem chamar o modelo. '
            'Edite à vontade: ele vai para o campo de mensagem da nova '
            'conversa e só é enviado quando você mandar.',
            style: _label,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('context-summary-text'),
            controller: _text,
            maxLines: 12,
            minLines: 6,
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('context-summary-use'),
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('Usar na nova conversa'),
      ),
    ],
  );
}

/// "Próximo envio" of the Fontes tab (R5): the attachments of the
/// composer, not sent yet. They do not count in the measured context;
/// removing one affects only the next message.
class NextSendSection extends StatelessWidget {
  const NextSendSection({
    super.key,
    required this.paths,
    required this.onRemove,
  });

  final List<String> paths;
  final ValueChanged<String> onRemove;

  static String _size(String path) {
    try {
      final n = File(path).lengthSync();
      if (n >= 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
      return '${(n / 1024).ceil()} KB';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('context-next-send'),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Próximo envio', style: _title),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                paths.isEmpty
                    ? 'nenhum anexo pendente'
                    : '${paths.length} ${paths.length == 1 ? 'anexo pendente' : 'anexos pendentes'} · não contam no contexto medido',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _label,
              ),
            ),
          ],
        ),
        for (final path in paths)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.attach_file,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Text(_size(path), style: _label),
                const SizedBox(width: 10),
                _Button(
                  key: ValueKey('context-next-remove-${p.basename(path)}'),
                  label: 'Remover',
                  onTap: () => onRemove(path),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
