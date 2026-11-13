import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../../data/db/enums.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_pressable.dart';
import '../../sessions/widgets/session_style.dart';
import '../spec_file.dart' show plannedLabel, specStatusLabel;
import 'spec_action_banner.dart' show ActionSpinner;

/// Editor modes of the spec (SPEC-024 R2) and the prototype of the screens
/// (SPEC-022 R1).
enum SpecViewMode {
  edit('Editar', Icons.edit_outlined),
  split('Lado a lado', Icons.vertical_split_outlined),
  preview('Visualizar', Icons.visibility_outlined),
  prototype('Protótipo', Icons.dashboard_outlined);

  const SpecViewMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Weight of an action in the header (SPEC-024 R3–R7).
enum SpecActionEmphasis { primary, secondary, menu }

/// One action of the spec header: the UI only draws the list
/// [specHeaderActions] returns.
@immutable
class SpecAction {
  const SpecAction({
    required this.id,
    required this.keyName,
    required this.label,
    required this.icon,
    required this.emphasis,
    required this.tooltip,
    this.onTap,
    this.unavailableReason,
    this.destructive = false,
    this.busy = false,
    this.priority = 0,
  });

  /// Stable name (`refine`, `design`, `approve`, `clone`, `compare`,
  /// `generate`, `archive`, `delete`).
  final String id;

  /// Widget key (`spec-refine`, `proto-generate`…), kept from before
  /// SPEC-024 so tests and callers keep finding them.
  final String keyName;
  final String label;
  final IconData icon;
  final SpecActionEmphasis emphasis;

  /// What the action does (R10).
  final String tooltip;

  /// Null = unavailable: drawn disabled with [unavailableReason] (R10).
  final VoidCallback? onTap;
  final String? unavailableReason;

  /// "Excluir…": red, after a divider in the menu (R7).
  final bool destructive;

  /// The action is running: gerund label and progress (SPEC-025 R2).
  final bool busy;

  /// Without room, the secondaries of lower priority go to the menu first
  /// (SPEC-062 R1: "Refinar com IA" before "Planejar de novo").
  final int priority;

  bool get enabled => onTap != null;

  /// Tooltip shown: what it does, or why it is unavailable.
  String get tooltipText =>
      enabled ? tooltip : (unavailableReason ?? 'Indisponível no momento.');

  /// The same action in the "Mais ações" menu (R9: no room in the bar).
  SpecAction toMenu() => SpecAction(
    id: id,
    keyName: keyName,
    label: label,
    icon: icon,
    emphasis: SpecActionEmphasis.menu,
    tooltip: tooltip,
    onTap: onTap,
    unavailableReason: unavailableReason,
    destructive: destructive,
    busy: busy,
    priority: priority,
  );

  /// Unavailable while another action runs; [running] = the gerund label of
  /// this one when it is the one running (SPEC-025 R2).
  SpecAction blocked(String reason, {String? running}) => SpecAction(
    id: id,
    keyName: keyName,
    label: running ?? label,
    icon: icon,
    emphasis: emphasis,
    tooltip: tooltip,
    unavailableReason: running == null ? reason : 'Em andamento.',
    destructive: destructive,
    busy: running != null,
    priority: priority,
  );
}

/// What the header needs to decide its actions (SPEC-024 R3–R7).
@immutable
class SpecHeaderState {
  const SpecHeaderState({
    this.locked = false,
    this.approved = false,
    this.hasPlan = false,
    this.prototype = false,
    this.archived = false,
    this.onRefine,
    this.onDesign,
    this.onApprove,
    this.onClone,
    this.onCompare,
    this.onGenerate,
    this.onArchive,
    this.onDelete,
    this.onAnswer,
    this.unavailableReason,
    this.compareReason,
    this.generateReason,
    this.runningId,
    this.runningLabel,
  });

  /// The execution started (`stage != backlog`): only "Clonar para alterar".
  final bool locked;

  /// `status: aprovada`: no "Aprovar" (R4).
  final bool approved;

  /// The spec has a plan: "Planejar de novo" (SPEC-037 R1).
  final bool hasPlan;

