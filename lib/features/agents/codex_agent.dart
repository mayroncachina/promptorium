import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/codex/codex_agent_mapping.dart';
import '../../core/providers/agent_provider.dart';
import '../../core/providers/provider_availability.dart';
import '../../core/providers/provider_preferences.dart';
import '../../data/providers.dart';
import 'agent_file.dart';
import 'agent_repository.dart';

export '../../core/codex/codex_agent_mapping.dart';

/// SPEC-106 in the app: the translation of an agent with the table of
/// `app_settings`, the cached `model/list` and the sandbox of this machine.
CodexAgentPlan codexAgentPlanFrom(
  Map<String, String> settings,
  AgentFile file, {
  required String name,
  required AgentAccess access,
  String runModel = 'inherit',
  String? runEffort,
  bool sandboxAvailable = true,
}) => codexAgentPlan(
  file,
  name: name,
  access: access,
  table: CodexAgentTable.fromSettings(settings),
  catalog: codexModelsCache(settings)?.models,
  runModel: runModel,
  runEffort: runEffort,
  sandboxAvailable: sandboxAvailable,
);

/// The OS sandbox of the Codex works here (unknown = yes; decision 15).
bool codexSandboxAvailable(Ref ref) =>
    ref.read(providerAvailabilityProvider('codex')).value?.sandboxWarning ==
    null;

/// The plan of [agent] for a Codex run in [workspacePath] (the effective
/// definition: project wins). Null = no such agent or an unreadable file.
Future<CodexAgentPlan?> resolveCodexAgentPlan(
  Ref ref, {
  required String agent,
  required String? workspacePath,
  required AgentAccess access,
  String runModel = 'inherit',
  String? runEffort,
}) async {
  try {
    final entry = await ref
        .read(agentRepositoryProvider(workspacePath))
        .find(agent);
    if (entry == null) return null;
    return codexAgentPlanFrom(
      ref.read(appSettingsProvider),
      entry.file,
      name: agent,
      access: access,
      runModel: runModel,
      runEffort: runEffort,
      sandboxAvailable: codexSandboxAvailable(ref),
    );
  } catch (e) {
    debugPrint('agente $agent no Codex: não traduzido — $e');
    return null;
  }
}

/// The translation recorded by the last run of [s] (R11), from its
/// `runConfig` — never from the `.md` as it is now.
CodexAgentPlan? sessionAgentRecord(Session s) {
  final raw = s.runConfig;
  if (raw == null || raw.isEmpty) return null;
  try {
    final j = jsonDecode(raw);
    return j is Map ? CodexAgentPlan.fromRecord(j['agent']) : null;
  } catch (_) {
    return null;
  }
}

/// "flutter-dev · adaptado" for a Codex session with a recorded agent;
/// else the agent name (null = none).
String? sessionAgentLabel(Session s) =>
    sessionAgentRecord(s)?.label ?? s.agentName;
