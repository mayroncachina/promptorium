import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';
import '../context_snapshot.dart';
import '../context_sources.dart';
import 'context_chart.dart';
import 'context_indicator.dart';

enum ContextTab { usage, sources }

/// The Contexto panel (SPEC-087 R2–R6, P1): Uso (bar, composition, auto
/// compaction, Evolução) and Fontes (observed evidence). [actions] is the
/// compaction section of T3, shown under the auto-compaction row.
class ContextPanel extends StatefulWidget {
  const ContextPanel({
    super.key,
    required this.snapshot,
    required this.sources,
    required this.onClose,
    this.place = 'Conversa',
    this.title,
    this.alive = true,
    this.onJump,
    this.onOpenSource,
    this.autocompact,
    this.actions,
    this.nextSend,
    this.initialTab = ContextTab.usage,
    this.tab,
    this.onTab,
  });

  final ContextSnapshot snapshot;
  final ContextSources sources;
  final VoidCallback onClose;

  /// "Conversa" / "Sessão" (header, right side).
  final String place;
  final String? title;
  final bool alive;
  final ValueChanged<ContextReading>? onJump;

  /// Opens the file / event of a source (R5).
  final ValueChanged<ContextSource>? onOpenSource;

  /// Auto-compaction row (R7); null = read-only text.
  final Widget? autocompact;

  /// Compaction actions (R9).
  final Widget? actions;

  /// "Próximo envio" of the Fontes tab (R5).
  final Widget? nextSend;
  final ContextTab initialTab;

  /// Controlled tab (the screen's); null = the panel keeps its own.
  final ContextTab? tab;
  final ValueChanged<ContextTab>? onTab;