  /// Protótipo mode (R6).
  final bool prototype;

  /// Archived spec: "Desarquivar".
  final bool archived;

  final VoidCallback? onRefine;
  final VoidCallback? onDesign;
  final VoidCallback? onApprove;
  final VoidCallback? onClone;
  final VoidCallback? onCompare;
  final VoidCallback? onGenerate;

  /// Null = not available: the menu item does not appear (R7).
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;

  /// "Responder perguntas" in "Mais ações" (SPEC-028 R6); null = the spec
  /// has no open questions (the item does not appear).
  final VoidCallback? onAnswer;

  /// Why refine/design/approve/clone are disabled (loading, busy).
  final String? unavailableReason;
  final String? compareReason;
  final String? generateReason;

  /// [SpecAction.id] of the action in progress (SPEC-025 R2): it shows
  /// [runningLabel] with progress; the others and the menu are disabled.
  final String? runningId;
  final String? runningLabel;

  bool get running => runningId != null;
}

/// Why the actions are disabled while one runs (SPEC-025 R2).
const runningReason = 'Aguarde a ação em andamento terminar.';

const refineTooltip =
    'Abre uma conversa com a IA para escrever objetivo, requisitos e '
    'critérios a partir do que você já tem.';
const designTooltip =
    'Escreve o plano de implementação a partir do código atual';
const approveTooltip = 'Marca a spec como pronta para virar etapas no Quadro.';
const answerTooltip =
    'Responde as perguntas em aberto uma por vez, com opções, e revisa o que '
    'muda na spec antes de salvar.';
const cloneTooltip =
    'A execução já começou; crie uma cópia em rascunho para mudar.';

/// Ordered actions of the header for [s] (SPEC-024 R3–R7): the bar ones
/// first (secondary, then the primary), then the "Mais ações" items. While
/// an action runs, all of them are unavailable and the running one carries
/// its gerund label (SPEC-025 R2).
List<SpecAction> specHeaderActions(SpecHeaderState s) {
  final all = _specHeaderActions(s);
  if (!s.running) return all;
  return [
    for (final a in all)
      a.blocked(
        runningReason,
        running: a.id == s.runningId ? s.runningLabel ?? a.label : null,
      ),
  ];
}

List<SpecAction> _specHeaderActions(SpecHeaderState s) {
  final why = s.unavailableReason ?? 'Aguarde a spec carregar.';
  final menu = <SpecAction>[
    if (s.onArchive != null)
      SpecAction(
        id: 'archive',
        keyName: 'spec-archive',
        label: s.archived ? 'Desarquivar' : 'Arquivar',
        icon: s.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
        emphasis: SpecActionEmphasis.menu,
        tooltip: s.archived
            ? 'Volta a mostrar a spec na lista.'
            : 'Tira a spec concluída da lista; o arquivo continua no '
                  'projeto.',
        onTap: s.onArchive,
      ),
    if (s.onDelete != null)
      SpecAction(
        id: 'delete',
        keyName: 'spec-delete',
        label: 'Excluir…',
        icon: Icons.delete_outline,
        emphasis: SpecActionEmphasis.menu,
        tooltip: 'Manda o arquivo da spec para a lixeira (pede confirmação).',
        onTap: s.onDelete,
        destructive: true,
      ),
  ];
  if (s.prototype) {
    return [
      SpecAction(
        id: 'compare',
        keyName: 'proto-compare',
        label: 'Comparar variações',
        icon: Icons.compare_arrows,
        emphasis: SpecActionEmphasis.secondary,
        tooltip: 'Mostra lado a lado as variações do requisito selecionado.',
        onTap: s.onCompare,
        unavailableReason:
            s.compareReason ??
            'Gere duas ou mais variações de um requisito para comparar.',
      ),
      SpecAction(
        id: 'generate',
        keyName: 'proto-generate',
        label: 'Gerar telas da spec',
        icon: Icons.layers_outlined,
        emphasis: SpecActionEmphasis.primary,
        tooltip: 'Pede ao Claude as telas dos requisitos da spec.',
        onTap: s.onGenerate,
        unavailableReason: s.generateReason ?? why,
      ),
      ...menu,
    ];
  }
  if (s.locked) {
    return [
      SpecAction(
        id: 'clone',
        keyName: 'spec-clone',
        label: 'Clonar para alterar',
        icon: Icons.content_copy_outlined,
        emphasis: SpecActionEmphasis.primary,
        tooltip: cloneTooltip,
        onTap: s.onClone,
        unavailableReason: why,
      ),
      ...menu,
    ];
  }
  return [
    SpecAction(
      id: 'refine',
      keyName: 'spec-refine',
      label: 'Refinar com IA',
      icon: Icons.auto_awesome_outlined,
      emphasis: SpecActionEmphasis.secondary,
      tooltip: refineTooltip,
      onTap: s.onRefine,
      unavailableReason: why,
      priority: -1,
    ),
    SpecAction(
      id: 'design',
      keyName: 'spec-design',
      label: s.hasPlan ? 'Planejar de novo' : 'Planejar',
      icon: Icons.checklist,
      // SPEC-039 R7: without a Plano, planning comes before approving.
      emphasis: s.hasPlan
          ? SpecActionEmphasis.secondary
          : SpecActionEmphasis.primary,
      tooltip: designTooltip,
      onTap: s.onDesign,
      unavailableReason: why,
    ),
    if (!s.approved)
      SpecAction(
        id: 'approve',
        keyName: 'spec-approve',
        label: 'Aprovar',
        icon: Icons.check,
        emphasis: s.hasPlan
            ? SpecActionEmphasis.primary
            : SpecActionEmphasis.secondary,
        tooltip: approveTooltip,
        onTap: s.onApprove,
        unavailableReason: why,
      ),
    if (s.onAnswer != null)
      SpecAction(
        id: 'answer',
        keyName: 'spec-answer-questions',
        label: 'Responder perguntas',
        icon: Icons.help_outline,
        emphasis: SpecActionEmphasis.menu,
        tooltip: answerTooltip,
        onTap: s.onAnswer,
      ),
    ...menu,
  ];
}

/// How many of the secondary actions, in order, fit in [available] pixels
/// ([widths] = natural width of each one, its gap included). The ones left
/// out go to "Mais ações" from the last one back (R9: "Planejar", then
/// "Refinar com IA"); the primary never enters this list.
int fitActions(List<double> widths, double available) {
  var used = 0.0;
  for (var i = 0; i < widths.length; i++) {
    used += widths[i];
    if (used > available) return i;
  }
  return widths.length;
}

/// Splits [actions] between the bar and the menu for [available] pixels
/// (R9): the primary always stays; secondaries that do not fit go to the
/// top of the menu.
({List<SpecAction> bar, List<SpecAction> menu}) layoutSpecActions(
  List<SpecAction> actions,
  double Function(SpecAction) widthOf,
  double available, {
  double gap = _gap,
  double moreWidth = _moreSize,
}) {
  final secondary = [
    for (final a in actions)
      if (a.emphasis == SpecActionEmphasis.secondary) a,
  ];
  final primary = [
    for (final a in actions)
      if (a.emphasis == SpecActionEmphasis.primary) a,
  ];
  final menu = [
    for (final a in actions)
      if (a.emphasis == SpecActionEmphasis.menu) a,
  ];
  // SPEC-062 R1: the ones that stay are picked by priority (stable), and
  // keep their order in the bar.
  final ranked = [...secondary]
    ..sort((a, b) => b.priority.compareTo(a.priority));
  final widths = [for (final a in ranked) widthOf(a) + gap];
  var room = available;
  for (final a in primary) {
    room -= widthOf(a) + gap;
  }
  if (menu.isNotEmpty) room -= moreWidth + gap;
  var kept = fitActions(widths, room);
  if (kept < ranked.length && menu.isEmpty) {
    kept = fitActions(widths, room - moreWidth - gap);
  }
  final shown = {...ranked.take(kept), ...primary};
  return (
    bar: [
      for (final a in actions)
        if (shown.contains(a)) a,
    ],
    menu: [
      for (final a in secondary)
        if (!shown.contains(a)) a.toMenu(),
      ...menu,
    ],
  );
}

const _gap = 8.0;
const _moreSize = 34.0;
const _buttonHeight = 34.0;
const _buttonPad = 12.0;
const _iconGap = 7.0;
const _actionFont = 13.0;

/// Natural width of [text] with the inherited font.
double _textWidth(BuildContext context, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w.ceilToDouble();
}

double _actionWidth(BuildContext context, SpecAction a) =>
    _buttonPad * 2 +
    2 +
    16 +
    _iconGap +
    _textWidth(
      context,
      a.label,
      TextStyle(
        fontSize: _actionFont,
        fontWeight: a.emphasis == SpecActionEmphasis.primary
            ? FontWeight.w600
            : FontWeight.w400,
      ),
    ) +
    1;

/// Header of the open spec (SPEC-024 R1): identity and actions on the first
/// line; mode tabs, save state and zoom on the second.
class SpecHeader extends StatelessWidget {
  const SpecHeader({
    super.key,
    required this.title,
    this.path,
    this.status,
    this.locked = false,
    this.actions,
    this.mode,
    this.onMode,
    this.showSaveState = false,
    this.dirty = false,
    this.onSave,
    this.zoom,
    this.lockLabel,
    this.statusLabel,
    this.lockAlert = false,
    this.planned = false,
  });

