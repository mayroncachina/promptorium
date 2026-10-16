import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'claude_args.dart';

/// Kinds of `claude -p` run with their own default model and effort
/// (Configurações → Consumo).
enum RunKind {
  /// Sessions (Nova sessão, Executar com agente, Continuar como sessão).
  session('Sessões', 'Executam tarefas: editam, rodam comandos, abrem PR.'),

  /// Prompt conversations (Perguntar, Planejar, Editar, Refinar).
  conversation('Conversas do Prompt', 'Perguntas, planos e refinar specs.'),

  /// Read-only structured runs: Projeto, Gerar tarefas, Nova skill.
  planner('Planner', 'Planejamento do Projeto, Gerar tarefas e Nova skill.');

  const RunKind(this.label, this.hint);

  final String label;
  final String hint;
}

/// Effort value meaning "do not pass `--effort`" (CLI default).
const defaultEffort = 'default';

/// Choices of the effort selectors: [defaultEffort] + `--effort` levels.
const effortChoices = [defaultEffort, ...ClaudeOptions.effortLevels];

/// `low` → `low`; [defaultEffort] → `padrão do CLI`.
String effortLabel(String effort) =>
    effort == defaultEffort || effort.isEmpty ? 'padrão do CLI' : effort;

/// `--effort` value of [effort] (null = CLI default).
String? effortArg(String? effort) =>
    effort == null || effort.isEmpty || effort == defaultEffort ? null : effort;

/// Choices of the auto-compact selector (`--autocompact`; the CLI accepts
/// `auto` or 100k–1M).
const autocompactChoices = ['100k', '150k', '200k', '300k', '500k', 'auto'];

/// Consumption preferences, stored in `app_settings` (`claude.*` keys).
///
/// Defaults favour cost: Sonnet with medium effort for sessions and
/// conversations, the CLI's model (Opus) with medium effort for the planner,
/// and compaction at 200k tokens (with a 1M window the CLI would only compact
/// near the end, and every call re-reads the whole context).
@immutable
class RunPrefs {
  const RunPrefs(this._settings);

  final Map<String, String> _settings;

  static const defaultModels = {
    RunKind.session: 'sonnet',
    RunKind.conversation: 'sonnet',
    RunKind.planner: 'inherit',
  };
  static const defaultEfforts = {
    RunKind.session: 'medium',
    RunKind.conversation: 'medium',
    RunKind.planner: 'medium',
  };
  static const defaultAutocompact = '200k';

  /// Model alias (`inherit` = the CLI's default model).
  String model(RunKind k) =>
      _settings[AppSettingKeys.runModel(k.name)] ?? defaultModels[k]!;

  /// One of [effortChoices].
  String effort(RunKind k) =>
      _settings[AppSettingKeys.runEffort(k.name)] ?? defaultEfforts[k]!;

  /// A spec with at most this many steps runs in a single session (Quadro).
  int get singleSessionMaxSteps =>
      int.tryParse(_settings[AppSettingKeys.singleSessionSteps] ?? '') ??
      defaultSingleSessionSteps;
  static const defaultSingleSessionSteps = 3;

  /// One of [autocompactChoices].
  String get autocompact =>
      _settings[AppSettingKeys.autocompact] ?? defaultAutocompact;

  /// Minutes without activity before an idle session's process is closed
  /// (0 = never).
  int get idleMinutes {
    final v = int.tryParse(_settings[AppSettingKeys.idleMinutes] ?? '');
    return v == null || v < 0 ? defaultIdleMinutes : v;
  }

  static const defaultIdleMinutes = 15;

  /// Choices of the idle selector (minutes; 0 = never).
  static const idleChoices = [5, 15, 30, 60, 0];

  /// `--model` value for [k] (null = CLI default).
  String? modelArg(RunKind k) {
    final m = model(k);
    return m.isEmpty || m == 'inherit' ? null : m;
  }
}

final runPrefsProvider = Provider<RunPrefs>(
  (ref) => RunPrefs(ref.watch(appSettingsProvider)),
);
