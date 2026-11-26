import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/capabilities.dart';
import '../../core/providers/provider_availability.dart';
import '../../core/providers/workspace_assets.dart';
import '../../core/system/worktree_launcher.dart';
import '../../core/text/line_diff.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/diff_view.dart';
import '../project/project_config.dart';
import '../project/widgets/project_widgets.dart';
import '../sessions/widgets/session_style.dart';

/// How a provider row reads (R2, R5): the state pill's tone.
enum InstructionsTone { loaded, expected, warning, missing }

/// One line of the providers table (R5): what the provider reads, its state
/// and the proof.
@immutable
class InstructionsRow {
  const InstructionsRow({
    required this.provider,
    required this.reads,
    required this.state,
    required this.tone,
    required this.proof,
  });

  final String provider;
  final String reads;
  final String state;
  final InstructionsTone tone;
  final String proof;
}

/// `hoje 14:32`, `20/11 14:32`.
String instructionsWhen(DateTime t, {DateTime? now}) {
  final l = t.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(l.hour)}:${two(l.minute)}';
  return l.year == n.year && l.month == n.month && l.day == n.day
      ? 'hoje $hm'
      : '${two(l.day)}/${two(l.month)} $hm';
}

/// Whether the Codex reads the root `CLAUDE.md` (R1, R3): the capability,
/// unless the last run proved otherwise (a project without `AGENTS.md`
/// whose run did not load the `CLAUDE.md`).
bool codexReadsClaudeMd(
  InstructionsInventory inv,
  InstructionsProof? proof, {
  required bool fallback,
}) {
  if (!fallback) return false;
  if (proof == null) return true;
  final onlyClaude =
      inv.claude != null && inv.agentsState == AgentsMdState.absent;
  return !onlyClaude || proof.loaded(claudeMdName);
}

/// The two rows of the table (R2, R4, R5). [codexReason] = why the Codex
/// cannot run (unavailable, incompatible, off): the row stays and says it.
List<InstructionsRow> instructionsRows(
  InstructionsInventory inv,
  InstructionsProof? proof, {
  required bool fallback,
  String? codexReason,
}) {
  final hasClaude = inv.claude != null;
  final single = inv.agentsState == AgentsMdState.singleSource;
  final claude = InstructionsRow(
    provider: 'Claude Code',
    reads: single
        ? '$claudeMdName + $agentsMdName (import)'
        : hasClaude
        ? claudeMdName
        : '—',
    state: hasClaude ? 'carregado' : 'sem CLAUDE.md',
    tone: hasClaude ? InstructionsTone.loaded : InstructionsTone.missing,
    proof: hasClaude
        ? 'lido pelo próprio CLI em toda execução'
        : 'o projeto não tem CLAUDE.md',
  );
  final proofText = proof == null
      ? 'nenhuma execução Codex ainda'
      : 'instructionSources da ${proof.where} · ${instructionsWhen(proof.at)}';
  final agents = inv.agentsState;
  final reads = switch (agents) {
    AgentsMdState.personal => 'AGENTS.md (no lugar do CLAUDE.md)',
    AgentsMdState.singleSource => 'AGENTS.md (fonte única)',
    AgentsMdState.fresh || AgentsMdState.stale => 'AGENTS.md gerado',
    AgentsMdState.absent when !hasClaude => '—',
    AgentsMdState.absent =>
      codexReadsClaudeMd(inv, proof, fallback: fallback)
          ? 'CLAUDE.md via override'
          : 'nada (não lê o CLAUDE.md)',
  };
  InstructionsRow codex(String state, InstructionsTone tone, [String? p]) =>
      InstructionsRow(
        provider: 'Codex',
        reads: reads,
        state: state,
        tone: tone,
        proof: p ?? proofText,
      );
  if (codexReason != null) {
    return [
      claude,
      codex('indisponível', InstructionsTone.missing, codexReason),
    ];
  }
  final loadedRoot =
      proof != null &&
      (proof.loaded(agentsMdName) || proof.loaded(claudeMdName));
  return [
    claude,
    switch (agents) {
      AgentsMdState.personal => codex('duas fontes', InstructionsTone.warning),
      // SPEC-113 R1: "carregado" only with the proof of a run.
      AgentsMdState.singleSource =>
        proof != null && proof.loaded(agentsMdName)
            ? codex('carregado', InstructionsTone.loaded)
            : codex('previsto', InstructionsTone.expected),
      AgentsMdState.stale => codex('desatualizado', InstructionsTone.warning),
      AgentsMdState.fresh =>
        proof != null && proof.loaded(agentsMdName)
            ? codex('carregado', InstructionsTone.loaded)
            : codex('previsto', InstructionsTone.expected),
      AgentsMdState.absent when !hasClaude => codex(
        'sem instruções',
        InstructionsTone.missing,
      ),
      AgentsMdState.absent
          when !codexReadsClaudeMd(inv, proof, fallback: fallback) =>
        codex('não carregado', InstructionsTone.warning),
      // R2: "carregado" only with the proof of a run.
      AgentsMdState.absent =>
        loadedRoot
            ? codex(
                'carregado na ${proof.where.split(' ').first} de '
                '${instructionsWhen(proof.at).replaceFirst('hoje ', '')}',
                InstructionsTone.loaded,
              )
            : proof == null
            ? codex('previsto', InstructionsTone.expected)
            : codex('não carregado', InstructionsTone.warning),
    },
  ];
}

