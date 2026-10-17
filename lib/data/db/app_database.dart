import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'enums.dart';
import 'migrations.dart';
import 'schema_versions.dart';

export 'enums.dart';

part 'app_database.g.dart';

/// Current schema (see the migrations; `drift_schemas/` has v8 onwards).
const appSchemaVersion = 12;

/// JSON array of strings stored in a TEXT column (`tasks.dependsOn`,
/// `agent_settings.mcpServers`).
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.trim().isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(fromDb);
    } on FormatException {
      return const [];
    }
    return decoded is List ? decoded.map((e) => '$e').toList() : const [];
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// `R1 · Cada sessão roda em um worktree` line of a spec (its step).
typedef SpecRequirement = ({String id, String text});

/// JSON array of `{"id": "R1", "text": "…"}` (`specs.requirements`).
class RequirementListConverter
    extends TypeConverter<List<SpecRequirement>, String> {
  const RequirementListConverter();

  @override
  List<SpecRequirement> fromSql(String fromDb) {
    if (fromDb.trim().isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(fromDb);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map && e['id'] is String)
          (id: e['id'] as String, text: '${e['text'] ?? ''}'),
    ];
  }

  @override
  String toSql(List<SpecRequirement> value) => jsonEncode([
    for (final r in value) {'id': r.id, 'text': r.text},
  ]);
}

/// A git repository opened in the IDE.
class Workspaces extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Absolute path of the repository root (`git rev-parse --show-toplevel`).
  TextColumn get path => text().unique()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Specs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workspaceId =>
      integer().references(Workspaces, #id, onDelete: KeyAction.cascade)();

  /// `SPEC-001`.
  TextColumn get code => text()();
  TextColumn get title => text()();
  TextColumn get status =>
      textEnum<SpecStatus>().withDefault(Constant(SpecStatus.draft.name))();

  /// Path relative to the workspace root.
  TextColumn get path => text()();

  // --- the spec as a card of the Quadro (schema v8) --------------------------

  /// Column of the Quadro.
  TextColumn get stage =>
      textEnum<SpecStage>().withDefault(Constant(SpecStage.backlog.name))();

  /// Mirror of the file's requirements: the steps of the card (`R1`…).
  TextColumn get requirements => text()
      .map(const RequirementListConverter())
      .withDefault(const Constant('[]'))();

  /// Codes of the specs that must be done first (frontmatter `depende-de`).
  TextColumn get dependsOn => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();

  /// Frontmatter `fase` (`fundacao`, `mvp`…).
  TextColumn get phase => text().nullable()();

  /// Agent of the step sessions (`--agent`).
  TextColumn get agentName => text().nullable()();

  /// Worktree / branch shared by every step session (`pr/spec-003-<slug>`),
  /// and the branch it came from (merge target). Null = not started.
  TextColumn get worktreePath => text().nullable()();
  TextColumn get branch => text().nullable()();
  TextColumn get baseBranch => text().nullable()();

  /// A finished step opens the session of the next one.
  BoolColumn get autoAdvance => boolean().withDefault(const Constant(true))();

  // --- worktree and review (schema v10) --------------------------------------

  /// Smallest free index among the workspace's live spec worktrees:
  /// `PROMPTORIUM_PORT` = `porta-base` + index.
  IntColumn get worktreeIndex => integer().nullable()();

  /// When the worktree got the `copiar:` files and ran `preparar:` (null =
  /// not prepared yet: the next run prepares it first).
  DateTimeColumn get preparedAt => dateTime().nullable()();

  /// `auto` while the automatic reviewer works on the spec, `human` after
  /// it approved or ran out of rounds (null = no reviewer).
  TextColumn get reviewPhase => text().nullable()();

  /// Correction rounds asked by the automatic reviewer.
  IntColumn get reviewRounds => integer().withDefault(const Constant(0))();

  /// Reason given for "Mergear mesmo assim" with acceptance criteria
  /// unchecked.
  TextColumn get mergeOverride => text().nullable()();

  /// Position in its column of the Quadro (schema v11; null = by code).
  IntColumn get boardOrder => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {workspaceId, code},
  ];
}

