import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dev/dev_server.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../session_dev.dart';
import 'session_style.dart';

/// Lines of the log sent by "Mandar erro para a sessão" (R4).
const errorTailLines = 60;

/// "há 4 min" since [since].
String uptimeLabel(Duration d) {
  if (d.inMinutes < 1) return 'há menos de 1 min';
  if (d.inHours < 1) return 'há ${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return 'há ${d.inHours} h${m == 0 ? '' : ' $m min'}';
}

/// Short state of the server, as the header and the tab show it (R2).
String devStatusLabel(DevServer s) => switch (s.status) {
  DevServerStatus.stopped => 'Servidor parado',
  DevServerStatus.starting => 'Iniciando… :${s.port}',
  DevServerStatus.running => 'No ar :${s.port}',
  DevServerStatus.failed => 'Falhou · ${s.failure?.reason ?? 'veja os logs'}',
};

Color devStatusColor(DevServerStatus s) => switch (s) {
  DevServerStatus.stopped => AppColors.textSecondary,
  DevServerStatus.starting => AppColors.amber,
  DevServerStatus.running => AppColors.teal,
  DevServerStatus.failed => AppColors.red,
};

/// The message of "Mandar erro para a sessão": the last lines of the log.
String devErrorMessage(DevServer s) {
  final reason = s.failure?.reason;
  return [
    'O servidor de desenvolvimento deste worktree'
        '${reason == null ? ' mostrou um erro' : ' falhou: $reason'}. '
        'Últimas linhas do log (`${s.command ?? 'dev'}`):',
    '',
    '```',
    s.logs.tail(errorTailLines),
    '```',
    '',
    'Veja o que deu errado e corrija.',
  ].join('\n');
}

/// Servers left running by a run of the app that crashed (R5).
final devLeftoversProvider = FutureProvider.autoDispose<List<DevServerRecord>>(
  (ref) => ref.watch(devServerRegistryProvider).leftovers(),
);

/// "Preview" tab of a spec session with `dev:` (R4): state, logs and
/// "Mandar erro para a sessão".
class PreviewTab extends ConsumerStatefulWidget {
  const PreviewTab({super.key, required this.dev, required this.sendToSession});

  final SessionDev dev;

  /// Sends a message to the session (the composer's path).
  final Future<void> Function(String text) sendToSession;

  @override
  ConsumerState<PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends ConsumerState<PreviewTab> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _clock;
  bool _sending = false;
  DevServerStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    // "No ar há N min" moves on its own.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showAppToast(SnackBar(content: Text(msg)));

