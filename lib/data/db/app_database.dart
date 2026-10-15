import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'enums.dart';

export 'enums.dart';

part 'app_database.g.dart';

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

  @override
  List<Set<Column>> get uniqueKeys => [
    {workspaceId, code},
  ];
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-disk database (`<data dir>/promptorium.sqlite`).
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: fileName,
      native: const DriftNativeOptions(databaseDirectory: databaseDirectory),
    ),
  );

  /// File name without the `.sqlite` extension (driftDatabase adds it).
  static const fileName = 'promptorium';

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
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
