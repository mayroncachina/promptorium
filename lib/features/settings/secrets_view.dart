import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/managed_hooks.dart';
import '../../core/codex/codex_hooks.dart';
import '../../core/secrets/gitleaks.dart';
import '../../core/secrets/secret_guard.dart';
import '../../core/secrets/secret_rules.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../agents/widgets/agent_style.dart';
import '../project/project_config.dart';
import '../sessions/session_manager.dart';

/// gitleaks found on this machine (R13); null = not installed.
final gitleaksVersionProvider = FutureProvider<String?>(
  (ref) => ref.read(secretGuardProvider).installedGitleaks(),
);

/// The waivers of a workspace (R12).
final secretWaiversProvider = StreamProvider.family<List<SecretWaiver>, int>(
  (ref, ws) => ref.watch(secretWaiversRepoProvider).watch(ws),
);

/// "Remover" date of a waiver: "hoje", "3 nov.".
String waiverDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (d.year == n.year && d.month == n.month && d.day == n.day) return 'hoje';
  const months = [
    'jan.',
    'fev.',
    'mar.',
    'abr.',
    'maio',
    'jun.',
    'jul.',
    'ago.',
    'set.',
    'out.',
    'nov.',
    'dez.',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// Configurações › Vigia de segredos (SPEC-085 R12–R15).
class SecretsSettingsView extends ConsumerStatefulWidget {
  const SecretsSettingsView({super.key});

  @override
  ConsumerState<SecretsSettingsView> createState() =>
      _SecretsSettingsViewState();
}

class _SecretsSettingsViewState extends ConsumerState<SecretsSettingsView> {
  final _paths = TextEditingController();
  String? _loadedFor;

  @override
  void dispose() {
    _paths.dispose();
    super.dispose();
  }

  Future<void> _set(String key, bool on) =>
      ref.read(appSettingsProvider.notifier).set(key, on ? '1' : '0');

  Future<void> _toggleAll(bool on) async {
    if (!on) {
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Desligar o Vigia de segredos?'),
          content: const Text(
            'Commits, pushes e PRs do agente, do app e da tela Código deixam '
            'de ser conferidos. Fica registrado na timeline das sessões '
            'abertas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('secrets-off-confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Desligar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _set(SecretSettingKeys.enabled, on);
    final manager = ref.read(sessionManagerProvider.notifier);
    for (final id in ref.read(sessionManagerProvider).live.keys) {
      await manager.note(
        id,
        on
            ? 'Vigia de segredos ligado nas Configurações (vale a partir da '
                  'próxima sessão iniciada ou retomada)'
            : 'Vigia de segredos desligado nas Configurações',
        error: !on,
      );
    }
  }

  Future<void> _savePaths(Workspace ws) async {
    final globs = [
      for (final p in _paths.text.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    final config = ProjectConfig.loadSync(ws.path);
    if (config.secretIgnore.join(',') == globs.join(',')) return;
    await ProjectConfig.save(ws.path, config.copyWith(secretIgnore: globs));
    ref.invalidate(projectConfigProvider(ws.path));
    await ref.read(sessionManagerProvider.notifier).refreshSecrets(ws.id);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final p = SecretPrefs.of(settings);
    final ws = ref.watch(activeWorkspaceProvider);
    final version = ref.watch(gitleaksVersionProvider).value;
    final supported = gitleaksSupported(version);
    if (ws != null && _loadedFor != ws.path) {
      _loadedFor = ws.path;
      _paths.text = ProjectConfig.loadSync(ws.path).secretIgnore.join(', ');
    }
    final waivers = ws == null
        ? const <SecretWaiver>[]
        : ref.watch(secretWaiversProvider(ws.id)).value ?? const [];

    Widget sw(
      String key,
      String title,
      String sub,
      bool value,
      ValueChanged<bool>? onChanged,
    ) => Material(
      color: Colors.transparent,
      child: SwitchListTile(
        key: ValueKey(key),
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          sub,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentCard(
          title: 'Vigia de segredos',
          trailing: Switch(
            key: const ValueKey('secrets-enabled'),
            value: p.enabled,
            onChanged: _toggleAll,
          ),
          children: [
            const Text(
              'MOTOR',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(
                  Icons.radio_button_checked,
                  size: 16,
                  color: AppColors.amber,
                ),
                SizedBox(width: 8),
                Text('Regras do Promptorium', style: TextStyle(fontSize: 13)),
                SizedBox(width: 8),
                Text(
                  'sempre disponíveis',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                key: const ValueKey('secrets-gitleaks'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: p.gitleaks && supported,
                onChanged: supported && p.enabled
                    ? (v) => _set(SecretSettingKeys.gitleaks, v ?? false)
                    : null,
                title: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Usar também o gitleaks  '),
                      TextSpan(
                        text: version == null
                            ? 'não encontrado'
                            : supported
                            ? '$version encontrado'
                            : '$version (precisa da 8.18 ou mais nova)',
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11.5,
                          color: supported
                              ? AppColors.teal
                              : AppColors.textMuted,
                        ),
                      ),
                      const TextSpan(
                        text: '  · sempre com --redact',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const Divider(height: 20),
            const Text(
              'ONDE VALE',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            sw(
              'secrets-agent',
              'Commits, push e PR do agente',
              secretsAgentWhere(
                python: ref.watch(pythonAvailableProvider).value,
                latest: latestCodexHookStatus(
                  ref.watch(codexHookStatusProvider),
                ),
                last: ref.watch(hookActivityProvider)[ManagedHook.secrets],
              ),
              p.enabled,
              null,
            ),
            sw(
              'secrets-app',
              'Commits e pushes do app',
              'Criar PR, arquivos restantes da etapa, VIBE, Corrigir CI',
              p.enabled && p.app,
              p.enabled ? (v) => _set(SecretSettingKeys.app, v) : null,
            ),
            sw(
              'secrets-manual',
              'Commit manual na tela Código',
              'Com “Commitar mesmo assim…” no lugar de Ignorar',
              p.enabled && p.manual,
              p.enabled ? (v) => _set(SecretSettingKeys.manual, v) : null,
            ),
            if (ws != null) ...[
              const Divider(height: 20),
              Text(
                'CAMINHOS IGNORADOS EM ${ws.name.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Focus(
                onFocusChange: (f) {
                  if (!f) _savePaths(ws);
                },
                child: TextField(
                  key: const ValueKey('secrets-ignore-paths'),
                  controller: _paths,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12.5,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'test/fixtures/**, docs/exemplos/*.env.example',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _savePaths(ws),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'gravado em segredos.ignorar no .promptorium/config.yml',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        AgentCard(
          title: 'Regras · ${SecretRuleGroup.values.length}',
          children: [
            for (final g in SecretRuleGroup.values)
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  key: ValueKey('secrets-rule-${g.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: !p.disabled.contains(g),
                  onChanged: p.enabled ? (v) => _set(g.settingKey, v) : null,
                  title: Text(g.label, style: const TextStyle(fontSize: 13)),
                ),
              ),
          ],
        ),
        if (ws != null) ...[
          const SizedBox(height: 16),
          AgentCard(
            title: 'Ignorados · ${waivers.length}',
            children: [
              if (waivers.isEmpty)
                const Text(
                  'Nenhum achado ignorado neste workspace.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              for (final w in waivers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: w.path.split('/').last,
                                    style: const TextStyle(
                                      fontFamily: AppFonts.mono,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        ' · ${_ruleName(w.rule)}'
                                        '${w.scope == 'valor' ? ' · só este valor' : ''}',
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              '“${w.reason}” · ${waiverDate(w.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        key: ValueKey('secrets-waiver-remove-${w.id}'),
                        onPressed: () async {
                          await ref
                              .read(secretWaiversRepoProvider)
                              .remove(w.id);
                          await ref
                              .read(sessionManagerProvider.notifier)
                              .refreshSecrets(ws.id);
                        },
                        child: const Text('Remover'),
                      ),
                    ],
                  ),
                ),
              const Text(
                'Um ignorado que fica 90 dias sem casar com nada sai sozinho. '
                'As justificativas ficam só no banco do app, nunca no '
                'repositório.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _ruleName(String id) {
  for (final r in defaultSecretRules) {
    if (r.id == id) return r.name;
  }
  return id.startsWith('gitleaks:') ? '${id.substring(9)} (gitleaks)' : id;
}

/// SPEC-103 R8: where the Vigia checks the agent's commits in each
/// provider, and the last check (instead of a fixed sentence).
String secretsAgentWhere({
  bool? python,
  CodexHookStatus? latest,
  HookActivity? last,
}) {
  String where(HookWhen? w) => w == HookWhen.beforeTool
      ? 'hook antes do comando'
      : 'ao fim do turno e antes do push';
  final claude = claudeHookWhen(ManagedHook.secrets, on: true, python: python);
  final codex = codexHookWhen(
    ManagedHook.secrets,
    on: true,
    python: python,
    latest: latest,
  );
  final b = StringBuffer(
    'Claude Code: ${where(claude)}. Codex: ${where(codex)}.',
  );
  if (last != null) {
    final t = last.at;
    b.write(
      ' Última verificação: ${last.provider == 'codex' ? 'Codex' : 'Claude Code'}'
      ' · ${last.text} · '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    );
  }
  return b.toString();
}