  Future<void> _sendError(DevServer s) async {
    setState(() => _sending = true);
    try {
      await widget.sendToSession(devErrorMessage(s));
      _toast('Erro mandado para a sessão');
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dev = widget.dev;
    ref.watch(devServerTickProvider(dev.worktree));
    final s = ref.watch(devServerProvider(dev.worktree));
    final registry = ref.watch(devServerRegistryProvider);
    // A leftover taken over ("reaproveitado") or stopped is not offered.
    final leftovers = <DevServerRecord>[
      for (final r in ref.watch(devLeftoversProvider).value ?? const [])
        if (!registry.servers.any((x) => x.pgid == r.pgid)) r,
    ];
    // A server that started or stopped may change the leftovers.
    if (_lastStatus != s.status) {
      _lastStatus = s.status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(devLeftoversProvider);
      });
    }
    final failure = s.status == DevServerStatus.failed ? s.failure : null;
    final lines = s.logs.search(_search.text);
    final hasError =
        s.status == DevServerStatus.failed ||
        s.logs.lines.any((l) => looksLikeError(l.text));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The cards take what they need, leaving the log at least
            // 150 px (or half the tab, when it is short).
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(c.maxHeight / 2, c.maxHeight - 150),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _cards(s, dev, failure, leftovers),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(child: _logs(s, lines, hasError)),
          ],
        ),
      ),
    );
  }

  List<Widget> _cards(
    DevServer s,
    SessionDev dev,
    DevServerFailure? failure,
    List<DevServerRecord> leftovers,
  ) => [
    if (failure?.portTaken ?? false)
      _PortTakenCard(
        failure: failure!,
        onUse: () => s.useRunning(failure.port!),
        onRetry: () => s.start(
          config: dev.config,
          port: dev.port ?? failure.port,
          environment: dev.environment,
        ),
      )
    else
      _StateCard(server: s, dev: dev),
    if (failure != null && !failure.portTaken) ...[
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: SmallButton(
          key: const ValueKey('preview-retry'),
          label: 'Tentar de novo',
          onTap: () => s.start(
            config: dev.config,
            port: dev.port,
            environment: dev.environment,
          ),
        ),
      ),
    ],
    for (final r in leftovers) ...[
      const SizedBox(height: 14),
      _LeftoverBanner(
        record: r,
        onEnd: () async {
          await ref.read(devServerRegistryProvider).endLeftover(r);
          ref.invalidate(devLeftoversProvider);
        },
        onKeep: () {
          ref.read(devServerRegistryProvider).dismissLeftover(r);
          ref.invalidate(devLeftoversProvider);
        },
      ),
    ],
  ];

  Widget _logs(DevServer s, List<DevLogLine> lines, bool hasError) => Container(
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                'Logs · ${_count(s.logs.length)}',
                key: const ValueKey('preview-log-count'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Buscar',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      key: const ValueKey('preview-log-search'),
                      controller: _search,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'texto no log',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SmallButton(
                    key: const ValueKey('preview-log-copy'),
                    label: 'Copiar',
                    onTap: s.logs.length == 0
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: lines.map((l) => l.text).join('\n'),
                              ),
                            );
                            _toast('Log copiado');
                          },
                  ),
                  const SizedBox(width: 8),
                  SmallButton(
                    key: const ValueKey('preview-send-error'),
                    label: _sending ? 'Mandando…' : 'Mandar erro para a sessão',
                    onTap: hasError && !_sending ? () => _sendError(s) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Text(
                    s.logs.length == 0
                        ? 'Sem logs ainda. Inicie o servidor no '
                              'cabeçalho da sessão.'
                        : 'Nada no log com "${_search.text}".',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    key: const ValueKey('preview-log-list'),
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: lines.length,
                    itemBuilder: (_, i) =>
                        _LogLine(lines[lines.length - 1 - i]),
                  ),
                ),
        ),
      ],
    ),
  );

  static String _count(int n) {
    final shown = n >= 1000
        ? '${n ~/ 1000}.${(n % 1000).toString().padLeft(3, '0')}'
        : '$n';
    return '$shown de 2.000 linhas';
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine(this.line);

  final DevLogLine line;

  @override
  Widget build(BuildContext context) {
    final t = line.text;
    // Many servers log ordinary lines to stderr: red only for errors (and
    // the app's own failure lines).
    final color = line.text.contains('✓')
        ? AppColors.teal
        : looksLikeError(t) ||
              (line.kind == DevLogKind.err && t.startsWith('promptorium:'))
        ? AppColors.red
        : t.toLowerCase().contains('warn')
        ? AppColors.amber
        : line.kind == DevLogKind.app
        ? AppColors.textSecondary
        : AppColors.text;
    return Text(
      t,
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        height: 1.6,
        color: color,
      ),
    );
  }
}

Widget _field(
  String label,
  String value, {
  Color? color,
  Key? key,
  int maxLines = 3,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      label,
      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
    ),
    const SizedBox(height: 4),
    Text(
      value,
      key: key,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: color == null ? 12 : 13,
        fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
        fontFamily: color == null ? AppFonts.mono : null,
        color: color ?? AppColors.text,
      ),
    ),
  ],
);