/// State of one step (requirement) of a spec (schema v8). The list of steps
/// comes from the file ([Specs.requirements]); this table keeps only state.
class SpecSteps extends Table {
  IntColumn get specId =>
      integer().references(Specs, #id, onDelete: KeyAction.cascade)();

  /// Requirement id (`R1`).
  TextColumn get step => text()();
  TextColumn get status =>
      textEnum<StepStatus>().withDefault(Constant(StepStatus.pending.name))();

  /// Last session that worked on the step.
  TextColumn get sessionId => text().nullable()();
  DateTimeColumn get doneAt => dateTime().nullable()();

  // --- gate and checkpoint (schema v9) ---------------------------------------

  /// HEAD of the worktree when the step's session started (the gate looks
  /// for the step's commit after it; "Voltar ao início da etapa" goes back
  /// to it, also kept as `refs/promptorium/<spec>/<step>-inicio`).
  TextColumn get startSha => text().nullable()();

  /// `git stash create` of the uncommitted changes at that moment.
  TextColumn get startStash => text().nullable()();

  /// JSON of the last `GateReport`.
  TextColumn get gateReport => text().nullable()();

  /// Automatic resends after a failed gate, in the current session.
  IntColumn get gateAttempts => integer().withDefault(const Constant(0))();

  /// Text of a step that is not in the file (schema v10): `REV1`, the
  /// corrections asked by the automatic reviewer.
  TextColumn get body => text().nullable()();

  @override
  Set<Column> get primaryKey => {specId, step};
}

/// Autopilot of the Quadro switched on for a workspace (schema v9): turned
/// back on when the app opens.
class AutopilotStates extends Table {
  IntColumn get workspaceId =>
      integer().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get since => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {workspaceId};
}

/// Draft of the Review of one item (schema v9): pending comments and
/// accepted hunks, as JSON.
@DataClassName('ReviewDraftRow')
class ReviewDrafts extends Table {
  TextColumn get sessionId => text()();
  TextColumn get data => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sessionId};
}

