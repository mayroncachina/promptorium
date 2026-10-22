import 'dart:async';
import 'dart:io';

import '../project/project_config.dart';

typedef HostCommand = Future<ProcessResult> Function(
  String,
  List<String>, {
  String? workingDirectory,
});

/// What a remote URL points to: a host, a path on this machine or nothing
/// usable.
enum RemoteKind { hosted, local, invalid }

RemoteKind remoteKind(String remote) {
  if (_isLocal(remote)) return RemoteKind.local;
  return remoteHost(remote) == null ? RemoteKind.invalid : RemoteKind.hosted;
}

bool _isLocal(String remote) =>
    remote.startsWith('/') ||
    remote.startsWith('./') ||
    remote.startsWith('../') ||
    remote.startsWith('~/') ||
    remote.startsWith('file:') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(remote);

String? remoteHost(String remote) {
  if (_isLocal(remote)) return null;
  final uri = Uri.tryParse(remote);
  if (uri != null &&
      uri.hasAuthority &&
      const ['https', 'http', 'ssh', 'git'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.pathSegments.any((s) => s.isNotEmpty)) {
    return uri.host.toLowerCase();
  }
  return RegExp(r'^(?:[^@/\s]+@)?([a-zA-Z0-9.-]+):[^/\s].+$')
      .firstMatch(remote)
      ?.group(1)
      ?.toLowerCase();
}

const reviewHostTypes = ['github', 'gitlab'];

String? detectReviewHost(String remote, ProjectConfig config) {
  final host = remoteHost(remote);
  if (host == 'github.com') return 'github';
  if (host == 'gitlab.com') return 'gitlab';
  if (host != null &&
      host == config.host?.toLowerCase() &&
      reviewHostTypes.contains(config.hostType)) {
    return config.hostType;
  }
  return null;
}

/// Canonical repository URL accepted by --repo, without SSH credentials.
String? reviewRepositoryUrl(String remote) {
  final host = remoteHost(remote);
  if (host == null) return null;
  final uri = Uri.tryParse(remote);
  var path = uri != null && uri.hasAuthority
      ? uri.path
      : remote.substring(remote.indexOf(':') + 1);
  path = path
      .replaceAll(RegExp(r'^/+|/+$'), '')
      .replaceFirst(RegExp(r'\.git$'), '');
  if (path.split('/').length < 2) return null;
  return 'https://$host/$path';
}

/// Resolves the destination before probing any CLI. Never guesses origin.
String? chooseReviewRemote(
  List<String> names, {
  String? explicit,
  String? upstream,
}) {
  if (explicit != null) return names.contains(explicit) ? explicit : null;
  if (upstream != null && names.contains(upstream)) return upstream;
  return names.length == 1 ? names.single : null;
}

enum HostProblem { missing, authentication, network, incompatible, unsupported }

class HostAvailability {
  const HostAvailability(
    this.available, {
    this.reason,
    this.problem,
    this.installUrl,
  });
  final bool available;
  final String? reason;
  final HostProblem? problem;
  final String? installUrl;
}

abstract class ReviewHost {
  String get id;
  String get requestLabel;
  Future<HostAvailability> availability(String cwd, String hostname);
}

class CliReviewHost implements ReviewHost {
  CliReviewHost(this.run, {required this.id});
  final HostCommand run;
  @override
  final String id;
  String get cli => id == 'gitlab' ? 'glab' : 'gh';
  String get name => id == 'gitlab' ? 'GitLab' : 'GitHub';
  String get installUrl => id == 'gitlab'
      ? 'https://gitlab.com/gitlab-org/cli#installation'
      : 'https://github.com/cli/cli#installation';
  @override
  String get requestLabel => id == 'gitlab' ? 'MR' : 'PR';
  String get limitation =>
      id == 'gitlab' ? '\nIntegração de MR ainda indisponível (DT-55).' : '';

  Future<ProcessResult> _probe(String exe, List<String> args, String cwd) =>
      run(
        exe,
        args,
        workingDirectory: cwd,
      ).timeout(const Duration(seconds: 15));

  @override
  Future<HostAvailability> availability(String cwd, String hostname) async {
    HostAvailability missing() => HostAvailability(
      false,
      problem: HostProblem.missing,
      installUrl: installUrl,
      reason:
          '$name CLI ($cli) não encontrado no PATH. Instale para usar as ações de $requestLabel.$limitation',
    );
    try {
      final which = await _probe('which', [cli], cwd);
      if (which.exitCode != 0 || '${which.stdout}'.trim().isEmpty) {
        return missing();
      }
      final auth = await _probe(cli, [
        'auth',
        'status',
        '--hostname',
        hostname,
      ], cwd);
      final output = '${auth.stdout}\n${auth.stderr}'.toLowerCase();
      if (auth.exitCode != 0 || output.contains('invalid token')) {
        if (RegExp(
          r'timeout|timed out|connection|network|no such host|resolve host|certificate|tls|offline',
        ).hasMatch(output)) {
          return HostAvailability(
            false,
            problem: HostProblem.network,
            reason:
                'Não foi possível conectar a $hostname. Verifique a rede e o certificado.$limitation',
          );
        }
        if (RegExp(r'unknown flag|unknown command|unrecognized')
            .hasMatch(output)) {
          return HostAvailability(
            false,
            problem: HostProblem.incompatible,
            installUrl: installUrl,
            reason:
                '$cli incompatível com a verificação de autenticação. Consulte a atualização.$limitation',
          );
        }
        if (output.trim().isEmpty ||
            RegExp(
              r'invalid token|not logged|not authenticated|auth login|401|unauthorized|authentication|token.*invalid|token.*expired',
            ).hasMatch(output)) {
          return HostAvailability(
            false,
            problem: HostProblem.authentication,
            reason:
                'Autenticação do $name inválida em $hostname. Execute $cli auth login --hostname $hostname.$limitation',
          );
        }
        return HostAvailability(
          false,
          problem: HostProblem.network,
          reason:
              'Não foi possível verificar a autenticação em $hostname.$limitation',
        );
      }
      return id == 'gitlab'
          ? const HostAvailability(
              false,
              problem: HostProblem.unsupported,
              reason: 'Integração de MR ainda indisponível (DT-55).',
            )
          : const HostAvailability(true);
    } on TimeoutException {
      return HostAvailability(
        false,
        problem: HostProblem.network,
        reason:
            'Tempo esgotado ao verificar $hostname. Tente novamente.$limitation',
      );
    } on ProcessException {
      return missing();
    }
  }
}

class GithubHost extends CliReviewHost {
  GithubHost(super.run) : super(id: 'github');
}

class GitlabHost extends CliReviewHost {
  GitlabHost(super.run) : super(id: 'gitlab');
}