  final String title;
  final String? path;

  /// Status of the badge; null = no badge.
  final SpecStatus? status;
  final bool locked;

  /// Null = no action bar (no spec open).
  final SpecHeaderState? actions;

  /// Null = no tabs line.
  final SpecViewMode? mode;
  final ValueChanged<SpecViewMode>? onMode;
  final bool showSaveState;
  final bool dirty;
  final VoidCallback? onSave;
  final Widget? zoom;

  /// An action holds the spec (SPEC-025 R6): replaces the save state with
  /// "Somente leitura enquanto aprova"; [lockAlert] = amber (long action).
  final String? lockLabel;

  /// Takes the place of the status next to the title (SPEC-037 R10).
  final String? statusLabel;
  final bool lockAlert;

  /// The editor's text has a `## Plano` and the spec is not approved:
  /// "Planejada" (SPEC-062 R3).
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (path != null)
          Text(
            path!,
            key: const ValueKey('spec-path'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        const SizedBox(height: 3),
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                key: const ValueKey('spec-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: 10),
              StatusBadge(
                status: status!,
                locked: locked,
                label: statusLabel,
                planned: planned,
              ),
            ],
          ],
        ),
      ],
    );
    final hasTabs = mode != null && onMode != null;
    final top = LayoutBuilder(
      builder: (context, c) {
        if (actions == null) {
          // No spec open: no actions; without the tabs line the zoom stays
          // on this one.
          return Row(
            children: [
              Expanded(child: identity),
              if (zoom != null && !hasTabs) ...[
                const SizedBox(width: 16),
                zoom!,
              ],
            ],
          );
        }
        const identityMin = 160.0;
        final split = layoutSpecActions(
          specHeaderActions(actions!),
          (a) => _actionWidth(context, a),
          c.maxWidth - identityMin - 16 + _gap,
        );
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 16),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: FocusTraversalGroup(
                child: Semantics(
                  container: true,
                  label: 'Ações da spec',
                  explicitChildNodes: true,
                  child: Row(
                    key: const ValueKey('spec-actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, a) in split.bar.indexed) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        SpecActionButton(action: a),
                      ],
                      if (split.menu.isNotEmpty) ...[
                        if (split.bar.isNotEmpty) const SizedBox(width: _gap),
                        SpecMoreButton(
                          items: split.menu,
                          enabled: !actions!.running,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    final saveState = showSaveState || lockLabel != null
        ? SaveState(
            dirty: dirty,
            locked: locked,
            onSave: onSave,
            lockLabel: lockLabel,
            lockAlert: lockAlert,
          )
        : null;
    final bottom = !hasTabs
        ? null
        : LayoutBuilder(
            builder: (context, c) {
              final trailing = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (saveState != null)
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: FocusTraversalGroup(child: saveState),
                    ),
                  if (saveState != null && zoom != null)
                    const SizedBox(width: 12),
                  if (zoom != null)
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: FocusTraversalGroup(child: zoom!),
                    ),
                ],
              );
              final trailingW =
                  (saveState == null ? 0 : saveState.naturalWidth(context)) +
                  (saveState != null && zoom != null ? 12 : 0) +
                  (zoom == null ? 0 : 100);
              final full = SpecModeTabs.naturalWidth(context, icons: true);
              final compact = SpecModeTabs.naturalWidth(context, icons: false);
              final icons = full + 16 + trailingW <= c.maxWidth;
              final oneLine = icons || compact + 16 + trailingW <= c.maxWidth;
              Widget tabs = FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: FocusTraversalGroup(
                  child: SpecModeTabs(
                    mode: mode!,
                    onMode: onMode!,
                    icons: icons,
                  ),
                ),
              );
              if (oneLine) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    tabs,
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: trailing,
                    ),
                  ],
                );
              }
              // Too narrow even without icons: the save state and the zoom
              // get their own line and the tabs scroll instead of cutting
              // a label (R9).
              if (compact > c.maxWidth) {
                tabs = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: tabs,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(alignment: Alignment.centerRight, child: trailing),
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerLeft, child: tabs),
                ],
              );
            },
          );
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottom == null ? 12 : 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            top,
            if (bottom != null) ...[const SizedBox(height: 10), bottom],
          ],
        ),
      ),
    );
  }
}

