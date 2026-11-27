import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/structured_run.dart' show providerDisplayName;
import '../../core/providers/workspace_assets.dart'
    show instructionsInventoryProvider;
import '../../data/providers.dart' show Workspace;
import '../../ui/providers/provider_logos.dart';
import '../../ui/theme/tokens.dart';
import '../cost/cost_format.dart' show spokenTokens;
import '../project/widgets/project_widgets.dart';
import '../sessions/widgets/session_style.dart';
import 'instructions_view.dart' show instructionsWhen;
import 'interview_controller.dart';

/// The screen of the interview of "Melhorar com IA" (SPEC-113 R13–R18,
/// mock `4-entrevista.png`): the rounds and the findings on the left, the
/// questions of the round in the middle and the draft on the right, with the
/// provider, the model and the tokens in the bar. A standalone widget: the
/// tab Projeto › Instruções (T3) places it.
///
/// [onProposalReady] receives the proposal when the interview ends (R16);
/// the proposal screen (T6) shows and applies it. [onPaused] runs after
/// "Pausar" (the tab goes back to the editor, where [InterviewResumeCard]
/// offers "Continuar").
class InstructionsInterviewView extends ConsumerStatefulWidget {
  const InstructionsInterviewView({
    super.key,
    required this.workspace,
    required this.onProposalReady,
    this.onPaused,
    this.autoStart = false,
  });

  final Workspace workspace;
  final ValueChanged<InstructionProposal> onProposalReady;
  final VoidCallback? onPaused;

  /// Starts a new interview when the project has none.
  final bool autoStart;

  @override
  ConsumerState<InstructionsInterviewView> createState() =>
      _InstructionsInterviewViewState();
}

