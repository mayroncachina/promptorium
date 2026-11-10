import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../../core/providers/agent_provider.dart';
import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';

/// Below this window height the examples go away (SPEC-055 R9).
const welcomeCompactHeight = 760.0;

/// What each mode lets the agent do, for who does not program (SPEC-055 R7):
/// a sentence, a seal with text and icon (not colour alone) and two fixed
/// examples.
@immutable
class ModeIntro {
  const ModeIntro({
    required this.sentence,
    required this.seal,
    required this.sealIcon,
    required this.tone,
    required this.sealText,
    required this.examples,
  });

  final String sentence;
  final String seal;
  final AppIconData sealIcon;

  /// Colour of the seal's icon and background.
  final Color tone;

  /// Colour of the seal's text (4,5:1 or more on its background).
  final Color sealText;
  final List<String> examples;
}

/// Icons of the cards, from spec-055/Main.dc.html (20 grid).
abstract final class _WelcomeIcons {
  static final ask = AppIconData(
    [
      'M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14ZM8 8a2 2 0 1 1 2.8 1.9c-.5.2-.8.6-.8 1.1M10 13.6v.1',
    ],
    strokeWidth: 1.9,
    viewBox: 20,
  );
  static final plan = AppIconData(
    ['M4 5h12M4 10h8M4 15h5M14 13.5l1.8 1.8 3-3.6'],
    strokeWidth: 1.9,
    viewBox: 20,
  );
  static final edit = AppIconData(
    ['M4 16l1-4 8-8 3 3-8 8zM11 6l3 3'],
    strokeWidth: 1.9,
    viewBox: 20,
  );
  static final lock = AppIconData(
    ['M4 9V7a6 6 0 0 1 12 0v2M4 9h12v8H4z'],
    strokeWidth: 1.9,
    viewBox: 20,
  );
  static final approve = AppIconData(
    ['M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14ZM7 10l2 2 4-4'],
    strokeWidth: 1.9,
    viewBox: 20,
  );
  static final alert = AppIconData(
    ['M10 3l7 13H3zM10 8v4M10 14.2v.1'],
    strokeWidth: 1.9,
    viewBox: 20,
  );
}

AppIconData modeIcon(PromptMode mode) => switch (mode) {
  PromptMode.plan => _WelcomeIcons.plan,
  PromptMode.edit => _WelcomeIcons.edit,
  _ => _WelcomeIcons.ask,
};

/// The intro of each mode offered in the Prompt ([PromptMode.selectable]).
final modeIntros = <PromptMode, ModeIntro>{
  PromptMode.ask: ModeIntro(
    sentence:
        'Tire dúvidas sobre o projeto. O agente lê, explica e não mexe em '
        'nada.',
    seal: 'Nada muda nos arquivos',
    sealIcon: _WelcomeIcons.lock,
    tone: AppColors.teal,
    sealText: const Color(0xFF7BE3CC),
    examples: const ['O que esse projeto faz?', 'Onde fica a tela de login?'],
  ),
  PromptMode.plan: ModeIntro(
    sentence:
        'Descreva o que quer. O agente monta um plano e espera o seu ok antes '
        'de agir.',
    seal: 'Você aprova antes',
    sealIcon: _WelcomeIcons.approve,
    tone: AppColors.amber,
    sealText: const Color(0xFFFFC879),
    examples: const [
      'Como eu colocaria modo escuro?',
      'Quero um cupom de desconto',
    ],
  ),
  PromptMode.edit: ModeIntro(
    sentence: 'Peça a mudança e o agente faz direto na pasta do projeto.',
    seal: 'Altera os arquivos',
    sealIcon: _WelcomeIcons.alert,
    tone: const Color(0xFFFF9B85),
    sealText: const Color(0xFFFFB4A3),
    examples: const [
      'Troque o título da página inicial',
      'Deixe o botão Comprar verde',
    ],
  ),
};

/// The empty Prompt with a workspace (SPEC-055 R7): "Converse com o seu
/// projeto", one card per mode mirroring the mode switch of the composer, and
/// examples that fill the field without sending.
class PromptWelcome extends StatelessWidget {
  const PromptWelcome({
    super.key,
    required this.mode,
    required this.onPickMode,
    required this.onExample,
  });

  /// The mode of the composer: its card is the selected one.
  final PromptMode mode;
  final ValueChanged<PromptMode> onPickMode;