/// Status of the spec next to the title, with the texts of the list (R1);
/// a lock when the execution started (R5).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.locked = false,
    this.label,
    this.planned = false,
  });

  final SpecStatus status;
  final bool locked;

  /// "Planejada" in yellow (SPEC-062 R3).
  final bool planned;

  /// Takes the place of the status: "Na fila" (SPEC-037 R10).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final queued = label != null;
    final approved = status == SpecStatus.approved && !queued;
    final plan = planned && !queued && !approved;
    final color = queued
        ? AppColors.amber
        : approved
        ? AppColors.teal
        : plan
        ? AppColors.yellow
        : AppColors.textSecondary;
    final icon = locked
        ? Icons.lock_outline
        : approved
        ? Icons.check
        : null;
    return Container(
      key: const ValueKey('spec-status'),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: queued
            ? SessionColors.approvalBg
            : approved
            ? SessionColors.runningToolBg
            : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: queued
              ? SessionColors.approvalBorder
              : approved
              ? SessionColors.runningToolBorder
              : plan
              ? AppColors.yellow.withValues(alpha: .45)
              : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              key: ValueKey(locked ? 'spec-status-lock' : 'spec-status-icon'),
              size: 12,
              color: color,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label ?? (plan ? plannedLabel : specStatusLabel(status)),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Focus ring of the header controls (R11): amber tint and a 2 px outline.
mixin _FocusRing<T extends StatefulWidget> on State<T> {
  bool focused = false;

  void onFocus(bool f) {
    if (f != focused) setState(() => focused = f);
  }
}

/// Button of the action bar: secondary (panel) or primary (amber), with
/// icon, full label and tooltip (R3, R9, R10, R11).
class SpecActionButton extends StatefulWidget {
  SpecActionButton({required this.action})
    : super(key: ValueKey(action.keyName));

  final SpecAction action;

  VoidCallback? get onTap => action.onTap;

  @override
  State<SpecActionButton> createState() => _SpecActionButtonState();
}

class _SpecActionButtonState extends State<SpecActionButton>
    with _FocusRing<SpecActionButton> {
  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final primary = a.emphasis == SpecActionEmphasis.primary;
    final enabled = a.enabled;
    final busy = a.busy;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Disabled: legible text on a raised surface, no opacity (R10,
    // SPEC-025 R10). Running: amber tint, the gerund label (SPEC-025 R2).
    final fg = busy
        ? AppColors.text
        : !enabled
        ? AppColors.textDisabled
        : primary
        ? AppColors.onAmber
        : AppColors.text;
    final bg = busy
        ? AppColors.amberTint
        : !enabled
        ? AppColors.surfaceRaised
        : primary
        ? AppColors.amber
        : AppColors.panel;
    final side = focused
        ? const BorderSide(color: AppColors.amber, width: 2)
        : BorderSide(
            color: busy
                ? SessionColors.approvalBorder
                : enabled && primary
                ? AppColors.amber
                : AppColors.border,
          );
    final radius = BorderRadius.circular(6);
    return Tooltip(
      message: a.tooltipText,
      waitDuration: const Duration(milliseconds: 500),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          enabled: enabled,
          label: a.label,
          child: AppPressable(
            enabled: enabled,
            borderRadius: radius,
            hoverTint: Colors.white.withValues(alpha: .12),
            child: Material(
              color: bg,
              animationDuration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              shape: RoundedRectangleBorder(borderRadius: radius, side: side),
              child: InkWell(
                onTap: a.onTap,
                onFocusChange: onFocus,
                borderRadius: radius,
                focusColor: (primary ? AppColors.onAmber : AppColors.amber)
                    .withValues(alpha: .25),
                hoverColor: Colors.transparent,
                highlightColor: Colors.black.withValues(alpha: .12),
                splashFactory: reduced ? NoSplash.splashFactory : null,
                child: Container(
                  height: _buttonHeight,
                  padding: const EdgeInsets.symmetric(horizontal: _buttonPad),
                  alignment: Alignment.center,
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (busy)
                          DelayedProgress(
                            key: const ValueKey('spec-action-progress'),
                            placeholder: Icon(a.icon, size: 16, color: fg),
                          )
                        else
                          Icon(a.icon, size: 16, color: fg),
                        const SizedBox(width: _iconGap),
                        Text(
                          a.label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: _actionFont,
                            fontWeight: primary ? FontWeight.w600 : null,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Progress of a running action (SPEC-025 R2, R6, R11): [placeholder] for
/// the first [delay] (a short action does not flash a spinner), then a 14 px
/// spinner, or a still icon with reduced motion.
class DelayedProgress extends StatefulWidget {
  const DelayedProgress({
    super.key,
    required this.placeholder,
    this.delay = const Duration(milliseconds: 300),
  });

  final Widget placeholder;
  final Duration delay;

  @override
  State<DelayedProgress> createState() => _DelayedProgressState();
}

class _DelayedProgressState extends State<DelayedProgress> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: Center(
      child: _shown
          ? const ActionSpinner(size: 14, color: AppColors.amber)
          : widget.placeholder,
    ),
  );
}

/// "Mais ações" (R7, R11): icon button with a menu; arrows move, Esc closes
/// and gives the focus back to the button.
class SpecMoreButton extends StatefulWidget {
  const SpecMoreButton({super.key, required this.items, this.enabled = true});

  final List<SpecAction> items;

  /// False while an action runs (SPEC-025 R2): drawn like the disabled
  /// actions, no menu.
  final bool enabled;

  @override
  State<SpecMoreButton> createState() => _SpecMoreButtonState();
}

class _SpecMoreButtonState extends State<SpecMoreButton>
    with _FocusRing<SpecMoreButton> {
  final _focus = FocusNode(debugLabel: 'spec-more');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Widget _item(SpecAction a) {
    final color = !a.enabled
        ? AppColors.textDisabled
        : a.destructive
        ? AppColors.red
        : AppColors.text;
    return Tooltip(
      message: a.tooltipText,
      waitDuration: const Duration(milliseconds: 500),
      child: MenuItemButton(
        key: ValueKey(a.keyName),
        onPressed: a.onTap,
        leadingIcon: Icon(a.icon, size: 16, color: color),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(180, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          foregroundColor: WidgetStatePropertyAll(color),
          overlayColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused)
                ? AppColors.amber.withValues(alpha: .25)
                : s.contains(WidgetState.hovered)
                ? SessionColors.selectedBg
                : null,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused)
                ? const BorderSide(color: AppColors.amber, width: 2)
                : BorderSide.none,
          ),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        ),
        child: Text(a.label, maxLines: 1, softWrap: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final rest = [
      for (final a in items)
        if (!a.destructive) a,
    ];
    final danger = [
      for (final a in items)
        if (a.destructive) a,
    ];
    final radius = BorderRadius.circular(6);
    return MenuAnchor(
      childFocusNode: _focus,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.panelSolid),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      menuChildren: [
        for (final a in rest) _item(a),
        if (rest.isNotEmpty && danger.isNotEmpty)
          const Divider(
            key: ValueKey('spec-more-divider'),
            height: 9,
            color: AppColors.border,
          ),
        for (final a in danger) _item(a),
      ],
      builder: (context, controller, _) => Tooltip(
        message: widget.enabled ? 'Mais ações' : runningReason,
        waitDuration: const Duration(milliseconds: 500),
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          label: 'Mais ações da spec',
          expanded: controller.isOpen,
          child: Material(
            color: widget.enabled ? AppColors.panel : AppColors.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: focused
                  ? const BorderSide(color: AppColors.amber, width: 2)
                  : const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              key: const ValueKey('spec-more'),
              focusNode: _focus,
              onFocusChange: onFocus,
              borderRadius: radius,
              focusColor: AppColors.amber.withValues(alpha: .25),
              hoverColor: Colors.white.withValues(alpha: .12),
              onTap: widget.enabled
                  ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                  : null,
              child: SizedBox(
                width: _moreSize,
                height: _buttonHeight,
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: widget.enabled
                        ? AppColors.text
                        : AppColors.textDisabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mode tabs (R2): icon + label, the active one underlined in amber.
class SpecModeTabs extends StatelessWidget {
  const SpecModeTabs({
    super.key,
    required this.mode,
    required this.onMode,
    this.icons = true,
  });

  final SpecViewMode mode;
  final ValueChanged<SpecViewMode> onMode;

  /// Narrow header: labels only, less padding (R9).
  final bool icons;

  static double _pad(bool icons) => icons ? 12 : 10;

  /// Natural width of the tabs (labels measured in the bold weight, so the
  /// active one never grows past it).
  static double naturalWidth(BuildContext context, {required bool icons}) {
    var w = 0.0;
    for (final m in SpecViewMode.values) {
      w +=
          _pad(icons) * 2 +
          (icons ? 16 + _iconGap : 0) +
          _textWidth(
            context,
            m.label,
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ) +
          2 +
          1;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    role: SemanticsRole.tabBar,
    explicitChildNodes: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final m in SpecViewMode.values) ...[
          _ModeTab(
            mode: m,
            selected: m == mode,
            icons: icons,
            pad: _pad(icons),
            onTap: () => onMode(m),
          ),
          const SizedBox(width: 2),
        ],
      ],
    ),
  );
}

class _ModeTab extends StatefulWidget {
  const _ModeTab({
    required this.mode,
    required this.selected,
    required this.icons,
    required this.pad,
    required this.onTap,
  });

  final SpecViewMode mode;
  final bool selected;
  final bool icons;
  final double pad;
  final VoidCallback onTap;

  @override
  State<_ModeTab> createState() => _ModeTabState();
}

class _ModeTabState extends State<_ModeTab> with _FocusRing<_ModeTab> {
  @override
  Widget build(BuildContext context) {
    final m = widget.mode;
    final sel = widget.selected;
    final color = sel ? AppColors.text : AppColors.textSecondary;
    return Semantics(
      role: SemanticsRole.tab,
      selected: sel,
      label: 'Modo ${m.label}',
      child: InkWell(
        key: ValueKey('spec-mode-${m.name}'),
        onTap: widget.onTap,
        onFocusChange: onFocus,
        borderRadius: BorderRadius.circular(4),
        focusColor: AppColors.amber.withValues(alpha: .25),
        hoverColor: Colors.white.withValues(alpha: .06),
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: widget.pad),
          decoration: BoxDecoration(
            border: focused
                ? Border.all(color: AppColors.amber, width: 2)
                : Border(
                    bottom: BorderSide(
                      color: sel ? AppColors.amber : Colors.transparent,
                      width: 2,
                    ),
                  ),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icons) ...[
                  Icon(m.icon, size: 16, color: color),
                  const SizedBox(width: _iconGap),
                ],
                Text(
                  m.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: color,
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

/// Save state of the tabs line (R5, R8): "● Não salvo" + "Salvar Ctrl+S",
/// "Salvo", or "Somente leitura".
class SaveState extends StatelessWidget {
  const SaveState({
    super.key,
    required this.dirty,
    this.locked = false,
    this.onSave,
    this.lockLabel,
    this.lockAlert = false,
  });

  final bool dirty;
  final bool locked;
  final VoidCallback? onSave;

  /// An action in progress holds the spec (SPEC-025 R6).
  final String? lockLabel;
  final bool lockAlert;

  static const _style = TextStyle(fontSize: 12, color: AppColors.textSecondary);

  /// Natural width, to decide the layout of the tabs line (R9).
  double naturalWidth(BuildContext context) {
    if (lockLabel != null) {
      return 14 + 5 + _textWidth(context, lockLabel!, _style) + 1;
    }
    if (locked) {
      return 14 + 5 + _textWidth(context, 'Somente leitura', _style) + 1;
    }
    if (!dirty) return 14 + 5 + _textWidth(context, 'Salvo', _style) + 1;
    return 6 +
        6 +
        _textWidth(context, 'Não salvo', _style) +
        10 +
        // Salvar button: padding, icon, label, Kbd.
        20 +
        2 +
        14 +
        6 +
        _textWidth(context, 'Salvar', const TextStyle(fontSize: 13)) +
        8 +
        Kbd.naturalWidth(context, 'Ctrl+S') +
        2;
  }

  @override
  Widget build(BuildContext context) {
    if (lockLabel != null) {
      final color = lockAlert ? AppColors.amber : AppColors.textSecondary;
      return Row(
        key: const ValueKey('spec-save-state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            lockLabel!,
            key: const ValueKey('spec-action-lock'),
            maxLines: 1,
            softWrap: false,
            style: _style.copyWith(color: color),
          ),
        ],
      );
    }
    if (locked || !dirty) {
      return Row(
        key: const ValueKey('spec-save-state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked ? Icons.lock_outline : Icons.check,
            size: 14,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            locked ? 'Somente leitura' : 'Salvo',
            key: ValueKey(locked ? 'spec-readonly' : 'spec-saved'),
            maxLines: 1,
            softWrap: false,
            style: _style,
          ),
        ],
      );
    }
    return Row(
      key: const ValueKey('spec-save-state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.amber,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'Não salvo',
          key: ValueKey('spec-unsaved'),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(fontSize: 12, color: AppColors.amber),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: 'Grava as alterações no arquivo da spec (Ctrl+S).',
          waitDuration: const Duration(milliseconds: 500),
          child: SmallButton(
            key: const ValueKey('spec-save'),
            label: 'Salvar',
            semanticLabel: 'Salvar (Ctrl+S)',
            icon: Icons.check,
            trailing: const Kbd('Ctrl+S'),
            height: 30,
            fontSize: 13,
            // Unsaved work is the next thing to do: the button says so
            // (after "Planejar" the Plano lives only in the editor).
            color: AppColors.amber,
            border: AppColors.amber.withValues(alpha: .55),
            background: AppColors.amber.withValues(alpha: .12),
            fontWeight: FontWeight.w600,
            focusColor: AppColors.amber.withValues(alpha: .25),
            onTap: onSave,
          ),
        ),
      ],
    );
  }
}

/// Keyboard shortcut chip (`Ctrl+S`).
class Kbd extends StatelessWidget {
  const Kbd(this.keys, {super.key});

  final String keys;

  static const _style = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 11,
    color: AppColors.textSecondary,
  );

  static double naturalWidth(BuildContext context, String keys) =>
      _textWidth(context, keys, _style) + 10 + 2;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(keys, maxLines: 1, softWrap: false, style: _style),
  );
}