  @override
  State<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends State<ContextPanel> {
  late ContextTab _tab = widget.initialTab;
  final _focus = FocusNode(debugLabel: 'context-panel');

  @override
  void initState() {
    super.initState();
    // Opened from the meter: the focus comes here (Esc closes, Tab walks).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _setTab(ContextTab t) {
    if (widget.onTab != null) {
      widget.onTab!(t);
    } else {
      setState(() => _tab = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final count = widget.sources.length;
    final tab = widget.tab ?? _tab;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      // Takes the focus when it opens: Esc closes it, Tab walks its rows.
      child: Focus(
        focusNode: _focus,
        skipTraversal: true,
        child: FocusTraversalGroup(
          child: ColoredBox(
            color: AppColors.panelSolid,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                  child: Row(
                    children: [
                      const Text(
                        'Contexto',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (s.model != null)
                        _Chip(
                          s.capacity == null
                              ? shortModel(s.model!)
                              : '${shortModel(s.model!)} · ${contextTokens(s.capacity!)}',
                        ),
                      const Spacer(),
                      Flexible(
                        flex: 3,
                        child: Text(
                          widget.title == null
                              ? widget.place
                              : '${widget.place} · ${widget.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('context-panel-close'),
                        tooltip: 'Fechar (Esc)',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close, size: 16),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _TabButton(
                        label: 'Uso',
                        on: tab == ContextTab.usage,
                        onTap: () => _setTab(ContextTab.usage),
                        tabKey: const ValueKey('context-tab-usage'),
                      ),
                      const SizedBox(width: 16),
                      _TabButton(
                        label: 'Fontes',
                        count: count,
                        on: tab == ContextTab.sources,
                        onTap: () => _setTab(ContextTab.sources),
                        tabKey: const ValueKey('context-tab-sources'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: tab == ContextTab.usage
                      ? _UsageTab(
                          snapshot: s,
                          alive: widget.alive,
                          onJump: widget.onJump,
                          autocompact: widget.autocompact,
                          actions: widget.actions,
                        )
                      : ContextSourcesView(
                          snapshot: s,
                          sources: widget.sources,
                          onOpen: widget.onOpenSource,
                          nextSend: widget.nextSend,
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.on,
    required this.onTap,
    required this.tabKey,
    this.count,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;
  final Key tabKey;
  final int? count;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    button: true,
    child: InkWell(
      key: tabKey,
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? AppColors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text.rich(
          TextSpan(
            text: label,
            children: [
              if (count != null)
                TextSpan(
                  text: ' $count',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
            ],
          ),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? AppColors.text : AppColors.textSecondary,
          ),
        ),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: AppColors.borderHover),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 11,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

const _label = TextStyle(fontSize: 11.5, color: AppColors.textSecondary);
const _monoBig = TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: AppColors.text,
);

class _UsageTab extends StatelessWidget {
  const _UsageTab({
    required this.snapshot,
    required this.alive,
    this.onJump,
    this.autocompact,
    this.actions,
  });

  final ContextSnapshot snapshot;
  final bool alive;
  final ValueChanged<ContextReading>? onJump;
  final Widget? autocompact;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final c = s.current;
    final points = contextPoints(s);
    return ListView(
      key: const ValueKey('context-usage'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Semantics(
          label: contextSummary(s, alive: alive),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _Headline(snapshot: s)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        c == null
                            ? s.pendingAfterCompaction
                                  ? 'compactado · aguardando medição'
                                  : 'aguardando medição'
                            : !c.live
                            ? 'leitura antiga · ${contextTime(c.at)} · turno ${c.turn}'
                            : c.turnEnd
                            ? 'medido no fim do turno ${c.turn} · ${contextTime(c.at)}'
                            : 'medido no turno ${c.turn} · ${contextTime(c.at)}',
                        style: _label,
                      ),
                      const Text(
                        'fonte: uso informado pelo agente',
                        style: _label,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _BigBar(snapshot: s),
              const SizedBox(height: 12),
              _Tiles(snapshot: s),
              const SizedBox(height: 10),
              _Composition(snapshot: s),
              if (s.subagents.isNotEmpty)
                SubagentContextNote(subagents: s.subagents),
            ],
          ),
        ),
        const SizedBox(height: 12),
        autocompact ?? _AutocompactText(snapshot: s),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              'Evolução',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${points.length} ${points.length == 1 ? 'leitura' : 'leituras'}',
              style: _label,
            ),
            const Spacer(),
            const Flexible(
              flex: 4,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '▣ compactou',
                      style: TextStyle(color: AppColors.teal),
                    ),
                    TextSpan(text: '   '),
                    TextSpan(
                      text: '◆ troca de modelo',
                      style: TextStyle(color: AppColors.lilac),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _label,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ContextEvolution(snapshot: s, onJump: onJump),
        const SizedBox(height: 8),
        for (final line in markerLines(s))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(line, style: _label),
          ),
        // The compaction actions (R9) come after the measured part.
        if (actions != null) ...[
          const SizedBox(height: 16),
          const Text(
            'Compactar e continuar',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          actions!,
        ],
      ],
    );
  }
}

/// "Turno 7: compactou (171 mil → 46 mil, duas leituras da mesma
/// execução)." Before/after only with two valid readings (R6).
List<String> markerLines(ContextSnapshot s) {
  final out = <String>[];
  for (final m in s.markers) {
    if (m.kind == ContextMarkerKind.modelChange) {
      out.add(
        'Turno ${m.turn}: ${shortModel(m.fromModel ?? '?')} → '
        '${shortModel(m.toModel ?? '?')}, limites revalidados.',
      );
      continue;
    }
    final before = m.readingsBefore > 0
        ? s.readings[m.readingsBefore - 1]
        : null;
    final after = m.readingsBefore < s.readings.length
        ? s.readings[m.readingsBefore]
        : null;
    final how = m.trigger == 'manual' ? 'compactado manualmente' : 'compactou';
    if (before != null && after != null) {
      out.add(
        'Turno ${m.turn}: $how (${contextTokens(before.tokens)} → '
        '${contextTokens(after.tokens)}, duas leituras da mesma execução).',
      );
    } else if (before != null) {
      out.add(
        'Turno ${m.turn}: $how (antes ${contextTokens(before.tokens)}; '
        'depois aguardando medição).',
      );
    } else {
      out.add('Turno ${m.turn}: $how.');
    }
  }
  return out;
}

class _Headline extends StatelessWidget {
  const _Headline({required this.snapshot});

  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final c = s.current;
    if (c == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.pendingAfterCompaction
                ? 'Contexto compactado'
                : 'Aguardando medição',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          if (s.last != null)
            Text(
              'Última leitura: ${contextTokens(s.last!.tokens)} no turno '
              '${s.last!.turn}${s.pendingAfterCompaction ? ', antes de compactar' : ''}',
              style: _label,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          contextTokens(c.tokens),
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        Text.rich(
          TextSpan(
            text: s.capacity == null
                ? 'tokens no contexto · limite desconhecido'
                : 'de ${contextTokens(s.capacity!)} · ',
            children: [
              if (s.percent != null)
                TextSpan(
                  text: '${s.percent}% ocupado',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          style: _label,
        ),
      ],
    );
  }
}

class _BigBar extends StatelessWidget {
  const _BigBar({required this.snapshot});

  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final cap = s.capacity;
    final t = s.threshold;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final tx = t != null && cap != null && t < cap ? w * t / cap : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 16,
              child: tx == null
                  ? null
                  : Stack(
                      children: [
                        Positioned(
                          left: (tx - 4).clamp(0, w - 140),
                          child: Text(
                            '┆ compacta em ${contextTokens(t!)}',
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: AppColors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            SizedBox(
              height: 16,
              child: CustomPaint(painter: ContextBarPainter(s, radius: 3)),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('0', style: _label),
                const Spacer(),
                Text(
                  cap == null
                      ? 'capacidade da janela · não informada'
                      : 'capacidade da janela · ${contextTokens(cap)}',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.snapshot});

  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final c = s.current;
    Widget tile(String label, String value, Widget icon, {Color? labelColor}) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: _label.copyWith(color: labelColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(value, style: _monoBig),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(
          'Ocupado',
          c == null ? '—' : contextTokens(c.tokens),
          Container(width: 9, height: 9, color: AppColors.amber),
        ),
        const SizedBox(width: 8),
        tile(
          'Livre',
          s.free == null ? '—' : contextTokens(s.free!),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        tile(
          'Até compactar',
          s.untilCompaction == null ? '—' : contextTokens(s.untilCompaction!),
          const Text(
            '┆',
            style: TextStyle(color: AppColors.teal, fontSize: 11),
          ),
          labelColor: AppColors.teal,
        ),
      ],
    );
  }
}

class _Composition extends StatelessWidget {
  const _Composition({required this.snapshot});

  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = snapshot.current;
    if (c == null) return const SizedBox.shrink();
    if (!c.hasComposition) {
      return const _Notice(
        title: 'Detalhamento indisponível',
        text:
            'O agente informou só o total. O ocupado fica numa cor só, sem '
            'fatias inventadas. A aba Fontes continua com as evidências do app.',
      );
    }
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11.5,
      color: AppColors.text,
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Entrada nova '),
          TextSpan(text: contextTokens(c.input), style: mono),
          const TextSpan(text: ' · escrita de cache '),
          TextSpan(text: contextTokens(c.cacheWrite), style: mono),
          const TextSpan(text: ' · leitura de cache '),
          TextSpan(text: contextTokens(c.cacheRead), style: mono),
          const TextSpan(text: ' · medidos na mesma chamada'),
        ],
      ),
      style: _label,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.borderHover),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber,
          size: 14,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              Text(text, style: _label),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AutocompactText extends StatelessWidget {
  const _AutocompactText({required this.snapshot});

  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final sent = s.configuredAutocompact;
    final text = sent == null
        ? 'Auto compactar: não informado para esta execução.'
        : 'Auto compactar: ${autocompactLabel(sent)} (--autocompact $sent)'
              '${s.threshold == null ? '' : ' · o agente compacta em ${contextTokens(s.threshold!)}'}.';
    return Text(text, style: _label);
  }
}

/// The Fontes tab (R4, R5): grouped evidence, keyboard focusable rows.
class ContextSourcesView extends StatelessWidget {
  const ContextSourcesView({
    super.key,
    required this.snapshot,
    required this.sources,
    this.onOpen,
    this.nextSend,
  });

  final ContextSnapshot snapshot;
  final ContextSources sources;
  final ValueChanged<ContextSource>? onOpen;
  final Widget? nextSend;

  @override
  Widget build(BuildContext context) {
    final groups = sources.grouped;
    final c = snapshot.current;
    final turn = sources.turn;
    final rows = <Widget>[
      Text.rich(
        TextSpan(
          text:
              'Evidências observadas pelo app. Não dizem o que o modelo usou '
              'no raciocínio.',
          children: [
            if (c != null) ...[
              const TextSpan(text: ' Total medido: '),
              TextSpan(
                text: contextTokens(c.tokens),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const TextSpan(text: ' · as fontes não somam a ele.'),
            ],
          ],
        ),
        style: _label,
      ),
      const SizedBox(height: 10),
    ];
    if (groups.isEmpty) {
      rows.add(
        const Text(
          'Nenhuma fonte observada ainda.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    for (final MapEntry(key: g, value: list) in groups.entries) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            '${g.label.toUpperCase()}  ${list.length}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .8,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
      for (final s in list) {
        rows.add(_SourceRow(source: s, turn: turn, onOpen: onOpen));
      }
    }
    if (nextSend != null) rows.addAll([const SizedBox(height: 10), nextSend!]);
    // Large histories: a lazy list (R12).
    return ListView.builder(
      key: const ValueKey('context-sources'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.turn, this.onOpen});

  final ContextSource source;
  final int turn;
  final ValueChanged<ContextSource>? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = source;
    final state = s.stateLabel(turn);
    final (color, dashed) = s.historical
        ? (AppColors.textMuted, true)
        : switch (s.evidence) {
            ContextEvidence.sent => (AppColors.teal, false),
            ContextEvidence.read ||
            ContextEvidence.edited => (AppColors.blue, false),
            ContextEvidence.agent => (AppColors.lilac, false),
          };
    final label = s.detail == null
        ? _short(s.label)
        : '${s.label} · ${s.detail}';
    final weight = s.method != null && s.tokens != null
        ? '${s.weightLabel} (${s.method})'
        : s.weightLabel;
    return Semantics(
      button: onOpen != null,
      label: '$label, $state, $weight',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('context-source-${s.label}'),
        onTap: onOpen == null ? null : () => onOpen!(s),
        borderRadius: BorderRadius.circular(6),
        focusColor: SessionColors.selectedBg,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: focused ? AppColors.amberLight : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(_icon(s), size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: color.withValues(alpha: dashed ? .35 : .55),
                      ),
                    ),
                    child: Text(
                      state,
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 112,
                    child: Tooltip(
                      message: s.method == null
                          ? weight
                          : 'Método: ${s.method}',
                      child: Text(
                        s.weightLabel,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static IconData _icon(ContextSource s) => switch (s.group) {
    ContextSourceGroup.instructions => Icons.info_outline,
    ContextSourceGroup.app =>
      s.ref == null ? Icons.chat_bubble_outline : Icons.description_outlined,
    ContextSourceGroup.files => Icons.insert_drive_file_outlined,
    ContextSourceGroup.attachments => Icons.image_outlined,
    ContextSourceGroup.tools => Icons.power_outlined,
  };

  /// `lib/features/x/y/z.dart` → `lib/…/z.dart`.
  static String _short(String path) {
    final parts = path.split('/');
    if (parts.length <= 3) return path;
    return '${parts.first}/…/${parts.last}';
  }
}
