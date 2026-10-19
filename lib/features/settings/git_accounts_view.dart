import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/session_style.dart';

/// Git hosts whose account can be connected in Configurações.
enum GitProvider {
  github('GitHub'),
  gitlab('GitLab');

  const GitProvider(this.label);

  final String label;

  /// `app_settings` key holding the connected user name (not a secret).
  String get loginKey => 'git.$name.login';
}

/// Connected user name of [provider], or null when not connected.
String? gitAccountLogin(Map<String, String> settings, GitProvider provider) {
  final login = settings[provider.loginKey]?.trim();
  return login == null || login.isEmpty ? null : login;
}

/// Configurações → GitHub e GitLab: one card per provider showing
/// "Não conectado" or "Conectado como <usuário>".
class GitAccountCard extends ConsumerWidget {
  const GitAccountCard({super.key, required this.provider});

  final GitProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final login = gitAccountLogin(ref.watch(appSettingsProvider), provider);
    return AgentCard(
      title: provider.label,
      children: [
        Row(
          children: [
            Dot(login == null ? AppColors.textMuted : AppColors.amber),
            const SizedBox(width: 8),
            Text(
              login == null ? 'Não conectado' : 'Conectado como $login',
              key: ValueKey('git-account-status-${provider.name}'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}