class _StateCard extends StatelessWidget {
  const _StateCard({required this.server, required this.dev});

  final DevServer server;
  final SessionDev dev;

  @override
  Widget build(BuildContext context) {
    final s = server;
    final state = switch (s.status) {
      DevServerStatus.running when s.startedAt != null =>
        'No ar ${uptimeLabel(DateTime.now().difference(s.startedAt!))}',
      DevServerStatus.running => 'No ar',
      DevServerStatus.starting => 'Iniciando…',
      DevServerStatus.stopped => 'Parado',
      DevServerStatus.failed => 'Falhou · ${s.failure?.reason ?? ''}',
    };
    final port = s.port ?? dev.port;
    final path = s.port == null ? dev.config.path : s.path;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _field(
              'Estado',
              state,
              color: devStatusColor(s.status),
              key: const ValueKey('preview-state'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: _field('Comando', s.command ?? dev.config.command)),
          const SizedBox(width: 12),
          Expanded(
            child: _field(
              'Porta',
              port == null
                  ? 'livre, escolhida ao iniciar'
                  : '127.0.0.1:$port · página $path',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _field(
              'Processo',
              s.external
                  ? 'de fora do app (não é encerrado)'
                  : s.pid == null
                  ? '—'
                  : 'PID ${s.pid} · grupo ${s.pgid}',
              key: const ValueKey('preview-process'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortTakenCard extends StatelessWidget {
  const _PortTakenCard({
    required this.failure,
    required this.onUse,
    required this.onRetry,
  });

  final DevServerFailure failure;
  final VoidCallback onUse;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final o = failure.owner!;
    return Container(
      key: const ValueKey('preview-port-taken'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SessionColors.stopBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColors.red,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'O servidor não subiu: a porta ${failure.port} já está em uso',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Outro processo, que o Promptorium não subiu, está escutando nessa '
            'porta. O app não mexe nele. Se ele já for o servidor desta spec, '
            'aberto num terminal por exemplo, dá para usar o que está no ar.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SessionColors.terminalPanel,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    'Processo na porta',
                    o.pid == null
                        ? 'de outro usuário'
                        : 'PID ${o.pid} · ${o.name ?? '?'}',
                    key: const ValueKey('preview-owner-pid'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field('Comando', o.command ?? '—', maxLines: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field('Pasta', _home(o.cwd) ?? '—', maxLines: 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              IntrinsicWidth(
                child: AmberButton(
                  key: const ValueKey('preview-use-running'),
                  label: 'Usar o que está no ar',
                  onTap: onUse,
                ),
              ),
              IntrinsicWidth(
                child: SmallButton(
                  key: const ValueKey('preview-retry'),
                  label: 'Tentar de novo',
                  onTap: onRetry,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _home(String? path) {
  if (path == null) return null;
  final home = Platform.environment['HOME'] ?? '';
  return home.isNotEmpty && path.startsWith(home)
      ? '~${path.substring(home.length)}'
      : path;
}

class _LeftoverBanner extends StatelessWidget {
  const _LeftoverBanner({
    required this.record,
    required this.onEnd,
    required this.onKeep,
  });

  final DevServerRecord record;
  final VoidCallback onEnd;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final name = r.worktree.split('/').where((p) => p.isNotEmpty).lastOrNull;
    return Container(
      key: ValueKey('preview-leftover-${r.pid}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: AppColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Da última vez o app fechou sem parar um servidor que ele tinha '
              'subido: ${name ?? r.worktree} · :${r.port} · PID ${r.pid}.',
              style: const TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 10),
          SmallButton(
            key: ValueKey('preview-leftover-end-${r.pid}'),
            label: 'Encerrar',
            onTap: onEnd,
          ),
          const SizedBox(width: 6),
          TextButton(
            key: ValueKey('preview-leftover-keep-${r.pid}'),
            onPressed: onKeep,
            child: const Text(
              'Deixar rodando',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
