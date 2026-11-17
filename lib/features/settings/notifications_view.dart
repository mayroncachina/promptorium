import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/desktop_notifications.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../activities/activities_state.dart' show activitiesProvider;
import '../activities/activity.dart' show ActivityPose;
import '../activities/widgets/robot_avatar.dart';
import '../activities/widgets/robot_snapshot.dart';
import '../agents/widgets/agent_style.dart';
import '../notifications/agent_alerts.dart';
import '../sessions/app_notifier.dart';
import '../sessions/widgets/session_style.dart';

/// Configurações › Notificações (SPEC-086 R15): the options of the system
/// notifications, a preview with the robot of an open agent and "Testar
/// notificação", which sends a real one and tells whether the click came
/// back.

/// What the notification server can do (null = none, or under tests).
final notificationServerProvider = FutureProvider<NotificationCapabilities?>((
  ref,
) async {
  final notifier = ref.watch(appNotifierProvider);
  if (notifier is! DbusAppNotifier) return null;
  return notifier.server.capabilities();
});

/// `GNOME Shell 47 · ações ✓ · imagens ✓ · Wayland, com token de ativação`.
String serverLine(NotificationCapabilities? caps, {String? session}) {
  if (caps == null) {
    return 'Sem servidor de notificações: a bandeja continua contando os '
        'pedidos.';
  }
  final wayland = (session ?? '').toLowerCase() == 'wayland';
  return [
    caps.server.isEmpty ? 'Servidor de notificações' : caps.server,
    'ações ${caps.actions ? '✓' : '✗'}',
    'imagens ${caps.images ? '✓' : '✗'}',
    if (wayland) 'Wayland, com token de ativação' else 'X11',
  ].join(' · ');
}

/// The robot of the preview: an agent open now, else a fixed one.
const _previewSeed = 'spec:0:SPEC-033';

enum _Test { idle, sent, clicked, failed }

class NotificationsView extends ConsumerStatefulWidget {
  const NotificationsView({super.key});

  @override
  ConsumerState<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends ConsumerState<NotificationsView> {
  _Test _test = _Test.idle;

  Future<void> _send(String seed) async {
    final notifier = ref.read(appNotifierProvider);
    final settings = ref.read(alertSettingsProvider);
    NotificationImage? image;
    if (settings.robot) {
      final p = await robotSnapshot(seed);
      image = NotificationImage(width: p.width, height: p.height, rgba: p.rgba);
    }
    final name = RobotIdentity.of(seed).name;
    final id = await notifier.show(
      '$name precisa de você',
      'Teste do Promptorium — clique aqui para conferir se o clique volta '
          'ao app',
      image: image,
      actions: const [clickAction, openAction],
      noActionsHint: alertNoActionsHint,
      category: 'im.received',
      onClick: () {
        if (mounted) setState(() => _test = _Test.clicked);
      },
    );
    if (!mounted) return;
    setState(() => _test = id == null ? _Test.failed : _Test.sent);
  }

  @override
  Widget build(BuildContext context) {
    final values = ref.watch(alertSettingsProvider);
    final store = ref.read(appSettingsProvider.notifier);
    final caps = ref.watch(notificationServerProvider);
    final open = ref
        .watch(activitiesProvider)
        .where((a) => a.hasRobot && a.needsYou)
        .firstOrNull;
    final seed = open?.seed ?? _previewSeed;
    final where = open?.title ?? 'SPEC-033 · Cupom de desconto';

    Widget toggle(String key, String id, String title, String sub, bool on) =>
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            key: ValueKey('settings-notify-$id'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: on,
            onChanged: (v) => v ? store.remove(key) : store.set(key, 'false'),
            title: Text(title, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              sub,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentCard(
          title: 'Avisos do sistema',
          children: [
            toggle(
              AlertSettingKeys.agents,
              'agents',
              'Avisar quando um agente precisa de você',
              'Aprovação, pergunta, plano pronto, etapa parada',
              values.agents,
            ),
            toggle(
              AlertSettingKeys.robot,
              'robot',
              'Mostrar o robô do agente',
              'Desligado, a notificação usa o ícone do app',
              values.robot,
            ),
            toggle(
              AlertSettingKeys.reminder,
              'reminder',
              'Lembrar uma vez depois de 15 min',
              'Só se o pedido continuar pendente e a janela em segundo plano',
              values.reminder,
            ),
            toggle(
              AlertSettingKeys.sessions,
              'sessions',
              'Avisar também quando uma sessão termina ou falha',
              'Sem robô, com o ícone do app',
              values.sessions,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Dot(
                  caps.value == null ? AppColors.textMuted : AppColors.teal,
                  size: 6,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    caps.isLoading
                        ? 'Conferindo o servidor de notificações…'
                        : serverLine(
                            caps.value,
                            session: Platform.environment['XDG_SESSION_TYPE'],
                          ),
                    key: const ValueKey('settings-notify-server'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        AgentCard(
          title: 'Prévia',
          children: [
            _Preview(
              seed: seed,
              robot: values.robot,
              title: '${RobotIdentity.of(seed).name} precisa de você',
              body: '$where — plano pronto para revisar',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                AmberButton(
                  key: const ValueKey('settings-notify-test'),
                  label: 'Testar notificação',
                  onTap: () => _send(seed),
                ),
                const SizedBox(width: 12),
                if (_test != _Test.idle)
                  Expanded(
                    child: Text(
                      switch (_test) {
                        _Test.sent => 'Enviada: clique nela para conferir',
                        _Test.clicked => 'Clique recebido: tudo certo',
                        _Test.failed =>
                          'Não saiu: sem servidor de notificações',
                        _Test.idle => '',
                      },
                      key: const ValueKey('settings-notify-test-result'),
                      style: TextStyle(
                        fontSize: 12,
                        color: _test == _Test.clicked
                            ? AppColors.teal
                            : _test == _Test.failed
                            ? AppColors.amber
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'O teste manda uma notificação de verdade e confere se o '
              'clique voltou ao app. Sem servidor de notificações, a bandeja '
              'continua contando os pedidos.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

/// A notification as the system shows it, drawn by the app.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.seed,
    required this.robot,
    required this.title,
    required this.body,
  });

  final String seed;
  final bool robot;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('settings-notify-preview'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.background,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Promptorium · agora',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(8),
              ),
              child: robot
                  ? RobotAvatar(
                      seed: seed,
                      pose: ActivityPose.wave,
                      size: 48,
                      selected: true,
                    )
                  : Image.asset(
                      'assets/icon/mark/mark-64.png',
                      width: 40,
                      height: 40,
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Abrir',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