/// Comment of a review round on a spec (schema v10): the automatic
/// reviewer's or the user's.
@DataClassName('ReviewCommentRow')
class ReviewComments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get specId =>
      integer().references(Specs, #id, onDelete: KeyAction.cascade)();

  /// 1, 2… (the round that asked for it).
  IntColumn get round => integer()();

  /// `revisor` (automatic) or `humano`.
  TextColumn get author => text()();

  /// Relative path; null = about the spec as a whole.
  TextColumn get path => text().nullable()();
  IntColumn get line => integer().nullable()();
  TextColumn get body => text()();

  /// `alta` / `media` / `baixa`.
  TextColumn get severity => text().nullable()();

  /// Requirement it is about (`R2`).
  TextColumn get requirement => text().nullable()();

  /// Verdict of the round (`aprovar` / `corrigir`) on its first comment, and
  /// the commit reviewed.
  TextColumn get verdict => text().nullable()();
  TextColumn get commitSha => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Acceptance criterion of a spec checked in the Review (schema v10), by
/// its text in the file.
class SpecCriteria extends Table {
  IntColumn get specId =>
      integer().references(Specs, #id, onDelete: KeyAction.cascade)();
  TextColumn get criterion => text()();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();

  /// `gate`, `revisor` or `humano`.
  TextColumn get checkedBy => text().nullable()();
  DateTimeColumn get checkedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {specId, criterion};
}

/// `SPEC SUGESTÃO: …` written by a step session (schema v11): shown on the
/// card until the user applies or ignores it.
class SpecSuggestions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get specId =>
      integer().references(Specs, #id, onDelete: KeyAction.cascade)();
  TextColumn get sessionId => text().nullable()();

  /// Steps of the session that wrote it (`R2`).
  TextColumn get steps => text().nullable()();
  TextColumn get body => text()();

  /// `pendente` / `aplicada` / `ignorada`.
  TextColumn get state => text().withDefault(const Constant('pendente'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Notification shown by the app (schema v12): the history of the
/// notification center, with where its click goes.
@DataClassName('AppNotification')
class Notifications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get body => text()();

  /// `AppSection.name` the click goes to.
  TextColumn get section => text().nullable()();

  /// Session selected by the click.
  TextColumn get sessionId => text().nullable()();
  BoolColumn get read => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Notices waiting to be sent to a session (manual edits, schema v9).
class PendingNotices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get specId => integer().nullable().references(
    Specs,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get workspaceId =>
      integer().references(Workspaces, #id, onDelete: KeyAction.cascade)();

  /// `TASK-001` (Fase 8; rows created before use `T-001`).
  TextColumn get code => text()();
  TextColumn get title => text()();
  TextColumn get status =>
      textEnum<TaskStatus>().withDefault(Constant(TaskStatus.backlog.name))();
  TextColumn get agentName => text().nullable()();

  /// Free text of the task (schema v3; e.g. the Prompt answer it came from).
  TextColumn get body => text().nullable()();

  /// Spec requirement the task implements, e.g. `R2` (schema v4, Fase 8:
  /// traceability requirement → task → session → commit).
  TextColumn get requirement => text().nullable()();

  /// Codes of the tasks this one depends on (JSON array).
  TextColumn get dependsOn => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {workspaceId, code},
  ];
}

/// A Claude Code session (`--session-id <uuid>`).
class Sessions extends Table {
  /// UUID passed to `--session-id` / `--resume`.
  TextColumn get id => text()();
  IntColumn get workspaceId =>
      integer().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  IntColumn get taskId => integer().nullable().references(
    Tasks,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get agentName => text().nullable()();

  /// Name shown in the list (schema v2). Null for v1 rows.
  TextColumn get title => text().nullable()();

  /// CLI `--permission-mode` value used to (re)start the process (schema v2).
  TextColumn get permissionMode => text().nullable()();
  TextColumn get worktreePath => text()();
  TextColumn get branch => text()();
  TextColumn get status => textEnum<SessionStatus>().withDefault(
    Constant(SessionStatus.running.name),
  )();
  TextColumn get model => text()();

  /// Spec (card) the session works on and the steps it was given (`R2` or
  /// `R2,R3`; schema v8).
  IntColumn get specId => integer().nullable().references(
    Specs,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get steps => text().nullable()();

  /// `--effort` used to (re)start the process (schema v7). Null = rows
  /// written before: resumes use the default of Configurações.
  TextColumn get effort => text().nullable()();
  RealColumn get costUsd => real().withDefault(const Constant(0))();
  IntColumn get tokensIn => integer().withDefault(const Constant(0))();
  IntColumn get tokensOut => integer().withDefault(const Constant(0))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Branch the worktree was created from (merge target of the Review;
  /// schema v5). Null for rows written before / sessions without worktree.
  TextColumn get baseBranch => text().nullable()();

  /// Hash of the merge commit made by the Review (schema v5, Fase 9).
  TextColumn get mergeCommit => text().nullable()();

  /// URL of the pull request opened by the Review (schema v5).
  TextColumn get prUrl => text().nullable()();

  /// PID of the `claude` process while it runs (schema v12): the next
  /// launch ends the ones left behind by a crash of the app.
  IntColumn get pid => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Raw stream-json lines of a session, in order.
class SessionEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// 1-based order inside the session.
  IntColumn get seq => integer()();

  /// `type` (and `/subtype`) of the event, e.g. `system/init`.
  TextColumn get type => text()();
  TextColumn get json => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, seq},
  ];
}

/// Free conversation of the Prompt screen (Fase 6).
class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workspaceId =>
      integer().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get provider => text().withDefault(const Constant('claude'))();
  TextColumn get model => text()();

  /// Session created from this conversation by "Continuar como sessão".
  TextColumn get sessionId => text().nullable().references(
    Sessions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Claude Code session id of the conversation itself (`--session-id` on
  /// the first start, `--resume` afterwards). Schema v3.
  TextColumn get claudeSessionId => text().nullable()();

  /// `PromptMode.name`: ask / plan / edit (schema v3).
  TextColumn get mode => text().withDefault(const Constant('ask'))();
  IntColumn get tokensIn => integer().withDefault(const Constant(0))();
  IntColumn get tokensOut => integer().withDefault(const Constant(0))();

  /// Last cumulative `total_cost_usd` (see plano, Fase 5).
  RealColumn get costUsd => real().withDefault(const Constant(0))();

  /// User messages + Claude answers (list meta).
  IntColumn get messageCount => integer().withDefault(const Constant(0))();

  /// Last activity (history order / grouping). Null = [createdAt].
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Raw stream-json lines of a conversation (same format as [SessionEvents]).
class ConversationEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId =>
      integer().references(Conversations, #id, onDelete: KeyAction.cascade)();
  IntColumn get seq => integer()();
  TextColumn get type => text()();
  TextColumn get json => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {conversationId, seq},
  ];
}

/// `/comando` prompts.
class SavedPrompts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Without the leading slash: `testes`.
  TextColumn get command => text().unique()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get body => text()();
  IntColumn get uses => integer().withDefault(const Constant(0))();
}

/// Agent options that do not live in the agent's frontmatter (Fase 7).
class AgentSettings extends Table {
  TextColumn get agentName => text()();
  TextColumn get scope => textEnum<AgentScope>()();

  /// CLI value (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`).
  TextColumn get permissionMode => text().nullable()();
  RealColumn get budgetUsd => real().nullable()();
  IntColumn get maxTurns => integer().nullable()();

  /// MCP server names enabled for the agent (JSON array). No secrets here.
  TextColumn get mcpServers => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {agentName, scope};
}

class McpToolRules extends Table {
  TextColumn get server => text()();
  TextColumn get tool => text()();
  TextColumn get rule => textEnum<McpRule>()();

  @override
  Set<Column> get primaryKey => {server, tool};
}

/// Planning of a project (Projeto screen): one row per workspace.
class ProjectPlans extends Table {
  IntColumn get workspaceId =>
      integer().references(Workspaces, #id, onDelete: KeyAction.cascade)();

  /// `ProjectStep.name` (vision, stack, roadmap, create).
  TextColumn get step => text().withDefault(const Constant('vision'))();

  /// JSON of `ProjectPlanData` (conversation, vision, stack, roadmap).
  TextColumn get data => text().withDefault(const Constant('{}'))();

  /// Claude session of the Visão conversation (`--resume`).
  TextColumn get plannerSessionId => text().nullable()();
  RealColumn get costUsd => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Set by "Criar projeto" (files, specs and tasks written).
  DateTimeColumn get materializedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {workspaceId};
}

/// Key/value preferences (see `AppSettingKeys`).
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Workspaces,
    Specs,
    SpecSteps,
    Tasks,
    Sessions,
    SessionEvents,
    Conversations,
    ConversationEvents,
    SavedPrompts,
    AgentSettings,
    McpToolRules,
    AppSettings,
    ProjectPlans,
    AutopilotStates,
    ReviewDrafts,
    PendingNotices,
    ReviewComments,
    SpecCriteria,
    SpecSuggestions,
    Notifications,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-disk database (`<data dir>/promptorium.sqlite`): a pending
  /// "Restaurar backup" is applied first, and a copy is kept before a
  /// migration ([backupBeforeMigration]).
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: fileName,
      native: const DriftNativeOptions(
        databaseDirectory: _directoryWithRestore,
        setup: backupBeforeMigration,
      ),
    ),
  );

  static Future<Directory> _directoryWithRestore() async {
    final dir = await databaseDirectory();
    applyPendingRestore(dir);
    return dir;
  }

  /// File name without the `.sqlite` extension (driftDatabase adds it).
  static const fileName = 'promptorium';

  @override
  int get schemaVersion => appSchemaVersion;

  Future<bool> _hasTable(String name) async => (await customSelect(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    variables: [Variable.withString(name)],
  ).get()).isNotEmpty;

  Future<bool> _hasColumn(String table, String column) async =>
      (await customSelect(
        'SELECT 1 FROM pragma_table_info(?) WHERE name = ?',
        variables: [Variable.withString(table), Variable.withString(column)],
      ).get()).isNotEmpty;

  /// v1 → v8 (hand-written).
  Future<void> _upgradeToV8(Migrator m, int from) async {
    // v2 (Fase 5): session title and permission mode.
    if (from < 2) {
      await m.addColumn(sessions, sessions.title);
      await m.addColumn(sessions, sessions.permissionMode);
    }
    // v3 (Fase 6): Prompt conversations, task body.
    if (from < 3) {
      await m.addColumn(tasks, tasks.body);
      await m.addColumn(conversations, conversations.claudeSessionId);
      await m.addColumn(conversations, conversations.mode);
      await m.addColumn(conversations, conversations.tokensIn);
      await m.addColumn(conversations, conversations.tokensOut);
      await m.addColumn(conversations, conversations.costUsd);
      await m.addColumn(conversations, conversations.messageCount);
      await m.addColumn(conversations, conversations.updatedAt);
      await m.createTable(conversationEvents);
    }
    // v4 (Fase 8): requirement of a task (planner output).
    if (from < 4) {
      await m.addColumn(tasks, tasks.requirement);
    }
    // v5 (Fase 9): base branch, merge commit and PR of a session (Review).
    if (from < 5) {
      await m.addColumn(sessions, sessions.baseBranch);
      await m.addColumn(sessions, sessions.mergeCommit);
      await m.addColumn(sessions, sessions.prUrl);
    }
    // v6: planning of a new project (Projeto screen).
    if (from < 6) {
      await m.createTable(projectPlans);
    }
    // v7: effort of a session; the footer no longer sums tokens per day
    // (the `usage.<yyyy-mm-dd>` rows of app_settings are dropped).
    if (from < 7) {
      await m.addColumn(sessions, sessions.effort);
      if (await _hasTable('app_settings')) {
        await customStatement(
          "DELETE FROM app_settings WHERE key GLOB 'usage.[0-9]*'",
        );
      }
    }
    // v8: the spec is the card of the Quadro; its requirements are the
    // steps. Tasks of a spec become step states and spec dependencies.
    if (from < 8 && await _hasTable('specs')) {
      for (final c in [
        specs.stage,
        specs.requirements,
        specs.dependsOn,
        specs.phase,
        specs.agentName,
        specs.worktreePath,
        specs.branch,
        specs.baseBranch,
        specs.autoAdvance,
      ]) {
        await m.addColumn(specs, c);
      }
      await m.addColumn(sessions, sessions.specId);
      await m.addColumn(sessions, sessions.steps);
      await m.createTable(specSteps);
      if (await _hasTable('tasks')) await migrateTasksToSteps(this);
    } else if (from < 8 && await _hasTable('sessions')) {
      // Partial schemas (migration tests without `specs`): no foreign key
      // to a table that is not there.
      await customStatement(
        'ALTER TABLE sessions ADD COLUMN spec_id INTEGER NULL',
      );
      await m.addColumn(sessions, sessions.steps);
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v1 … v8: written by hand (the old tests start from partial schemas).
      if (from < 8) await _upgradeToV8(m, from);
      // v8 onwards: the steps generated from drift_schemas/
      // (`dart run drift_dev schema steps`); checked by
      // test/data/generated_migration_test.dart. The guards stay: a v7 → v8
      // upgrade creates spec_steps whole and partial schemas lack tables.
      await m.runMigrationSteps(
        from: from < 8 ? 8 : from,
        to: to,
        steps: migrationSteps(
          // v9: step gate and checkpoint; durable autopilot, review drafts
          // and notices.
          from8To9: (m, v) async {
            if (await _hasTable('spec_steps')) {
              for (final c in [
                v.specSteps.startSha,
                v.specSteps.startStash,
                v.specSteps.gateReport,
                v.specSteps.gateAttempts,
              ]) {
                if (!await _hasColumn('spec_steps', c.name)) {
                  await m.addColumn(v.specSteps, c);
                }
              }
            }
            if (await _hasTable('workspaces')) {
              await m.createTable(v.autopilotStates);
            }
            await m.createTable(v.reviewDrafts);
            if (await _hasTable('sessions')) {
              await m.createTable(v.pendingNotices);
            }
          },
          // v10: worktree index / preparation, automatic reviewer, review
          // comments by round, criteria, merge override, extra steps.
          from9To10: (m, v) async {
            if (!await _hasTable('specs')) return;
            for (final c in [
              v.specs.worktreeIndex,
              v.specs.preparedAt,
              v.specs.reviewPhase,
              v.specs.reviewRounds,
              v.specs.mergeOverride,
            ]) {
              if (!await _hasColumn('specs', c.name)) {
                await m.addColumn(v.specs, c);
              }
            }
            await m.createTable(v.reviewComments);
            await m.createTable(v.specCriteria);
            if (await _hasTable('spec_steps') &&
                !await _hasColumn('spec_steps', 'body')) {
              await m.addColumn(v.specSteps, v.specSteps.body);
            }
          },
          // v11: order of the cards and suggestions of the sessions.
          from10To11: (m, v) async {
            if (!await _hasTable('specs')) return;
            if (!await _hasColumn('specs', 'board_order')) {
              await m.addColumn(v.specs, v.specs.boardOrder);
            }
            await m.createTable(v.specSuggestions);
          },
          // v12: pid of the running `claude`, notification history.
          from11To12: (m, v) async {
            if (await _hasTable('sessions') &&
                !await _hasColumn('sessions', 'pid')) {
              await m.addColumn(v.sessions, v.sessions.pid);
            }
            await m.createTable(v.notifications);
          },
        ),
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Forces the connection to open (runs migrations). Used by the splash.
  Future<void> ensureOpen() => customSelect('SELECT 1').get();
}

/// `~/.local/share/promptorium` on Linux: the parent of path_provider's
/// application support dir (`$XDG_DATA_HOME/<application id>`) + `promptorium`.
Future<Directory> databaseDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(
    '${support.parent.path}${Platform.pathSeparator}promptorium',
  );
  await dir.create(recursive: true);
  return dir;
}

// --- backups (F11) -------------------------------------------------------------

/// Before a migration (`user_version` below [appSchemaVersion]) the file is
/// copied to `promptorium.sqlite.bak-v<N>` (`VACUUM INTO`). Runs on the raw
/// connection, outside any transaction (`DriftNativeOptions.setup`).
void backupBeforeMigration(CommonDatabase db) {
  try {
    final version = db.userVersion;
    if (version == 0 || version >= appSchemaVersion) return;
    final main = db
        .select('PRAGMA database_list')
        .where((r) => r['name'] == 'main')
        .firstOrNull;
    final file = '${main?['file'] ?? ''}';
    if (file.isEmpty) return; // in memory
    final bak = backupPath(file, version);
    if (File(bak).existsSync()) return;
    db.execute("VACUUM INTO '${bak.replaceAll("'", "''")}'");
  } catch (_) {
    // A failed backup must not stop the app from opening.
  }
}

String backupPath(String dbFile, int version) => '$dbFile.bak-v$version';

/// Backups next to the database, newest version first.
List<File> listBackups(Directory dir) {
  final re = RegExp(r'\.sqlite\.bak-v(\d+)$');
  final out = [
    for (final e in dir.listSync())
      if (e is File && re.hasMatch(e.path)) e,
  ];
  int v(File f) => int.parse(re.firstMatch(f.path)!.group(1)!);
  return out..sort((a, b) => v(b).compareTo(v(a)));
}

/// File asking the next launch to restore a backup (its path inside).
File restoreRequest(Directory dir) =>
    File('${dir.path}/${AppDatabase.fileName}.sqlite.restore');

/// "Restaurar backup" (Configurações): applied on the next launch, before
/// the database opens. The current file is kept as `.antes-da-restauracao`.
Future<void> requestRestore(Directory dir, File backup) =>
    restoreRequest(dir).writeAsString(backup.path);

void applyPendingRestore(Directory dir) {
  final req = restoreRequest(dir);
  if (!req.existsSync()) return;
  try {
    final backup = File(req.readAsStringSync().trim());
    final db = File('${dir.path}/${AppDatabase.fileName}.sqlite');
    if (backup.existsSync()) {
      if (db.existsSync()) db.copySync('${db.path}.antes-da-restauracao');
      for (final side in ['-wal', '-shm']) {
        final f = File('${db.path}$side');
        if (f.existsSync()) f.deleteSync();
      }
      backup.copySync(db.path);
    }
  } finally {
    req.deleteSync();
  }
}
