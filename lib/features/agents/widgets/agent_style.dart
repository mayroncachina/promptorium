import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';

/// Models of the editor (plano 0.2). `inherit` = "Herdar".
const agentModels = [
  ('opus', 'Opus'),
  ('sonnet', 'Sonnet'),
  ('haiku', 'Haiku'),
  ('fable', 'Fable'),
  ('inherit', 'Herdar'),
];

/// Tool pills of the mockup.
const agentToolPills = [
  'Read',
  'Edit',
  'Write',
  'Bash',
  'Glob',
  'Grep',
  'WebFetch',
  'WebSearch',
];

/// Permission modes of the editor with the mockup's hints.
const agentPermissionModes = [
  ('default', 'pergunta tudo'),
  ('acceptEdits', 'edita sem perguntar'),
  ('plan', 'só planeja'),
];

String agentModelLabel(String? model) {
  if (model == null || model == 'inherit') return 'Herdar';
  for (final (id, label) in agentModels) {
    if (id == model) return label;
  }
  return model;
}

/// Avatar color: the frontmatter `color` when it is a known name, else a
/// palette color picked from the name.
Color agentTint(String name, String? color) {
  switch (color?.toLowerCase()) {
    case 'red':
      return AppColors.red;
    case 'blue':
      return AppColors.blue;
    case 'green' || 'cyan':
      return AppColors.teal;
    case 'yellow' || 'orange':
      return AppColors.amber;
    case 'purple' || 'pink':
      return AppColors.lilac;
  }
  const palette = [
    AppColors.amber,
    AppColors.lilac,
    AppColors.blue,
    AppColors.teal,
    AppColors.red,
  ];
  final h = name.codeUnits.fold(0, (a, c) => (a * 31 + c) & 0x7fffffff);
  return palette[h % palette.length];
}

class AgentAvatar extends StatelessWidget {
  const AgentAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 28,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size / 4),
    ),
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: size * 0.42,
        fontWeight: FontWeight.w600,
        color: AppColors.background,
      ),
    ),
  );
}

/// Card of the editor (Identidade, Ferramentas, …).
class AgentCard extends StatelessWidget {
  const AgentCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.panel,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

/// On / off look of the mockup's toggles (amber when on).
class ToggleBox extends StatelessWidget {
  const ToggleBox({
    super.key,
    required this.on,
    required this.onTap,
    required this.child,
    this.height,
    this.radius = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
  });

  final bool on;
  final VoidCallback? onTap;
  final Widget child;
  final double? height;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Semantics(
      button: true,
      toggled: on,
      child: Material(
        color: on ? AppColors.amberTint : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: on ? AppColors.amber : AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          child: Container(
            height: height,
            padding: padding,
            alignment: height == null ? Alignment.centerLeft : Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Pill with mono text (tools, MCP servers).
class TogglePill extends StatelessWidget {
  const TogglePill({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ToggleBox(
    on: on,
    onTap: onTap,
    height: 30,
    radius: 15,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        color: on ? AppColors.amber : AppColors.textSecondary,
      ),
    ),
  );
}

InputDecoration agentFieldDecoration([String? hint]) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
  isDense: true,
  filled: true,
  fillColor: AppColors.background,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AppColors.border),
  ),
);

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    ),
  );
}

/// Confirmation dialog (excluir / mover). Returns true on confirm.
Future<bool> confirmAgentAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('agent-confirm'),
      backgroundColor: AppColors.panel,
      title: Text(title, style: const TextStyle(fontSize: 15)),
      content: Text(
        message,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: const ValueKey('agent-confirm-ok'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirm, style: const TextStyle(color: AppColors.amber)),
        ),
      ],
    ),
  );
  return ok ?? false;
}