class _InstructionsInterviewViewState
    extends ConsumerState<InstructionsInterviewView> {
  final _texts = <String, TextEditingController>{};

  /// Questions where the person chose "Outra resposta" / "Responder".
  final _writing = <String>{};

  /// The question answered last (the card "Com a Qn respondida").
  String? _lastAnswered;

  Workspace get ws => widget.workspace;
  InterviewController get _c =>
      ref.read(instructionInterviewProvider(ws.id).notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      final s = ref.read(instructionInterviewProvider(ws.id));
      if (!s.loaded) await _c.load(ws);
      if (!mounted) return;
      final now = ref.read(instructionInterviewProvider(ws.id));
      if (!now.exists && widget.autoStart) await _c.start(ws);
    });
  }

  @override
  void dispose() {
    for (final t in _texts.values) {
      t.dispose();
    }
    super.dispose();
  }

  TextEditingController _text(String id, String initial) =>
      _texts.putIfAbsent(id, () => TextEditingController(text: initial));

  Future<void> _answer(String id, InterviewAnswer? a) async {
    setState(() => _lastAnswered = a == null || a.skipped ? null : id);
    await _c.answer(id, a);
  }

  Future<void> _propose(Future<InstructionProposal?> Function() run) async {
    final p = await run();
    if (p != null && mounted) widget.onProposalReady(p);
  }

  Future<void> _pause() async {
    await _c.pause();
    widget.onPaused?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(instructionInterviewProvider(ws.id));
    if (!s.loaded) {
      return const Center(child: PlannerBusy('Abrindo a entrevista…'));
    }
    if (!s.exists) {
      return StepEmpty(
        title: 'Melhorar com IA',
        text:
            'A IA lê o projeto em somente leitura e pergunta, em rodadas, o '
            'que só você pode decidir. Nada é gravado nos arquivos sem a sua '
            'aprovação.',
        action: AmberButton(
          key: const ValueKey('interview-start'),
          label: 'Começar a entrevista',
          busy: s.busy,
          onTap: () => _c.start(ws),
        ),
      );
    }
    if (s.paused) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: InterviewResumeCard(workspace: ws),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(s),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 220, child: _side(s)),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(child: _center(s)),
              const VerticalDivider(width: 1, color: AppColors.border),
              SizedBox(width: 300, child: _draft(s)),
            ],
          ),
        ),
      ],
    );
  }

  // --- Barra ----------------------------------------------------------------

  Widget _bar(InterviewState s) {
    final provider = s.provider ?? 'claude';
    final model = s.model;
    final round = s.data.current?.number ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text(
            'Melhorar com IA',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 10),
          _Pill('rodada $round', key: const ValueKey('interview-round')),
          const SizedBox(width: 8),
          ProviderChip(
            provider,
            key: const ValueKey('interview-provider'),
            dense: true,
            name: [
              providerDisplayName(provider),
              if (model case final m? when m.isNotEmpty) m,
            ].join(' · '),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'somente leitura · ${spokenTokens(s.tokens)}',
              key: const ValueKey('interview-tokens'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          SmallButton(
            key: const ValueKey('interview-pause'),
            label: 'Pausar',
            onTap: _pause,
          ),
          const SizedBox(width: 8),
          SmallButton(
            key: const ValueKey('interview-finish'),
            label: 'Encerrar e ver a proposta',
            color: AppColors.teal,
            border: SessionColors.runningToolBorder,
            background: SessionColors.runningToolBg,
            onTap:
                s.busy ||
                    s.data.rounds.isEmpty ||
                    s.data.stage == InterviewStage.proposal
                ? null
                : () => _propose(() => _c.finishEarly(ws)),
          ),
        ],
      ),
    );
  }

  // --- Lateral --------------------------------------------------------------

  Widget _side(InterviewState s) {
    final data = s.data;
    final findings = data.findings;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final r in data.rounds)
          if (r.questions.isNotEmpty) ...[
            Row(
              children: [
                Text('RODADA ${r.number}', style: sectionTitleStyle),
                const Spacer(),
                if (r.sent)
                  Text(
                    '${r.answered} respondidas',
                    style: const TextStyle(fontSize: 11, color: AppColors.teal),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final q in r.questions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${q.id} ',
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          color: r.sent
                              ? AppColors.textSecondary
                              : AppColors.amber,
                        ),
                      ),
                      ...interviewCodeSpans(q.title),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
            if (r.sent && identical(r, _lastSent(data)))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SmallButton(
                    key: const ValueKey('interview-review'),
                    label: 'Rever respostas',
                    height: 26,
                    fontSize: 11,
                    onTap: () => showInterviewAnswers(context, data),
                  ),
                ),
              ),
            const SizedBox(height: 14),
          ],
        Text('ACHADO NO CÓDIGO · ${findings.length}', style: sectionTitleStyle),
        const SizedBox(height: 6),
        const Text(
          'A IA não pergunta o que o projeto já responde.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final f in findings)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  ...interviewCodeSpans(f.text),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: f.path,
                    style: const TextStyle(fontFamily: AppFonts.mono),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
      ],
    );
  }

  InterviewRound? _lastSent(InterviewData d) =>
      d.rounds.where((r) => r.sent && r.questions.isNotEmpty).lastOrNull;

  // --- Centro ---------------------------------------------------------------

  Widget _center(InterviewState s) {
    final data = s.data;
    final round = data.current;
    Widget? notice;
    if (s.filesChanged) {
      notice = const NoticeBox.warning(
        key: ValueKey('interview-files-changed'),
        text:
            'Os arquivos de instruções mudaram depois da última leitura. Na '
            'próxima rodada, a IA relê os arquivos. As suas respostas são '
            'mantidas.',
      );
    }
    if (s.error case final e?) {
      notice = NoticeBox.error(
        key: const ValueKey('interview-error'),
        text: 'A IA não respondeu: $e',
        action: SmallButton(
          key: const ValueKey('interview-retry'),
          label: 'Tentar de novo',
          onTap: s.busy ? null : () => _propose(() => _c.retry(ws)),
        ),
      );
    }
    final Widget body;
    if (s.busy && (data.needsRun || data.stage != InterviewStage.asking)) {
      body = Center(
        child: PlannerBusy(
          data.stage == InterviewStage.asking
              ? 'A IA está lendo o projeto…'
              : 'Escrevendo a proposta…',
        ),
      );
    } else if (data.stage == InterviewStage.summary) {
      body = _summary(s);
    } else if (data.stage == InterviewStage.proposal) {
      body = StepEmpty(
        title: 'Proposta pronta',
        text:
            '${data.proposal?.hunks.length ?? 0} trechos para revisar. Nada '
            'foi gravado.',
        action: AmberButton(
          key: const ValueKey('interview-open-proposal'),
          label: 'Ver a proposta',
          onTap: data.proposal == null
              ? null
              : () => widget.onProposalReady(data.proposal!),
        ),
      );
    } else if (round == null || data.needsRun) {
      body = const SizedBox.shrink();
    } else {
      body = _questions(s, round);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null) ...[notice, const SizedBox(height: 12)],
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _questions(InterviewState s, InterviewRound round) {
    final focus = round.questions
        .where((q) => !(round.answers[q.id]?.complete ?? false))
        .firstOrNull
        ?.id;
    final missing = round.questions.length - round.answered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              for (final q in round.questions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _card(q, round.answers[q.id], focused: q.id == focus),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SmallButton(
              key: const ValueKey('interview-accept-all'),
              label: 'Aceitar as recomendadas que faltam',
              height: 34,
              onTap: missing == 0 ? null : _c.acceptRemainingRecommended,
            ),
            const Spacer(),
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  missing == 1
                      ? 'Falta 1 resposta'
                      : 'Faltam $missing respostas',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            AmberButton(
              key: const ValueKey('interview-send'),
              label: 'Enviar rodada',
              height: 34,
              busy: s.busy,
              onTap: missing == 0 ? () => _c.sendRound(ws) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(
    InterviewQuestion q,
    InterviewAnswer? a, {
    required bool focused,
  }) {
    final writing =
        _writing.contains(q.id) || a?.kind == InterviewAnswerKind.text;
    final hasOptions = q.options.isNotEmpty;
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q.id,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 13,
            color: AppColors.amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: interviewCodeSpans(q.text)),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
        if (q.onlyClaude) const _Pill('só do Claude'),
      ],
    );
    final reason = hasOptions
        ? q.reason
        : [
            if (q.recommended.isNotEmpty) 'Recomendo: ${q.recommended}.',
            if (q.reason.isNotEmpty) q.reason,
          ].join(' ');
    final selected = a == null || a.kind == InterviewAnswerKind.text
        ? null
        : a.value;
    return Container(
      key: ValueKey('interview-q-${q.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: focused ? SessionColors.approvalBg : AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? SessionColors.approvalBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: interviewCodeSpans(reason)),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (hasOptions) ...[
            const SizedBox(height: 10),
            for (final o in q.options)
              _Option(
                key: ValueKey(
                  'interview-q-${q.id}-opt-${q.options.indexOf(o)}',
                ),
                label: o,
                recommended: o == q.recommended,
                selected: !writing && selected == o,
                onTap: () {
                  _writing.remove(q.id);
                  _answer(
                    q.id,
                    InterviewAnswer(
                      o == q.recommended
                          ? InterviewAnswerKind.recommended
                          : InterviewAnswerKind.option,
                      o,
                    ),
                  );
                },
              ),
            _Option(
              key: ValueKey('interview-q-${q.id}-other'),
              label: 'Outra resposta',
              selected: writing,
              onTap: () {
                setState(() => _writing.add(q.id));
                if (a?.kind != InterviewAnswerKind.text) {
                  _answer(
                    q.id,
                    InterviewAnswer(
                      InterviewAnswerKind.text,
                      _text(q.id, '').text,
                    ),
                  );
                }
              },
            ),
          ],
          if (writing) ...[
            const SizedBox(height: 8),
            const Text(
              'Sua resposta',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            TextField(
              key: ValueKey('interview-q-${q.id}-text'),
              controller: _text(
                q.id,
                a?.kind == InterviewAnswerKind.text ? a!.value : '',
              ),
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              decoration: const InputDecoration(isDense: true),
              onChanged: (v) =>
                  _answer(q.id, InterviewAnswer(InterviewAnswerKind.text, v)),
            ),
          ],
          if (a?.skipped ?? false) ...[
            const SizedBox(height: 8),
            const Text(
              'Pulada: não vira regra.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (q.recommended.isNotEmpty)
                SmallButton(
                  key: ValueKey('interview-q-${q.id}-accept'),
                  label: 'Aceitar a recomendação',
                  height: 26,
                  fontSize: 11,
                  color: AppColors.lilac,
                  border: projectLilacBorder,
                  background: projectLilacBg,
                  onTap: () {
                    _writing.remove(q.id);
                    _answer(
                      q.id,
                      InterviewAnswer(
                        InterviewAnswerKind.recommended,
                        q.recommended,
                      ),
                    );
                  },
                ),
              if (!hasOptions && !writing)
                SmallButton(
                  key: ValueKey('interview-q-${q.id}-write'),
                  label: 'Responder',
                  height: 26,
                  fontSize: 11,
                  onTap: () {
                    setState(() => _writing.add(q.id));
                    _answer(
                      q.id,
                      InterviewAnswer(
                        InterviewAnswerKind.text,
                        _text(q.id, '').text,
                      ),
                    );
                  },
                ),
              SmallButton(
                key: ValueKey('interview-q-${q.id}-skip'),
                label: 'Pular',
                height: 26,
                fontSize: 11,
                onTap: () {
                  setState(() => _writing.remove(q.id));
                  _answer(q.id, const InterviewAnswer.skipped());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(InterviewState s) => ListView(
    key: const ValueKey('interview-summary'),
    children: [
      const Text(
        'O que foi entendido',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(
          children: interviewCodeSpans(
            s.data.summary.isEmpty
                ? 'Sem perguntas abertas.'
                : interviewBullets(s.data.summary),
          ),
        ),
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.text,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Confira antes de ver a proposta. Nada foi gravado nos arquivos.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: AmberButton(
          key: const ValueKey('interview-confirm'),
          label: 'Confirmar e ver a proposta',
          busy: s.busy,
          onTap: () => _propose(() => _c.propose(ws)),
        ),
      ),
    ],
  );

  // --- Rascunho -------------------------------------------------------------

  Widget _draft(InterviewState s) {
    final data = s.data;
    final before = data.previousDraft.split('\n').toSet();
    final lines = data.draft.isEmpty
        ? const <String>[]
        : data.draft.split('\n');
    final round = data.current;
    final last = _lastAnswered;
    final q = last == null || round == null
        ? null
        : round.questions.where((x) => x.id == last).firstOrNull;
    final answer = q == null ? null : round?.answers[q.id];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('RASCUNHO ATÉ AGORA', style: sectionTitleStyle),
          const SizedBox(height: 8),
          // The draft takes the free height (up to its text); the footer
          // stays at the bottom. A Spacer next to it split the height in two
          // and the draft scrolled with room left.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: Container(
                    key: const ValueKey('interview-draft'),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: lines.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: Text(
                              'O rascunho aparece depois da primeira rodada.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              for (final l in lines)
                                Container(
                                  color:
                                      l.trim().isNotEmpty &&
                                          data.previousDraft.isNotEmpty &&
                                          !before.contains(l)
                                      ? SessionColors.addBg
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    l,
                                    style: TextStyle(
                                      fontFamily: AppFonts.mono,
                                      fontSize: 11.5,
                                      height: 1.45,
                                      fontWeight: l.startsWith('#')
                                          ? FontWeight.w700
                                          : null,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                if (q != null && answer != null && answer.complete) ...[
                  const SizedBox(height: 12),
                  Container(
                    key: const ValueKey('interview-answered'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SessionColors.approvalBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SessionColors.approvalBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COM A ${q.id} RESPONDIDA',
                          style: sectionTitleStyle.copyWith(
                            color: AppColors.amber,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '- ${answer.value}',
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        if (q.target.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            q.target,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Nada foi gravado nos arquivos. As respostas ficam guardadas '
            'neste projeto.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// "Rever respostas" / "Ver respostas": every question and its answer.
Future<void> showInterviewAnswers(
  BuildContext context,
  InterviewData data,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: AppColors.panelSolid,
    title: const Text(
      'Respostas da entrevista',
      style: TextStyle(fontSize: 15, color: AppColors.text),
    ),
    content: SizedBox(
      width: 520,
      child: ListView(
        key: const ValueKey('interview-answers'),
        shrinkWrap: true,
        children: [
          for (final q in data.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${q.id} ',
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        color: AppColors.amber,
                      ),
                    ),
                    ...interviewCodeSpans('${q.text}\n'),
                    TextSpan(
                      text: switch (data.answers[q.id]) {
                        final a? when a.complete => a.spoken,
                        _ => 'aberta',
                      },
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ),
        ],
      ),
    ),
    actions: [
      SmallButton(label: 'Fechar', onTap: () => Navigator.of(context).pop()),
    ],
  ),
);

/// The paused interview in the side of Projeto › Instruções (R18, mock
/// `6-retomar.png`): progress, "Continuar", "Ver respostas", "Descartar e
/// começar outra", and the warning when the files changed after the pause.
/// Renders nothing without a paused interview.
class InterviewResumeCard extends ConsumerStatefulWidget {
  const InterviewResumeCard({
    super.key,
    required this.workspace,
    this.onContinue,
  });

  final Workspace workspace;

  /// After "Continuar" (the tab opens [InstructionsInterviewView]).
  final VoidCallback? onContinue;

  @override
  ConsumerState<InterviewResumeCard> createState() =>
      _InterviewResumeCardState();
}

class _InterviewResumeCardState extends ConsumerState<InterviewResumeCard> {
  Workspace get ws => widget.workspace;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final s = ref.read(instructionInterviewProvider(ws.id));
      if (!s.loaded) {
        ref.read(instructionInterviewProvider(ws.id).notifier).load(ws);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // A file changed while paused (the tab's watcher rescans): the warning
    // shows now, not only after reopening the app (R18).
    ref.listen(instructionsInventoryProvider(ws.path), (prev, next) {
      final st = ref.read(instructionInterviewProvider(ws.id));
      if (prev?.hasValue == true && next.hasValue && st.paused && !st.busy) {
        ref.read(instructionInterviewProvider(ws.id).notifier).load(ws);
      }
    });
    final s = ref.watch(instructionInterviewProvider(ws.id));
    if (!s.exists || !s.paused) return const SizedBox.shrink();
    final c = ref.read(instructionInterviewProvider(ws.id).notifier);
    final data = s.data;
    final total = data.questions.length;
    final answered = data.answeredCount;
    final round = data.current?.number ?? 1;
    final provider = providerDisplayName(s.provider ?? 'claude');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('interview-paused'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: projectLilacBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: projectLilacBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Entrevista pausada',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  _Pill('rodada $round'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$answered ${answered == 1 ? 'pergunta respondida' : 'perguntas respondidas'}'
                ' e ${total - answered} ${total - answered == 1 ? 'aberta' : 'abertas'}'
                '${s.pausedAt == null ? '' : ' · parada ${instructionsWhen(s.pausedAt!)}'}',
                key: const ValueKey('interview-paused-progress'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : answered / total,
                  minHeight: 4,
                  color: AppColors.lilac,
                  backgroundColor: AppColors.border,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SmallButton(
                    key: const ValueKey('interview-continue'),
                    label: 'Continuar',
                    color: AppColors.lilac,
                    border: projectLilacBorder,
                    background: projectLilacBg,
                    onTap: () {
                      widget.onContinue?.call();
                      c.resume(ws);
                    },
                  ),
                  SmallButton(
                    key: const ValueKey('interview-show-answers'),
                    label: 'Ver respostas',
                    onTap: () => showInterviewAnswers(context, data),
                  ),
                  SmallButton(
                    key: const ValueKey('interview-discard'),
                    label: 'Descartar e começar outra',
                    onTap: () async {
                      await c.discard();
                      await c.start(ws);
                      widget.onContinue?.call();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Continua no $provider, onde começou.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (s.filesChanged) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('interview-paused-files-changed'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SessionColors.approvalBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SessionColors.approvalBorder),
            ),
            child: const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        'Os arquivos de instruções mudaram depois da pausa.\n',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.amber,
                    ),
                  ),
                  TextSpan(
                    text:
                        'Ao continuar, a IA relê os arquivos. As suas '
                        'respostas são mantidas.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: projectLilacBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: projectLilacBorder),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: AppColors.lilac),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final String label;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.amber : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.amber : AppColors.textSecondary,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.amber,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : null,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (recommended) ...[
                const SizedBox(width: 6),
                const _Pill('recomendada'),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// The AI writes Markdown: the text between backticks shows in the code
/// font (no backticks), the rest as is.
List<InlineSpan> interviewCodeSpans(String text) {
  final parts = text.split('`');
  // An unpaired backtick is text, not the start of a code span.
  if (parts.length.isEven) return [TextSpan(text: text)];
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        i.isOdd
            ? TextSpan(
                text: parts[i],
                style: const TextStyle(fontFamily: AppFonts.mono),
              )
            : TextSpan(text: parts[i]),
  ];
}

/// The summary's Markdown list items (`- `, `* `) as bullets.
String interviewBullets(String text) => text.replaceAllMapped(
  RegExp(r'^(\s*)[-*] ', multiLine: true),
  (m) => '${m[1]}• ',
);