  /// Picks [PromptMode] and puts the text in the field (never sends).
  final void Function(PromptMode mode, String text) onExample;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < welcomeCompactHeight;
    return LayoutBuilder(
      builder: (context, box) {
        final pad = box.maxWidth < 720 ? 24.0 : 48.0;
        return SingleChildScrollView(
          key: const ValueKey('prompt-welcome'),
          padding: EdgeInsets.fromLTRB(pad, compact ? 24 : 40, pad, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Title(compact: compact),
                  SizedBox(height: compact ? 18 : 28),
                  _Cards(
                    mode: mode,
                    compact: compact,
                    onPickMode: onPickMode,
                    onExample: onExample,
                  ),
                  // Low window: the cards only, as in spec-055/Estreito.
                  if (!compact) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Clique num exemplo para começar com ele, ou escreva o '
                      'seu pedido. Dá para trocar o modo a qualquer momento.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final box = compact ? 44.0 : 56.0;
    return Row(
      children: [
        Container(
          width: box,
          height: box,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 13 : 16),
            gradient: LinearGradient(
              begin: const Alignment(-.35, -1),
              end: const Alignment(.35, 1),
              colors: [
                AppColors.amber.withValues(alpha: .28),
                AppColors.teal.withValues(alpha: .12),
              ],
            ),
            border: Border.all(color: AppColors.amber.withValues(alpha: .4)),
          ),
          child: AppIcon(
            AppIcons.prompt,
            key: const ValueKey('prompt-welcome-icon'),
            size: compact ? 24 : 30,
            color: AppColors.amber,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Converse com o seu projeto',
                  style: TextStyle(
                    fontSize: compact ? 20 : 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.2,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                const Text(
                  'Escreva como num chat. Escolha abaixo o quanto o agente '
                  'pode mexer.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The three cards: a row when the width allows, else they wrap (R9).
class _Cards extends StatelessWidget {
  const _Cards({
    required this.mode,
    required this.compact,
    required this.onPickMode,
    required this.onExample,
  });

  final PromptMode mode;
  final bool compact;
  final ValueChanged<PromptMode> onPickMode;
  final void Function(PromptMode mode, String text) onExample;

  static const _gap = 14.0;
  static const _minCard = 220.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const modes = PromptMode.selectable;
      var cols = modes.length;
      while (cols > 1 && (box.maxWidth - _gap * (cols - 1)) / cols < _minCard) {
        cols--;
      }
      final width = (box.maxWidth - _gap * (cols - 1)) / cols;
      final cards = [
        for (final m in modes)
          SizedBox(
            width: width,
            child: _ModeCard(
              mode: m,
              intro: modeIntros[m]!,
              selected: m == mode,
              compact: compact,
              onPick: () => onPickMode(m),
              onExample: (t) => onExample(m, t),
            ),
          ),
      ];
      return Semantics(
        key: const ValueKey('prompt-welcome-modes'),
        container: true,
        role: SemanticsRole.radioGroup,
        label: 'Modo da conversa',
        child: cols == modes.length
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, c) in cards.indexed) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      c,
                    ],
                  ],
                ),
              )
            : Wrap(spacing: _gap, runSpacing: _gap, children: cards),
      );
    },
  );
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.mode,
    required this.intro,
    required this.selected,
    required this.compact,
    required this.onPick,
    required this.onExample,
  });

  final PromptMode mode;
  final ModeIntro intro;
  final bool selected;
  final bool compact;
  final VoidCallback onPick;
  final ValueChanged<String> onExample;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final intro = widget.intro;
    final radius = BorderRadius.circular(14);
    final hover = AppMotion.duration(
      context,
      _hovered ? AppMotion.quick : AppMotion.quickExit,
    );
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${widget.mode.label} · ${intro.seal}',
      onTap: widget.onPick,
      child: AnimatedContainer(
        key: ValueKey('prompt-welcome-${widget.mode.name}'),
        duration: hover,
        curve: _hovered ? AppMotion.enter : AppMotion.exit,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.amber.withValues(alpha: .07)
              : _hovered
              ? AppColors.surfaceRaised
              : AppColors.panel,
          borderRadius: radius,
          // A shadow would show through the glass: the selected card gets a
          // stronger border instead (the width never changes the layout).
          border: Border.all(
            width: 1.5,
            color: selected
                ? AppColors.amber.withValues(alpha: .7)
                : _hovered
                ? AppColors.borderHover
                : Colors.white.withValues(alpha: .07),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: widget.onPick,
            onHover: (v) => setState(() => _hovered = v),
            borderRadius: radius,
            hoverColor: Colors.transparent,
            excludeFromSemantics: true,
            child: Padding(
              padding: const EdgeInsets.all(15.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: _header(intro)),
                  if (!widget.compact) ...[
                    const SizedBox(height: 12),
                    for (final (i, e) in intro.examples.indexed) ...[
                      if (i > 0) const SizedBox(height: 6),
                      _Example(
                        key: ValueKey('prompt-example-${widget.mode.name}-$i'),
                        text: e,
                        onTap: () => widget.onExample(e),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ModeIntro intro) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          AppIcon(modeIcon(widget.mode), size: 20, color: AppColors.amber),
          const SizedBox(width: 8),
          Text(
            widget.mode.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        intro.sentence,
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 10),
      Container(
        key: ValueKey('prompt-seal-${widget.mode.name}'),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: intro.tone.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(intro.sealIcon, size: 12, color: intro.tone),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                intro.seal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: intro.sealText,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// One example: a button that fills the field (R7, R10).
class _Example extends StatefulWidget {
  const _Example({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  State<_Example> createState() => _ExampleState();
}

class _ExampleState extends State<_Example> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(9);
    return Semantics(
      container: true,
      button: true,
      label: widget.text,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hovered = v),
          borderRadius: radius,
          child: AnimatedContainer(
            duration: AppMotion.duration(
              context,
              _hovered ? AppMotion.quick : AppMotion.quickExit,
            ),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x590A0C10),
              borderRadius: radius,
              border: Border.all(
                color: _hovered
                    ? AppColors.amber.withValues(alpha: .45)
                    : Colors.white.withValues(alpha: .08),
              ),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: '“',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(text: widget.text),
                  const TextSpan(
                    text: '”',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFC9CED8)),
            ),
          ),
        ),
      ),
    );
  }
}