/// Ferramentas → Instruções (SPEC-104 R5): the `CLAUDE.md` as the source,
/// what each provider reads with the proof (R2), the nested files (P3) and
/// the `AGENTS.md` cases (R3, R4).
class InstructionsView extends ConsumerStatefulWidget {
  const InstructionsView({super.key});

  @override
  ConsumerState<InstructionsView> createState() => _InstructionsViewState();
}

class _InstructionsViewState extends ConsumerState<InstructionsView> {
  /// Selected file, relative to the root (null = the CLAUDE.md).
  String? _selected;
  bool _busy = false;
  String? _error;

  Future<void> _open(String root, List<String> paths) async {
    final launcher = ref.read(worktreeLauncherProvider);
    final editor = ProjectConfig.loadSync(root).editorCommand;
    for (final p in paths) {
      try {
        await launcher.editor('$root/$p', editor: editor, cwd: root);
      } catch (e) {
        if (mounted) setState(() => _error = 'Não foi possível abrir $p: $e');
      }
    }
  }

  Future<void> _generate(String root, {required bool replace}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await writeGeneratedAgentsMd(root, replaceGenerated: replace);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      ref.invalidate(instructionsInventoryProvider(root));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const ColoredBox(
        color: AppColors.background,
        child: StepEmpty(
          title: 'Nenhum workspace',
          text: 'Abra um projeto para ver as instruções que os agentes leem.',
        ),
      );
    }
    final invAsync = ref.watch(instructionsInventoryProvider(ws.path));
    final inv = invAsync.value;
    if (inv == null) {
      return ColoredBox(
        color: AppColors.background,
        child: invAsync.hasError
            ? StepEmpty(
                title: 'Erro ao ler as instruções',
                text: '${invAsync.error}',
              )
            : const SizedBox.shrink(),
      );
    }
    final proof = ref.watch(instructionsProofProvider(ws.id)).value;
    final caps = ref.watch(codexCapabilitiesProvider);
    final fallback = caps.supports(ProviderCapability.instructionsFallback);
    final flows = ref.watch(providerFlowsProvider);
    final availability = ref.watch(providerAvailabilityProvider('codex'));
    final codexReason = flows.isOff('codex')
        ? providerOffLabel
        : switch (availability.value) {
            final a? when !a.available => 'Codex ${a.label}: ${a.message}',
            _ => null,
          };
    final reads = codexReadsClaudeMd(inv, proof, fallback: fallback);
    final rows = instructionsRows(
      inv,
      proof,
      fallback: fallback,
      codexReason: codexReason,
    );
    final selected = _selected ?? (inv.claude != null ? claudeMdName : null);
    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FileList(
            inv: inv,
            selected: selected,
            planB: !reads,
            onSelect: (p) => setState(() => _selected = p),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('instructions-detail'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                if (inv.claude == null)
                  NoticeBox.warning(
                    key: const ValueKey('instructions-no-claude'),
                    text:
                        'O projeto não tem CLAUDE.md. Crie um na raiz: é a '
                        'fonte das instruções para o Claude Code e para o '
                        'Codex.',
                  )
                else
                  _Header(
                    file: inv.claude!,
                    onOpen: () => _open(ws.path, [claudeMdName]),
                  ),
                const SizedBox(height: 14),
                _Table(rows: rows),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  NoticeBox.error(text: _error!),
                ],
                ..._state(ws.path, inv, reads: reads),
                if (fallback && inv.claude != null) ...[
                  const SizedBox(height: 14),
                  _Mechanism(proof: proof),
                ],
                if (selected != null) ...[
                  const SizedBox(height: 14),
                  _Preview(root: ws.path, path: selected, inv: inv),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The AGENTS.md cases (R3, R4).
  List<Widget> _state(
    String root,
    InstructionsInventory inv, {
    required bool reads,
  }) {
    const gap = SizedBox(height: 14);
    switch (inv.agentsState) {
      case AgentsMdState.personal:
        return [
          gap,
          _Notice(
            key: const ValueKey('instructions-two-sources'),
            title: 'Duas fontes.',
            text:
                'Este repositório tem um AGENTS.md escrito por você: o Codex '
                'lê o AGENTS.md primeiro, e o Claude lê o CLAUDE.md. O app '
                'não sobrescreve um arquivo que não gerou.',
            actions: [
              SmallButton(
                key: const ValueKey('instructions-open-both'),
                label: 'Abrir os dois',
                onTap: () => _open(root, [claudeMdName, agentsMdName]),
              ),
            ],
          ),
        ];
      case AgentsMdState.singleSource:
        return [
          gap,
          NoticeBox(
            key: const ValueKey('instructions-single-source'),
            text:
                'Fonte única. O AGENTS.md tem as instruções, e o CLAUDE.md o '
                'importa com @AGENTS.md: o Codex e o Claude Code leem o mesmo '
                'texto.',
          ),
        ];
      case AgentsMdState.stale:
        final current = agentsMdBody(inv.agentsText ?? '');
        return [
          gap,
          _Notice(
            key: const ValueKey('instructions-stale'),
            title: 'AGENTS.md desatualizado.',
            text:
                'O CLAUDE.md mudou depois que o AGENTS.md foi gerado'
                '${inv.claude == null ? '' : ' (${instructionsWhen(inv.claude!.modified)})'}'
                '. O Codex está lendo a versão antiga. O app nunca atualiza '
                'sozinho.',
          ),
          gap,
          Text('DIFERENÇA ANTES DE GRAVAR', style: sectionTitleStyle),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('instructions-diff'),
            decoration: BoxDecoration(
              color: SessionColors.terminalPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DiffView(
              rows: _diffRows(current, inv.claudeText ?? ''),
              collapseSame: 3,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AmberButton(
                key: const ValueKey('instructions-update-agents'),
                label: _busy ? 'Gravando…' : 'Atualizar AGENTS.md',
                onTap: _busy ? null : () => _generate(root, replace: true),
              ),
              SmallButton(
                key: const ValueKey('instructions-open-both'),
                label: 'Abrir os dois',
                onTap: () => _open(root, [claudeMdName, agentsMdName]),
              ),
            ],
          ),
        ];
      case AgentsMdState.fresh:
        return [
          gap,
          NoticeBox(
            key: const ValueKey('instructions-fresh'),
            text:
                'AGENTS.md gerado · em dia. É uma cópia do CLAUDE.md com aviso '
                'no topo: edite sempre o CLAUDE.md.',
          ),
        ];
      case AgentsMdState.absent:
        if (reads || inv.claude == null) return const [];
        // Plano B (R3): the Codex does not read the CLAUDE.md.
        return [
          gap,
          _Notice(
            key: const ValueKey('instructions-plan-b'),
            title: 'O Codex não lê o CLAUDE.md nesta versão.',
            text:
                'Gere um AGENTS.md: uma cópia do CLAUDE.md com aviso no topo '
                'e o hash da origem. O app nunca o atualiza sozinho.',
            actions: [
              AmberButton(
                key: const ValueKey('instructions-generate-agents'),
                label: _busy ? 'Gerando…' : 'Gerar AGENTS.md',
                onTap: _busy ? null : () => _generate(root, replace: false),
              ),
            ],
          ),
        ];
    }
  }
}

List<DiffRow> _diffRows(String before, String after) {
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

String _size(int bytes) => bytes < 1024
    ? '$bytes B'
    : '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB';

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.tone);

  final String text;
  final InstructionsTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = switch (tone) {
      InstructionsTone.loaded => (
        AppColors.teal,
        SessionColors.runningToolBg,
        SessionColors.runningToolBorder,
      ),
      InstructionsTone.warning => (
        AppColors.amber,
        SessionColors.approvalBg,
        SessionColors.approvalBorder,
      ),
      InstructionsTone.expected => (
        AppColors.textSecondary,
        AppColors.surfaceRaised,
        AppColors.border,
      ),
      InstructionsTone.missing => (
        AppColors.textMuted,
        AppColors.surfaceRaised,
        AppColors.border,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.inv,
    required this.selected,
    required this.planB,
    required this.onSelect,
  });

  final InstructionsInventory inv;
  final String? selected;
  final bool planB;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget item(InstructionFile f, String sub, {Widget? tag}) {
      final on = f.path == selected;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: on ? SessionColors.selectedBg : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: on ? SessionColors.selectedBorder : Colors.transparent,
            ),
          ),
          child: InkWell(
            key: ValueKey('instructions-file-${f.path}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(f.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          sub,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?tag,
                ],
              ),
            ),
          ),
        ),
      );
    }

    final agentsSub = switch (inv.agentsState) {
      AgentsMdState.personal => 'raiz · escrito por você',
      AgentsMdState.singleSource => 'raiz · fonte única',
      AgentsMdState.fresh => 'raiz · gerado · em dia',
      AgentsMdState.stale => 'raiz · gerado · desatualizado',
      AgentsMdState.absent => '',
    };
    final single = inv.agentsState == AgentsMdState.singleSource;
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text(
                    'INSTRUÇÕES DO PROJETO',
                    style: sectionTitleStyle,
                  ),
                ),
                if (inv.claude case final c?)
                  item(
                    c,
                    single
                        ? 'importa o AGENTS.md · raiz · ${_size(c.size)}'
                        : 'fonte · raiz · ${_size(c.size)}',
                    tag: single
                        ? null
                        : const _Pill('fonte', InstructionsTone.warning),
                  ),
                if (inv.agents case final a?)
                  item(
                    a,
                    agentsSub,
                    tag: single
                        ? const _Pill('fonte', InstructionsTone.warning)
                        : inv.agentsState == AgentsMdState.stale
                        ? const _Pill('desatualizado', InstructionsTone.warning)
                        : null,
                  ),
                if (inv.claude == null && inv.agents == null)
                  const _Muted('Nenhum arquivo na raiz.'),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text(
                    'SUBPASTAS · SÓ LEITURA',
                    style: sectionTitleStyle,
                  ),
                ),
                if (inv.nested.isEmpty) const _Muted('Nenhum.'),
                for (final f in inv.nested)
                  item(
                    f,
                    _size(f.size),
                    // P3: in plano B only the root gets an AGENTS.md.
                    tag: planB && f.name == claudeMdName
                        ? const _Pill(
                            'Só Claude Code',
                            InstructionsTone.expected,
                          )
                        : null,
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Text(
              'O CLAUDE.md é a fonte. O app não grava nada em ~/.codex nem '
              'altera o repositório para o Codex lê-lo.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.file, required this.onOpen});

  final InstructionFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              claudeMdName,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
            const _Pill('fonte', InstructionsTone.warning),
            Text(
              'editado ${instructionsWhen(file.modified)} · ${file.lines} linhas',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      SmallButton(
        key: const ValueKey('instructions-open-editor'),
        label: 'Abrir no editor',
        onTap: onOpen,
      ),
    ],
  );
}

class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<InstructionsRow> rows;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.textSecondary,
    );
    Widget row(List<Widget> cells, {Key? key, bool top = false}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: top
            ? null
            : const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 120, child: cells[0]),
          Expanded(flex: 3, child: cells[1]),
          SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Align(alignment: Alignment.centerLeft, child: cells[2]),
          ),
          SizedBox(width: 12),
          Expanded(flex: 4, child: cells[3]),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          row(const [
            Text('PROVEDOR', style: head),
            Text('LÊ', style: head),
            Text('ESTADO', style: head),
            Text('PROVA', style: head),
          ], top: true),
          for (final r in rows)
            row(key: ValueKey('instructions-row-${r.provider}'), [
              Text(
                r.provider,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              Text(
                r.reads,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.text,
                ),
              ),
              _Pill(r.state, r.tone),
              Text(
                r.proof,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.title,
    required this.text,
    this.actions = const [],
  });

  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: SessionColors.approvalBg,
      border: Border.all(color: SessionColors.approvalBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$title ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: text),
            ],
          ),
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: AppColors.amberLight,
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    ),
  );
}

class _Mechanism extends StatelessWidget {
  const _Mechanism({required this.proof});

  final InstructionsProof? proof;

  @override
  Widget build(BuildContext context) {
    final p = proof;
    Widget line(String k, String v, {bool mono = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontFamily: mono ? AppFonts.mono : null,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('instructions-mechanism'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'COMO O CODEX RECEBE O CLAUDE.MD',
            style: sectionTitleStyle,
          ),
          const SizedBox(height: 10),
          line(
            'Mecanismo',
            '-c project_doc_fallback_filenames=["CLAUDE.md"]',
            mono: true,
          ),
          line('Grava em', 'nada · vale só para cada execução do app'),
          line(
            'Última conferência',
            p == null
                ? 'nenhuma execução Codex ainda'
                : '${instructionsWhen(p.at)} · '
                      '${p.sources.isEmpty ? 'nenhum arquivo' : p.sources.join(', ')}',
            mono: p != null,
          ),
          line(
            'Sem execução ainda',
            'a linha mostra “previsto”, nunca “carregado”',
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.root, required this.path, required this.inv});

  final String root;
  final String path;
  final InstructionsInventory inv;

  String _text() {
    if (path == claudeMdName) return inv.claudeText ?? '';
    if (path == agentsMdName) return inv.agentsText ?? '';
    try {
      return File('$root/$path').readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _text().split('\n');
    final shown = lines.length > 200 ? lines.sublist(0, 200) : lines;
    return Container(
      key: const ValueKey('instructions-preview'),
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SessionColors.terminalPanel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        [
          ...shown,
          if (lines.length > shown.length)
            '… (${lines.length - shown.length} linhas)',
        ].join('\n'),
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12,
          height: 1.6,
          color: AppColors.text,
        ),
      ),
    );
  }
}
