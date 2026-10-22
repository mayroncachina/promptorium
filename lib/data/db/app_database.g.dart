// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WorkspacesTable extends Workspaces
    with TableInfo<$WorkspacesTable, Workspace> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, path, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspaces';
  @override
  VerificationContext validateIntegrity(
    Insertable<Workspace> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Workspace map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Workspace(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WorkspacesTable createAlias(String alias) {
    return $WorkspacesTable(attachedDatabase, alias);
  }
}

class Workspace extends DataClass implements Insertable<Workspace> {
  final int id;

  /// Absolute path of the repository root (`git rev-parse --show-toplevel`).
  final String path;
  final String name;
  final DateTime createdAt;
  const Workspace({
    required this.id,
    required this.path,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['path'] = Variable<String>(path);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WorkspacesCompanion toCompanion(bool nullToAbsent) {
    return WorkspacesCompanion(
      id: Value(id),
      path: Value(path),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory Workspace.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Workspace(
      id: serializer.fromJson<int>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'path': serializer.toJson<String>(path),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Workspace copyWith({
    int? id,
    String? path,
    String? name,
    DateTime? createdAt,
  }) => Workspace(
    id: id ?? this.id,
    path: path ?? this.path,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  Workspace copyWithCompanion(WorkspacesCompanion data) {
    return Workspace(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Workspace(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, path, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Workspace &&
          other.id == this.id &&
          other.path == this.path &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class WorkspacesCompanion extends UpdateCompanion<Workspace> {
  final Value<int> id;
  final Value<String> path;
  final Value<String> name;
  final Value<DateTime> createdAt;
  const WorkspacesCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  WorkspacesCompanion.insert({
    this.id = const Value.absent(),
    required String path,
    required String name,
    this.createdAt = const Value.absent(),
  }) : path = Value(path),
       name = Value(name);
  static Insertable<Workspace> custom({
    Expression<int>? id,
    Expression<String>? path,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  WorkspacesCompanion copyWith({
    Value<int>? id,
    Value<String>? path,
    Value<String>? name,
    Value<DateTime>? createdAt,
  }) {
    return WorkspacesCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspacesCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SpecsTable extends Specs with TableInfo<$SpecsTable, Spec> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpecsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<int> workspaceId = GeneratedColumn<int>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SpecStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(SpecStatus.draft.name),
      ).withConverter<SpecStatus>($SpecsTable.$converterstatus);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SpecStage, String> stage =
      GeneratedColumn<String>(
        'stage',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(SpecStage.backlog.name),
      ).withConverter<SpecStage>($SpecsTable.$converterstage);
  @override
  late final GeneratedColumnWithTypeConverter<
    List<({String id, String text})>,
    String
  >
  requirements =
      GeneratedColumn<String>(
        'requirements',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<({String id, String text})>>(
        $SpecsTable.$converterrequirements,
      );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> dependsOn =
      GeneratedColumn<String>(
        'depends_on',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($SpecsTable.$converterdependsOn);
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _worktreePathMeta = const VerificationMeta(
    'worktreePath',
  );
  @override
  late final GeneratedColumn<String> worktreePath = GeneratedColumn<String>(
    'worktree_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchMeta = const VerificationMeta('branch');
  @override
  late final GeneratedColumn<String> branch = GeneratedColumn<String>(
    'branch',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseBranchMeta = const VerificationMeta(
    'baseBranch',
  );
  @override
  late final GeneratedColumn<String> baseBranch = GeneratedColumn<String>(
    'base_branch',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoAdvanceMeta = const VerificationMeta(
    'autoAdvance',
  );
  @override
  late final GeneratedColumn<bool> autoAdvance = GeneratedColumn<bool>(
    'auto_advance',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_advance" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _worktreeIndexMeta = const VerificationMeta(
    'worktreeIndex',
  );
  @override
  late final GeneratedColumn<int> worktreeIndex = GeneratedColumn<int>(
    'worktree_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preparedAtMeta = const VerificationMeta(
    'preparedAt',
  );
  @override
  late final GeneratedColumn<DateTime> preparedAt = GeneratedColumn<DateTime>(
    'prepared_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewPhaseMeta = const VerificationMeta(
    'reviewPhase',
  );
  @override
  late final GeneratedColumn<String> reviewPhase = GeneratedColumn<String>(
    'review_phase',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewRoundsMeta = const VerificationMeta(
    'reviewRounds',
  );
  @override
  late final GeneratedColumn<int> reviewRounds = GeneratedColumn<int>(
    'review_rounds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mergeOverrideMeta = const VerificationMeta(
    'mergeOverride',
  );
  @override
  late final GeneratedColumn<String> mergeOverride = GeneratedColumn<String>(
    'merge_override',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _boardOrderMeta = const VerificationMeta(
    'boardOrder',
  );
  @override
  late final GeneratedColumn<int> boardOrder = GeneratedColumn<int>(
    'board_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gateResendsMeta = const VerificationMeta(
    'gateResends',
  );
  @override
  late final GeneratedColumn<int> gateResends = GeneratedColumn<int>(
    'gate_resends',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rejectedHunksMeta = const VerificationMeta(
    'rejectedHunks',
  );
  @override
  late final GeneratedColumn<int> rejectedHunks = GeneratedColumn<int>(
    'rejected_hunks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    code,
    title,
    status,
    path,
    stage,
    requirements,
    dependsOn,
    phase,
    agentName,
    worktreePath,
    branch,
    baseBranch,
    autoAdvance,
    worktreeIndex,
    preparedAt,
    reviewPhase,
    reviewRounds,
    mergeOverride,
    boardOrder,
    gateResends,
    rejectedHunks,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'specs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Spec> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    }
    if (data.containsKey('worktree_path')) {
      context.handle(
        _worktreePathMeta,
        worktreePath.isAcceptableOrUnknown(
          data['worktree_path']!,
          _worktreePathMeta,
        ),
      );
    }
    if (data.containsKey('branch')) {
      context.handle(
        _branchMeta,
        branch.isAcceptableOrUnknown(data['branch']!, _branchMeta),
      );
    }
    if (data.containsKey('base_branch')) {
      context.handle(
        _baseBranchMeta,
        baseBranch.isAcceptableOrUnknown(data['base_branch']!, _baseBranchMeta),
      );
    }
    if (data.containsKey('auto_advance')) {
      context.handle(
        _autoAdvanceMeta,
        autoAdvance.isAcceptableOrUnknown(
          data['auto_advance']!,
          _autoAdvanceMeta,
        ),
      );
    }
    if (data.containsKey('worktree_index')) {
      context.handle(
        _worktreeIndexMeta,
        worktreeIndex.isAcceptableOrUnknown(
          data['worktree_index']!,
          _worktreeIndexMeta,
        ),
      );
    }
    if (data.containsKey('prepared_at')) {
      context.handle(
        _preparedAtMeta,
        preparedAt.isAcceptableOrUnknown(data['prepared_at']!, _preparedAtMeta),
      );
    }
    if (data.containsKey('review_phase')) {
      context.handle(
        _reviewPhaseMeta,
        reviewPhase.isAcceptableOrUnknown(
          data['review_phase']!,
          _reviewPhaseMeta,
        ),
      );
    }
    if (data.containsKey('review_rounds')) {
      context.handle(
        _reviewRoundsMeta,
        reviewRounds.isAcceptableOrUnknown(
          data['review_rounds']!,
          _reviewRoundsMeta,
        ),
      );
    }
    if (data.containsKey('merge_override')) {
      context.handle(
        _mergeOverrideMeta,
        mergeOverride.isAcceptableOrUnknown(
          data['merge_override']!,
          _mergeOverrideMeta,
        ),
      );
    }
    if (data.containsKey('board_order')) {
      context.handle(
        _boardOrderMeta,
        boardOrder.isAcceptableOrUnknown(data['board_order']!, _boardOrderMeta),
      );
    }
    if (data.containsKey('gate_resends')) {
      context.handle(
        _gateResendsMeta,
        gateResends.isAcceptableOrUnknown(
          data['gate_resends']!,
          _gateResendsMeta,
        ),
      );
    }
    if (data.containsKey('rejected_hunks')) {
      context.handle(
        _rejectedHunksMeta,
        rejectedHunks.isAcceptableOrUnknown(
          data['rejected_hunks']!,
          _rejectedHunksMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, code},
  ];
  @override
  Spec map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Spec(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workspace_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      status: $SpecsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      stage: $SpecsTable.$converterstage.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}stage'],
        )!,
      ),
      requirements: $SpecsTable.$converterrequirements.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}requirements'],
        )!,
      ),
      dependsOn: $SpecsTable.$converterdependsOn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}depends_on'],
        )!,
      ),
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      ),
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      ),
      worktreePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}worktree_path'],
      ),
      branch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch'],
      ),
      baseBranch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_branch'],
      ),
      autoAdvance: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_advance'],
      )!,
      worktreeIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}worktree_index'],
      ),
      preparedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}prepared_at'],
      ),
      reviewPhase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_phase'],
      ),
      reviewRounds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}review_rounds'],
      )!,
      mergeOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merge_override'],
      ),
      boardOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}board_order'],
      ),
      gateResends: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gate_resends'],
      )!,
      rejectedHunks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rejected_hunks'],
      )!,
    );
  }

  @override
  $SpecsTable createAlias(String alias) {
    return $SpecsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SpecStatus, String, String> $converterstatus =
      const EnumNameConverter<SpecStatus>(SpecStatus.values);
  static JsonTypeConverter2<SpecStage, String, String> $converterstage =
      const EnumNameConverter<SpecStage>(SpecStage.values);
  static TypeConverter<List<({String id, String text})>, String>
  $converterrequirements = const RequirementListConverter();
  static TypeConverter<List<String>, String> $converterdependsOn =
      const StringListConverter();
}

class Spec extends DataClass implements Insertable<Spec> {
  final int id;
  final int workspaceId;

  /// `SPEC-001`.
  final String code;
  final String title;
  final SpecStatus status;

  /// Path relative to the workspace root.
  final String path;

  /// Column of the Quadro.
  final SpecStage stage;

  /// Mirror of the file's requirements: the steps of the card (`R1`…).
  final List<({String id, String text})> requirements;

  /// Codes of the specs that must be done first (frontmatter `depende-de`).
  final List<String> dependsOn;

  /// Frontmatter `fase` (`fundacao`, `mvp`…).
  final String? phase;

  /// Agent of the step sessions (`--agent`).
  final String? agentName;

  /// Worktree / branch shared by every step session (`pr/spec-003-<slug>`),
  /// and the branch it came from (merge target). Null = not started.
  final String? worktreePath;
  final String? branch;
  final String? baseBranch;

  /// A finished step opens the session of the next one.
  final bool autoAdvance;

  /// Smallest free index among the workspace's live spec worktrees:
  /// `PROMPTORIUM_PORT` = `porta-base` + index.
  final int? worktreeIndex;

  /// When the worktree got the `copiar:` files and ran `preparar:` (null =
  /// not prepared yet: the next run prepares it first).
  final DateTime? preparedAt;

  /// `auto` while the automatic reviewer works on the spec, `human` after
  /// it approved or ran out of rounds (null = no reviewer).
  final String? reviewPhase;

  /// Correction rounds asked by the automatic reviewer.
  final int reviewRounds;

  /// Reason given for "Mergear mesmo assim" with acceptance criteria
  /// unchecked.
  final String? mergeOverride;

  /// Position in its column of the Quadro (schema v11; null = by code).
  final int? boardOrder;

  /// Failures of the step gate sent back to the agent (automatic fixes).
  final int gateResends;

  /// Hunks rejected in the Review.
  final int rejectedHunks;
  const Spec({
    required this.id,
    required this.workspaceId,
    required this.code,
    required this.title,
    required this.status,
    required this.path,
    required this.stage,
    required this.requirements,
    required this.dependsOn,
    this.phase,
    this.agentName,
    this.worktreePath,
    this.branch,
    this.baseBranch,
    required this.autoAdvance,
    this.worktreeIndex,
    this.preparedAt,
    this.reviewPhase,
    required this.reviewRounds,
    this.mergeOverride,
    this.boardOrder,
    required this.gateResends,
    required this.rejectedHunks,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['workspace_id'] = Variable<int>(workspaceId);
    map['code'] = Variable<String>(code);
    map['title'] = Variable<String>(title);
    {
      map['status'] = Variable<String>(
        $SpecsTable.$converterstatus.toSql(status),
      );
    }
    map['path'] = Variable<String>(path);
    {
      map['stage'] = Variable<String>($SpecsTable.$converterstage.toSql(stage));
    }
    {
      map['requirements'] = Variable<String>(
        $SpecsTable.$converterrequirements.toSql(requirements),
      );
    }
    {
      map['depends_on'] = Variable<String>(
        $SpecsTable.$converterdependsOn.toSql(dependsOn),
      );
    }
    if (!nullToAbsent || phase != null) {
      map['phase'] = Variable<String>(phase);
    }
    if (!nullToAbsent || agentName != null) {
      map['agent_name'] = Variable<String>(agentName);
    }
    if (!nullToAbsent || worktreePath != null) {
      map['worktree_path'] = Variable<String>(worktreePath);
    }
    if (!nullToAbsent || branch != null) {
      map['branch'] = Variable<String>(branch);
    }
    if (!nullToAbsent || baseBranch != null) {
      map['base_branch'] = Variable<String>(baseBranch);
    }
    map['auto_advance'] = Variable<bool>(autoAdvance);
    if (!nullToAbsent || worktreeIndex != null) {
      map['worktree_index'] = Variable<int>(worktreeIndex);
    }
    if (!nullToAbsent || preparedAt != null) {
      map['prepared_at'] = Variable<DateTime>(preparedAt);
    }
    if (!nullToAbsent || reviewPhase != null) {
      map['review_phase'] = Variable<String>(reviewPhase);
    }
    map['review_rounds'] = Variable<int>(reviewRounds);
    if (!nullToAbsent || mergeOverride != null) {
      map['merge_override'] = Variable<String>(mergeOverride);
    }
    if (!nullToAbsent || boardOrder != null) {
      map['board_order'] = Variable<int>(boardOrder);
    }
    map['gate_resends'] = Variable<int>(gateResends);
    map['rejected_hunks'] = Variable<int>(rejectedHunks);
    return map;
  }

  SpecsCompanion toCompanion(bool nullToAbsent) {
    return SpecsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      code: Value(code),
      title: Value(title),
      status: Value(status),
      path: Value(path),
      stage: Value(stage),
      requirements: Value(requirements),
      dependsOn: Value(dependsOn),
      phase: phase == null && nullToAbsent
          ? const Value.absent()
          : Value(phase),
      agentName: agentName == null && nullToAbsent
          ? const Value.absent()
          : Value(agentName),
      worktreePath: worktreePath == null && nullToAbsent
          ? const Value.absent()
          : Value(worktreePath),
      branch: branch == null && nullToAbsent
          ? const Value.absent()
          : Value(branch),
      baseBranch: baseBranch == null && nullToAbsent
          ? const Value.absent()
          : Value(baseBranch),
      autoAdvance: Value(autoAdvance),
      worktreeIndex: worktreeIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(worktreeIndex),
      preparedAt: preparedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(preparedAt),
      reviewPhase: reviewPhase == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewPhase),
      reviewRounds: Value(reviewRounds),
      mergeOverride: mergeOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(mergeOverride),
      boardOrder: boardOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(boardOrder),
      gateResends: Value(gateResends),
      rejectedHunks: Value(rejectedHunks),
    );
  }

  factory Spec.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Spec(
      id: serializer.fromJson<int>(json['id']),
      workspaceId: serializer.fromJson<int>(json['workspaceId']),
      code: serializer.fromJson<String>(json['code']),
      title: serializer.fromJson<String>(json['title']),
      status: $SpecsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      path: serializer.fromJson<String>(json['path']),
      stage: $SpecsTable.$converterstage.fromJson(
        serializer.fromJson<String>(json['stage']),
      ),
      requirements: serializer.fromJson<List<({String id, String text})>>(
        json['requirements'],
      ),
      dependsOn: serializer.fromJson<List<String>>(json['dependsOn']),
      phase: serializer.fromJson<String?>(json['phase']),
      agentName: serializer.fromJson<String?>(json['agentName']),
      worktreePath: serializer.fromJson<String?>(json['worktreePath']),
      branch: serializer.fromJson<String?>(json['branch']),
      baseBranch: serializer.fromJson<String?>(json['baseBranch']),
      autoAdvance: serializer.fromJson<bool>(json['autoAdvance']),
      worktreeIndex: serializer.fromJson<int?>(json['worktreeIndex']),
      preparedAt: serializer.fromJson<DateTime?>(json['preparedAt']),
      reviewPhase: serializer.fromJson<String?>(json['reviewPhase']),
      reviewRounds: serializer.fromJson<int>(json['reviewRounds']),
      mergeOverride: serializer.fromJson<String?>(json['mergeOverride']),
      boardOrder: serializer.fromJson<int?>(json['boardOrder']),
      gateResends: serializer.fromJson<int>(json['gateResends']),
      rejectedHunks: serializer.fromJson<int>(json['rejectedHunks']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'workspaceId': serializer.toJson<int>(workspaceId),
      'code': serializer.toJson<String>(code),
      'title': serializer.toJson<String>(title),
      'status': serializer.toJson<String>(
        $SpecsTable.$converterstatus.toJson(status),
      ),
      'path': serializer.toJson<String>(path),
      'stage': serializer.toJson<String>(
        $SpecsTable.$converterstage.toJson(stage),
      ),
      'requirements': serializer.toJson<List<({String id, String text})>>(
        requirements,
      ),
      'dependsOn': serializer.toJson<List<String>>(dependsOn),
      'phase': serializer.toJson<String?>(phase),
      'agentName': serializer.toJson<String?>(agentName),
      'worktreePath': serializer.toJson<String?>(worktreePath),
      'branch': serializer.toJson<String?>(branch),
      'baseBranch': serializer.toJson<String?>(baseBranch),
      'autoAdvance': serializer.toJson<bool>(autoAdvance),
      'worktreeIndex': serializer.toJson<int?>(worktreeIndex),
      'preparedAt': serializer.toJson<DateTime?>(preparedAt),
      'reviewPhase': serializer.toJson<String?>(reviewPhase),
      'reviewRounds': serializer.toJson<int>(reviewRounds),
      'mergeOverride': serializer.toJson<String?>(mergeOverride),
      'boardOrder': serializer.toJson<int?>(boardOrder),
      'gateResends': serializer.toJson<int>(gateResends),
      'rejectedHunks': serializer.toJson<int>(rejectedHunks),
    };
  }

  Spec copyWith({
    int? id,
    int? workspaceId,
    String? code,
    String? title,
    SpecStatus? status,
    String? path,
    SpecStage? stage,
    List<({String id, String text})>? requirements,
    List<String>? dependsOn,
    Value<String?> phase = const Value.absent(),
    Value<String?> agentName = const Value.absent(),
    Value<String?> worktreePath = const Value.absent(),
    Value<String?> branch = const Value.absent(),
    Value<String?> baseBranch = const Value.absent(),
    bool? autoAdvance,
    Value<int?> worktreeIndex = const Value.absent(),
    Value<DateTime?> preparedAt = const Value.absent(),
    Value<String?> reviewPhase = const Value.absent(),
    int? reviewRounds,
    Value<String?> mergeOverride = const Value.absent(),
    Value<int?> boardOrder = const Value.absent(),
    int? gateResends,
    int? rejectedHunks,
  }) => Spec(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    code: code ?? this.code,
    title: title ?? this.title,
    status: status ?? this.status,
    path: path ?? this.path,
    stage: stage ?? this.stage,
    requirements: requirements ?? this.requirements,
    dependsOn: dependsOn ?? this.dependsOn,
    phase: phase.present ? phase.value : this.phase,
    agentName: agentName.present ? agentName.value : this.agentName,
    worktreePath: worktreePath.present ? worktreePath.value : this.worktreePath,
    branch: branch.present ? branch.value : this.branch,
    baseBranch: baseBranch.present ? baseBranch.value : this.baseBranch,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    worktreeIndex: worktreeIndex.present
        ? worktreeIndex.value
        : this.worktreeIndex,
    preparedAt: preparedAt.present ? preparedAt.value : this.preparedAt,
    reviewPhase: reviewPhase.present ? reviewPhase.value : this.reviewPhase,
    reviewRounds: reviewRounds ?? this.reviewRounds,
    mergeOverride: mergeOverride.present
        ? mergeOverride.value
        : this.mergeOverride,
    boardOrder: boardOrder.present ? boardOrder.value : this.boardOrder,
    gateResends: gateResends ?? this.gateResends,
    rejectedHunks: rejectedHunks ?? this.rejectedHunks,
  );
  Spec copyWithCompanion(SpecsCompanion data) {
    return Spec(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      code: data.code.present ? data.code.value : this.code,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      path: data.path.present ? data.path.value : this.path,
      stage: data.stage.present ? data.stage.value : this.stage,
      requirements: data.requirements.present
          ? data.requirements.value
          : this.requirements,
      dependsOn: data.dependsOn.present ? data.dependsOn.value : this.dependsOn,
      phase: data.phase.present ? data.phase.value : this.phase,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      worktreePath: data.worktreePath.present
          ? data.worktreePath.value
          : this.worktreePath,
      branch: data.branch.present ? data.branch.value : this.branch,
      baseBranch: data.baseBranch.present
          ? data.baseBranch.value
          : this.baseBranch,
      autoAdvance: data.autoAdvance.present
          ? data.autoAdvance.value
          : this.autoAdvance,
      worktreeIndex: data.worktreeIndex.present
          ? data.worktreeIndex.value
          : this.worktreeIndex,
      preparedAt: data.preparedAt.present
          ? data.preparedAt.value
          : this.preparedAt,
      reviewPhase: data.reviewPhase.present
          ? data.reviewPhase.value
          : this.reviewPhase,
      reviewRounds: data.reviewRounds.present
          ? data.reviewRounds.value
          : this.reviewRounds,
      mergeOverride: data.mergeOverride.present
          ? data.mergeOverride.value
          : this.mergeOverride,
      boardOrder: data.boardOrder.present
          ? data.boardOrder.value
          : this.boardOrder,
      gateResends: data.gateResends.present
          ? data.gateResends.value
          : this.gateResends,
      rejectedHunks: data.rejectedHunks.present
          ? data.rejectedHunks.value
          : this.rejectedHunks,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Spec(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('code: $code, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('path: $path, ')
          ..write('stage: $stage, ')
          ..write('requirements: $requirements, ')
          ..write('dependsOn: $dependsOn, ')
          ..write('phase: $phase, ')
          ..write('agentName: $agentName, ')
          ..write('worktreePath: $worktreePath, ')
          ..write('branch: $branch, ')
          ..write('baseBranch: $baseBranch, ')
          ..write('autoAdvance: $autoAdvance, ')
          ..write('worktreeIndex: $worktreeIndex, ')
          ..write('preparedAt: $preparedAt, ')
          ..write('reviewPhase: $reviewPhase, ')
          ..write('reviewRounds: $reviewRounds, ')
          ..write('mergeOverride: $mergeOverride, ')
          ..write('boardOrder: $boardOrder, ')
          ..write('gateResends: $gateResends, ')
          ..write('rejectedHunks: $rejectedHunks')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    workspaceId,
    code,
    title,
    status,
    path,
    stage,
    requirements,
    dependsOn,
    phase,
    agentName,
    worktreePath,
    branch,
    baseBranch,
    autoAdvance,
    worktreeIndex,
    preparedAt,
    reviewPhase,
    reviewRounds,
    mergeOverride,
    boardOrder,
    gateResends,
    rejectedHunks,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Spec &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.code == this.code &&
          other.title == this.title &&
          other.status == this.status &&
          other.path == this.path &&
          other.stage == this.stage &&
          other.requirements == this.requirements &&
          other.dependsOn == this.dependsOn &&
          other.phase == this.phase &&
          other.agentName == this.agentName &&
          other.worktreePath == this.worktreePath &&
          other.branch == this.branch &&
          other.baseBranch == this.baseBranch &&
          other.autoAdvance == this.autoAdvance &&
          other.worktreeIndex == this.worktreeIndex &&
          other.preparedAt == this.preparedAt &&
          other.reviewPhase == this.reviewPhase &&
          other.reviewRounds == this.reviewRounds &&
          other.mergeOverride == this.mergeOverride &&
          other.boardOrder == this.boardOrder &&
          other.gateResends == this.gateResends &&
          other.rejectedHunks == this.rejectedHunks);
}

class SpecsCompanion extends UpdateCompanion<Spec> {
  final Value<int> id;
  final Value<int> workspaceId;
  final Value<String> code;
  final Value<String> title;
  final Value<SpecStatus> status;
  final Value<String> path;
  final Value<SpecStage> stage;
  final Value<List<({String id, String text})>> requirements;
  final Value<List<String>> dependsOn;
  final Value<String?> phase;
  final Value<String?> agentName;
  final Value<String?> worktreePath;
  final Value<String?> branch;
  final Value<String?> baseBranch;
  final Value<bool> autoAdvance;
  final Value<int?> worktreeIndex;
  final Value<DateTime?> preparedAt;
  final Value<String?> reviewPhase;
  final Value<int> reviewRounds;
  final Value<String?> mergeOverride;
  final Value<int?> boardOrder;
  final Value<int> gateResends;
  final Value<int> rejectedHunks;
  const SpecsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.code = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.path = const Value.absent(),
    this.stage = const Value.absent(),
    this.requirements = const Value.absent(),
    this.dependsOn = const Value.absent(),
    this.phase = const Value.absent(),
    this.agentName = const Value.absent(),
    this.worktreePath = const Value.absent(),
    this.branch = const Value.absent(),
    this.baseBranch = const Value.absent(),
    this.autoAdvance = const Value.absent(),
    this.worktreeIndex = const Value.absent(),
    this.preparedAt = const Value.absent(),
    this.reviewPhase = const Value.absent(),
    this.reviewRounds = const Value.absent(),
    this.mergeOverride = const Value.absent(),
    this.boardOrder = const Value.absent(),
    this.gateResends = const Value.absent(),
    this.rejectedHunks = const Value.absent(),
  });
  SpecsCompanion.insert({
    this.id = const Value.absent(),
    required int workspaceId,
    required String code,
    required String title,
    this.status = const Value.absent(),
    required String path,
    this.stage = const Value.absent(),
    this.requirements = const Value.absent(),
    this.dependsOn = const Value.absent(),
    this.phase = const Value.absent(),
    this.agentName = const Value.absent(),
    this.worktreePath = const Value.absent(),
    this.branch = const Value.absent(),
    this.baseBranch = const Value.absent(),
    this.autoAdvance = const Value.absent(),
    this.worktreeIndex = const Value.absent(),
    this.preparedAt = const Value.absent(),
    this.reviewPhase = const Value.absent(),
    this.reviewRounds = const Value.absent(),
    this.mergeOverride = const Value.absent(),
    this.boardOrder = const Value.absent(),
    this.gateResends = const Value.absent(),
    this.rejectedHunks = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       code = Value(code),
       title = Value(title),
       path = Value(path);
  static Insertable<Spec> custom({
    Expression<int>? id,
    Expression<int>? workspaceId,
    Expression<String>? code,
    Expression<String>? title,
    Expression<String>? status,
    Expression<String>? path,
    Expression<String>? stage,
    Expression<String>? requirements,
    Expression<String>? dependsOn,
    Expression<String>? phase,
    Expression<String>? agentName,
    Expression<String>? worktreePath,
    Expression<String>? branch,
    Expression<String>? baseBranch,
    Expression<bool>? autoAdvance,
    Expression<int>? worktreeIndex,
    Expression<DateTime>? preparedAt,
    Expression<String>? reviewPhase,
    Expression<int>? reviewRounds,
    Expression<String>? mergeOverride,
    Expression<int>? boardOrder,
    Expression<int>? gateResends,
    Expression<int>? rejectedHunks,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (code != null) 'code': code,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (path != null) 'path': path,
      if (stage != null) 'stage': stage,
      if (requirements != null) 'requirements': requirements,
      if (dependsOn != null) 'depends_on': dependsOn,
      if (phase != null) 'phase': phase,
      if (agentName != null) 'agent_name': agentName,
      if (worktreePath != null) 'worktree_path': worktreePath,
      if (branch != null) 'branch': branch,
      if (baseBranch != null) 'base_branch': baseBranch,
      if (autoAdvance != null) 'auto_advance': autoAdvance,
      if (worktreeIndex != null) 'worktree_index': worktreeIndex,
      if (preparedAt != null) 'prepared_at': preparedAt,
      if (reviewPhase != null) 'review_phase': reviewPhase,
      if (reviewRounds != null) 'review_rounds': reviewRounds,
      if (mergeOverride != null) 'merge_override': mergeOverride,
      if (boardOrder != null) 'board_order': boardOrder,
      if (gateResends != null) 'gate_resends': gateResends,
      if (rejectedHunks != null) 'rejected_hunks': rejectedHunks,
    });
  }

  SpecsCompanion copyWith({
    Value<int>? id,
    Value<int>? workspaceId,
    Value<String>? code,
    Value<String>? title,
    Value<SpecStatus>? status,
    Value<String>? path,
    Value<SpecStage>? stage,
    Value<List<({String id, String text})>>? requirements,
    Value<List<String>>? dependsOn,
    Value<String?>? phase,
    Value<String?>? agentName,
    Value<String?>? worktreePath,
    Value<String?>? branch,
    Value<String?>? baseBranch,
    Value<bool>? autoAdvance,
    Value<int?>? worktreeIndex,
    Value<DateTime?>? preparedAt,
    Value<String?>? reviewPhase,
    Value<int>? reviewRounds,
    Value<String?>? mergeOverride,
    Value<int?>? boardOrder,
    Value<int>? gateResends,
    Value<int>? rejectedHunks,
  }) {
    return SpecsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      code: code ?? this.code,
      title: title ?? this.title,
      status: status ?? this.status,
      path: path ?? this.path,
      stage: stage ?? this.stage,
      requirements: requirements ?? this.requirements,
      dependsOn: dependsOn ?? this.dependsOn,
      phase: phase ?? this.phase,
      agentName: agentName ?? this.agentName,
      worktreePath: worktreePath ?? this.worktreePath,
      branch: branch ?? this.branch,
      baseBranch: baseBranch ?? this.baseBranch,
      autoAdvance: autoAdvance ?? this.autoAdvance,
      worktreeIndex: worktreeIndex ?? this.worktreeIndex,
      preparedAt: preparedAt ?? this.preparedAt,
      reviewPhase: reviewPhase ?? this.reviewPhase,
      reviewRounds: reviewRounds ?? this.reviewRounds,
      mergeOverride: mergeOverride ?? this.mergeOverride,
      boardOrder: boardOrder ?? this.boardOrder,
      gateResends: gateResends ?? this.gateResends,
      rejectedHunks: rejectedHunks ?? this.rejectedHunks,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<int>(workspaceId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $SpecsTable.$converterstatus.toSql(status.value),
      );
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(
        $SpecsTable.$converterstage.toSql(stage.value),
      );
    }
    if (requirements.present) {
      map['requirements'] = Variable<String>(
        $SpecsTable.$converterrequirements.toSql(requirements.value),
      );
    }
    if (dependsOn.present) {
      map['depends_on'] = Variable<String>(
        $SpecsTable.$converterdependsOn.toSql(dependsOn.value),
      );
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (worktreePath.present) {
      map['worktree_path'] = Variable<String>(worktreePath.value);
    }
    if (branch.present) {
      map['branch'] = Variable<String>(branch.value);
    }
    if (baseBranch.present) {
      map['base_branch'] = Variable<String>(baseBranch.value);
    }
    if (autoAdvance.present) {
      map['auto_advance'] = Variable<bool>(autoAdvance.value);
    }
    if (worktreeIndex.present) {
      map['worktree_index'] = Variable<int>(worktreeIndex.value);
    }
    if (preparedAt.present) {
      map['prepared_at'] = Variable<DateTime>(preparedAt.value);
    }
    if (reviewPhase.present) {
      map['review_phase'] = Variable<String>(reviewPhase.value);
    }
    if (reviewRounds.present) {
      map['review_rounds'] = Variable<int>(reviewRounds.value);
    }
    if (mergeOverride.present) {
      map['merge_override'] = Variable<String>(mergeOverride.value);
    }
    if (boardOrder.present) {
      map['board_order'] = Variable<int>(boardOrder.value);
    }
    if (gateResends.present) {
      map['gate_resends'] = Variable<int>(gateResends.value);
    }
    if (rejectedHunks.present) {
      map['rejected_hunks'] = Variable<int>(rejectedHunks.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpecsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('code: $code, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('path: $path, ')
          ..write('stage: $stage, ')
          ..write('requirements: $requirements, ')
          ..write('dependsOn: $dependsOn, ')
          ..write('phase: $phase, ')
          ..write('agentName: $agentName, ')
          ..write('worktreePath: $worktreePath, ')
          ..write('branch: $branch, ')
          ..write('baseBranch: $baseBranch, ')
          ..write('autoAdvance: $autoAdvance, ')
          ..write('worktreeIndex: $worktreeIndex, ')
          ..write('preparedAt: $preparedAt, ')
          ..write('reviewPhase: $reviewPhase, ')
          ..write('reviewRounds: $reviewRounds, ')
          ..write('mergeOverride: $mergeOverride, ')
          ..write('boardOrder: $boardOrder, ')
          ..write('gateResends: $gateResends, ')
          ..write('rejectedHunks: $rejectedHunks')
          ..write(')'))
        .toString();
  }
}

class $SpecStepsTable extends SpecSteps
    with TableInfo<$SpecStepsTable, SpecStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpecStepsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _specIdMeta = const VerificationMeta('specId');
  @override
  late final GeneratedColumn<int> specId = GeneratedColumn<int>(
    'spec_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<String> step = GeneratedColumn<String>(
    'step',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<StepStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(StepStatus.pending.name),
      ).withConverter<StepStatus>($SpecStepsTable.$converterstatus);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doneAtMeta = const VerificationMeta('doneAt');
  @override
  late final GeneratedColumn<DateTime> doneAt = GeneratedColumn<DateTime>(
    'done_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startShaMeta = const VerificationMeta(
    'startSha',
  );
  @override
  late final GeneratedColumn<String> startSha = GeneratedColumn<String>(
    'start_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startStashMeta = const VerificationMeta(
    'startStash',
  );
  @override
  late final GeneratedColumn<String> startStash = GeneratedColumn<String>(
    'start_stash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gateReportMeta = const VerificationMeta(
    'gateReport',
  );
  @override
  late final GeneratedColumn<String> gateReport = GeneratedColumn<String>(
    'gate_report',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gateAttemptsMeta = const VerificationMeta(
    'gateAttempts',
  );
  @override
  late final GeneratedColumn<int> gateAttempts = GeneratedColumn<int>(
    'gate_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    specId,
    step,
    status,
    sessionId,
    doneAt,
    startSha,
    startStash,
    gateReport,
    gateAttempts,
    body,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spec_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpecStep> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('spec_id')) {
      context.handle(
        _specIdMeta,
        specId.isAcceptableOrUnknown(data['spec_id']!, _specIdMeta),
      );
    } else if (isInserting) {
      context.missing(_specIdMeta);
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    } else if (isInserting) {
      context.missing(_stepMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('done_at')) {
      context.handle(
        _doneAtMeta,
        doneAt.isAcceptableOrUnknown(data['done_at']!, _doneAtMeta),
      );
    }
    if (data.containsKey('start_sha')) {
      context.handle(
        _startShaMeta,
        startSha.isAcceptableOrUnknown(data['start_sha']!, _startShaMeta),
      );
    }
    if (data.containsKey('start_stash')) {
      context.handle(
        _startStashMeta,
        startStash.isAcceptableOrUnknown(data['start_stash']!, _startStashMeta),
      );
    }
    if (data.containsKey('gate_report')) {
      context.handle(
        _gateReportMeta,
        gateReport.isAcceptableOrUnknown(data['gate_report']!, _gateReportMeta),
      );
    }
    if (data.containsKey('gate_attempts')) {
      context.handle(
        _gateAttemptsMeta,
        gateAttempts.isAcceptableOrUnknown(
          data['gate_attempts']!,
          _gateAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {specId, step};
  @override
  SpecStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpecStep(
      specId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spec_id'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step'],
      )!,
      status: $SpecStepsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      doneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}done_at'],
      ),
      startSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_sha'],
      ),
      startStash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_stash'],
      ),
      gateReport: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gate_report'],
      ),
      gateAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gate_attempts'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
    );
  }

  @override
  $SpecStepsTable createAlias(String alias) {
    return $SpecStepsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<StepStatus, String, String> $converterstatus =
      const EnumNameConverter<StepStatus>(StepStatus.values);
}

class SpecStep extends DataClass implements Insertable<SpecStep> {
  final int specId;

  /// Requirement id (`R1`).
  final String step;
  final StepStatus status;

  /// Last session that worked on the step.
  final String? sessionId;
  final DateTime? doneAt;

  /// HEAD of the worktree when the step's session started (the gate looks
  /// for the step's commit after it; "Voltar ao início da etapa" goes back
  /// to it, also kept as `refs/promptorium/<spec>/<step>-inicio`).
  final String? startSha;

  /// `git stash create` of the uncommitted changes at that moment.
  final String? startStash;

  /// JSON of the last `GateReport`.
  final String? gateReport;

  /// Automatic resends after a failed gate, in the current session.
  final int gateAttempts;

  /// Text of a step that is not in the file (schema v10): `REV1`, the
  /// corrections asked by the automatic reviewer.
  final String? body;
  const SpecStep({
    required this.specId,
    required this.step,
    required this.status,
    this.sessionId,
    this.doneAt,
    this.startSha,
    this.startStash,
    this.gateReport,
    required this.gateAttempts,
    this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['spec_id'] = Variable<int>(specId);
    map['step'] = Variable<String>(step);
    {
      map['status'] = Variable<String>(
        $SpecStepsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    if (!nullToAbsent || doneAt != null) {
      map['done_at'] = Variable<DateTime>(doneAt);
    }
    if (!nullToAbsent || startSha != null) {
      map['start_sha'] = Variable<String>(startSha);
    }
    if (!nullToAbsent || startStash != null) {
      map['start_stash'] = Variable<String>(startStash);
    }
    if (!nullToAbsent || gateReport != null) {
      map['gate_report'] = Variable<String>(gateReport);
    }
    map['gate_attempts'] = Variable<int>(gateAttempts);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    return map;
  }

  SpecStepsCompanion toCompanion(bool nullToAbsent) {
    return SpecStepsCompanion(
      specId: Value(specId),
      step: Value(step),
      status: Value(status),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      doneAt: doneAt == null && nullToAbsent
          ? const Value.absent()
          : Value(doneAt),
      startSha: startSha == null && nullToAbsent
          ? const Value.absent()
          : Value(startSha),
      startStash: startStash == null && nullToAbsent
          ? const Value.absent()
          : Value(startStash),
      gateReport: gateReport == null && nullToAbsent
          ? const Value.absent()
          : Value(gateReport),
      gateAttempts: Value(gateAttempts),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
    );
  }

  factory SpecStep.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpecStep(
      specId: serializer.fromJson<int>(json['specId']),
      step: serializer.fromJson<String>(json['step']),
      status: $SpecStepsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      doneAt: serializer.fromJson<DateTime?>(json['doneAt']),
      startSha: serializer.fromJson<String?>(json['startSha']),
      startStash: serializer.fromJson<String?>(json['startStash']),
      gateReport: serializer.fromJson<String?>(json['gateReport']),
      gateAttempts: serializer.fromJson<int>(json['gateAttempts']),
      body: serializer.fromJson<String?>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'specId': serializer.toJson<int>(specId),
      'step': serializer.toJson<String>(step),
      'status': serializer.toJson<String>(
        $SpecStepsTable.$converterstatus.toJson(status),
      ),
      'sessionId': serializer.toJson<String?>(sessionId),
      'doneAt': serializer.toJson<DateTime?>(doneAt),
      'startSha': serializer.toJson<String?>(startSha),
      'startStash': serializer.toJson<String?>(startStash),
      'gateReport': serializer.toJson<String?>(gateReport),
      'gateAttempts': serializer.toJson<int>(gateAttempts),
      'body': serializer.toJson<String?>(body),
    };
  }

  SpecStep copyWith({
    int? specId,
    String? step,
    StepStatus? status,
    Value<String?> sessionId = const Value.absent(),
    Value<DateTime?> doneAt = const Value.absent(),
    Value<String?> startSha = const Value.absent(),
    Value<String?> startStash = const Value.absent(),
    Value<String?> gateReport = const Value.absent(),
    int? gateAttempts,
    Value<String?> body = const Value.absent(),
  }) => SpecStep(
    specId: specId ?? this.specId,
    step: step ?? this.step,
    status: status ?? this.status,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    doneAt: doneAt.present ? doneAt.value : this.doneAt,
    startSha: startSha.present ? startSha.value : this.startSha,
    startStash: startStash.present ? startStash.value : this.startStash,
    gateReport: gateReport.present ? gateReport.value : this.gateReport,
    gateAttempts: gateAttempts ?? this.gateAttempts,
    body: body.present ? body.value : this.body,
  );
  SpecStep copyWithCompanion(SpecStepsCompanion data) {
    return SpecStep(
      specId: data.specId.present ? data.specId.value : this.specId,
      step: data.step.present ? data.step.value : this.step,
      status: data.status.present ? data.status.value : this.status,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      doneAt: data.doneAt.present ? data.doneAt.value : this.doneAt,
      startSha: data.startSha.present ? data.startSha.value : this.startSha,
      startStash: data.startStash.present
          ? data.startStash.value
          : this.startStash,
      gateReport: data.gateReport.present
          ? data.gateReport.value
          : this.gateReport,
      gateAttempts: data.gateAttempts.present
          ? data.gateAttempts.value
          : this.gateAttempts,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpecStep(')
          ..write('specId: $specId, ')
          ..write('step: $step, ')
          ..write('status: $status, ')
          ..write('sessionId: $sessionId, ')
          ..write('doneAt: $doneAt, ')
          ..write('startSha: $startSha, ')
          ..write('startStash: $startStash, ')
          ..write('gateReport: $gateReport, ')
          ..write('gateAttempts: $gateAttempts, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    specId,
    step,
    status,
    sessionId,
    doneAt,
    startSha,
    startStash,
    gateReport,
    gateAttempts,
    body,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpecStep &&
          other.specId == this.specId &&
          other.step == this.step &&
          other.status == this.status &&
          other.sessionId == this.sessionId &&
          other.doneAt == this.doneAt &&
          other.startSha == this.startSha &&
          other.startStash == this.startStash &&
          other.gateReport == this.gateReport &&
          other.gateAttempts == this.gateAttempts &&
          other.body == this.body);
}

class SpecStepsCompanion extends UpdateCompanion<SpecStep> {
  final Value<int> specId;
  final Value<String> step;
  final Value<StepStatus> status;
  final Value<String?> sessionId;
  final Value<DateTime?> doneAt;
  final Value<String?> startSha;
  final Value<String?> startStash;
  final Value<String?> gateReport;
  final Value<int> gateAttempts;
  final Value<String?> body;
  final Value<int> rowid;
  const SpecStepsCompanion({
    this.specId = const Value.absent(),
    this.step = const Value.absent(),
    this.status = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.startSha = const Value.absent(),
    this.startStash = const Value.absent(),
    this.gateReport = const Value.absent(),
    this.gateAttempts = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SpecStepsCompanion.insert({
    required int specId,
    required String step,
    this.status = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.startSha = const Value.absent(),
    this.startStash = const Value.absent(),
    this.gateReport = const Value.absent(),
    this.gateAttempts = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : specId = Value(specId),
       step = Value(step);
  static Insertable<SpecStep> custom({
    Expression<int>? specId,
    Expression<String>? step,
    Expression<String>? status,
    Expression<String>? sessionId,
    Expression<DateTime>? doneAt,
    Expression<String>? startSha,
    Expression<String>? startStash,
    Expression<String>? gateReport,
    Expression<int>? gateAttempts,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (specId != null) 'spec_id': specId,
      if (step != null) 'step': step,
      if (status != null) 'status': status,
      if (sessionId != null) 'session_id': sessionId,
      if (doneAt != null) 'done_at': doneAt,
      if (startSha != null) 'start_sha': startSha,
      if (startStash != null) 'start_stash': startStash,
      if (gateReport != null) 'gate_report': gateReport,
      if (gateAttempts != null) 'gate_attempts': gateAttempts,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SpecStepsCompanion copyWith({
    Value<int>? specId,
    Value<String>? step,
    Value<StepStatus>? status,
    Value<String?>? sessionId,
    Value<DateTime?>? doneAt,
    Value<String?>? startSha,
    Value<String?>? startStash,
    Value<String?>? gateReport,
    Value<int>? gateAttempts,
    Value<String?>? body,
    Value<int>? rowid,
  }) {
    return SpecStepsCompanion(
      specId: specId ?? this.specId,
      step: step ?? this.step,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      doneAt: doneAt ?? this.doneAt,
      startSha: startSha ?? this.startSha,
      startStash: startStash ?? this.startStash,
      gateReport: gateReport ?? this.gateReport,
      gateAttempts: gateAttempts ?? this.gateAttempts,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (specId.present) {
      map['spec_id'] = Variable<int>(specId.value);
    }
    if (step.present) {
      map['step'] = Variable<String>(step.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $SpecStepsTable.$converterstatus.toSql(status.value),
      );
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (doneAt.present) {
      map['done_at'] = Variable<DateTime>(doneAt.value);
    }
    if (startSha.present) {
      map['start_sha'] = Variable<String>(startSha.value);
    }
    if (startStash.present) {
      map['start_stash'] = Variable<String>(startStash.value);
    }
    if (gateReport.present) {
      map['gate_report'] = Variable<String>(gateReport.value);
    }
    if (gateAttempts.present) {
      map['gate_attempts'] = Variable<int>(gateAttempts.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpecStepsCompanion(')
          ..write('specId: $specId, ')
          ..write('step: $step, ')
          ..write('status: $status, ')
          ..write('sessionId: $sessionId, ')
          ..write('doneAt: $doneAt, ')
          ..write('startSha: $startSha, ')
          ..write('startStash: $startStash, ')
          ..write('gateReport: $gateReport, ')
          ..write('gateAttempts: $gateAttempts, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _specIdMeta = const VerificationMeta('specId');
  @override
  late final GeneratedColumn<int> specId = GeneratedColumn<int>(
    'spec_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specs (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<int> workspaceId = GeneratedColumn<int>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TaskStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(TaskStatus.backlog.name),
      ).withConverter<TaskStatus>($TasksTable.$converterstatus);
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requirementMeta = const VerificationMeta(
    'requirement',
  );
  @override
  late final GeneratedColumn<String> requirement = GeneratedColumn<String>(
    'requirement',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> dependsOn =
      GeneratedColumn<String>(
        'depends_on',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($TasksTable.$converterdependsOn);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    specId,
    workspaceId,
    code,
    title,
    status,
    agentName,
    body,
    requirement,
    dependsOn,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Task> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('spec_id')) {
      context.handle(
        _specIdMeta,
        specId.isAcceptableOrUnknown(data['spec_id']!, _specIdMeta),
      );
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('requirement')) {
      context.handle(
        _requirementMeta,
        requirement.isAcceptableOrUnknown(
          data['requirement']!,
          _requirementMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, code},
  ];
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      specId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spec_id'],
      ),
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workspace_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      status: $TasksTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      requirement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requirement'],
      ),
      dependsOn: $TasksTable.$converterdependsOn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}depends_on'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TaskStatus, String, String> $converterstatus =
      const EnumNameConverter<TaskStatus>(TaskStatus.values);
  static TypeConverter<List<String>, String> $converterdependsOn =
      const StringListConverter();
}

class Task extends DataClass implements Insertable<Task> {
  final int id;
  final int? specId;
  final int workspaceId;

  /// `TASK-001` (Fase 8; rows created before use `T-001`).
  final String code;
  final String title;
  final TaskStatus status;
  final String? agentName;

  /// Free text of the task (schema v3; e.g. the Prompt answer it came from).
  final String? body;

  /// Spec requirement the task implements, e.g. `R2` (schema v4, Fase 8:
  /// traceability requirement → task → session → commit).
  final String? requirement;

  /// Codes of the tasks this one depends on (JSON array).
  final List<String> dependsOn;
  final DateTime createdAt;
  const Task({
    required this.id,
    this.specId,
    required this.workspaceId,
    required this.code,
    required this.title,
    required this.status,
    this.agentName,
    this.body,
    this.requirement,
    required this.dependsOn,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || specId != null) {
      map['spec_id'] = Variable<int>(specId);
    }
    map['workspace_id'] = Variable<int>(workspaceId);
    map['code'] = Variable<String>(code);
    map['title'] = Variable<String>(title);
    {
      map['status'] = Variable<String>(
        $TasksTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || agentName != null) {
      map['agent_name'] = Variable<String>(agentName);
    }
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    if (!nullToAbsent || requirement != null) {
      map['requirement'] = Variable<String>(requirement);
    }
    {
      map['depends_on'] = Variable<String>(
        $TasksTable.$converterdependsOn.toSql(dependsOn),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      specId: specId == null && nullToAbsent
          ? const Value.absent()
          : Value(specId),
      workspaceId: Value(workspaceId),
      code: Value(code),
      title: Value(title),
      status: Value(status),
      agentName: agentName == null && nullToAbsent
          ? const Value.absent()
          : Value(agentName),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      requirement: requirement == null && nullToAbsent
          ? const Value.absent()
          : Value(requirement),
      dependsOn: Value(dependsOn),
      createdAt: Value(createdAt),
    );
  }

  factory Task.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<int>(json['id']),
      specId: serializer.fromJson<int?>(json['specId']),
      workspaceId: serializer.fromJson<int>(json['workspaceId']),
      code: serializer.fromJson<String>(json['code']),
      title: serializer.fromJson<String>(json['title']),
      status: $TasksTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      agentName: serializer.fromJson<String?>(json['agentName']),
      body: serializer.fromJson<String?>(json['body']),
      requirement: serializer.fromJson<String?>(json['requirement']),
      dependsOn: serializer.fromJson<List<String>>(json['dependsOn']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'specId': serializer.toJson<int?>(specId),
      'workspaceId': serializer.toJson<int>(workspaceId),
      'code': serializer.toJson<String>(code),
      'title': serializer.toJson<String>(title),
      'status': serializer.toJson<String>(
        $TasksTable.$converterstatus.toJson(status),
      ),
      'agentName': serializer.toJson<String?>(agentName),
      'body': serializer.toJson<String?>(body),
      'requirement': serializer.toJson<String?>(requirement),
      'dependsOn': serializer.toJson<List<String>>(dependsOn),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Task copyWith({
    int? id,
    Value<int?> specId = const Value.absent(),
    int? workspaceId,
    String? code,
    String? title,
    TaskStatus? status,
    Value<String?> agentName = const Value.absent(),
    Value<String?> body = const Value.absent(),
    Value<String?> requirement = const Value.absent(),
    List<String>? dependsOn,
    DateTime? createdAt,
  }) => Task(
    id: id ?? this.id,
    specId: specId.present ? specId.value : this.specId,
    workspaceId: workspaceId ?? this.workspaceId,
    code: code ?? this.code,
    title: title ?? this.title,
    status: status ?? this.status,
    agentName: agentName.present ? agentName.value : this.agentName,
    body: body.present ? body.value : this.body,
    requirement: requirement.present ? requirement.value : this.requirement,
    dependsOn: dependsOn ?? this.dependsOn,
    createdAt: createdAt ?? this.createdAt,
  );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      specId: data.specId.present ? data.specId.value : this.specId,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      code: data.code.present ? data.code.value : this.code,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      body: data.body.present ? data.body.value : this.body,
      requirement: data.requirement.present
          ? data.requirement.value
          : this.requirement,
      dependsOn: data.dependsOn.present ? data.dependsOn.value : this.dependsOn,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('code: $code, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('agentName: $agentName, ')
          ..write('body: $body, ')
          ..write('requirement: $requirement, ')
          ..write('dependsOn: $dependsOn, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    specId,
    workspaceId,
    code,
    title,
    status,
    agentName,
    body,
    requirement,
    dependsOn,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.specId == this.specId &&
          other.workspaceId == this.workspaceId &&
          other.code == this.code &&
          other.title == this.title &&
          other.status == this.status &&
          other.agentName == this.agentName &&
          other.body == this.body &&
          other.requirement == this.requirement &&
          other.dependsOn == this.dependsOn &&
          other.createdAt == this.createdAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<int> id;
  final Value<int?> specId;
  final Value<int> workspaceId;
  final Value<String> code;
  final Value<String> title;
  final Value<TaskStatus> status;
  final Value<String?> agentName;
  final Value<String?> body;
  final Value<String?> requirement;
  final Value<List<String>> dependsOn;
  final Value<DateTime> createdAt;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.specId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.code = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.agentName = const Value.absent(),
    this.body = const Value.absent(),
    this.requirement = const Value.absent(),
    this.dependsOn = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TasksCompanion.insert({
    this.id = const Value.absent(),
    this.specId = const Value.absent(),
    required int workspaceId,
    required String code,
    required String title,
    this.status = const Value.absent(),
    this.agentName = const Value.absent(),
    this.body = const Value.absent(),
    this.requirement = const Value.absent(),
    this.dependsOn = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       code = Value(code),
       title = Value(title);
  static Insertable<Task> custom({
    Expression<int>? id,
    Expression<int>? specId,
    Expression<int>? workspaceId,
    Expression<String>? code,
    Expression<String>? title,
    Expression<String>? status,
    Expression<String>? agentName,
    Expression<String>? body,
    Expression<String>? requirement,
    Expression<String>? dependsOn,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (specId != null) 'spec_id': specId,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (code != null) 'code': code,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (agentName != null) 'agent_name': agentName,
      if (body != null) 'body': body,
      if (requirement != null) 'requirement': requirement,
      if (dependsOn != null) 'depends_on': dependsOn,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TasksCompanion copyWith({
    Value<int>? id,
    Value<int?>? specId,
    Value<int>? workspaceId,
    Value<String>? code,
    Value<String>? title,
    Value<TaskStatus>? status,
    Value<String?>? agentName,
    Value<String?>? body,
    Value<String?>? requirement,
    Value<List<String>>? dependsOn,
    Value<DateTime>? createdAt,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      specId: specId ?? this.specId,
      workspaceId: workspaceId ?? this.workspaceId,
      code: code ?? this.code,
      title: title ?? this.title,
      status: status ?? this.status,
      agentName: agentName ?? this.agentName,
      body: body ?? this.body,
      requirement: requirement ?? this.requirement,
      dependsOn: dependsOn ?? this.dependsOn,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (specId.present) {
      map['spec_id'] = Variable<int>(specId.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<int>(workspaceId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $TasksTable.$converterstatus.toSql(status.value),
      );
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (requirement.present) {
      map['requirement'] = Variable<String>(requirement.value);
    }
    if (dependsOn.present) {
      map['depends_on'] = Variable<String>(
        $TasksTable.$converterdependsOn.toSql(dependsOn.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('code: $code, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('agentName: $agentName, ')
          ..write('body: $body, ')
          ..write('requirement: $requirement, ')
          ..write('dependsOn: $dependsOn, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('claude'),
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _runConfigMeta = const VerificationMeta(
    'runConfig',
  );
  @override
  late final GeneratedColumn<String> runConfig = GeneratedColumn<String>(
    'run_config',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<int> workspaceId = GeneratedColumn<int>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<int> taskId = GeneratedColumn<int>(
    'task_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _permissionModeMeta = const VerificationMeta(
    'permissionMode',
  );
  @override
  late final GeneratedColumn<String> permissionMode = GeneratedColumn<String>(
    'permission_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _worktreePathMeta = const VerificationMeta(
    'worktreePath',
  );
  @override
  late final GeneratedColumn<String> worktreePath = GeneratedColumn<String>(
    'worktree_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchMeta = const VerificationMeta('branch');
  @override
  late final GeneratedColumn<String> branch = GeneratedColumn<String>(
    'branch',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SessionStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(SessionStatus.running.name),
      ).withConverter<SessionStatus>($SessionsTable.$converterstatus);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _specIdMeta = const VerificationMeta('specId');
  @override
  late final GeneratedColumn<int> specId = GeneratedColumn<int>(
    'spec_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specs (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<String> steps = GeneratedColumn<String>(
    'steps',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effortMeta = const VerificationMeta('effort');
  @override
  late final GeneratedColumn<String> effort = GeneratedColumn<String>(
    'effort',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _costUsdMeta = const VerificationMeta(
    'costUsd',
  );
  @override
  late final GeneratedColumn<double> costUsd = GeneratedColumn<double>(
    'cost_usd',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tokensInMeta = const VerificationMeta(
    'tokensIn',
  );
  @override
  late final GeneratedColumn<int> tokensIn = GeneratedColumn<int>(
    'tokens_in',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tokensOutMeta = const VerificationMeta(
    'tokensOut',
  );
  @override
  late final GeneratedColumn<int> tokensOut = GeneratedColumn<int>(
    'tokens_out',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseBranchMeta = const VerificationMeta(
    'baseBranch',
  );
  @override
  late final GeneratedColumn<String> baseBranch = GeneratedColumn<String>(
    'base_branch',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mergeCommitMeta = const VerificationMeta(
    'mergeCommit',
  );
  @override
  late final GeneratedColumn<String> mergeCommit = GeneratedColumn<String>(
    'merge_commit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _prUrlMeta = const VerificationMeta('prUrl');
  @override
  late final GeneratedColumn<String> prUrl = GeneratedColumn<String>(
    'pr_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<int> pid = GeneratedColumn<int>(
    'pid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _duelIdMeta = const VerificationMeta('duelId');
  @override
  late final GeneratedColumn<int> duelId = GeneratedColumn<int>(
    'duel_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    provider,
    externalId,
    runConfig,
    id,
    workspaceId,
    taskId,
    agentName,
    title,
    permissionMode,
    worktreePath,
    branch,
    status,
    model,
    specId,
    steps,
    effort,
    costUsd,
    tokensIn,
    tokensOut,
    startedAt,
    endedAt,
    baseBranch,
    mergeCommit,
    prUrl,
    pid,
    duelId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('run_config')) {
      context.handle(
        _runConfigMeta,
        runConfig.isAcceptableOrUnknown(data['run_config']!, _runConfigMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('permission_mode')) {
      context.handle(
        _permissionModeMeta,
        permissionMode.isAcceptableOrUnknown(
          data['permission_mode']!,
          _permissionModeMeta,
        ),
      );
    }
    if (data.containsKey('worktree_path')) {
      context.handle(
        _worktreePathMeta,
        worktreePath.isAcceptableOrUnknown(
          data['worktree_path']!,
          _worktreePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_worktreePathMeta);
    }
    if (data.containsKey('branch')) {
      context.handle(
        _branchMeta,
        branch.isAcceptableOrUnknown(data['branch']!, _branchMeta),
      );
    } else if (isInserting) {
      context.missing(_branchMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('spec_id')) {
      context.handle(
        _specIdMeta,
        specId.isAcceptableOrUnknown(data['spec_id']!, _specIdMeta),
      );
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    }
    if (data.containsKey('effort')) {
      context.handle(
        _effortMeta,
        effort.isAcceptableOrUnknown(data['effort']!, _effortMeta),
      );
    }
    if (data.containsKey('cost_usd')) {
      context.handle(
        _costUsdMeta,
        costUsd.isAcceptableOrUnknown(data['cost_usd']!, _costUsdMeta),
      );
    }
    if (data.containsKey('tokens_in')) {
      context.handle(
        _tokensInMeta,
        tokensIn.isAcceptableOrUnknown(data['tokens_in']!, _tokensInMeta),
      );
    }
    if (data.containsKey('tokens_out')) {
      context.handle(
        _tokensOutMeta,
        tokensOut.isAcceptableOrUnknown(data['tokens_out']!, _tokensOutMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('base_branch')) {
      context.handle(
        _baseBranchMeta,
        baseBranch.isAcceptableOrUnknown(data['base_branch']!, _baseBranchMeta),
      );
    }
    if (data.containsKey('merge_commit')) {
      context.handle(
        _mergeCommitMeta,
        mergeCommit.isAcceptableOrUnknown(
          data['merge_commit']!,
          _mergeCommitMeta,
        ),
      );
    }
    if (data.containsKey('pr_url')) {
      context.handle(
        _prUrlMeta,
        prUrl.isAcceptableOrUnknown(data['pr_url']!, _prUrlMeta),
      );
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    }
    if (data.containsKey('duel_id')) {
      context.handle(
        _duelIdMeta,
        duelId.isAcceptableOrUnknown(data['duel_id']!, _duelIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      runConfig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_config'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workspace_id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}task_id'],
      ),
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      permissionMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}permission_mode'],
      ),
      worktreePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}worktree_path'],
      )!,
      branch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch'],
      )!,
      status: $SessionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      specId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spec_id'],
      ),
      steps: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}steps'],
      ),
      effort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effort'],
      ),
      costUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost_usd'],
      )!,
      tokensIn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tokens_in'],
      )!,
      tokensOut: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tokens_out'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      baseBranch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_branch'],
      ),
      mergeCommit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merge_commit'],
      ),
      prUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pr_url'],
      ),
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pid'],
      ),
      duelId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duel_id'],
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SessionStatus, String, String> $converterstatus =
      const EnumNameConverter<SessionStatus>(SessionStatus.values);
}

class Session extends DataClass implements Insertable<Session> {
  final String provider;
  final String? externalId;
  final String? runConfig;

  /// UUID passed to `--session-id` / `--resume`.
  final String id;
  final int workspaceId;
  final int? taskId;
  final String? agentName;

  /// Name shown in the list (schema v2). Null for v1 rows.
  final String? title;

  /// CLI `--permission-mode` value used to (re)start the process (schema v2).
  final String? permissionMode;
  final String worktreePath;
  final String branch;
  final SessionStatus status;
  final String model;

  /// Spec (card) the session works on and the steps it was given (`R2` or
  /// `R2,R3`; schema v8).
  final int? specId;
  final String? steps;

  /// `--effort` used to (re)start the process (schema v7). Null = rows
  /// written before: resumes use the default of Configurações.
  final String? effort;
  final double costUsd;
  final int tokensIn;
  final int tokensOut;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Branch the worktree was created from (merge target of the Review;
  /// schema v5). Null for rows written before / sessions without worktree.
  final String? baseBranch;

  /// Hash of the merge commit made by the Review (schema v5, Fase 9).
  final String? mergeCommit;

  /// URL of the pull request opened by the Review (schema v5).
  final String? prUrl;

  /// PID of the `claude` process while it runs (schema v12): the next
  /// launch ends the ones left behind by a crash of the app.
  final int? pid;

  /// Best-of-N attempt it belongs to (schema v14; `spec_duels.id`): its
  /// result does not move the spec's steps, the user picks a winner.
  final int? duelId;
  const Session({
    required this.provider,
    this.externalId,
    this.runConfig,
    required this.id,
    required this.workspaceId,
    this.taskId,
    this.agentName,
    this.title,
    this.permissionMode,
    required this.worktreePath,
    required this.branch,
    required this.status,
    required this.model,
    this.specId,
    this.steps,
    this.effort,
    required this.costUsd,
    required this.tokensIn,
    required this.tokensOut,
    required this.startedAt,
    this.endedAt,
    this.baseBranch,
    this.mergeCommit,
    this.prUrl,
    this.pid,
    this.duelId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provider'] = Variable<String>(provider);
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    if (!nullToAbsent || runConfig != null) {
      map['run_config'] = Variable<String>(runConfig);
    }
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<int>(workspaceId);
    if (!nullToAbsent || taskId != null) {
      map['task_id'] = Variable<int>(taskId);
    }
    if (!nullToAbsent || agentName != null) {
      map['agent_name'] = Variable<String>(agentName);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || permissionMode != null) {
      map['permission_mode'] = Variable<String>(permissionMode);
    }
    map['worktree_path'] = Variable<String>(worktreePath);
    map['branch'] = Variable<String>(branch);
    {
      map['status'] = Variable<String>(
        $SessionsTable.$converterstatus.toSql(status),
      );
    }
    map['model'] = Variable<String>(model);
    if (!nullToAbsent || specId != null) {
      map['spec_id'] = Variable<int>(specId);
    }
    if (!nullToAbsent || steps != null) {
      map['steps'] = Variable<String>(steps);
    }
    if (!nullToAbsent || effort != null) {
      map['effort'] = Variable<String>(effort);
    }
    map['cost_usd'] = Variable<double>(costUsd);
    map['tokens_in'] = Variable<int>(tokensIn);
    map['tokens_out'] = Variable<int>(tokensOut);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    if (!nullToAbsent || baseBranch != null) {
      map['base_branch'] = Variable<String>(baseBranch);
    }
    if (!nullToAbsent || mergeCommit != null) {
      map['merge_commit'] = Variable<String>(mergeCommit);
    }
    if (!nullToAbsent || prUrl != null) {
      map['pr_url'] = Variable<String>(prUrl);
    }
    if (!nullToAbsent || pid != null) {
      map['pid'] = Variable<int>(pid);
    }
    if (!nullToAbsent || duelId != null) {
      map['duel_id'] = Variable<int>(duelId);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      provider: Value(provider),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      runConfig: runConfig == null && nullToAbsent
          ? const Value.absent()
          : Value(runConfig),
      id: Value(id),
      workspaceId: Value(workspaceId),
      taskId: taskId == null && nullToAbsent
          ? const Value.absent()
          : Value(taskId),
      agentName: agentName == null && nullToAbsent
          ? const Value.absent()
          : Value(agentName),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      permissionMode: permissionMode == null && nullToAbsent
          ? const Value.absent()
          : Value(permissionMode),
      worktreePath: Value(worktreePath),
      branch: Value(branch),
      status: Value(status),
      model: Value(model),
      specId: specId == null && nullToAbsent
          ? const Value.absent()
          : Value(specId),
      steps: steps == null && nullToAbsent
          ? const Value.absent()
          : Value(steps),
      effort: effort == null && nullToAbsent
          ? const Value.absent()
          : Value(effort),
      costUsd: Value(costUsd),
      tokensIn: Value(tokensIn),
      tokensOut: Value(tokensOut),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      baseBranch: baseBranch == null && nullToAbsent
          ? const Value.absent()
          : Value(baseBranch),
      mergeCommit: mergeCommit == null && nullToAbsent
          ? const Value.absent()
          : Value(mergeCommit),
      prUrl: prUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(prUrl),
      pid: pid == null && nullToAbsent ? const Value.absent() : Value(pid),
      duelId: duelId == null && nullToAbsent
          ? const Value.absent()
          : Value(duelId),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      provider: serializer.fromJson<String>(json['provider']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      runConfig: serializer.fromJson<String?>(json['runConfig']),
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<int>(json['workspaceId']),
      taskId: serializer.fromJson<int?>(json['taskId']),
      agentName: serializer.fromJson<String?>(json['agentName']),
      title: serializer.fromJson<String?>(json['title']),
      permissionMode: serializer.fromJson<String?>(json['permissionMode']),
      worktreePath: serializer.fromJson<String>(json['worktreePath']),
      branch: serializer.fromJson<String>(json['branch']),
      status: $SessionsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      model: serializer.fromJson<String>(json['model']),
      specId: serializer.fromJson<int?>(json['specId']),
      steps: serializer.fromJson<String?>(json['steps']),
      effort: serializer.fromJson<String?>(json['effort']),
      costUsd: serializer.fromJson<double>(json['costUsd']),
      tokensIn: serializer.fromJson<int>(json['tokensIn']),
      tokensOut: serializer.fromJson<int>(json['tokensOut']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      baseBranch: serializer.fromJson<String?>(json['baseBranch']),
      mergeCommit: serializer.fromJson<String?>(json['mergeCommit']),
      prUrl: serializer.fromJson<String?>(json['prUrl']),
      pid: serializer.fromJson<int?>(json['pid']),
      duelId: serializer.fromJson<int?>(json['duelId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'provider': serializer.toJson<String>(provider),
      'externalId': serializer.toJson<String?>(externalId),
      'runConfig': serializer.toJson<String?>(runConfig),
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<int>(workspaceId),
      'taskId': serializer.toJson<int?>(taskId),
      'agentName': serializer.toJson<String?>(agentName),
      'title': serializer.toJson<String?>(title),
      'permissionMode': serializer.toJson<String?>(permissionMode),
      'worktreePath': serializer.toJson<String>(worktreePath),
      'branch': serializer.toJson<String>(branch),
      'status': serializer.toJson<String>(
        $SessionsTable.$converterstatus.toJson(status),
      ),
      'model': serializer.toJson<String>(model),
      'specId': serializer.toJson<int?>(specId),
      'steps': serializer.toJson<String?>(steps),
      'effort': serializer.toJson<String?>(effort),
      'costUsd': serializer.toJson<double>(costUsd),
      'tokensIn': serializer.toJson<int>(tokensIn),
      'tokensOut': serializer.toJson<int>(tokensOut),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'baseBranch': serializer.toJson<String?>(baseBranch),
      'mergeCommit': serializer.toJson<String?>(mergeCommit),
      'prUrl': serializer.toJson<String?>(prUrl),
      'pid': serializer.toJson<int?>(pid),
      'duelId': serializer.toJson<int?>(duelId),
    };
  }

  Session copyWith({
    String? provider,
    Value<String?> externalId = const Value.absent(),
    Value<String?> runConfig = const Value.absent(),
    String? id,
    int? workspaceId,
    Value<int?> taskId = const Value.absent(),
    Value<String?> agentName = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> permissionMode = const Value.absent(),
    String? worktreePath,
    String? branch,
    SessionStatus? status,
    String? model,
    Value<int?> specId = const Value.absent(),
    Value<String?> steps = const Value.absent(),
    Value<String?> effort = const Value.absent(),
    double? costUsd,
    int? tokensIn,
    int? tokensOut,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    Value<String?> baseBranch = const Value.absent(),
    Value<String?> mergeCommit = const Value.absent(),
    Value<String?> prUrl = const Value.absent(),
    Value<int?> pid = const Value.absent(),
    Value<int?> duelId = const Value.absent(),
  }) => Session(
    provider: provider ?? this.provider,
    externalId: externalId.present ? externalId.value : this.externalId,
    runConfig: runConfig.present ? runConfig.value : this.runConfig,
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    taskId: taskId.present ? taskId.value : this.taskId,
    agentName: agentName.present ? agentName.value : this.agentName,
    title: title.present ? title.value : this.title,
    permissionMode: permissionMode.present
        ? permissionMode.value
        : this.permissionMode,
    worktreePath: worktreePath ?? this.worktreePath,
    branch: branch ?? this.branch,
    status: status ?? this.status,
    model: model ?? this.model,
    specId: specId.present ? specId.value : this.specId,
    steps: steps.present ? steps.value : this.steps,
    effort: effort.present ? effort.value : this.effort,
    costUsd: costUsd ?? this.costUsd,
    tokensIn: tokensIn ?? this.tokensIn,
    tokensOut: tokensOut ?? this.tokensOut,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    baseBranch: baseBranch.present ? baseBranch.value : this.baseBranch,
    mergeCommit: mergeCommit.present ? mergeCommit.value : this.mergeCommit,
    prUrl: prUrl.present ? prUrl.value : this.prUrl,
    pid: pid.present ? pid.value : this.pid,
    duelId: duelId.present ? duelId.value : this.duelId,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      provider: data.provider.present ? data.provider.value : this.provider,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      runConfig: data.runConfig.present ? data.runConfig.value : this.runConfig,
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      title: data.title.present ? data.title.value : this.title,
      permissionMode: data.permissionMode.present
          ? data.permissionMode.value
          : this.permissionMode,
      worktreePath: data.worktreePath.present
          ? data.worktreePath.value
          : this.worktreePath,
      branch: data.branch.present ? data.branch.value : this.branch,
      status: data.status.present ? data.status.value : this.status,
      model: data.model.present ? data.model.value : this.model,
      specId: data.specId.present ? data.specId.value : this.specId,
      steps: data.steps.present ? data.steps.value : this.steps,
      effort: data.effort.present ? data.effort.value : this.effort,
      costUsd: data.costUsd.present ? data.costUsd.value : this.costUsd,
      tokensIn: data.tokensIn.present ? data.tokensIn.value : this.tokensIn,
      tokensOut: data.tokensOut.present ? data.tokensOut.value : this.tokensOut,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      baseBranch: data.baseBranch.present
          ? data.baseBranch.value
          : this.baseBranch,
      mergeCommit: data.mergeCommit.present
          ? data.mergeCommit.value
          : this.mergeCommit,
      prUrl: data.prUrl.present ? data.prUrl.value : this.prUrl,
      pid: data.pid.present ? data.pid.value : this.pid,
      duelId: data.duelId.present ? data.duelId.value : this.duelId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('runConfig: $runConfig, ')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('taskId: $taskId, ')
          ..write('agentName: $agentName, ')
          ..write('title: $title, ')
          ..write('permissionMode: $permissionMode, ')
          ..write('worktreePath: $worktreePath, ')
          ..write('branch: $branch, ')
          ..write('status: $status, ')
          ..write('model: $model, ')
          ..write('specId: $specId, ')
          ..write('steps: $steps, ')
          ..write('effort: $effort, ')
          ..write('costUsd: $costUsd, ')
          ..write('tokensIn: $tokensIn, ')
          ..write('tokensOut: $tokensOut, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('baseBranch: $baseBranch, ')
          ..write('mergeCommit: $mergeCommit, ')
          ..write('prUrl: $prUrl, ')
          ..write('pid: $pid, ')
          ..write('duelId: $duelId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    provider,
    externalId,
    runConfig,
    id,
    workspaceId,
    taskId,
    agentName,
    title,
    permissionMode,
    worktreePath,
    branch,
    status,
    model,
    specId,
    steps,
    effort,
    costUsd,
    tokensIn,
    tokensOut,
    startedAt,
    endedAt,
    baseBranch,
    mergeCommit,
    prUrl,
    pid,
    duelId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.provider == this.provider &&
          other.externalId == this.externalId &&
          other.runConfig == this.runConfig &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.taskId == this.taskId &&
          other.agentName == this.agentName &&
          other.title == this.title &&
          other.permissionMode == this.permissionMode &&
          other.worktreePath == this.worktreePath &&
          other.branch == this.branch &&
          other.status == this.status &&
          other.model == this.model &&
          other.specId == this.specId &&
          other.steps == this.steps &&
          other.effort == this.effort &&
          other.costUsd == this.costUsd &&
          other.tokensIn == this.tokensIn &&
          other.tokensOut == this.tokensOut &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.baseBranch == this.baseBranch &&
          other.mergeCommit == this.mergeCommit &&
          other.prUrl == this.prUrl &&
          other.pid == this.pid &&
          other.duelId == this.duelId);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> provider;
  final Value<String?> externalId;
  final Value<String?> runConfig;
  final Value<String> id;
  final Value<int> workspaceId;
  final Value<int?> taskId;
  final Value<String?> agentName;
  final Value<String?> title;
  final Value<String?> permissionMode;
  final Value<String> worktreePath;
  final Value<String> branch;
  final Value<SessionStatus> status;
  final Value<String> model;
  final Value<int?> specId;
  final Value<String?> steps;
  final Value<String?> effort;
  final Value<double> costUsd;
  final Value<int> tokensIn;
  final Value<int> tokensOut;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<String?> baseBranch;
  final Value<String?> mergeCommit;
  final Value<String?> prUrl;
  final Value<int?> pid;
  final Value<int?> duelId;
  final Value<int> rowid;
  const SessionsCompanion({
    this.provider = const Value.absent(),
    this.externalId = const Value.absent(),
    this.runConfig = const Value.absent(),
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.agentName = const Value.absent(),
    this.title = const Value.absent(),
    this.permissionMode = const Value.absent(),
    this.worktreePath = const Value.absent(),
    this.branch = const Value.absent(),
    this.status = const Value.absent(),
    this.model = const Value.absent(),
    this.specId = const Value.absent(),
    this.steps = const Value.absent(),
    this.effort = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.tokensIn = const Value.absent(),
    this.tokensOut = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.baseBranch = const Value.absent(),
    this.mergeCommit = const Value.absent(),
    this.prUrl = const Value.absent(),
    this.pid = const Value.absent(),
    this.duelId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    this.provider = const Value.absent(),
    this.externalId = const Value.absent(),
    this.runConfig = const Value.absent(),
    required String id,
    required int workspaceId,
    this.taskId = const Value.absent(),
    this.agentName = const Value.absent(),
    this.title = const Value.absent(),
    this.permissionMode = const Value.absent(),
    required String worktreePath,
    required String branch,
    this.status = const Value.absent(),
    required String model,
    this.specId = const Value.absent(),
    this.steps = const Value.absent(),
    this.effort = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.tokensIn = const Value.absent(),
    this.tokensOut = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.baseBranch = const Value.absent(),
    this.mergeCommit = const Value.absent(),
    this.prUrl = const Value.absent(),
    this.pid = const Value.absent(),
    this.duelId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       worktreePath = Value(worktreePath),
       branch = Value(branch),
       model = Value(model);
  static Insertable<Session> custom({
    Expression<String>? provider,
    Expression<String>? externalId,
    Expression<String>? runConfig,
    Expression<String>? id,
    Expression<int>? workspaceId,
    Expression<int>? taskId,
    Expression<String>? agentName,
    Expression<String>? title,
    Expression<String>? permissionMode,
    Expression<String>? worktreePath,
    Expression<String>? branch,
    Expression<String>? status,
    Expression<String>? model,
    Expression<int>? specId,
    Expression<String>? steps,
    Expression<String>? effort,
    Expression<double>? costUsd,
    Expression<int>? tokensIn,
    Expression<int>? tokensOut,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<String>? baseBranch,
    Expression<String>? mergeCommit,
    Expression<String>? prUrl,
    Expression<int>? pid,
    Expression<int>? duelId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (provider != null) 'provider': provider,
      if (externalId != null) 'external_id': externalId,
      if (runConfig != null) 'run_config': runConfig,
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (taskId != null) 'task_id': taskId,
      if (agentName != null) 'agent_name': agentName,
      if (title != null) 'title': title,
      if (permissionMode != null) 'permission_mode': permissionMode,
      if (worktreePath != null) 'worktree_path': worktreePath,
      if (branch != null) 'branch': branch,
      if (status != null) 'status': status,
      if (model != null) 'model': model,
      if (specId != null) 'spec_id': specId,
      if (steps != null) 'steps': steps,
      if (effort != null) 'effort': effort,
      if (costUsd != null) 'cost_usd': costUsd,
      if (tokensIn != null) 'tokens_in': tokensIn,
      if (tokensOut != null) 'tokens_out': tokensOut,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (baseBranch != null) 'base_branch': baseBranch,
      if (mergeCommit != null) 'merge_commit': mergeCommit,
      if (prUrl != null) 'pr_url': prUrl,
      if (pid != null) 'pid': pid,
      if (duelId != null) 'duel_id': duelId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? provider,
    Value<String?>? externalId,
    Value<String?>? runConfig,
    Value<String>? id,
    Value<int>? workspaceId,
    Value<int?>? taskId,
    Value<String?>? agentName,
    Value<String?>? title,
    Value<String?>? permissionMode,
    Value<String>? worktreePath,
    Value<String>? branch,
    Value<SessionStatus>? status,
    Value<String>? model,
    Value<int?>? specId,
    Value<String?>? steps,
    Value<String?>? effort,
    Value<double>? costUsd,
    Value<int>? tokensIn,
    Value<int>? tokensOut,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<String?>? baseBranch,
    Value<String?>? mergeCommit,
    Value<String?>? prUrl,
    Value<int?>? pid,
    Value<int?>? duelId,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      provider: provider ?? this.provider,
      externalId: externalId ?? this.externalId,
      runConfig: runConfig ?? this.runConfig,
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      taskId: taskId ?? this.taskId,
      agentName: agentName ?? this.agentName,
      title: title ?? this.title,
      permissionMode: permissionMode ?? this.permissionMode,
      worktreePath: worktreePath ?? this.worktreePath,
      branch: branch ?? this.branch,
      status: status ?? this.status,
      model: model ?? this.model,
      specId: specId ?? this.specId,
      steps: steps ?? this.steps,
      effort: effort ?? this.effort,
      costUsd: costUsd ?? this.costUsd,
      tokensIn: tokensIn ?? this.tokensIn,
      tokensOut: tokensOut ?? this.tokensOut,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      baseBranch: baseBranch ?? this.baseBranch,
      mergeCommit: mergeCommit ?? this.mergeCommit,
      prUrl: prUrl ?? this.prUrl,
      pid: pid ?? this.pid,
      duelId: duelId ?? this.duelId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (runConfig.present) {
      map['run_config'] = Variable<String>(runConfig.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<int>(workspaceId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<int>(taskId.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (permissionMode.present) {
      map['permission_mode'] = Variable<String>(permissionMode.value);
    }
    if (worktreePath.present) {
      map['worktree_path'] = Variable<String>(worktreePath.value);
    }
    if (branch.present) {
      map['branch'] = Variable<String>(branch.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $SessionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (specId.present) {
      map['spec_id'] = Variable<int>(specId.value);
    }
    if (steps.present) {
      map['steps'] = Variable<String>(steps.value);
    }
    if (effort.present) {
      map['effort'] = Variable<String>(effort.value);
    }
    if (costUsd.present) {
      map['cost_usd'] = Variable<double>(costUsd.value);
    }
    if (tokensIn.present) {
      map['tokens_in'] = Variable<int>(tokensIn.value);
    }
    if (tokensOut.present) {
      map['tokens_out'] = Variable<int>(tokensOut.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (baseBranch.present) {
      map['base_branch'] = Variable<String>(baseBranch.value);
    }
    if (mergeCommit.present) {
      map['merge_commit'] = Variable<String>(mergeCommit.value);
    }
    if (prUrl.present) {
      map['pr_url'] = Variable<String>(prUrl.value);
    }
    if (pid.present) {
      map['pid'] = Variable<int>(pid.value);
    }
    if (duelId.present) {
      map['duel_id'] = Variable<int>(duelId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('provider: $provider, ')
          ..write('externalId: $externalId, ')
          ..write('runConfig: $runConfig, ')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('taskId: $taskId, ')
          ..write('agentName: $agentName, ')
          ..write('title: $title, ')
          ..write('permissionMode: $permissionMode, ')
          ..write('worktreePath: $worktreePath, ')
          ..write('branch: $branch, ')
          ..write('status: $status, ')
          ..write('model: $model, ')
          ..write('specId: $specId, ')
          ..write('steps: $steps, ')
          ..write('effort: $effort, ')
          ..write('costUsd: $costUsd, ')
          ..write('tokensIn: $tokensIn, ')
          ..write('tokensOut: $tokensOut, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('baseBranch: $baseBranch, ')
          ..write('mergeCommit: $mergeCommit, ')
          ..write('prUrl: $prUrl, ')
          ..write('pid: $pid, ')
          ..write('duelId: $duelId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionEventsTable extends SessionEvents
    with TableInfo<$SessionEventsTable, SessionEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    seq,
    type,
    json,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, seq},
  ];
  @override
  SessionEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SessionEventsTable createAlias(String alias) {
    return $SessionEventsTable(attachedDatabase, alias);
  }
}

class SessionEvent extends DataClass implements Insertable<SessionEvent> {
  final int id;
  final String sessionId;

  /// 1-based order inside the session.
  final int seq;

  /// `type` (and `/subtype`) of the event, e.g. `system/init`.
  final String type;
  final String json;
  final DateTime createdAt;
  const SessionEvent({
    required this.id,
    required this.sessionId,
    required this.seq,
    required this.type,
    required this.json,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['seq'] = Variable<int>(seq);
    map['type'] = Variable<String>(type);
    map['json'] = Variable<String>(json);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SessionEventsCompanion toCompanion(bool nullToAbsent) {
    return SessionEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      seq: Value(seq),
      type: Value(type),
      json: Value(json),
      createdAt: Value(createdAt),
    );
  }

  factory SessionEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionEvent(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      seq: serializer.fromJson<int>(json['seq']),
      type: serializer.fromJson<String>(json['type']),
      json: serializer.fromJson<String>(json['json']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'seq': serializer.toJson<int>(seq),
      'type': serializer.toJson<String>(type),
      'json': serializer.toJson<String>(json),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SessionEvent copyWith({
    int? id,
    String? sessionId,
    int? seq,
    String? type,
    String? json,
    DateTime? createdAt,
  }) => SessionEvent(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    seq: seq ?? this.seq,
    type: type ?? this.type,
    json: json ?? this.json,
    createdAt: createdAt ?? this.createdAt,
  );
  SessionEvent copyWithCompanion(SessionEventsCompanion data) {
    return SessionEvent(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      seq: data.seq.present ? data.seq.value : this.seq,
      type: data.type.present ? data.type.value : this.type,
      json: data.json.present ? data.json.value : this.json,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionEvent(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('seq: $seq, ')
          ..write('type: $type, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, seq, type, json, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionEvent &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.seq == this.seq &&
          other.type == this.type &&
          other.json == this.json &&
          other.createdAt == this.createdAt);
}

class SessionEventsCompanion extends UpdateCompanion<SessionEvent> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<int> seq;
  final Value<String> type;
  final Value<String> json;
  final Value<DateTime> createdAt;
  const SessionEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.seq = const Value.absent(),
    this.type = const Value.absent(),
    this.json = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SessionEventsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required int seq,
    required String type,
    required String json,
    this.createdAt = const Value.absent(),
  }) : sessionId = Value(sessionId),
       seq = Value(seq),
       type = Value(type),
       json = Value(json);
  static Insertable<SessionEvent> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<int>? seq,
    Expression<String>? type,
    Expression<String>? json,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (seq != null) 'seq': seq,
      if (type != null) 'type': type,
      if (json != null) 'json': json,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SessionEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<int>? seq,
    Value<String>? type,
    Value<String>? json,
    Value<DateTime>? createdAt,
  }) {
    return SessionEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      seq: seq ?? this.seq,
      type: type ?? this.type,
      json: json ?? this.json,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('seq: $seq, ')
          ..write('type: $type, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _runConfigMeta = const VerificationMeta(
    'runConfig',
  );
  @override
  late final GeneratedColumn<String> runConfig = GeneratedColumn<String>(
    'run_config',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<int> workspaceId = GeneratedColumn<int>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('claude'),
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _claudeSessionIdMeta = const VerificationMeta(
    'claudeSessionId',
  );
  @override
  late final GeneratedColumn<String> claudeSessionId = GeneratedColumn<String>(
    'claude_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ask'),
  );
  static const VerificationMeta _tokensInMeta = const VerificationMeta(
    'tokensIn',
  );
  @override
  late final GeneratedColumn<int> tokensIn = GeneratedColumn<int>(
    'tokens_in',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tokensOutMeta = const VerificationMeta(
    'tokensOut',
  );
  @override
  late final GeneratedColumn<int> tokensOut = GeneratedColumn<int>(
    'tokens_out',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _costUsdMeta = const VerificationMeta(
    'costUsd',
  );
  @override
  late final GeneratedColumn<double> costUsd = GeneratedColumn<double>(
    'cost_usd',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _messageCountMeta = const VerificationMeta(
    'messageCount',
  );
  @override
  late final GeneratedColumn<int> messageCount = GeneratedColumn<int>(
    'message_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    runConfig,
    id,
    workspaceId,
    title,
    provider,
    model,
    sessionId,
    createdAt,
    claudeSessionId,
    mode,
    tokensIn,
    tokensOut,
    costUsd,
    messageCount,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('run_config')) {
      context.handle(
        _runConfigMeta,
        runConfig.isAcceptableOrUnknown(data['run_config']!, _runConfigMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('claude_session_id')) {
      context.handle(
        _claudeSessionIdMeta,
        claudeSessionId.isAcceptableOrUnknown(
          data['claude_session_id']!,
          _claudeSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('tokens_in')) {
      context.handle(
        _tokensInMeta,
        tokensIn.isAcceptableOrUnknown(data['tokens_in']!, _tokensInMeta),
      );
    }
    if (data.containsKey('tokens_out')) {
      context.handle(
        _tokensOutMeta,
        tokensOut.isAcceptableOrUnknown(data['tokens_out']!, _tokensOutMeta),
      );
    }
    if (data.containsKey('cost_usd')) {
      context.handle(
        _costUsdMeta,
        costUsd.isAcceptableOrUnknown(data['cost_usd']!, _costUsdMeta),
      );
    }
    if (data.containsKey('message_count')) {
      context.handle(
        _messageCountMeta,
        messageCount.isAcceptableOrUnknown(
          data['message_count']!,
          _messageCountMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      runConfig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_config'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workspace_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      claudeSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}claude_session_id'],
      ),
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      tokensIn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tokens_in'],
      )!,
      tokensOut: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tokens_out'],
      )!,
      costUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost_usd'],
      )!,
      messageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String? runConfig;
  final int id;
  final int workspaceId;
  final String title;
  final String provider;
  final String model;

  /// Session created from this conversation by "Continuar como sessão".
  final String? sessionId;
  final DateTime createdAt;

  /// Claude Code session id of the conversation itself (`--session-id` on
  /// the first start, `--resume` afterwards). Schema v3.
  final String? claudeSessionId;

  /// `PromptMode.name`: ask / plan / edit (schema v3).
  final String mode;
  final int tokensIn;
  final int tokensOut;

  /// Last cumulative `total_cost_usd` (see plano, Fase 5).
  final double costUsd;

  /// User messages + Claude answers (list meta).
  final int messageCount;

  /// Last activity (history order / grouping). Null = [createdAt].
  final DateTime? updatedAt;
  const Conversation({
    this.runConfig,
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.provider,
    required this.model,
    this.sessionId,
    required this.createdAt,
    this.claudeSessionId,
    required this.mode,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
    required this.messageCount,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (!nullToAbsent || runConfig != null) {
      map['run_config'] = Variable<String>(runConfig);
    }
    map['id'] = Variable<int>(id);
    map['workspace_id'] = Variable<int>(workspaceId);
    map['title'] = Variable<String>(title);
    map['provider'] = Variable<String>(provider);
    map['model'] = Variable<String>(model);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || claudeSessionId != null) {
      map['claude_session_id'] = Variable<String>(claudeSessionId);
    }
    map['mode'] = Variable<String>(mode);
    map['tokens_in'] = Variable<int>(tokensIn);
    map['tokens_out'] = Variable<int>(tokensOut);
    map['cost_usd'] = Variable<double>(costUsd);
    map['message_count'] = Variable<int>(messageCount);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      runConfig: runConfig == null && nullToAbsent
          ? const Value.absent()
          : Value(runConfig),
      id: Value(id),
      workspaceId: Value(workspaceId),
      title: Value(title),
      provider: Value(provider),
      model: Value(model),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      createdAt: Value(createdAt),
      claudeSessionId: claudeSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(claudeSessionId),
      mode: Value(mode),
      tokensIn: Value(tokensIn),
      tokensOut: Value(tokensOut),
      costUsd: Value(costUsd),
      messageCount: Value(messageCount),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      runConfig: serializer.fromJson<String?>(json['runConfig']),
      id: serializer.fromJson<int>(json['id']),
      workspaceId: serializer.fromJson<int>(json['workspaceId']),
      title: serializer.fromJson<String>(json['title']),
      provider: serializer.fromJson<String>(json['provider']),
      model: serializer.fromJson<String>(json['model']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      claudeSessionId: serializer.fromJson<String?>(json['claudeSessionId']),
      mode: serializer.fromJson<String>(json['mode']),
      tokensIn: serializer.fromJson<int>(json['tokensIn']),
      tokensOut: serializer.fromJson<int>(json['tokensOut']),
      costUsd: serializer.fromJson<double>(json['costUsd']),
      messageCount: serializer.fromJson<int>(json['messageCount']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'runConfig': serializer.toJson<String?>(runConfig),
      'id': serializer.toJson<int>(id),
      'workspaceId': serializer.toJson<int>(workspaceId),
      'title': serializer.toJson<String>(title),
      'provider': serializer.toJson<String>(provider),
      'model': serializer.toJson<String>(model),
      'sessionId': serializer.toJson<String?>(sessionId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'claudeSessionId': serializer.toJson<String?>(claudeSessionId),
      'mode': serializer.toJson<String>(mode),
      'tokensIn': serializer.toJson<int>(tokensIn),
      'tokensOut': serializer.toJson<int>(tokensOut),
      'costUsd': serializer.toJson<double>(costUsd),
      'messageCount': serializer.toJson<int>(messageCount),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Conversation copyWith({
    Value<String?> runConfig = const Value.absent(),
    int? id,
    int? workspaceId,
    String? title,
    String? provider,
    String? model,
    Value<String?> sessionId = const Value.absent(),
    DateTime? createdAt,
    Value<String?> claudeSessionId = const Value.absent(),
    String? mode,
    int? tokensIn,
    int? tokensOut,
    double? costUsd,
    int? messageCount,
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Conversation(
    runConfig: runConfig.present ? runConfig.value : this.runConfig,
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    title: title ?? this.title,
    provider: provider ?? this.provider,
    model: model ?? this.model,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    createdAt: createdAt ?? this.createdAt,
    claudeSessionId: claudeSessionId.present
        ? claudeSessionId.value
        : this.claudeSessionId,
    mode: mode ?? this.mode,
    tokensIn: tokensIn ?? this.tokensIn,
    tokensOut: tokensOut ?? this.tokensOut,
    costUsd: costUsd ?? this.costUsd,
    messageCount: messageCount ?? this.messageCount,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      runConfig: data.runConfig.present ? data.runConfig.value : this.runConfig,
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      title: data.title.present ? data.title.value : this.title,
      provider: data.provider.present ? data.provider.value : this.provider,
      model: data.model.present ? data.model.value : this.model,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      claudeSessionId: data.claudeSessionId.present
          ? data.claudeSessionId.value
          : this.claudeSessionId,
      mode: data.mode.present ? data.mode.value : this.mode,
      tokensIn: data.tokensIn.present ? data.tokensIn.value : this.tokensIn,
      tokensOut: data.tokensOut.present ? data.tokensOut.value : this.tokensOut,
      costUsd: data.costUsd.present ? data.costUsd.value : this.costUsd,
      messageCount: data.messageCount.present
          ? data.messageCount.value
          : this.messageCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('runConfig: $runConfig, ')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAt: $createdAt, ')
          ..write('claudeSessionId: $claudeSessionId, ')
          ..write('mode: $mode, ')
          ..write('tokensIn: $tokensIn, ')
          ..write('tokensOut: $tokensOut, ')
          ..write('costUsd: $costUsd, ')
          ..write('messageCount: $messageCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    runConfig,
    id,
    workspaceId,
    title,
    provider,
    model,
    sessionId,
    createdAt,
    claudeSessionId,
    mode,
    tokensIn,
    tokensOut,
    costUsd,
    messageCount,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.runConfig == this.runConfig &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.title == this.title &&
          other.provider == this.provider &&
          other.model == this.model &&
          other.sessionId == this.sessionId &&
          other.createdAt == this.createdAt &&
          other.claudeSessionId == this.claudeSessionId &&
          other.mode == this.mode &&
          other.tokensIn == this.tokensIn &&
          other.tokensOut == this.tokensOut &&
          other.costUsd == this.costUsd &&
          other.messageCount == this.messageCount &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String?> runConfig;
  final Value<int> id;
  final Value<int> workspaceId;
  final Value<String> title;
  final Value<String> provider;
  final Value<String> model;
  final Value<String?> sessionId;
  final Value<DateTime> createdAt;
  final Value<String?> claudeSessionId;
  final Value<String> mode;
  final Value<int> tokensIn;
  final Value<int> tokensOut;
  final Value<double> costUsd;
  final Value<int> messageCount;
  final Value<DateTime?> updatedAt;
  const ConversationsCompanion({
    this.runConfig = const Value.absent(),
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.title = const Value.absent(),
    this.provider = const Value.absent(),
    this.model = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.claudeSessionId = const Value.absent(),
    this.mode = const Value.absent(),
    this.tokensIn = const Value.absent(),
    this.tokensOut = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ConversationsCompanion.insert({
    this.runConfig = const Value.absent(),
    this.id = const Value.absent(),
    required int workspaceId,
    required String title,
    this.provider = const Value.absent(),
    required String model,
    this.sessionId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.claudeSessionId = const Value.absent(),
    this.mode = const Value.absent(),
    this.tokensIn = const Value.absent(),
    this.tokensOut = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       title = Value(title),
       model = Value(model);
  static Insertable<Conversation> custom({
    Expression<String>? runConfig,
    Expression<int>? id,
    Expression<int>? workspaceId,
    Expression<String>? title,
    Expression<String>? provider,
    Expression<String>? model,
    Expression<String>? sessionId,
    Expression<DateTime>? createdAt,
    Expression<String>? claudeSessionId,
    Expression<String>? mode,
    Expression<int>? tokensIn,
    Expression<int>? tokensOut,
    Expression<double>? costUsd,
    Expression<int>? messageCount,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (runConfig != null) 'run_config': runConfig,
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (title != null) 'title': title,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (sessionId != null) 'session_id': sessionId,
      if (createdAt != null) 'created_at': createdAt,
      if (claudeSessionId != null) 'claude_session_id': claudeSessionId,
      if (mode != null) 'mode': mode,
      if (tokensIn != null) 'tokens_in': tokensIn,
      if (tokensOut != null) 'tokens_out': tokensOut,
      if (costUsd != null) 'cost_usd': costUsd,
      if (messageCount != null) 'message_count': messageCount,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ConversationsCompanion copyWith({
    Value<String?>? runConfig,
    Value<int>? id,
    Value<int>? workspaceId,
    Value<String>? title,
    Value<String>? provider,
    Value<String>? model,
    Value<String?>? sessionId,
    Value<DateTime>? createdAt,
    Value<String?>? claudeSessionId,
    Value<String>? mode,
    Value<int>? tokensIn,
    Value<int>? tokensOut,
    Value<double>? costUsd,
    Value<int>? messageCount,
    Value<DateTime?>? updatedAt,
  }) {
    return ConversationsCompanion(
      runConfig: runConfig ?? this.runConfig,
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      claudeSessionId: claudeSessionId ?? this.claudeSessionId,
      mode: mode ?? this.mode,
      tokensIn: tokensIn ?? this.tokensIn,
      tokensOut: tokensOut ?? this.tokensOut,
      costUsd: costUsd ?? this.costUsd,
      messageCount: messageCount ?? this.messageCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (runConfig.present) {
      map['run_config'] = Variable<String>(runConfig.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<int>(workspaceId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (claudeSessionId.present) {
      map['claude_session_id'] = Variable<String>(claudeSessionId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (tokensIn.present) {
      map['tokens_in'] = Variable<int>(tokensIn.value);
    }
    if (tokensOut.present) {
      map['tokens_out'] = Variable<int>(tokensOut.value);
    }
    if (costUsd.present) {
      map['cost_usd'] = Variable<double>(costUsd.value);
    }
    if (messageCount.present) {
      map['message_count'] = Variable<int>(messageCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('runConfig: $runConfig, ')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAt: $createdAt, ')
          ..write('claudeSessionId: $claudeSessionId, ')
          ..write('mode: $mode, ')
          ..write('tokensIn: $tokensIn, ')
          ..write('tokensOut: $tokensOut, ')
          ..write('costUsd: $costUsd, ')
          ..write('messageCount: $messageCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ConversationEventsTable extends ConversationEvents
    with TableInfo<$ConversationEventsTable, ConversationEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    seq,
    type,
    json,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {conversationId, seq},
  ];
  @override
  ConversationEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ConversationEventsTable createAlias(String alias) {
    return $ConversationEventsTable(attachedDatabase, alias);
  }
}

class ConversationEvent extends DataClass
    implements Insertable<ConversationEvent> {
  final int id;
  final int conversationId;
  final int seq;
  final String type;
  final String json;
  final DateTime createdAt;
  const ConversationEvent({
    required this.id,
    required this.conversationId,
    required this.seq,
    required this.type,
    required this.json,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<int>(conversationId);
    map['seq'] = Variable<int>(seq);
    map['type'] = Variable<String>(type);
    map['json'] = Variable<String>(json);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ConversationEventsCompanion toCompanion(bool nullToAbsent) {
    return ConversationEventsCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      seq: Value(seq),
      type: Value(type),
      json: Value(json),
      createdAt: Value(createdAt),
    );
  }

  factory ConversationEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationEvent(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      seq: serializer.fromJson<int>(json['seq']),
      type: serializer.fromJson<String>(json['type']),
      json: serializer.fromJson<String>(json['json']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<int>(conversationId),
      'seq': serializer.toJson<int>(seq),
      'type': serializer.toJson<String>(type),
      'json': serializer.toJson<String>(json),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ConversationEvent copyWith({
    int? id,
    int? conversationId,
    int? seq,
    String? type,
    String? json,
    DateTime? createdAt,
  }) => ConversationEvent(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    seq: seq ?? this.seq,
    type: type ?? this.type,
    json: json ?? this.json,
    createdAt: createdAt ?? this.createdAt,
  );
  ConversationEvent copyWithCompanion(ConversationEventsCompanion data) {
    return ConversationEvent(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      seq: data.seq.present ? data.seq.value : this.seq,
      type: data.type.present ? data.type.value : this.type,
      json: data.json.present ? data.json.value : this.json,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationEvent(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('seq: $seq, ')
          ..write('type: $type, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, conversationId, seq, type, json, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationEvent &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.seq == this.seq &&
          other.type == this.type &&
          other.json == this.json &&
          other.createdAt == this.createdAt);
}

class ConversationEventsCompanion extends UpdateCompanion<ConversationEvent> {
  final Value<int> id;
  final Value<int> conversationId;
  final Value<int> seq;
  final Value<String> type;
  final Value<String> json;
  final Value<DateTime> createdAt;
  const ConversationEventsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.seq = const Value.absent(),
    this.type = const Value.absent(),
    this.json = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ConversationEventsCompanion.insert({
    this.id = const Value.absent(),
    required int conversationId,
    required int seq,
    required String type,
    required String json,
    this.createdAt = const Value.absent(),
  }) : conversationId = Value(conversationId),
       seq = Value(seq),
       type = Value(type),
       json = Value(json);
  static Insertable<ConversationEvent> custom({
    Expression<int>? id,
    Expression<int>? conversationId,
    Expression<int>? seq,
    Expression<String>? type,
    Expression<String>? json,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (seq != null) 'seq': seq,
      if (type != null) 'type': type,
      if (json != null) 'json': json,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ConversationEventsCompanion copyWith({
    Value<int>? id,
    Value<int>? conversationId,
    Value<int>? seq,
    Value<String>? type,
    Value<String>? json,
    Value<DateTime>? createdAt,
  }) {
    return ConversationEventsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      seq: seq ?? this.seq,
      type: type ?? this.type,
      json: json ?? this.json,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationEventsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('seq: $seq, ')
          ..write('type: $type, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SavedPromptsTable extends SavedPrompts
    with TableInfo<$SavedPromptsTable, SavedPrompt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedPromptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usesMeta = const VerificationMeta('uses');
  @override
  late final GeneratedColumn<int> uses = GeneratedColumn<int>(
    'uses',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, command, description, body, uses];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_prompts';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedPrompt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    } else if (isInserting) {
      context.missing(_commandMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('uses')) {
      context.handle(
        _usesMeta,
        uses.isAcceptableOrUnknown(data['uses']!, _usesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedPrompt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedPrompt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      uses: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uses'],
      )!,
    );
  }

  @override
  $SavedPromptsTable createAlias(String alias) {
    return $SavedPromptsTable(attachedDatabase, alias);
  }
}

class SavedPrompt extends DataClass implements Insertable<SavedPrompt> {
  final int id;

  /// Without the leading slash: `testes`.
  final String command;
  final String description;
  final String body;
  final int uses;
  const SavedPrompt({
    required this.id,
    required this.command,
    required this.description,
    required this.body,
    required this.uses,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['command'] = Variable<String>(command);
    map['description'] = Variable<String>(description);
    map['body'] = Variable<String>(body);
    map['uses'] = Variable<int>(uses);
    return map;
  }

  SavedPromptsCompanion toCompanion(bool nullToAbsent) {
    return SavedPromptsCompanion(
      id: Value(id),
      command: Value(command),
      description: Value(description),
      body: Value(body),
      uses: Value(uses),
    );
  }

  factory SavedPrompt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedPrompt(
      id: serializer.fromJson<int>(json['id']),
      command: serializer.fromJson<String>(json['command']),
      description: serializer.fromJson<String>(json['description']),
      body: serializer.fromJson<String>(json['body']),
      uses: serializer.fromJson<int>(json['uses']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'command': serializer.toJson<String>(command),
      'description': serializer.toJson<String>(description),
      'body': serializer.toJson<String>(body),
      'uses': serializer.toJson<int>(uses),
    };
  }

  SavedPrompt copyWith({
    int? id,
    String? command,
    String? description,
    String? body,
    int? uses,
  }) => SavedPrompt(
    id: id ?? this.id,
    command: command ?? this.command,
    description: description ?? this.description,
    body: body ?? this.body,
    uses: uses ?? this.uses,
  );
  SavedPrompt copyWithCompanion(SavedPromptsCompanion data) {
    return SavedPrompt(
      id: data.id.present ? data.id.value : this.id,
      command: data.command.present ? data.command.value : this.command,
      description: data.description.present
          ? data.description.value
          : this.description,
      body: data.body.present ? data.body.value : this.body,
      uses: data.uses.present ? data.uses.value : this.uses,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedPrompt(')
          ..write('id: $id, ')
          ..write('command: $command, ')
          ..write('description: $description, ')
          ..write('body: $body, ')
          ..write('uses: $uses')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, command, description, body, uses);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedPrompt &&
          other.id == this.id &&
          other.command == this.command &&
          other.description == this.description &&
          other.body == this.body &&
          other.uses == this.uses);
}

class SavedPromptsCompanion extends UpdateCompanion<SavedPrompt> {
  final Value<int> id;
  final Value<String> command;
  final Value<String> description;
  final Value<String> body;
  final Value<int> uses;
  const SavedPromptsCompanion({
    this.id = const Value.absent(),
    this.command = const Value.absent(),
    this.description = const Value.absent(),
    this.body = const Value.absent(),
    this.uses = const Value.absent(),
  });
  SavedPromptsCompanion.insert({
    this.id = const Value.absent(),
    required String command,
    this.description = const Value.absent(),
    required String body,
    this.uses = const Value.absent(),
  }) : command = Value(command),
       body = Value(body);
  static Insertable<SavedPrompt> custom({
    Expression<int>? id,
    Expression<String>? command,
    Expression<String>? description,
    Expression<String>? body,
    Expression<int>? uses,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (command != null) 'command': command,
      if (description != null) 'description': description,
      if (body != null) 'body': body,
      if (uses != null) 'uses': uses,
    });
  }

  SavedPromptsCompanion copyWith({
    Value<int>? id,
    Value<String>? command,
    Value<String>? description,
    Value<String>? body,
    Value<int>? uses,
  }) {
    return SavedPromptsCompanion(
      id: id ?? this.id,
      command: command ?? this.command,
      description: description ?? this.description,
      body: body ?? this.body,
      uses: uses ?? this.uses,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (uses.present) {
      map['uses'] = Variable<int>(uses.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedPromptsCompanion(')
          ..write('id: $id, ')
          ..write('command: $command, ')
          ..write('description: $description, ')
          ..write('body: $body, ')
          ..write('uses: $uses')
          ..write(')'))
        .toString();
  }
}

class $AgentSettingsTable extends AgentSettings
    with TableInfo<$AgentSettingsTable, AgentSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AgentScope, String> scope =
      GeneratedColumn<String>(
        'scope',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AgentScope>($AgentSettingsTable.$converterscope);
  static const VerificationMeta _permissionModeMeta = const VerificationMeta(
    'permissionMode',
  );
  @override
  late final GeneratedColumn<String> permissionMode = GeneratedColumn<String>(
    'permission_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _budgetUsdMeta = const VerificationMeta(
    'budgetUsd',
  );
  @override
  late final GeneratedColumn<double> budgetUsd = GeneratedColumn<double>(
    'budget_usd',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxTurnsMeta = const VerificationMeta(
    'maxTurns',
  );
  @override
  late final GeneratedColumn<int> maxTurns = GeneratedColumn<int>(
    'max_turns',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> mcpServers =
      GeneratedColumn<String>(
        'mcp_servers',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($AgentSettingsTable.$convertermcpServers);
  @override
  List<GeneratedColumn> get $columns => [
    agentName,
    scope,
    permissionMode,
    budgetUsd,
    maxTurns,
    mcpServers,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    } else if (isInserting) {
      context.missing(_agentNameMeta);
    }
    if (data.containsKey('permission_mode')) {
      context.handle(
        _permissionModeMeta,
        permissionMode.isAcceptableOrUnknown(
          data['permission_mode']!,
          _permissionModeMeta,
        ),
      );
    }
    if (data.containsKey('budget_usd')) {
      context.handle(
        _budgetUsdMeta,
        budgetUsd.isAcceptableOrUnknown(data['budget_usd']!, _budgetUsdMeta),
      );
    }
    if (data.containsKey('max_turns')) {
      context.handle(
        _maxTurnsMeta,
        maxTurns.isAcceptableOrUnknown(data['max_turns']!, _maxTurnsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {agentName, scope};
  @override
  AgentSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentSetting(
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      )!,
      scope: $AgentSettingsTable.$converterscope.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}scope'],
        )!,
      ),
      permissionMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}permission_mode'],
      ),
      budgetUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}budget_usd'],
      ),
      maxTurns: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_turns'],
      ),
      mcpServers: $AgentSettingsTable.$convertermcpServers.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mcp_servers'],
        )!,
      ),
    );
  }

  @override
  $AgentSettingsTable createAlias(String alias) {
    return $AgentSettingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AgentScope, String, String> $converterscope =
      const EnumNameConverter<AgentScope>(AgentScope.values);
  static TypeConverter<List<String>, String> $convertermcpServers =
      const StringListConverter();
}

class AgentSetting extends DataClass implements Insertable<AgentSetting> {
  final String agentName;
  final AgentScope scope;

  /// CLI value (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`).
  final String? permissionMode;
  final double? budgetUsd;
  final int? maxTurns;

  /// MCP server names enabled for the agent (JSON array). No secrets here.
  final List<String> mcpServers;
  const AgentSetting({
    required this.agentName,
    required this.scope,
    this.permissionMode,
    this.budgetUsd,
    this.maxTurns,
    required this.mcpServers,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['agent_name'] = Variable<String>(agentName);
    {
      map['scope'] = Variable<String>(
        $AgentSettingsTable.$converterscope.toSql(scope),
      );
    }
    if (!nullToAbsent || permissionMode != null) {
      map['permission_mode'] = Variable<String>(permissionMode);
    }
    if (!nullToAbsent || budgetUsd != null) {
      map['budget_usd'] = Variable<double>(budgetUsd);
    }
    if (!nullToAbsent || maxTurns != null) {
      map['max_turns'] = Variable<int>(maxTurns);
    }
    {
      map['mcp_servers'] = Variable<String>(
        $AgentSettingsTable.$convertermcpServers.toSql(mcpServers),
      );
    }
    return map;
  }

  AgentSettingsCompanion toCompanion(bool nullToAbsent) {
    return AgentSettingsCompanion(
      agentName: Value(agentName),
      scope: Value(scope),
      permissionMode: permissionMode == null && nullToAbsent
          ? const Value.absent()
          : Value(permissionMode),
      budgetUsd: budgetUsd == null && nullToAbsent
          ? const Value.absent()
          : Value(budgetUsd),
      maxTurns: maxTurns == null && nullToAbsent
          ? const Value.absent()
          : Value(maxTurns),
      mcpServers: Value(mcpServers),
    );
  }

  factory AgentSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentSetting(
      agentName: serializer.fromJson<String>(json['agentName']),
      scope: $AgentSettingsTable.$converterscope.fromJson(
        serializer.fromJson<String>(json['scope']),
      ),
      permissionMode: serializer.fromJson<String?>(json['permissionMode']),
      budgetUsd: serializer.fromJson<double?>(json['budgetUsd']),
      maxTurns: serializer.fromJson<int?>(json['maxTurns']),
      mcpServers: serializer.fromJson<List<String>>(json['mcpServers']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'agentName': serializer.toJson<String>(agentName),
      'scope': serializer.toJson<String>(
        $AgentSettingsTable.$converterscope.toJson(scope),
      ),
      'permissionMode': serializer.toJson<String?>(permissionMode),
      'budgetUsd': serializer.toJson<double?>(budgetUsd),
      'maxTurns': serializer.toJson<int?>(maxTurns),
      'mcpServers': serializer.toJson<List<String>>(mcpServers),
    };
  }

  AgentSetting copyWith({
    String? agentName,
    AgentScope? scope,
    Value<String?> permissionMode = const Value.absent(),
    Value<double?> budgetUsd = const Value.absent(),
    Value<int?> maxTurns = const Value.absent(),
    List<String>? mcpServers,
  }) => AgentSetting(
    agentName: agentName ?? this.agentName,
    scope: scope ?? this.scope,
    permissionMode: permissionMode.present
        ? permissionMode.value
        : this.permissionMode,
    budgetUsd: budgetUsd.present ? budgetUsd.value : this.budgetUsd,
    maxTurns: maxTurns.present ? maxTurns.value : this.maxTurns,
    mcpServers: mcpServers ?? this.mcpServers,
  );
  AgentSetting copyWithCompanion(AgentSettingsCompanion data) {
    return AgentSetting(
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      scope: data.scope.present ? data.scope.value : this.scope,
      permissionMode: data.permissionMode.present
          ? data.permissionMode.value
          : this.permissionMode,
      budgetUsd: data.budgetUsd.present ? data.budgetUsd.value : this.budgetUsd,
      maxTurns: data.maxTurns.present ? data.maxTurns.value : this.maxTurns,
      mcpServers: data.mcpServers.present
          ? data.mcpServers.value
          : this.mcpServers,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentSetting(')
          ..write('agentName: $agentName, ')
          ..write('scope: $scope, ')
          ..write('permissionMode: $permissionMode, ')
          ..write('budgetUsd: $budgetUsd, ')
          ..write('maxTurns: $maxTurns, ')
          ..write('mcpServers: $mcpServers')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    agentName,
    scope,
    permissionMode,
    budgetUsd,
    maxTurns,
    mcpServers,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentSetting &&
          other.agentName == this.agentName &&
          other.scope == this.scope &&
          other.permissionMode == this.permissionMode &&
          other.budgetUsd == this.budgetUsd &&
          other.maxTurns == this.maxTurns &&
          other.mcpServers == this.mcpServers);
}

class AgentSettingsCompanion extends UpdateCompanion<AgentSetting> {
  final Value<String> agentName;
  final Value<AgentScope> scope;
  final Value<String?> permissionMode;
  final Value<double?> budgetUsd;
  final Value<int?> maxTurns;
  final Value<List<String>> mcpServers;
  final Value<int> rowid;
  const AgentSettingsCompanion({
    this.agentName = const Value.absent(),
    this.scope = const Value.absent(),
    this.permissionMode = const Value.absent(),
    this.budgetUsd = const Value.absent(),
    this.maxTurns = const Value.absent(),
    this.mcpServers = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentSettingsCompanion.insert({
    required String agentName,
    required AgentScope scope,
    this.permissionMode = const Value.absent(),
    this.budgetUsd = const Value.absent(),
    this.maxTurns = const Value.absent(),
    this.mcpServers = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : agentName = Value(agentName),
       scope = Value(scope);
  static Insertable<AgentSetting> custom({
    Expression<String>? agentName,
    Expression<String>? scope,
    Expression<String>? permissionMode,
    Expression<double>? budgetUsd,
    Expression<int>? maxTurns,
    Expression<String>? mcpServers,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (agentName != null) 'agent_name': agentName,
      if (scope != null) 'scope': scope,
      if (permissionMode != null) 'permission_mode': permissionMode,
      if (budgetUsd != null) 'budget_usd': budgetUsd,
      if (maxTurns != null) 'max_turns': maxTurns,
      if (mcpServers != null) 'mcp_servers': mcpServers,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentSettingsCompanion copyWith({
    Value<String>? agentName,
    Value<AgentScope>? scope,
    Value<String?>? permissionMode,
    Value<double?>? budgetUsd,
    Value<int?>? maxTurns,
    Value<List<String>>? mcpServers,
    Value<int>? rowid,
  }) {
    return AgentSettingsCompanion(
      agentName: agentName ?? this.agentName,
      scope: scope ?? this.scope,
      permissionMode: permissionMode ?? this.permissionMode,
      budgetUsd: budgetUsd ?? this.budgetUsd,
      maxTurns: maxTurns ?? this.maxTurns,
      mcpServers: mcpServers ?? this.mcpServers,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(
        $AgentSettingsTable.$converterscope.toSql(scope.value),
      );
    }
    if (permissionMode.present) {
      map['permission_mode'] = Variable<String>(permissionMode.value);
    }
    if (budgetUsd.present) {
      map['budget_usd'] = Variable<double>(budgetUsd.value);
    }
    if (maxTurns.present) {
      map['max_turns'] = Variable<int>(maxTurns.value);
    }
    if (mcpServers.present) {
      map['mcp_servers'] = Variable<String>(
        $AgentSettingsTable.$convertermcpServers.toSql(mcpServers.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentSettingsCompanion(')
          ..write('agentName: $agentName, ')
          ..write('scope: $scope, ')
          ..write('permissionMode: $permissionMode, ')
          ..write('budgetUsd: $budgetUsd, ')
          ..write('maxTurns: $maxTurns, ')
          ..write('mcpServers: $mcpServers, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpToolRulesTable extends McpToolRules
    with TableInfo<$McpToolRulesTable, McpToolRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpToolRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverMeta = const VerificationMeta('server');
  @override
  late final GeneratedColumn<String> server = GeneratedColumn<String>(
    'server',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toolMeta = const VerificationMeta('tool');
  @override
  late final GeneratedColumn<String> tool = GeneratedColumn<String>(
    'tool',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<McpRule, String> rule =
      GeneratedColumn<String>(
        'rule',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<McpRule>($McpToolRulesTable.$converterrule);
  @override
  List<GeneratedColumn> get $columns => [server, tool, rule];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_tool_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpToolRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server')) {
      context.handle(
        _serverMeta,
        server.isAcceptableOrUnknown(data['server']!, _serverMeta),
      );
    } else if (isInserting) {
      context.missing(_serverMeta);
    }
    if (data.containsKey('tool')) {
      context.handle(
        _toolMeta,
        tool.isAcceptableOrUnknown(data['tool']!, _toolMeta),
      );
    } else if (isInserting) {
      context.missing(_toolMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {server, tool};
  @override
  McpToolRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpToolRule(
      server: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server'],
      )!,
      tool: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool'],
      )!,
      rule: $McpToolRulesTable.$converterrule.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}rule'],
        )!,
      ),
    );
  }

  @override
  $McpToolRulesTable createAlias(String alias) {
    return $McpToolRulesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<McpRule, String, String> $converterrule =
      const EnumNameConverter<McpRule>(McpRule.values);
}

class McpToolRule extends DataClass implements Insertable<McpToolRule> {
  final String server;
  final String tool;
  final McpRule rule;
  const McpToolRule({
    required this.server,
    required this.tool,
    required this.rule,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server'] = Variable<String>(server);
    map['tool'] = Variable<String>(tool);
    {
      map['rule'] = Variable<String>(
        $McpToolRulesTable.$converterrule.toSql(rule),
      );
    }
    return map;
  }

  McpToolRulesCompanion toCompanion(bool nullToAbsent) {
    return McpToolRulesCompanion(
      server: Value(server),
      tool: Value(tool),
      rule: Value(rule),
    );
  }

  factory McpToolRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpToolRule(
      server: serializer.fromJson<String>(json['server']),
      tool: serializer.fromJson<String>(json['tool']),
      rule: $McpToolRulesTable.$converterrule.fromJson(
        serializer.fromJson<String>(json['rule']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'server': serializer.toJson<String>(server),
      'tool': serializer.toJson<String>(tool),
      'rule': serializer.toJson<String>(
        $McpToolRulesTable.$converterrule.toJson(rule),
      ),
    };
  }

  McpToolRule copyWith({String? server, String? tool, McpRule? rule}) =>
      McpToolRule(
        server: server ?? this.server,
        tool: tool ?? this.tool,
        rule: rule ?? this.rule,
      );
  McpToolRule copyWithCompanion(McpToolRulesCompanion data) {
    return McpToolRule(
      server: data.server.present ? data.server.value : this.server,
      tool: data.tool.present ? data.tool.value : this.tool,
      rule: data.rule.present ? data.rule.value : this.rule,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpToolRule(')
          ..write('server: $server, ')
          ..write('tool: $tool, ')
          ..write('rule: $rule')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(server, tool, rule);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpToolRule &&
          other.server == this.server &&
          other.tool == this.tool &&
          other.rule == this.rule);
}

class McpToolRulesCompanion extends UpdateCompanion<McpToolRule> {
  final Value<String> server;
  final Value<String> tool;
  final Value<McpRule> rule;
  final Value<int> rowid;
  const McpToolRulesCompanion({
    this.server = const Value.absent(),
    this.tool = const Value.absent(),
    this.rule = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpToolRulesCompanion.insert({
    required String server,
    required String tool,
    required McpRule rule,
    this.rowid = const Value.absent(),
  }) : server = Value(server),
       tool = Value(tool),
       rule = Value(rule);
  static Insertable<McpToolRule> custom({
    Expression<String>? server,
    Expression<String>? tool,
    Expression<String>? rule,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (server != null) 'server': server,
      if (tool != null) 'tool': tool,
      if (rule != null) 'rule': rule,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpToolRulesCompanion copyWith({
    Value<String>? server,
    Value<String>? tool,
    Value<McpRule>? rule,
    Value<int>? rowid,
  }) {
    return McpToolRulesCompanion(
      server: server ?? this.server,
      tool: tool ?? this.tool,
      rule: rule ?? this.rule,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (server.present) {
      map['server'] = Variable<String>(server.value);
    }
    if (tool.present) {
      map['tool'] = Variable<String>(tool.value);
    }
    if (rule.present) {
      map['rule'] = Variable<String>(
        $McpToolRulesTable.$converterrule.toSql(rule.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpToolRulesCompanion(')
          ..write('server: $server, ')
          ..write('tool: $tool, ')
          ..write('rule: $rule, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectPlansTable extends ProjectPlans
    with TableInfo<$ProjectPlansTable, ProjectPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<int> workspaceId = GeneratedColumn<int>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<String> step = GeneratedColumn<String>(
    'step',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('vision'),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _plannerSessionIdMeta = const VerificationMeta(
    'plannerSessionId',
  );
  @override
  late final GeneratedColumn<String> plannerSessionId = GeneratedColumn<String>(
    'planner_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _costUsdMeta = const VerificationMeta(
    'costUsd',
  );
  @override
  late final GeneratedColumn<double> costUsd = GeneratedColumn<double>(
    'cost_usd',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _materializedAtMeta = const VerificationMeta(
    'materializedAt',
  );
  @override
  late final GeneratedColumn<DateTime> materializedAt =
      GeneratedColumn<DateTime>(
        'materialized_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    workspaceId,
    step,
    data,
    plannerSessionId,
    costUsd,
    createdAt,
    updatedAt,
    materializedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    }
    if (data.containsKey('planner_session_id')) {
      context.handle(
        _plannerSessionIdMeta,
        plannerSessionId.isAcceptableOrUnknown(
          data['planner_session_id']!,
          _plannerSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('cost_usd')) {
      context.handle(
        _costUsdMeta,
        costUsd.isAcceptableOrUnknown(data['cost_usd']!, _costUsdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('materialized_at')) {
      context.handle(
        _materializedAtMeta,
        materializedAt.isAcceptableOrUnknown(
          data['materialized_at']!,
          _materializedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workspaceId};
  @override
  ProjectPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectPlan(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workspace_id'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      plannerSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}planner_session_id'],
      ),
      costUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost_usd'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      materializedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}materialized_at'],
      ),
    );
  }

  @override
  $ProjectPlansTable createAlias(String alias) {
    return $ProjectPlansTable(attachedDatabase, alias);
  }
}

class ProjectPlan extends DataClass implements Insertable<ProjectPlan> {
  final int workspaceId;

  /// `ProjectStep.name` (vision, stack, roadmap, create).
  final String step;

  /// JSON of `ProjectPlanData` (conversation, vision, stack, roadmap).
  final String data;

  /// Claude session of the Visão conversation (`--resume`).
  final String? plannerSessionId;
  final double costUsd;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set by "Criar projeto" (files, specs and tasks written).
  final DateTime? materializedAt;
  const ProjectPlan({
    required this.workspaceId,
    required this.step,
    required this.data,
    this.plannerSessionId,
    required this.costUsd,
    required this.createdAt,
    required this.updatedAt,
    this.materializedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<int>(workspaceId);
    map['step'] = Variable<String>(step);
    map['data'] = Variable<String>(data);
    if (!nullToAbsent || plannerSessionId != null) {
      map['planner_session_id'] = Variable<String>(plannerSessionId);
    }
    map['cost_usd'] = Variable<double>(costUsd);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || materializedAt != null) {
      map['materialized_at'] = Variable<DateTime>(materializedAt);
    }
    return map;
  }

  ProjectPlansCompanion toCompanion(bool nullToAbsent) {
    return ProjectPlansCompanion(
      workspaceId: Value(workspaceId),
      step: Value(step),
      data: Value(data),
      plannerSessionId: plannerSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(plannerSessionId),
      costUsd: Value(costUsd),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      materializedAt: materializedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(materializedAt),
    );
  }

  factory ProjectPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectPlan(
      workspaceId: serializer.fromJson<int>(json['workspaceId']),
      step: serializer.fromJson<String>(json['step']),
      data: serializer.fromJson<String>(json['data']),
      plannerSessionId: serializer.fromJson<String?>(json['plannerSessionId']),
      costUsd: serializer.fromJson<double>(json['costUsd']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      materializedAt: serializer.fromJson<DateTime?>(json['materializedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<int>(workspaceId),
      'step': serializer.toJson<String>(step),
      'data': serializer.toJson<String>(data),
      'plannerSessionId': serializer.toJson<String?>(plannerSessionId),
      'costUsd': serializer.toJson<double>(costUsd),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'materializedAt': serializer.toJson<DateTime?>(materializedAt),
    };
  }

  ProjectPlan copyWith({
    int? workspaceId,
    String? step,
    String? data,
    Value<String?> plannerSessionId = const Value.absent(),
    double? costUsd,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> materializedAt = const Value.absent(),
  }) => ProjectPlan(
    workspaceId: workspaceId ?? this.workspaceId,
    step: step ?? this.step,
    data: data ?? this.data,
    plannerSessionId: plannerSessionId.present
        ? plannerSessionId.value
        : this.plannerSessionId,
    costUsd: costUsd ?? this.costUsd,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    materializedAt: materializedAt.present
        ? materializedAt.value
        : this.materializedAt,
  );
  ProjectPlan copyWithCompanion(ProjectPlansCompanion data) {
    return ProjectPlan(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      step: data.step.present ? data.step.value : this.step,
      data: data.data.present ? data.data.value : this.data,
      plannerSessionId: data.plannerSessionId.present
          ? data.plannerSessionId.value
          : this.plannerSessionId,
      costUsd: data.costUsd.present ? data.costUsd.value : this.costUsd,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      materializedAt: data.materializedAt.present
          ? data.materializedAt.value
          : this.materializedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectPlan(')
          ..write('workspaceId: $workspaceId, ')
          ..write('step: $step, ')
          ..write('data: $data, ')
          ..write('plannerSessionId: $plannerSessionId, ')
          ..write('costUsd: $costUsd, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('materializedAt: $materializedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    step,
    data,
    plannerSessionId,
    costUsd,
    createdAt,
    updatedAt,
    materializedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectPlan &&
          other.workspaceId == this.workspaceId &&
          other.step == this.step &&
          other.data == this.data &&
          other.plannerSessionId == this.plannerSessionId &&
          other.costUsd == this.costUsd &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.materializedAt == this.materializedAt);
}

class ProjectPlansCompanion extends UpdateCompanion<ProjectPlan> {
  final Value<int> workspaceId;
  final Value<String> step;
  final Value<String> data;
  final Value<String?> plannerSessionId;
  final Value<double> costUsd;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> materializedAt;
  const ProjectPlansCompanion({
    this.workspaceId = const Value.absent(),
    this.step = const Value.absent(),
    this.data = const Value.absent(),
    this.plannerSessionId = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.materializedAt = const Value.absent(),
  });
  ProjectPlansCompanion.insert({
    this.workspaceId = const Value.absent(),
    this.step = const Value.absent(),
    this.data = const Value.absent(),
    this.plannerSessionId = const Value.absent(),
    this.costUsd = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.materializedAt = const Value.absent(),
  });
  static Insertable<ProjectPlan> custom({
    Expression<int>? workspaceId,
    Expression<String>? step,
    Expression<String>? data,
    Expression<String>? plannerSessionId,
    Expression<double>? costUsd,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? materializedAt,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (step != null) 'step': step,
      if (data != null) 'data': data,
      if (plannerSessionId != null) 'planner_session_id': plannerSessionId,
      if (costUsd != null) 'cost_usd': costUsd,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (materializedAt != null) 'materialized_at': materializedAt,
    });
  }

  ProjectPlansCompanion copyWith({
    Value<int>? workspaceId,
    Value<String>? step,
    Value<String>? data,
    Value<String?>? plannerSessionId,
    Value<double>? costUsd,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? materializedAt,
  }) {
    return ProjectPlansCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      step: step ?? this.step,
      data: data ?? this.data,
      plannerSessionId: plannerSessionId ?? this.plannerSessionId,
      costUsd: costUsd ?? this.costUsd,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      materializedAt: materializedAt ?? this.materializedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<int>(workspaceId.value);
    }
    if (step.present) {
      map['step'] = Variable<String>(step.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (plannerSessionId.present) {
      map['planner_session_id'] = Variable<String>(plannerSessionId.value);
    }
    if (costUsd.present) {
      map['cost_usd'] = Variable<double>(costUsd.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (materializedAt.present) {
      map['materialized_at'] = Variable<DateTime>(materializedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectPlansCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('step: $step, ')
          ..write('data: $data, ')
          ..write('plannerSessionId: $plannerSessionId, ')
          ..write('costUsd: $costUsd, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('materializedAt: $materializedAt')
          ..write(')'))
        .toString();
  }
}

class $AutopilotStatesTable extends AutopilotStates
    with TableInfo<$AutopilotStatesTable, AutopilotState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AutopilotStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<int> workspaceId = GeneratedColumn<int>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sinceMeta = const VerificationMeta('since');
  @override
  late final GeneratedColumn<DateTime> since = GeneratedColumn<DateTime>(
    'since',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [workspaceId, since];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'autopilot_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<AutopilotState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    }
    if (data.containsKey('since')) {
      context.handle(
        _sinceMeta,
        since.isAcceptableOrUnknown(data['since']!, _sinceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workspaceId};
  @override
  AutopilotState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AutopilotState(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workspace_id'],
      )!,
      since: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}since'],
      )!,
    );
  }

  @override
  $AutopilotStatesTable createAlias(String alias) {
    return $AutopilotStatesTable(attachedDatabase, alias);
  }
}

class AutopilotState extends DataClass implements Insertable<AutopilotState> {
  final int workspaceId;
  final DateTime since;
  const AutopilotState({required this.workspaceId, required this.since});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<int>(workspaceId);
    map['since'] = Variable<DateTime>(since);
    return map;
  }

  AutopilotStatesCompanion toCompanion(bool nullToAbsent) {
    return AutopilotStatesCompanion(
      workspaceId: Value(workspaceId),
      since: Value(since),
    );
  }

  factory AutopilotState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AutopilotState(
      workspaceId: serializer.fromJson<int>(json['workspaceId']),
      since: serializer.fromJson<DateTime>(json['since']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<int>(workspaceId),
      'since': serializer.toJson<DateTime>(since),
    };
  }

  AutopilotState copyWith({int? workspaceId, DateTime? since}) =>
      AutopilotState(
        workspaceId: workspaceId ?? this.workspaceId,
        since: since ?? this.since,
      );
  AutopilotState copyWithCompanion(AutopilotStatesCompanion data) {
    return AutopilotState(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      since: data.since.present ? data.since.value : this.since,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AutopilotState(')
          ..write('workspaceId: $workspaceId, ')
          ..write('since: $since')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(workspaceId, since);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AutopilotState &&
          other.workspaceId == this.workspaceId &&
          other.since == this.since);
}

class AutopilotStatesCompanion extends UpdateCompanion<AutopilotState> {
  final Value<int> workspaceId;
  final Value<DateTime> since;
  const AutopilotStatesCompanion({
    this.workspaceId = const Value.absent(),
    this.since = const Value.absent(),
  });
  AutopilotStatesCompanion.insert({
    this.workspaceId = const Value.absent(),
    this.since = const Value.absent(),
  });
  static Insertable<AutopilotState> custom({
    Expression<int>? workspaceId,
    Expression<DateTime>? since,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (since != null) 'since': since,
    });
  }

  AutopilotStatesCompanion copyWith({
    Value<int>? workspaceId,
    Value<DateTime>? since,
  }) {
    return AutopilotStatesCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      since: since ?? this.since,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<int>(workspaceId.value);
    }
    if (since.present) {
      map['since'] = Variable<DateTime>(since.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AutopilotStatesCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('since: $since')
          ..write(')'))
        .toString();
  }
}

class $ReviewDraftsTable extends ReviewDrafts
    with TableInfo<$ReviewDraftsTable, ReviewDraftRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [sessionId, data, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewDraftRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  ReviewDraftRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewDraftRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReviewDraftsTable createAlias(String alias) {
    return $ReviewDraftsTable(attachedDatabase, alias);
  }
}

class ReviewDraftRow extends DataClass implements Insertable<ReviewDraftRow> {
  final String sessionId;
  final String data;
  final DateTime updatedAt;
  const ReviewDraftRow({
    required this.sessionId,
    required this.data,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['data'] = Variable<String>(data);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReviewDraftsCompanion toCompanion(bool nullToAbsent) {
    return ReviewDraftsCompanion(
      sessionId: Value(sessionId),
      data: Value(data),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReviewDraftRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewDraftRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      data: serializer.fromJson<String>(json['data']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'data': serializer.toJson<String>(data),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReviewDraftRow copyWith({
    String? sessionId,
    String? data,
    DateTime? updatedAt,
  }) => ReviewDraftRow(
    sessionId: sessionId ?? this.sessionId,
    data: data ?? this.data,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReviewDraftRow copyWithCompanion(ReviewDraftsCompanion data) {
    return ReviewDraftRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      data: data.data.present ? data.data.value : this.data,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDraftRow(')
          ..write('sessionId: $sessionId, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, data, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewDraftRow &&
          other.sessionId == this.sessionId &&
          other.data == this.data &&
          other.updatedAt == this.updatedAt);
}

class ReviewDraftsCompanion extends UpdateCompanion<ReviewDraftRow> {
  final Value<String> sessionId;
  final Value<String> data;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReviewDraftsCompanion({
    this.sessionId = const Value.absent(),
    this.data = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewDraftsCompanion.insert({
    required String sessionId,
    required String data,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       data = Value(data);
  static Insertable<ReviewDraftRow> custom({
    Expression<String>? sessionId,
    Expression<String>? data,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (data != null) 'data': data,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewDraftsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? data,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReviewDraftsCompanion(
      sessionId: sessionId ?? this.sessionId,
      data: data ?? this.data,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDraftsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingNoticesTable extends PendingNotices
    with TableInfo<$PendingNoticesTable, PendingNotice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingNoticesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sessionId, body, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_notices';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingNotice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingNotice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingNotice(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PendingNoticesTable createAlias(String alias) {
    return $PendingNoticesTable(attachedDatabase, alias);
  }
}

class PendingNotice extends DataClass implements Insertable<PendingNotice> {
  final int id;
  final String sessionId;
  final String body;
  final DateTime createdAt;
  const PendingNotice({
    required this.id,
    required this.sessionId,
    required this.body,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['body'] = Variable<String>(body);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PendingNoticesCompanion toCompanion(bool nullToAbsent) {
    return PendingNoticesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      body: Value(body),
      createdAt: Value(createdAt),
    );
  }

  factory PendingNotice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingNotice(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      body: serializer.fromJson<String>(json['body']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'body': serializer.toJson<String>(body),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PendingNotice copyWith({
    int? id,
    String? sessionId,
    String? body,
    DateTime? createdAt,
  }) => PendingNotice(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    body: body ?? this.body,
    createdAt: createdAt ?? this.createdAt,
  );
  PendingNotice copyWithCompanion(PendingNoticesCompanion data) {
    return PendingNotice(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      body: data.body.present ? data.body.value : this.body,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingNotice(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, body, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingNotice &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.body == this.body &&
          other.createdAt == this.createdAt);
}

class PendingNoticesCompanion extends UpdateCompanion<PendingNotice> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<String> body;
  final Value<DateTime> createdAt;
  const PendingNoticesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PendingNoticesCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required String body,
    this.createdAt = const Value.absent(),
  }) : sessionId = Value(sessionId),
       body = Value(body);
  static Insertable<PendingNotice> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<String>? body,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (body != null) 'body': body,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PendingNoticesCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<String>? body,
    Value<DateTime>? createdAt,
  }) {
    return PendingNoticesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingNoticesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ReviewCommentsTable extends ReviewComments
    with TableInfo<$ReviewCommentsTable, ReviewCommentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewCommentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _specIdMeta = const VerificationMeta('specId');
  @override
  late final GeneratedColumn<int> specId = GeneratedColumn<int>(
    'spec_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _roundMeta = const VerificationMeta('round');
  @override
  late final GeneratedColumn<int> round = GeneratedColumn<int>(
    'round',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lineMeta = const VerificationMeta('line');
  @override
  late final GeneratedColumn<int> line = GeneratedColumn<int>(
    'line',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requirementMeta = const VerificationMeta(
    'requirement',
  );
  @override
  late final GeneratedColumn<String> requirement = GeneratedColumn<String>(
    'requirement',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verdictMeta = const VerificationMeta(
    'verdict',
  );
  @override
  late final GeneratedColumn<String> verdict = GeneratedColumn<String>(
    'verdict',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _commitShaMeta = const VerificationMeta(
    'commitSha',
  );
  @override
  late final GeneratedColumn<String> commitSha = GeneratedColumn<String>(
    'commit_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedMeta = const VerificationMeta(
    'resolved',
  );
  @override
  late final GeneratedColumn<bool> resolved = GeneratedColumn<bool>(
    'resolved',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("resolved" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    specId,
    round,
    author,
    path,
    line,
    body,
    severity,
    requirement,
    verdict,
    commitSha,
    resolved,
    resolvedAt,
    externalId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_comments';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewCommentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('spec_id')) {
      context.handle(
        _specIdMeta,
        specId.isAcceptableOrUnknown(data['spec_id']!, _specIdMeta),
      );
    } else if (isInserting) {
      context.missing(_specIdMeta);
    }
    if (data.containsKey('round')) {
      context.handle(
        _roundMeta,
        round.isAcceptableOrUnknown(data['round']!, _roundMeta),
      );
    } else if (isInserting) {
      context.missing(_roundMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    } else if (isInserting) {
      context.missing(_authorMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('line')) {
      context.handle(
        _lineMeta,
        line.isAcceptableOrUnknown(data['line']!, _lineMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    }
    if (data.containsKey('requirement')) {
      context.handle(
        _requirementMeta,
        requirement.isAcceptableOrUnknown(
          data['requirement']!,
          _requirementMeta,
        ),
      );
    }
    if (data.containsKey('verdict')) {
      context.handle(
        _verdictMeta,
        verdict.isAcceptableOrUnknown(data['verdict']!, _verdictMeta),
      );
    }
    if (data.containsKey('commit_sha')) {
      context.handle(
        _commitShaMeta,
        commitSha.isAcceptableOrUnknown(data['commit_sha']!, _commitShaMeta),
      );
    }
    if (data.containsKey('resolved')) {
      context.handle(
        _resolvedMeta,
        resolved.isAcceptableOrUnknown(data['resolved']!, _resolvedMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewCommentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewCommentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      specId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spec_id'],
      )!,
      round: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}round'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      ),
      line: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      ),
      requirement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requirement'],
      ),
      verdict: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verdict'],
      ),
      commitSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}commit_sha'],
      ),
      resolved: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}resolved'],
      )!,
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReviewCommentsTable createAlias(String alias) {
    return $ReviewCommentsTable(attachedDatabase, alias);
  }
}

class ReviewCommentRow extends DataClass
    implements Insertable<ReviewCommentRow> {
  final int id;
  final int specId;

  /// 1, 2… (the round that asked for it).
  final int round;

  /// `revisor` (automatic) or `humano`.
  final String author;

  /// Relative path; null = about the spec as a whole.
  final String? path;
  final int? line;
  final String body;

  /// `alta` / `media` / `baixa`.
  final String? severity;

  /// Requirement it is about (`R2`).
  final String? requirement;

  /// Verdict of the round (`aprovar` / `corrigir`) on its first comment, and
  /// the commit reviewed.
  final String? verdict;
  final String? commitSha;
  final bool resolved;
  final DateTime? resolvedAt;
  final String? externalId;
  final DateTime createdAt;
  const ReviewCommentRow({
    required this.id,
    required this.specId,
    required this.round,
    required this.author,
    this.path,
    this.line,
    required this.body,
    this.severity,
    this.requirement,
    this.verdict,
    this.commitSha,
    required this.resolved,
    this.resolvedAt,
    this.externalId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['spec_id'] = Variable<int>(specId);
    map['round'] = Variable<int>(round);
    map['author'] = Variable<String>(author);
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || line != null) {
      map['line'] = Variable<int>(line);
    }
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || severity != null) {
      map['severity'] = Variable<String>(severity);
    }
    if (!nullToAbsent || requirement != null) {
      map['requirement'] = Variable<String>(requirement);
    }
    if (!nullToAbsent || verdict != null) {
      map['verdict'] = Variable<String>(verdict);
    }
    if (!nullToAbsent || commitSha != null) {
      map['commit_sha'] = Variable<String>(commitSha);
    }
    map['resolved'] = Variable<bool>(resolved);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ReviewCommentsCompanion toCompanion(bool nullToAbsent) {
    return ReviewCommentsCompanion(
      id: Value(id),
      specId: Value(specId),
      round: Value(round),
      author: Value(author),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      line: line == null && nullToAbsent ? const Value.absent() : Value(line),
      body: Value(body),
      severity: severity == null && nullToAbsent
          ? const Value.absent()
          : Value(severity),
      requirement: requirement == null && nullToAbsent
          ? const Value.absent()
          : Value(requirement),
      verdict: verdict == null && nullToAbsent
          ? const Value.absent()
          : Value(verdict),
      commitSha: commitSha == null && nullToAbsent
          ? const Value.absent()
          : Value(commitSha),
      resolved: Value(resolved),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      createdAt: Value(createdAt),
    );
  }

  factory ReviewCommentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewCommentRow(
      id: serializer.fromJson<int>(json['id']),
      specId: serializer.fromJson<int>(json['specId']),
      round: serializer.fromJson<int>(json['round']),
      author: serializer.fromJson<String>(json['author']),
      path: serializer.fromJson<String?>(json['path']),
      line: serializer.fromJson<int?>(json['line']),
      body: serializer.fromJson<String>(json['body']),
      severity: serializer.fromJson<String?>(json['severity']),
      requirement: serializer.fromJson<String?>(json['requirement']),
      verdict: serializer.fromJson<String?>(json['verdict']),
      commitSha: serializer.fromJson<String?>(json['commitSha']),
      resolved: serializer.fromJson<bool>(json['resolved']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'specId': serializer.toJson<int>(specId),
      'round': serializer.toJson<int>(round),
      'author': serializer.toJson<String>(author),
      'path': serializer.toJson<String?>(path),
      'line': serializer.toJson<int?>(line),
      'body': serializer.toJson<String>(body),
      'severity': serializer.toJson<String?>(severity),
      'requirement': serializer.toJson<String?>(requirement),
      'verdict': serializer.toJson<String?>(verdict),
      'commitSha': serializer.toJson<String?>(commitSha),
      'resolved': serializer.toJson<bool>(resolved),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
      'externalId': serializer.toJson<String?>(externalId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ReviewCommentRow copyWith({
    int? id,
    int? specId,
    int? round,
    String? author,
    Value<String?> path = const Value.absent(),
    Value<int?> line = const Value.absent(),
    String? body,
    Value<String?> severity = const Value.absent(),
    Value<String?> requirement = const Value.absent(),
    Value<String?> verdict = const Value.absent(),
    Value<String?> commitSha = const Value.absent(),
    bool? resolved,
    Value<DateTime?> resolvedAt = const Value.absent(),
    Value<String?> externalId = const Value.absent(),
    DateTime? createdAt,
  }) => ReviewCommentRow(
    id: id ?? this.id,
    specId: specId ?? this.specId,
    round: round ?? this.round,
    author: author ?? this.author,
    path: path.present ? path.value : this.path,
    line: line.present ? line.value : this.line,
    body: body ?? this.body,
    severity: severity.present ? severity.value : this.severity,
    requirement: requirement.present ? requirement.value : this.requirement,
    verdict: verdict.present ? verdict.value : this.verdict,
    commitSha: commitSha.present ? commitSha.value : this.commitSha,
    resolved: resolved ?? this.resolved,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    externalId: externalId.present ? externalId.value : this.externalId,
    createdAt: createdAt ?? this.createdAt,
  );
  ReviewCommentRow copyWithCompanion(ReviewCommentsCompanion data) {
    return ReviewCommentRow(
      id: data.id.present ? data.id.value : this.id,
      specId: data.specId.present ? data.specId.value : this.specId,
      round: data.round.present ? data.round.value : this.round,
      author: data.author.present ? data.author.value : this.author,
      path: data.path.present ? data.path.value : this.path,
      line: data.line.present ? data.line.value : this.line,
      body: data.body.present ? data.body.value : this.body,
      severity: data.severity.present ? data.severity.value : this.severity,
      requirement: data.requirement.present
          ? data.requirement.value
          : this.requirement,
      verdict: data.verdict.present ? data.verdict.value : this.verdict,
      commitSha: data.commitSha.present ? data.commitSha.value : this.commitSha,
      resolved: data.resolved.present ? data.resolved.value : this.resolved,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewCommentRow(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('round: $round, ')
          ..write('author: $author, ')
          ..write('path: $path, ')
          ..write('line: $line, ')
          ..write('body: $body, ')
          ..write('severity: $severity, ')
          ..write('requirement: $requirement, ')
          ..write('verdict: $verdict, ')
          ..write('commitSha: $commitSha, ')
          ..write('resolved: $resolved, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('externalId: $externalId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    specId,
    round,
    author,
    path,
    line,
    body,
    severity,
    requirement,
    verdict,
    commitSha,
    resolved,
    resolvedAt,
    externalId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewCommentRow &&
          other.id == this.id &&
          other.specId == this.specId &&
          other.round == this.round &&
          other.author == this.author &&
          other.path == this.path &&
          other.line == this.line &&
          other.body == this.body &&
          other.severity == this.severity &&
          other.requirement == this.requirement &&
          other.verdict == this.verdict &&
          other.commitSha == this.commitSha &&
          other.resolved == this.resolved &&
          other.resolvedAt == this.resolvedAt &&
          other.externalId == this.externalId &&
          other.createdAt == this.createdAt);
}

class ReviewCommentsCompanion extends UpdateCompanion<ReviewCommentRow> {
  final Value<int> id;
  final Value<int> specId;
  final Value<int> round;
  final Value<String> author;
  final Value<String?> path;
  final Value<int?> line;
  final Value<String> body;
  final Value<String?> severity;
  final Value<String?> requirement;
  final Value<String?> verdict;
  final Value<String?> commitSha;
  final Value<bool> resolved;
  final Value<DateTime?> resolvedAt;
  final Value<String?> externalId;
  final Value<DateTime> createdAt;
  const ReviewCommentsCompanion({
    this.id = const Value.absent(),
    this.specId = const Value.absent(),
    this.round = const Value.absent(),
    this.author = const Value.absent(),
    this.path = const Value.absent(),
    this.line = const Value.absent(),
    this.body = const Value.absent(),
    this.severity = const Value.absent(),
    this.requirement = const Value.absent(),
    this.verdict = const Value.absent(),
    this.commitSha = const Value.absent(),
    this.resolved = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.externalId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ReviewCommentsCompanion.insert({
    this.id = const Value.absent(),
    required int specId,
    required int round,
    required String author,
    this.path = const Value.absent(),
    this.line = const Value.absent(),
    required String body,
    this.severity = const Value.absent(),
    this.requirement = const Value.absent(),
    this.verdict = const Value.absent(),
    this.commitSha = const Value.absent(),
    this.resolved = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.externalId = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : specId = Value(specId),
       round = Value(round),
       author = Value(author),
       body = Value(body);
  static Insertable<ReviewCommentRow> custom({
    Expression<int>? id,
    Expression<int>? specId,
    Expression<int>? round,
    Expression<String>? author,
    Expression<String>? path,
    Expression<int>? line,
    Expression<String>? body,
    Expression<String>? severity,
    Expression<String>? requirement,
    Expression<String>? verdict,
    Expression<String>? commitSha,
    Expression<bool>? resolved,
    Expression<DateTime>? resolvedAt,
    Expression<String>? externalId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (specId != null) 'spec_id': specId,
      if (round != null) 'round': round,
      if (author != null) 'author': author,
      if (path != null) 'path': path,
      if (line != null) 'line': line,
      if (body != null) 'body': body,
      if (severity != null) 'severity': severity,
      if (requirement != null) 'requirement': requirement,
      if (verdict != null) 'verdict': verdict,
      if (commitSha != null) 'commit_sha': commitSha,
      if (resolved != null) 'resolved': resolved,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (externalId != null) 'external_id': externalId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ReviewCommentsCompanion copyWith({
    Value<int>? id,
    Value<int>? specId,
    Value<int>? round,
    Value<String>? author,
    Value<String?>? path,
    Value<int?>? line,
    Value<String>? body,
    Value<String?>? severity,
    Value<String?>? requirement,
    Value<String?>? verdict,
    Value<String?>? commitSha,
    Value<bool>? resolved,
    Value<DateTime?>? resolvedAt,
    Value<String?>? externalId,
    Value<DateTime>? createdAt,
  }) {
    return ReviewCommentsCompanion(
      id: id ?? this.id,
      specId: specId ?? this.specId,
      round: round ?? this.round,
      author: author ?? this.author,
      path: path ?? this.path,
      line: line ?? this.line,
      body: body ?? this.body,
      severity: severity ?? this.severity,
      requirement: requirement ?? this.requirement,
      verdict: verdict ?? this.verdict,
      commitSha: commitSha ?? this.commitSha,
      resolved: resolved ?? this.resolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      externalId: externalId ?? this.externalId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (specId.present) {
      map['spec_id'] = Variable<int>(specId.value);
    }
    if (round.present) {
      map['round'] = Variable<int>(round.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (line.present) {
      map['line'] = Variable<int>(line.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (requirement.present) {
      map['requirement'] = Variable<String>(requirement.value);
    }
    if (verdict.present) {
      map['verdict'] = Variable<String>(verdict.value);
    }
    if (commitSha.present) {
      map['commit_sha'] = Variable<String>(commitSha.value);
    }
    if (resolved.present) {
      map['resolved'] = Variable<bool>(resolved.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewCommentsCompanion(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('round: $round, ')
          ..write('author: $author, ')
          ..write('path: $path, ')
          ..write('line: $line, ')
          ..write('body: $body, ')
          ..write('severity: $severity, ')
          ..write('requirement: $requirement, ')
          ..write('verdict: $verdict, ')
          ..write('commitSha: $commitSha, ')
          ..write('resolved: $resolved, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('externalId: $externalId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SpecCriteriaTable extends SpecCriteria
    with TableInfo<$SpecCriteriaTable, SpecCriteriaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpecCriteriaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _specIdMeta = const VerificationMeta('specId');
  @override
  late final GeneratedColumn<int> specId = GeneratedColumn<int>(
    'spec_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _criterionMeta = const VerificationMeta(
    'criterion',
  );
  @override
  late final GeneratedColumn<String> criterion = GeneratedColumn<String>(
    'criterion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkedMeta = const VerificationMeta(
    'checked',
  );
  @override
  late final GeneratedColumn<bool> checked = GeneratedColumn<bool>(
    'checked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("checked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _checkedByMeta = const VerificationMeta(
    'checkedBy',
  );
  @override
  late final GeneratedColumn<String> checkedBy = GeneratedColumn<String>(
    'checked_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    specId,
    criterion,
    checked,
    checkedBy,
    checkedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spec_criteria';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpecCriteriaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('spec_id')) {
      context.handle(
        _specIdMeta,
        specId.isAcceptableOrUnknown(data['spec_id']!, _specIdMeta),
      );
    } else if (isInserting) {
      context.missing(_specIdMeta);
    }
    if (data.containsKey('criterion')) {
      context.handle(
        _criterionMeta,
        criterion.isAcceptableOrUnknown(data['criterion']!, _criterionMeta),
      );
    } else if (isInserting) {
      context.missing(_criterionMeta);
    }
    if (data.containsKey('checked')) {
      context.handle(
        _checkedMeta,
        checked.isAcceptableOrUnknown(data['checked']!, _checkedMeta),
      );
    }
    if (data.containsKey('checked_by')) {
      context.handle(
        _checkedByMeta,
        checkedBy.isAcceptableOrUnknown(data['checked_by']!, _checkedByMeta),
      );
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {specId, criterion};
  @override
  SpecCriteriaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpecCriteriaData(
      specId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spec_id'],
      )!,
      criterion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}criterion'],
      )!,
      checked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}checked'],
      )!,
      checkedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checked_by'],
      ),
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      ),
    );
  }

  @override
  $SpecCriteriaTable createAlias(String alias) {
    return $SpecCriteriaTable(attachedDatabase, alias);
  }
}

class SpecCriteriaData extends DataClass
    implements Insertable<SpecCriteriaData> {
  final int specId;
  final String criterion;
  final bool checked;

  /// `gate`, `revisor` or `humano`.
  final String? checkedBy;
  final DateTime? checkedAt;
  const SpecCriteriaData({
    required this.specId,
    required this.criterion,
    required this.checked,
    this.checkedBy,
    this.checkedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['spec_id'] = Variable<int>(specId);
    map['criterion'] = Variable<String>(criterion);
    map['checked'] = Variable<bool>(checked);
    if (!nullToAbsent || checkedBy != null) {
      map['checked_by'] = Variable<String>(checkedBy);
    }
    if (!nullToAbsent || checkedAt != null) {
      map['checked_at'] = Variable<DateTime>(checkedAt);
    }
    return map;
  }

  SpecCriteriaCompanion toCompanion(bool nullToAbsent) {
    return SpecCriteriaCompanion(
      specId: Value(specId),
      criterion: Value(criterion),
      checked: Value(checked),
      checkedBy: checkedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedBy),
      checkedAt: checkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedAt),
    );
  }

  factory SpecCriteriaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpecCriteriaData(
      specId: serializer.fromJson<int>(json['specId']),
      criterion: serializer.fromJson<String>(json['criterion']),
      checked: serializer.fromJson<bool>(json['checked']),
      checkedBy: serializer.fromJson<String?>(json['checkedBy']),
      checkedAt: serializer.fromJson<DateTime?>(json['checkedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'specId': serializer.toJson<int>(specId),
      'criterion': serializer.toJson<String>(criterion),
      'checked': serializer.toJson<bool>(checked),
      'checkedBy': serializer.toJson<String?>(checkedBy),
      'checkedAt': serializer.toJson<DateTime?>(checkedAt),
    };
  }

  SpecCriteriaData copyWith({
    int? specId,
    String? criterion,
    bool? checked,
    Value<String?> checkedBy = const Value.absent(),
    Value<DateTime?> checkedAt = const Value.absent(),
  }) => SpecCriteriaData(
    specId: specId ?? this.specId,
    criterion: criterion ?? this.criterion,
    checked: checked ?? this.checked,
    checkedBy: checkedBy.present ? checkedBy.value : this.checkedBy,
    checkedAt: checkedAt.present ? checkedAt.value : this.checkedAt,
  );
  SpecCriteriaData copyWithCompanion(SpecCriteriaCompanion data) {
    return SpecCriteriaData(
      specId: data.specId.present ? data.specId.value : this.specId,
      criterion: data.criterion.present ? data.criterion.value : this.criterion,
      checked: data.checked.present ? data.checked.value : this.checked,
      checkedBy: data.checkedBy.present ? data.checkedBy.value : this.checkedBy,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpecCriteriaData(')
          ..write('specId: $specId, ')
          ..write('criterion: $criterion, ')
          ..write('checked: $checked, ')
          ..write('checkedBy: $checkedBy, ')
          ..write('checkedAt: $checkedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(specId, criterion, checked, checkedBy, checkedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpecCriteriaData &&
          other.specId == this.specId &&
          other.criterion == this.criterion &&
          other.checked == this.checked &&
          other.checkedBy == this.checkedBy &&
          other.checkedAt == this.checkedAt);
}

class SpecCriteriaCompanion extends UpdateCompanion<SpecCriteriaData> {
  final Value<int> specId;
  final Value<String> criterion;
  final Value<bool> checked;
  final Value<String?> checkedBy;
  final Value<DateTime?> checkedAt;
  final Value<int> rowid;
  const SpecCriteriaCompanion({
    this.specId = const Value.absent(),
    this.criterion = const Value.absent(),
    this.checked = const Value.absent(),
    this.checkedBy = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SpecCriteriaCompanion.insert({
    required int specId,
    required String criterion,
    this.checked = const Value.absent(),
    this.checkedBy = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : specId = Value(specId),
       criterion = Value(criterion);
  static Insertable<SpecCriteriaData> custom({
    Expression<int>? specId,
    Expression<String>? criterion,
    Expression<bool>? checked,
    Expression<String>? checkedBy,
    Expression<DateTime>? checkedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (specId != null) 'spec_id': specId,
      if (criterion != null) 'criterion': criterion,
      if (checked != null) 'checked': checked,
      if (checkedBy != null) 'checked_by': checkedBy,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SpecCriteriaCompanion copyWith({
    Value<int>? specId,
    Value<String>? criterion,
    Value<bool>? checked,
    Value<String?>? checkedBy,
    Value<DateTime?>? checkedAt,
    Value<int>? rowid,
  }) {
    return SpecCriteriaCompanion(
      specId: specId ?? this.specId,
      criterion: criterion ?? this.criterion,
      checked: checked ?? this.checked,
      checkedBy: checkedBy ?? this.checkedBy,
      checkedAt: checkedAt ?? this.checkedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (specId.present) {
      map['spec_id'] = Variable<int>(specId.value);
    }
    if (criterion.present) {
      map['criterion'] = Variable<String>(criterion.value);
    }
    if (checked.present) {
      map['checked'] = Variable<bool>(checked.value);
    }
    if (checkedBy.present) {
      map['checked_by'] = Variable<String>(checkedBy.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpecCriteriaCompanion(')
          ..write('specId: $specId, ')
          ..write('criterion: $criterion, ')
          ..write('checked: $checked, ')
          ..write('checkedBy: $checkedBy, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SpecSuggestionsTable extends SpecSuggestions
    with TableInfo<$SpecSuggestionsTable, SpecSuggestion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpecSuggestionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _specIdMeta = const VerificationMeta('specId');
  @override
  late final GeneratedColumn<int> specId = GeneratedColumn<int>(
    'spec_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<String> steps = GeneratedColumn<String>(
    'steps',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pendente'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    specId,
    sessionId,
    steps,
    body,
    state,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spec_suggestions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpecSuggestion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('spec_id')) {
      context.handle(
        _specIdMeta,
        specId.isAcceptableOrUnknown(data['spec_id']!, _specIdMeta),
      );
    } else if (isInserting) {
      context.missing(_specIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SpecSuggestion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpecSuggestion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      specId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spec_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      steps: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}steps'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SpecSuggestionsTable createAlias(String alias) {
    return $SpecSuggestionsTable(attachedDatabase, alias);
  }
}

class SpecSuggestion extends DataClass implements Insertable<SpecSuggestion> {
  final int id;
  final int specId;
  final String? sessionId;

  /// Steps of the session that wrote it (`R2`).
  final String? steps;
  final String body;

  /// `pendente` / `aplicada` / `ignorada`.
  final String state;
  final DateTime createdAt;
  const SpecSuggestion({
    required this.id,
    required this.specId,
    this.sessionId,
    this.steps,
    required this.body,
    required this.state,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['spec_id'] = Variable<int>(specId);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    if (!nullToAbsent || steps != null) {
      map['steps'] = Variable<String>(steps);
    }
    map['body'] = Variable<String>(body);
    map['state'] = Variable<String>(state);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SpecSuggestionsCompanion toCompanion(bool nullToAbsent) {
    return SpecSuggestionsCompanion(
      id: Value(id),
      specId: Value(specId),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      steps: steps == null && nullToAbsent
          ? const Value.absent()
          : Value(steps),
      body: Value(body),
      state: Value(state),
      createdAt: Value(createdAt),
    );
  }

  factory SpecSuggestion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpecSuggestion(
      id: serializer.fromJson<int>(json['id']),
      specId: serializer.fromJson<int>(json['specId']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      steps: serializer.fromJson<String?>(json['steps']),
      body: serializer.fromJson<String>(json['body']),
      state: serializer.fromJson<String>(json['state']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'specId': serializer.toJson<int>(specId),
      'sessionId': serializer.toJson<String?>(sessionId),
      'steps': serializer.toJson<String?>(steps),
      'body': serializer.toJson<String>(body),
      'state': serializer.toJson<String>(state),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SpecSuggestion copyWith({
    int? id,
    int? specId,
    Value<String?> sessionId = const Value.absent(),
    Value<String?> steps = const Value.absent(),
    String? body,
    String? state,
    DateTime? createdAt,
  }) => SpecSuggestion(
    id: id ?? this.id,
    specId: specId ?? this.specId,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    steps: steps.present ? steps.value : this.steps,
    body: body ?? this.body,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
  );
  SpecSuggestion copyWithCompanion(SpecSuggestionsCompanion data) {
    return SpecSuggestion(
      id: data.id.present ? data.id.value : this.id,
      specId: data.specId.present ? data.specId.value : this.specId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      steps: data.steps.present ? data.steps.value : this.steps,
      body: data.body.present ? data.body.value : this.body,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpecSuggestion(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('sessionId: $sessionId, ')
          ..write('steps: $steps, ')
          ..write('body: $body, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, specId, sessionId, steps, body, state, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpecSuggestion &&
          other.id == this.id &&
          other.specId == this.specId &&
          other.sessionId == this.sessionId &&
          other.steps == this.steps &&
          other.body == this.body &&
          other.state == this.state &&
          other.createdAt == this.createdAt);
}

class SpecSuggestionsCompanion extends UpdateCompanion<SpecSuggestion> {
  final Value<int> id;
  final Value<int> specId;
  final Value<String?> sessionId;
  final Value<String?> steps;
  final Value<String> body;
  final Value<String> state;
  final Value<DateTime> createdAt;
  const SpecSuggestionsCompanion({
    this.id = const Value.absent(),
    this.specId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.steps = const Value.absent(),
    this.body = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SpecSuggestionsCompanion.insert({
    this.id = const Value.absent(),
    required int specId,
    this.sessionId = const Value.absent(),
    this.steps = const Value.absent(),
    required String body,
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : specId = Value(specId),
       body = Value(body);
  static Insertable<SpecSuggestion> custom({
    Expression<int>? id,
    Expression<int>? specId,
    Expression<String>? sessionId,
    Expression<String>? steps,
    Expression<String>? body,
    Expression<String>? state,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (specId != null) 'spec_id': specId,
      if (sessionId != null) 'session_id': sessionId,
      if (steps != null) 'steps': steps,
      if (body != null) 'body': body,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SpecSuggestionsCompanion copyWith({
    Value<int>? id,
    Value<int>? specId,
    Value<String?>? sessionId,
    Value<String?>? steps,
    Value<String>? body,
    Value<String>? state,
    Value<DateTime>? createdAt,
  }) {
    return SpecSuggestionsCompanion(
      id: id ?? this.id,
      specId: specId ?? this.specId,
      sessionId: sessionId ?? this.sessionId,
      steps: steps ?? this.steps,
      body: body ?? this.body,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (specId.present) {
      map['spec_id'] = Variable<int>(specId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (steps.present) {
      map['steps'] = Variable<String>(steps.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpecSuggestionsCompanion(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('sessionId: $sessionId, ')
          ..write('steps: $steps, ')
          ..write('body: $body, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $NotificationsTable extends Notifications
    with TableInfo<$NotificationsTable, AppNotification> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sectionMeta = const VerificationMeta(
    'section',
  );
  @override
  late final GeneratedColumn<String> section = GeneratedColumn<String>(
    'section',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  @override
  late final GeneratedColumn<bool> read = GeneratedColumn<bool>(
    'read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    section,
    sessionId,
    read,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notifications';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppNotification> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('section')) {
      context.handle(
        _sectionMeta,
        section.isAcceptableOrUnknown(data['section']!, _sectionMeta),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('read')) {
      context.handle(
        _readMeta,
        read.isAcceptableOrUnknown(data['read']!, _readMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppNotification map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppNotification(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      section: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section'],
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      read: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NotificationsTable createAlias(String alias) {
    return $NotificationsTable(attachedDatabase, alias);
  }
}

class AppNotification extends DataClass implements Insertable<AppNotification> {
  final int id;
  final String title;
  final String body;

  /// `AppSection.name` the click goes to.
  final String? section;

  /// Session selected by the click.
  final String? sessionId;
  final bool read;
  final DateTime createdAt;
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.section,
    this.sessionId,
    required this.read,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || section != null) {
      map['section'] = Variable<String>(section);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['read'] = Variable<bool>(read);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NotificationsCompanion toCompanion(bool nullToAbsent) {
    return NotificationsCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      section: section == null && nullToAbsent
          ? const Value.absent()
          : Value(section),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      read: Value(read),
      createdAt: Value(createdAt),
    );
  }

  factory AppNotification.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppNotification(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      section: serializer.fromJson<String?>(json['section']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      read: serializer.fromJson<bool>(json['read']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'section': serializer.toJson<String?>(section),
      'sessionId': serializer.toJson<String?>(sessionId),
      'read': serializer.toJson<bool>(read),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AppNotification copyWith({
    int? id,
    String? title,
    String? body,
    Value<String?> section = const Value.absent(),
    Value<String?> sessionId = const Value.absent(),
    bool? read,
    DateTime? createdAt,
  }) => AppNotification(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    section: section.present ? section.value : this.section,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    read: read ?? this.read,
    createdAt: createdAt ?? this.createdAt,
  );
  AppNotification copyWithCompanion(NotificationsCompanion data) {
    return AppNotification(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      section: data.section.present ? data.section.value : this.section,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      read: data.read.present ? data.read.value : this.read,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppNotification(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('section: $section, ')
          ..write('sessionId: $sessionId, ')
          ..write('read: $read, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, body, section, sessionId, read, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppNotification &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.section == this.section &&
          other.sessionId == this.sessionId &&
          other.read == this.read &&
          other.createdAt == this.createdAt);
}

class NotificationsCompanion extends UpdateCompanion<AppNotification> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> body;
  final Value<String?> section;
  final Value<String?> sessionId;
  final Value<bool> read;
  final Value<DateTime> createdAt;
  const NotificationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.section = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.read = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  NotificationsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required String body,
    this.section = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.read = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : title = Value(title),
       body = Value(body);
  static Insertable<AppNotification> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? section,
    Expression<String>? sessionId,
    Expression<bool>? read,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (section != null) 'section': section,
      if (sessionId != null) 'session_id': sessionId,
      if (read != null) 'read': read,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  NotificationsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? body,
    Value<String?>? section,
    Value<String?>? sessionId,
    Value<bool>? read,
    Value<DateTime>? createdAt,
  }) {
    return NotificationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      section: section ?? this.section,
      sessionId: sessionId ?? this.sessionId,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (section.present) {
      map['section'] = Variable<String>(section.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (read.present) {
      map['read'] = Variable<bool>(read.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('section: $section, ')
          ..write('sessionId: $sessionId, ')
          ..write('read: $read, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SpecDuelsTable extends SpecDuels
    with TableInfo<$SpecDuelsTable, SpecDuel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpecDuelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _specIdMeta = const VerificationMeta('specId');
  @override
  late final GeneratedColumn<int> specId = GeneratedColumn<int>(
    'spec_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES specs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<String> steps = GeneratedColumn<String>(
    'steps',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseShaMeta = const VerificationMeta(
    'baseSha',
  );
  @override
  late final GeneratedColumn<String> baseSha = GeneratedColumn<String>(
    'base_sha',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionAMeta = const VerificationMeta(
    'sessionA',
  );
  @override
  late final GeneratedColumn<String> sessionA = GeneratedColumn<String>(
    'session_a',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionBMeta = const VerificationMeta(
    'sessionB',
  );
  @override
  late final GeneratedColumn<String> sessionB = GeneratedColumn<String>(
    'session_b',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _worktreeAMeta = const VerificationMeta(
    'worktreeA',
  );
  @override
  late final GeneratedColumn<String> worktreeA = GeneratedColumn<String>(
    'worktree_a',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _worktreeBMeta = const VerificationMeta(
    'worktreeB',
  );
  @override
  late final GeneratedColumn<String> worktreeB = GeneratedColumn<String>(
    'worktree_b',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchAMeta = const VerificationMeta(
    'branchA',
  );
  @override
  late final GeneratedColumn<String> branchA = GeneratedColumn<String>(
    'branch_a',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchBMeta = const VerificationMeta(
    'branchB',
  );
  @override
  late final GeneratedColumn<String> branchB = GeneratedColumn<String>(
    'branch_b',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reportAMeta = const VerificationMeta(
    'reportA',
  );
  @override
  late final GeneratedColumn<String> reportA = GeneratedColumn<String>(
    'report_a',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reportBMeta = const VerificationMeta(
    'reportB',
  );
  @override
  late final GeneratedColumn<String> reportB = GeneratedColumn<String>(
    'report_b',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('rodando'),
  );
  static const VerificationMeta _chosenMeta = const VerificationMeta('chosen');
  @override
  late final GeneratedColumn<String> chosen = GeneratedColumn<String>(
    'chosen',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    specId,
    steps,
    baseSha,
    sessionA,
    sessionB,
    worktreeA,
    worktreeB,
    branchA,
    branchB,
    reportA,
    reportB,
    state,
    chosen,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spec_duels';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpecDuel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('spec_id')) {
      context.handle(
        _specIdMeta,
        specId.isAcceptableOrUnknown(data['spec_id']!, _specIdMeta),
      );
    } else if (isInserting) {
      context.missing(_specIdMeta);
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    } else if (isInserting) {
      context.missing(_stepsMeta);
    }
    if (data.containsKey('base_sha')) {
      context.handle(
        _baseShaMeta,
        baseSha.isAcceptableOrUnknown(data['base_sha']!, _baseShaMeta),
      );
    } else if (isInserting) {
      context.missing(_baseShaMeta);
    }
    if (data.containsKey('session_a')) {
      context.handle(
        _sessionAMeta,
        sessionA.isAcceptableOrUnknown(data['session_a']!, _sessionAMeta),
      );
    }
    if (data.containsKey('session_b')) {
      context.handle(
        _sessionBMeta,
        sessionB.isAcceptableOrUnknown(data['session_b']!, _sessionBMeta),
      );
    }
    if (data.containsKey('worktree_a')) {
      context.handle(
        _worktreeAMeta,
        worktreeA.isAcceptableOrUnknown(data['worktree_a']!, _worktreeAMeta),
      );
    } else if (isInserting) {
      context.missing(_worktreeAMeta);
    }
    if (data.containsKey('worktree_b')) {
      context.handle(
        _worktreeBMeta,
        worktreeB.isAcceptableOrUnknown(data['worktree_b']!, _worktreeBMeta),
      );
    } else if (isInserting) {
      context.missing(_worktreeBMeta);
    }
    if (data.containsKey('branch_a')) {
      context.handle(
        _branchAMeta,
        branchA.isAcceptableOrUnknown(data['branch_a']!, _branchAMeta),
      );
    } else if (isInserting) {
      context.missing(_branchAMeta);
    }
    if (data.containsKey('branch_b')) {
      context.handle(
        _branchBMeta,
        branchB.isAcceptableOrUnknown(data['branch_b']!, _branchBMeta),
      );
    } else if (isInserting) {
      context.missing(_branchBMeta);
    }
    if (data.containsKey('report_a')) {
      context.handle(
        _reportAMeta,
        reportA.isAcceptableOrUnknown(data['report_a']!, _reportAMeta),
      );
    }
    if (data.containsKey('report_b')) {
      context.handle(
        _reportBMeta,
        reportB.isAcceptableOrUnknown(data['report_b']!, _reportBMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('chosen')) {
      context.handle(
        _chosenMeta,
        chosen.isAcceptableOrUnknown(data['chosen']!, _chosenMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SpecDuel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpecDuel(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      specId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spec_id'],
      )!,
      steps: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}steps'],
      )!,
      baseSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_sha'],
      )!,
      sessionA: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_a'],
      ),
      sessionB: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_b'],
      ),
      worktreeA: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}worktree_a'],
      )!,
      worktreeB: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}worktree_b'],
      )!,
      branchA: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_a'],
      )!,
      branchB: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_b'],
      )!,
      reportA: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}report_a'],
      ),
      reportB: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}report_b'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      chosen: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chosen'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SpecDuelsTable createAlias(String alias) {
    return $SpecDuelsTable(attachedDatabase, alias);
  }
}

class SpecDuel extends DataClass implements Insertable<SpecDuel> {
  final int id;
  final int specId;

  /// `R2` / `R2,R3`.
  final String steps;

  /// HEAD of the spec's worktree when the attempts started.
  final String baseSha;
  final String? sessionA;
  final String? sessionB;
  final String worktreeA;
  final String worktreeB;
  final String branchA;
  final String branchB;

  /// Gate of each attempt (JSON of `GateReport`).
  final String? reportA;
  final String? reportB;

  /// `rodando` / `pronto` / `escolhido` / `descartado`.
  final String state;

  /// `A` / `B` once chosen.
  final String? chosen;
  final DateTime createdAt;
  const SpecDuel({
    required this.id,
    required this.specId,
    required this.steps,
    required this.baseSha,
    this.sessionA,
    this.sessionB,
    required this.worktreeA,
    required this.worktreeB,
    required this.branchA,
    required this.branchB,
    this.reportA,
    this.reportB,
    required this.state,
    this.chosen,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['spec_id'] = Variable<int>(specId);
    map['steps'] = Variable<String>(steps);
    map['base_sha'] = Variable<String>(baseSha);
    if (!nullToAbsent || sessionA != null) {
      map['session_a'] = Variable<String>(sessionA);
    }
    if (!nullToAbsent || sessionB != null) {
      map['session_b'] = Variable<String>(sessionB);
    }
    map['worktree_a'] = Variable<String>(worktreeA);
    map['worktree_b'] = Variable<String>(worktreeB);
    map['branch_a'] = Variable<String>(branchA);
    map['branch_b'] = Variable<String>(branchB);
    if (!nullToAbsent || reportA != null) {
      map['report_a'] = Variable<String>(reportA);
    }
    if (!nullToAbsent || reportB != null) {
      map['report_b'] = Variable<String>(reportB);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || chosen != null) {
      map['chosen'] = Variable<String>(chosen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SpecDuelsCompanion toCompanion(bool nullToAbsent) {
    return SpecDuelsCompanion(
      id: Value(id),
      specId: Value(specId),
      steps: Value(steps),
      baseSha: Value(baseSha),
      sessionA: sessionA == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionA),
      sessionB: sessionB == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionB),
      worktreeA: Value(worktreeA),
      worktreeB: Value(worktreeB),
      branchA: Value(branchA),
      branchB: Value(branchB),
      reportA: reportA == null && nullToAbsent
          ? const Value.absent()
          : Value(reportA),
      reportB: reportB == null && nullToAbsent
          ? const Value.absent()
          : Value(reportB),
      state: Value(state),
      chosen: chosen == null && nullToAbsent
          ? const Value.absent()
          : Value(chosen),
      createdAt: Value(createdAt),
    );
  }

  factory SpecDuel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpecDuel(
      id: serializer.fromJson<int>(json['id']),
      specId: serializer.fromJson<int>(json['specId']),
      steps: serializer.fromJson<String>(json['steps']),
      baseSha: serializer.fromJson<String>(json['baseSha']),
      sessionA: serializer.fromJson<String?>(json['sessionA']),
      sessionB: serializer.fromJson<String?>(json['sessionB']),
      worktreeA: serializer.fromJson<String>(json['worktreeA']),
      worktreeB: serializer.fromJson<String>(json['worktreeB']),
      branchA: serializer.fromJson<String>(json['branchA']),
      branchB: serializer.fromJson<String>(json['branchB']),
      reportA: serializer.fromJson<String?>(json['reportA']),
      reportB: serializer.fromJson<String?>(json['reportB']),
      state: serializer.fromJson<String>(json['state']),
      chosen: serializer.fromJson<String?>(json['chosen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'specId': serializer.toJson<int>(specId),
      'steps': serializer.toJson<String>(steps),
      'baseSha': serializer.toJson<String>(baseSha),
      'sessionA': serializer.toJson<String?>(sessionA),
      'sessionB': serializer.toJson<String?>(sessionB),
      'worktreeA': serializer.toJson<String>(worktreeA),
      'worktreeB': serializer.toJson<String>(worktreeB),
      'branchA': serializer.toJson<String>(branchA),
      'branchB': serializer.toJson<String>(branchB),
      'reportA': serializer.toJson<String?>(reportA),
      'reportB': serializer.toJson<String?>(reportB),
      'state': serializer.toJson<String>(state),
      'chosen': serializer.toJson<String?>(chosen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SpecDuel copyWith({
    int? id,
    int? specId,
    String? steps,
    String? baseSha,
    Value<String?> sessionA = const Value.absent(),
    Value<String?> sessionB = const Value.absent(),
    String? worktreeA,
    String? worktreeB,
    String? branchA,
    String? branchB,
    Value<String?> reportA = const Value.absent(),
    Value<String?> reportB = const Value.absent(),
    String? state,
    Value<String?> chosen = const Value.absent(),
    DateTime? createdAt,
  }) => SpecDuel(
    id: id ?? this.id,
    specId: specId ?? this.specId,
    steps: steps ?? this.steps,
    baseSha: baseSha ?? this.baseSha,
    sessionA: sessionA.present ? sessionA.value : this.sessionA,
    sessionB: sessionB.present ? sessionB.value : this.sessionB,
    worktreeA: worktreeA ?? this.worktreeA,
    worktreeB: worktreeB ?? this.worktreeB,
    branchA: branchA ?? this.branchA,
    branchB: branchB ?? this.branchB,
    reportA: reportA.present ? reportA.value : this.reportA,
    reportB: reportB.present ? reportB.value : this.reportB,
    state: state ?? this.state,
    chosen: chosen.present ? chosen.value : this.chosen,
    createdAt: createdAt ?? this.createdAt,
  );
  SpecDuel copyWithCompanion(SpecDuelsCompanion data) {
    return SpecDuel(
      id: data.id.present ? data.id.value : this.id,
      specId: data.specId.present ? data.specId.value : this.specId,
      steps: data.steps.present ? data.steps.value : this.steps,
      baseSha: data.baseSha.present ? data.baseSha.value : this.baseSha,
      sessionA: data.sessionA.present ? data.sessionA.value : this.sessionA,
      sessionB: data.sessionB.present ? data.sessionB.value : this.sessionB,
      worktreeA: data.worktreeA.present ? data.worktreeA.value : this.worktreeA,
      worktreeB: data.worktreeB.present ? data.worktreeB.value : this.worktreeB,
      branchA: data.branchA.present ? data.branchA.value : this.branchA,
      branchB: data.branchB.present ? data.branchB.value : this.branchB,
      reportA: data.reportA.present ? data.reportA.value : this.reportA,
      reportB: data.reportB.present ? data.reportB.value : this.reportB,
      state: data.state.present ? data.state.value : this.state,
      chosen: data.chosen.present ? data.chosen.value : this.chosen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpecDuel(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('steps: $steps, ')
          ..write('baseSha: $baseSha, ')
          ..write('sessionA: $sessionA, ')
          ..write('sessionB: $sessionB, ')
          ..write('worktreeA: $worktreeA, ')
          ..write('worktreeB: $worktreeB, ')
          ..write('branchA: $branchA, ')
          ..write('branchB: $branchB, ')
          ..write('reportA: $reportA, ')
          ..write('reportB: $reportB, ')
          ..write('state: $state, ')
          ..write('chosen: $chosen, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    specId,
    steps,
    baseSha,
    sessionA,
    sessionB,
    worktreeA,
    worktreeB,
    branchA,
    branchB,
    reportA,
    reportB,
    state,
    chosen,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpecDuel &&
          other.id == this.id &&
          other.specId == this.specId &&
          other.steps == this.steps &&
          other.baseSha == this.baseSha &&
          other.sessionA == this.sessionA &&
          other.sessionB == this.sessionB &&
          other.worktreeA == this.worktreeA &&
          other.worktreeB == this.worktreeB &&
          other.branchA == this.branchA &&
          other.branchB == this.branchB &&
          other.reportA == this.reportA &&
          other.reportB == this.reportB &&
          other.state == this.state &&
          other.chosen == this.chosen &&
          other.createdAt == this.createdAt);
}

class SpecDuelsCompanion extends UpdateCompanion<SpecDuel> {
  final Value<int> id;
  final Value<int> specId;
  final Value<String> steps;
  final Value<String> baseSha;
  final Value<String?> sessionA;
  final Value<String?> sessionB;
  final Value<String> worktreeA;
  final Value<String> worktreeB;
  final Value<String> branchA;
  final Value<String> branchB;
  final Value<String?> reportA;
  final Value<String?> reportB;
  final Value<String> state;
  final Value<String?> chosen;
  final Value<DateTime> createdAt;
  const SpecDuelsCompanion({
    this.id = const Value.absent(),
    this.specId = const Value.absent(),
    this.steps = const Value.absent(),
    this.baseSha = const Value.absent(),
    this.sessionA = const Value.absent(),
    this.sessionB = const Value.absent(),
    this.worktreeA = const Value.absent(),
    this.worktreeB = const Value.absent(),
    this.branchA = const Value.absent(),
    this.branchB = const Value.absent(),
    this.reportA = const Value.absent(),
    this.reportB = const Value.absent(),
    this.state = const Value.absent(),
    this.chosen = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SpecDuelsCompanion.insert({
    this.id = const Value.absent(),
    required int specId,
    required String steps,
    required String baseSha,
    this.sessionA = const Value.absent(),
    this.sessionB = const Value.absent(),
    required String worktreeA,
    required String worktreeB,
    required String branchA,
    required String branchB,
    this.reportA = const Value.absent(),
    this.reportB = const Value.absent(),
    this.state = const Value.absent(),
    this.chosen = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : specId = Value(specId),
       steps = Value(steps),
       baseSha = Value(baseSha),
       worktreeA = Value(worktreeA),
       worktreeB = Value(worktreeB),
       branchA = Value(branchA),
       branchB = Value(branchB);
  static Insertable<SpecDuel> custom({
    Expression<int>? id,
    Expression<int>? specId,
    Expression<String>? steps,
    Expression<String>? baseSha,
    Expression<String>? sessionA,
    Expression<String>? sessionB,
    Expression<String>? worktreeA,
    Expression<String>? worktreeB,
    Expression<String>? branchA,
    Expression<String>? branchB,
    Expression<String>? reportA,
    Expression<String>? reportB,
    Expression<String>? state,
    Expression<String>? chosen,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (specId != null) 'spec_id': specId,
      if (steps != null) 'steps': steps,
      if (baseSha != null) 'base_sha': baseSha,
      if (sessionA != null) 'session_a': sessionA,
      if (sessionB != null) 'session_b': sessionB,
      if (worktreeA != null) 'worktree_a': worktreeA,
      if (worktreeB != null) 'worktree_b': worktreeB,
      if (branchA != null) 'branch_a': branchA,
      if (branchB != null) 'branch_b': branchB,
      if (reportA != null) 'report_a': reportA,
      if (reportB != null) 'report_b': reportB,
      if (state != null) 'state': state,
      if (chosen != null) 'chosen': chosen,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SpecDuelsCompanion copyWith({
    Value<int>? id,
    Value<int>? specId,
    Value<String>? steps,
    Value<String>? baseSha,
    Value<String?>? sessionA,
    Value<String?>? sessionB,
    Value<String>? worktreeA,
    Value<String>? worktreeB,
    Value<String>? branchA,
    Value<String>? branchB,
    Value<String?>? reportA,
    Value<String?>? reportB,
    Value<String>? state,
    Value<String?>? chosen,
    Value<DateTime>? createdAt,
  }) {
    return SpecDuelsCompanion(
      id: id ?? this.id,
      specId: specId ?? this.specId,
      steps: steps ?? this.steps,
      baseSha: baseSha ?? this.baseSha,
      sessionA: sessionA ?? this.sessionA,
      sessionB: sessionB ?? this.sessionB,
      worktreeA: worktreeA ?? this.worktreeA,
      worktreeB: worktreeB ?? this.worktreeB,
      branchA: branchA ?? this.branchA,
      branchB: branchB ?? this.branchB,
      reportA: reportA ?? this.reportA,
      reportB: reportB ?? this.reportB,
      state: state ?? this.state,
      chosen: chosen ?? this.chosen,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (specId.present) {
      map['spec_id'] = Variable<int>(specId.value);
    }
    if (steps.present) {
      map['steps'] = Variable<String>(steps.value);
    }
    if (baseSha.present) {
      map['base_sha'] = Variable<String>(baseSha.value);
    }
    if (sessionA.present) {
      map['session_a'] = Variable<String>(sessionA.value);
    }
    if (sessionB.present) {
      map['session_b'] = Variable<String>(sessionB.value);
    }
    if (worktreeA.present) {
      map['worktree_a'] = Variable<String>(worktreeA.value);
    }
    if (worktreeB.present) {
      map['worktree_b'] = Variable<String>(worktreeB.value);
    }
    if (branchA.present) {
      map['branch_a'] = Variable<String>(branchA.value);
    }
    if (branchB.present) {
      map['branch_b'] = Variable<String>(branchB.value);
    }
    if (reportA.present) {
      map['report_a'] = Variable<String>(reportA.value);
    }
    if (reportB.present) {
      map['report_b'] = Variable<String>(reportB.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (chosen.present) {
      map['chosen'] = Variable<String>(chosen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpecDuelsCompanion(')
          ..write('id: $id, ')
          ..write('specId: $specId, ')
          ..write('steps: $steps, ')
          ..write('baseSha: $baseSha, ')
          ..write('sessionA: $sessionA, ')
          ..write('sessionB: $sessionB, ')
          ..write('worktreeA: $worktreeA, ')
          ..write('worktreeB: $worktreeB, ')
          ..write('branchA: $branchA, ')
          ..write('branchB: $branchB, ')
          ..write('reportA: $reportA, ')
          ..write('reportB: $reportB, ')
          ..write('state: $state, ')
          ..write('chosen: $chosen, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WorkspacesTable workspaces = $WorkspacesTable(this);
  late final $SpecsTable specs = $SpecsTable(this);
  late final $SpecStepsTable specSteps = $SpecStepsTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $SessionEventsTable sessionEvents = $SessionEventsTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $ConversationEventsTable conversationEvents =
      $ConversationEventsTable(this);
  late final $SavedPromptsTable savedPrompts = $SavedPromptsTable(this);
  late final $AgentSettingsTable agentSettings = $AgentSettingsTable(this);
  late final $McpToolRulesTable mcpToolRules = $McpToolRulesTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $ProjectPlansTable projectPlans = $ProjectPlansTable(this);
  late final $AutopilotStatesTable autopilotStates = $AutopilotStatesTable(
    this,
  );
  late final $ReviewDraftsTable reviewDrafts = $ReviewDraftsTable(this);
  late final $PendingNoticesTable pendingNotices = $PendingNoticesTable(this);
  late final $ReviewCommentsTable reviewComments = $ReviewCommentsTable(this);
  late final $SpecCriteriaTable specCriteria = $SpecCriteriaTable(this);
  late final $SpecSuggestionsTable specSuggestions = $SpecSuggestionsTable(
    this,
  );
  late final $NotificationsTable notifications = $NotificationsTable(this);
  late final $SpecDuelsTable specDuels = $SpecDuelsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    workspaces,
    specs,
    specSteps,
    tasks,
    sessions,
    sessionEvents,
    conversations,
    conversationEvents,
    savedPrompts,
    agentSettings,
    mcpToolRules,
    appSettings,
    projectPlans,
    autopilotStates,
    reviewDrafts,
    pendingNotices,
    reviewComments,
    specCriteria,
    specSuggestions,
    notifications,
    specDuels,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('specs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('spec_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sessions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sessions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sessions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('session_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversation_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('project_plans', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('autopilot_states', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('pending_notices', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_comments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('spec_criteria', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('spec_suggestions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'specs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('spec_duels', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$WorkspacesTableCreateCompanionBuilder = WorkspacesCompanion Function({
  Value<int> id,
  required String path,
  required String name,
  Value<DateTime> createdAt,
});
typedef $$WorkspacesTableUpdateCompanionBuilder = WorkspacesCompanion Function({
  Value<int> id,
  Value<String> path,
  Value<String> name,
  Value<DateTime> createdAt,
});

final class $$WorkspacesTableReferences
    extends BaseReferences<_$AppDatabase, $WorkspacesTable, Workspace> {
  $$WorkspacesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SpecsTable, List<Spec>> _specsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.specs,
    aliasName: 'workspaces__id__specs__workspace_id',
  );

  $$SpecsTableProcessedTableManager get specsRefs {
    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_specsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TasksTable, List<Task>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: 'workspaces__id__tasks__workspace_id',
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SessionsTable, List<Session>> _sessionsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: 'workspaces__id__sessions__workspace_id',
  );

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ConversationsTable, List<Conversation>>
  _conversationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.conversations,
    aliasName: 'workspaces__id__conversations__workspace_id',
  );

  $$ConversationsTableProcessedTableManager get conversationsRefs {
    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_conversationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProjectPlansTable, List<ProjectPlan>>
  _projectPlansRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.projectPlans,
    aliasName: 'workspaces__id__project_plans__workspace_id',
  );

  $$ProjectPlansTableProcessedTableManager get projectPlansRefs {
    final manager = $$ProjectPlansTableTableManager(
      $_db,
      $_db.projectPlans,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_projectPlansRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AutopilotStatesTable, List<AutopilotState>>
  _autopilotStatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.autopilotStates,
    aliasName: 'workspaces__id__autopilot_states__workspace_id',
  );

  $$AutopilotStatesTableProcessedTableManager get autopilotStatesRefs {
    final manager = $$AutopilotStatesTableTableManager(
      $_db,
      $_db.autopilotStates,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _autopilotStatesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WorkspacesTableFilterComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> specsRefs(
    Expression<bool> Function($$SpecsTableFilterComposer f) f,
  ) {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionsRefs(
    Expression<bool> Function($$SessionsTableFilterComposer f) f,
  ) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> conversationsRefs(
    Expression<bool> Function($$ConversationsTableFilterComposer f) f,
  ) {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> projectPlansRefs(
    Expression<bool> Function($$ProjectPlansTableFilterComposer f) f,
  ) {
    final $$ProjectPlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectPlans,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectPlansTableFilterComposer(
            $db: $db,
            $table: $db.projectPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> autopilotStatesRefs(
    Expression<bool> Function($$AutopilotStatesTableFilterComposer f) f,
  ) {
    final $$AutopilotStatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.autopilotStates,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AutopilotStatesTableFilterComposer(
            $db: $db,
            $table: $db.autopilotStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorkspacesTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> specsRefs<T extends Object>(
    Expression<T> Function($$SpecsTableAnnotationComposer a) f,
  ) {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($$SessionsTableAnnotationComposer a) f,
  ) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> conversationsRefs<T extends Object>(
    Expression<T> Function($$ConversationsTableAnnotationComposer a) f,
  ) {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> projectPlansRefs<T extends Object>(
    Expression<T> Function($$ProjectPlansTableAnnotationComposer a) f,
  ) {
    final $$ProjectPlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectPlans,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectPlansTableAnnotationComposer(
            $db: $db,
            $table: $db.projectPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> autopilotStatesRefs<T extends Object>(
    Expression<T> Function($$AutopilotStatesTableAnnotationComposer a) f,
  ) {
    final $$AutopilotStatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.autopilotStates,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AutopilotStatesTableAnnotationComposer(
            $db: $db,
            $table: $db.autopilotStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorkspacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkspacesTable,
          Workspace,
          $$WorkspacesTableFilterComposer,
          $$WorkspacesTableOrderingComposer,
          $$WorkspacesTableAnnotationComposer,
          $$WorkspacesTableCreateCompanionBuilder,
          $$WorkspacesTableUpdateCompanionBuilder,
          (Workspace, $$WorkspacesTableReferences),
          Workspace,
          PrefetchHooks Function({
            bool specsRefs,
            bool tasksRefs,
            bool sessionsRefs,
            bool conversationsRefs,
            bool projectPlansRefs,
            bool autopilotStatesRefs,
          })
        > {
  $$WorkspacesTableTableManager(_$AppDatabase db, $WorkspacesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkspacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkspacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => WorkspacesCompanion(
                id: id,
                path: path,
                name: name,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String path,
                required String name,
                Value<DateTime> createdAt = const Value.absent(),
              }) => WorkspacesCompanion.insert(
                id: id,
                path: path,
                name: name,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkspacesTable, Workspace>(table),
                  $$WorkspacesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                specsRefs = false,
                tasksRefs = false,
                sessionsRefs = false,
                conversationsRefs = false,
                projectPlansRefs = false,
                autopilotStatesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (specsRefs) db.specs,
                    if (tasksRefs) db.tasks,
                    if (sessionsRefs) db.sessions,
                    if (conversationsRefs) db.conversations,
                    if (projectPlansRefs) db.projectPlans,
                    if (autopilotStatesRefs) db.autopilotStates,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (specsRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Spec
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._specsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).specsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (tasksRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Task
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._tasksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).tasksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sessionsRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Session
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._sessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (conversationsRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Conversation
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._conversationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).conversationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (projectPlansRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          ProjectPlan
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._projectPlansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).projectPlansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (autopilotStatesRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          AutopilotState
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._autopilotStatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).autopilotStatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$WorkspacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkspacesTable,
      Workspace,
      $$WorkspacesTableFilterComposer,
      $$WorkspacesTableOrderingComposer,
      $$WorkspacesTableAnnotationComposer,
      $$WorkspacesTableCreateCompanionBuilder,
      $$WorkspacesTableUpdateCompanionBuilder,
      (Workspace, $$WorkspacesTableReferences),
      Workspace,
      PrefetchHooks Function({
        bool specsRefs,
        bool tasksRefs,
        bool sessionsRefs,
        bool conversationsRefs,
        bool projectPlansRefs,
        bool autopilotStatesRefs,
      })
    >;
typedef $$SpecsTableCreateCompanionBuilder = SpecsCompanion Function({
  Value<int> id,
  required int workspaceId,
  required String code,
  required String title,
  Value<SpecStatus> status,
  required String path,
  Value<SpecStage> stage,
  Value<List<({String id, String text})>> requirements,
  Value<List<String>> dependsOn,
  Value<String?> phase,
  Value<String?> agentName,
  Value<String?> worktreePath,
  Value<String?> branch,
  Value<String?> baseBranch,
  Value<bool> autoAdvance,
  Value<int?> worktreeIndex,
  Value<DateTime?> preparedAt,
  Value<String?> reviewPhase,
  Value<int> reviewRounds,
  Value<String?> mergeOverride,
  Value<int?> boardOrder,
  Value<int> gateResends,
  Value<int> rejectedHunks,
});
typedef $$SpecsTableUpdateCompanionBuilder = SpecsCompanion Function({
  Value<int> id,
  Value<int> workspaceId,
  Value<String> code,
  Value<String> title,
  Value<SpecStatus> status,
  Value<String> path,
  Value<SpecStage> stage,
  Value<List<({String id, String text})>> requirements,
  Value<List<String>> dependsOn,
  Value<String?> phase,
  Value<String?> agentName,
  Value<String?> worktreePath,
  Value<String?> branch,
  Value<String?> baseBranch,
  Value<bool> autoAdvance,
  Value<int?> worktreeIndex,
  Value<DateTime?> preparedAt,
  Value<String?> reviewPhase,
  Value<int> reviewRounds,
  Value<String?> mergeOverride,
  Value<int?> boardOrder,
  Value<int> gateResends,
  Value<int> rejectedHunks,
});

final class $$SpecsTableReferences
    extends BaseReferences<_$AppDatabase, $SpecsTable, Spec> {
  $$SpecsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('specs__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<int>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SpecStepsTable, List<SpecStep>>
  _specStepsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.specSteps,
    aliasName: 'specs__id__spec_steps__spec_id',
  );

  $$SpecStepsTableProcessedTableManager get specStepsRefs {
    final manager = $$SpecStepsTableTableManager(
      $_db,
      $_db.specSteps,
    ).filter((f) => f.specId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_specStepsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TasksTable, List<Task>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: 'specs__id__tasks__spec_id',
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.specId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SessionsTable, List<Session>> _sessionsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: 'specs__id__sessions__spec_id',
  );

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.specId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewCommentsTable, List<ReviewCommentRow>>
  _reviewCommentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewComments,
    aliasName: 'specs__id__review_comments__spec_id',
  );

  $$ReviewCommentsTableProcessedTableManager get reviewCommentsRefs {
    final manager = $$ReviewCommentsTableTableManager(
      $_db,
      $_db.reviewComments,
    ).filter((f) => f.specId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewCommentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SpecCriteriaTable, List<SpecCriteriaData>>
  _specCriteriaRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.specCriteria,
    aliasName: 'specs__id__spec_criteria__spec_id',
  );

  $$SpecCriteriaTableProcessedTableManager get specCriteriaRefs {
    final manager = $$SpecCriteriaTableTableManager(
      $_db,
      $_db.specCriteria,
    ).filter((f) => f.specId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_specCriteriaRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SpecSuggestionsTable, List<SpecSuggestion>>
  _specSuggestionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.specSuggestions,
    aliasName: 'specs__id__spec_suggestions__spec_id',
  );

  $$SpecSuggestionsTableProcessedTableManager get specSuggestionsRefs {
    final manager = $$SpecSuggestionsTableTableManager(
      $_db,
      $_db.specSuggestions,
    ).filter((f) => f.specId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _specSuggestionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SpecDuelsTable, List<SpecDuel>>
  _specDuelsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.specDuels,
    aliasName: 'specs__id__spec_duels__spec_id',
  );

  $$SpecDuelsTableProcessedTableManager get specDuelsRefs {
    final manager = $$SpecDuelsTableTableManager(
      $_db,
      $_db.specDuels,
    ).filter((f) => f.specId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_specDuelsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SpecsTableFilterComposer extends Composer<_$AppDatabase, $SpecsTable> {
  $$SpecsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SpecStatus, SpecStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SpecStage, SpecStage, String> get stage =>
      $composableBuilder(
        column: $table.stage,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<
    List<({String id, String text})>,
    List<({String id, String text})>,
    String
  >
  get requirements => $composableBuilder(
    column: $table.requirements,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get dependsOn => $composableBuilder(
    column: $table.dependsOn,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get worktreePath => $composableBuilder(
    column: $table.worktreePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseBranch => $composableBuilder(
    column: $table.baseBranch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoAdvance => $composableBuilder(
    column: $table.autoAdvance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get worktreeIndex => $composableBuilder(
    column: $table.worktreeIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get preparedAt => $composableBuilder(
    column: $table.preparedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewPhase => $composableBuilder(
    column: $table.reviewPhase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewRounds => $composableBuilder(
    column: $table.reviewRounds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mergeOverride => $composableBuilder(
    column: $table.mergeOverride,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get boardOrder => $composableBuilder(
    column: $table.boardOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gateResends => $composableBuilder(
    column: $table.gateResends,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rejectedHunks => $composableBuilder(
    column: $table.rejectedHunks,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> specStepsRefs(
    Expression<bool> Function($$SpecStepsTableFilterComposer f) f,
  ) {
    final $$SpecStepsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specSteps,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecStepsTableFilterComposer(
            $db: $db,
            $table: $db.specSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionsRefs(
    Expression<bool> Function($$SessionsTableFilterComposer f) f,
  ) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewCommentsRefs(
    Expression<bool> Function($$ReviewCommentsTableFilterComposer f) f,
  ) {
    final $$ReviewCommentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewComments,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewCommentsTableFilterComposer(
            $db: $db,
            $table: $db.reviewComments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> specCriteriaRefs(
    Expression<bool> Function($$SpecCriteriaTableFilterComposer f) f,
  ) {
    final $$SpecCriteriaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specCriteria,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecCriteriaTableFilterComposer(
            $db: $db,
            $table: $db.specCriteria,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> specSuggestionsRefs(
    Expression<bool> Function($$SpecSuggestionsTableFilterComposer f) f,
  ) {
    final $$SpecSuggestionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specSuggestions,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecSuggestionsTableFilterComposer(
            $db: $db,
            $table: $db.specSuggestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> specDuelsRefs(
    Expression<bool> Function($$SpecDuelsTableFilterComposer f) f,
  ) {
    final $$SpecDuelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specDuels,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecDuelsTableFilterComposer(
            $db: $db,
            $table: $db.specDuels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SpecsTableOrderingComposer
    extends Composer<_$AppDatabase, $SpecsTable> {
  $$SpecsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requirements => $composableBuilder(
    column: $table.requirements,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependsOn => $composableBuilder(
    column: $table.dependsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get worktreePath => $composableBuilder(
    column: $table.worktreePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseBranch => $composableBuilder(
    column: $table.baseBranch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoAdvance => $composableBuilder(
    column: $table.autoAdvance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get worktreeIndex => $composableBuilder(
    column: $table.worktreeIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get preparedAt => $composableBuilder(
    column: $table.preparedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewPhase => $composableBuilder(
    column: $table.reviewPhase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewRounds => $composableBuilder(
    column: $table.reviewRounds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mergeOverride => $composableBuilder(
    column: $table.mergeOverride,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get boardOrder => $composableBuilder(
    column: $table.boardOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gateResends => $composableBuilder(
    column: $table.gateResends,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rejectedHunks => $composableBuilder(
    column: $table.rejectedHunks,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpecsTable> {
  $$SpecsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SpecStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SpecStage, String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<({String id, String text})>, String>
  get requirements => $composableBuilder(
    column: $table.requirements,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get dependsOn =>
      $composableBuilder(column: $table.dependsOn, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get worktreePath => $composableBuilder(
    column: $table.worktreePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branch =>
      $composableBuilder(column: $table.branch, builder: (column) => column);

  GeneratedColumn<String> get baseBranch => $composableBuilder(
    column: $table.baseBranch,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoAdvance => $composableBuilder(
    column: $table.autoAdvance,
    builder: (column) => column,
  );

  GeneratedColumn<int> get worktreeIndex => $composableBuilder(
    column: $table.worktreeIndex,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get preparedAt => $composableBuilder(
    column: $table.preparedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewPhase => $composableBuilder(
    column: $table.reviewPhase,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reviewRounds => $composableBuilder(
    column: $table.reviewRounds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mergeOverride => $composableBuilder(
    column: $table.mergeOverride,
    builder: (column) => column,
  );

  GeneratedColumn<int> get boardOrder => $composableBuilder(
    column: $table.boardOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get gateResends => $composableBuilder(
    column: $table.gateResends,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rejectedHunks => $composableBuilder(
    column: $table.rejectedHunks,
    builder: (column) => column,
  );

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> specStepsRefs<T extends Object>(
    Expression<T> Function($$SpecStepsTableAnnotationComposer a) f,
  ) {
    final $$SpecStepsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specSteps,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecStepsTableAnnotationComposer(
            $db: $db,
            $table: $db.specSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($$SessionsTableAnnotationComposer a) f,
  ) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewCommentsRefs<T extends Object>(
    Expression<T> Function($$ReviewCommentsTableAnnotationComposer a) f,
  ) {
    final $$ReviewCommentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewComments,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewCommentsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewComments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> specCriteriaRefs<T extends Object>(
    Expression<T> Function($$SpecCriteriaTableAnnotationComposer a) f,
  ) {
    final $$SpecCriteriaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specCriteria,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecCriteriaTableAnnotationComposer(
            $db: $db,
            $table: $db.specCriteria,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> specSuggestionsRefs<T extends Object>(
    Expression<T> Function($$SpecSuggestionsTableAnnotationComposer a) f,
  ) {
    final $$SpecSuggestionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specSuggestions,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecSuggestionsTableAnnotationComposer(
            $db: $db,
            $table: $db.specSuggestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> specDuelsRefs<T extends Object>(
    Expression<T> Function($$SpecDuelsTableAnnotationComposer a) f,
  ) {
    final $$SpecDuelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.specDuels,
      getReferencedColumn: (t) => t.specId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecDuelsTableAnnotationComposer(
            $db: $db,
            $table: $db.specDuels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SpecsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpecsTable,
          Spec,
          $$SpecsTableFilterComposer,
          $$SpecsTableOrderingComposer,
          $$SpecsTableAnnotationComposer,
          $$SpecsTableCreateCompanionBuilder,
          $$SpecsTableUpdateCompanionBuilder,
          (Spec, $$SpecsTableReferences),
          Spec,
          PrefetchHooks Function({
            bool workspaceId,
            bool specStepsRefs,
            bool tasksRefs,
            bool sessionsRefs,
            bool reviewCommentsRefs,
            bool specCriteriaRefs,
            bool specSuggestionsRefs,
            bool specDuelsRefs,
          })
        > {
  $$SpecsTableTableManager(_$AppDatabase db, $SpecsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpecsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpecsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpecsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> workspaceId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<SpecStatus> status = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<SpecStage> stage = const Value.absent(),
                Value<List<({String id, String text})>> requirements =
                    const Value.absent(),
                Value<List<String>> dependsOn = const Value.absent(),
                Value<String?> phase = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> worktreePath = const Value.absent(),
                Value<String?> branch = const Value.absent(),
                Value<String?> baseBranch = const Value.absent(),
                Value<bool> autoAdvance = const Value.absent(),
                Value<int?> worktreeIndex = const Value.absent(),
                Value<DateTime?> preparedAt = const Value.absent(),
                Value<String?> reviewPhase = const Value.absent(),
                Value<int> reviewRounds = const Value.absent(),
                Value<String?> mergeOverride = const Value.absent(),
                Value<int?> boardOrder = const Value.absent(),
                Value<int> gateResends = const Value.absent(),
                Value<int> rejectedHunks = const Value.absent(),
              }) => SpecsCompanion(
                id: id,
                workspaceId: workspaceId,
                code: code,
                title: title,
                status: status,
                path: path,
                stage: stage,
                requirements: requirements,
                dependsOn: dependsOn,
                phase: phase,
                agentName: agentName,
                worktreePath: worktreePath,
                branch: branch,
                baseBranch: baseBranch,
                autoAdvance: autoAdvance,
                worktreeIndex: worktreeIndex,
                preparedAt: preparedAt,
                reviewPhase: reviewPhase,
                reviewRounds: reviewRounds,
                mergeOverride: mergeOverride,
                boardOrder: boardOrder,
                gateResends: gateResends,
                rejectedHunks: rejectedHunks,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int workspaceId,
                required String code,
                required String title,
                Value<SpecStatus> status = const Value.absent(),
                required String path,
                Value<SpecStage> stage = const Value.absent(),
                Value<List<({String id, String text})>> requirements =
                    const Value.absent(),
                Value<List<String>> dependsOn = const Value.absent(),
                Value<String?> phase = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> worktreePath = const Value.absent(),
                Value<String?> branch = const Value.absent(),
                Value<String?> baseBranch = const Value.absent(),
                Value<bool> autoAdvance = const Value.absent(),
                Value<int?> worktreeIndex = const Value.absent(),
                Value<DateTime?> preparedAt = const Value.absent(),
                Value<String?> reviewPhase = const Value.absent(),
                Value<int> reviewRounds = const Value.absent(),
                Value<String?> mergeOverride = const Value.absent(),
                Value<int?> boardOrder = const Value.absent(),
                Value<int> gateResends = const Value.absent(),
                Value<int> rejectedHunks = const Value.absent(),
              }) => SpecsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                code: code,
                title: title,
                status: status,
                path: path,
                stage: stage,
                requirements: requirements,
                dependsOn: dependsOn,
                phase: phase,
                agentName: agentName,
                worktreePath: worktreePath,
                branch: branch,
                baseBranch: baseBranch,
                autoAdvance: autoAdvance,
                worktreeIndex: worktreeIndex,
                preparedAt: preparedAt,
                reviewPhase: reviewPhase,
                reviewRounds: reviewRounds,
                mergeOverride: mergeOverride,
                boardOrder: boardOrder,
                gateResends: gateResends,
                rejectedHunks: rejectedHunks,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpecsTable, Spec>(table),
                  $$SpecsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                workspaceId = false,
                specStepsRefs = false,
                tasksRefs = false,
                sessionsRefs = false,
                reviewCommentsRefs = false,
                specCriteriaRefs = false,
                specSuggestionsRefs = false,
                specDuelsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (specStepsRefs) db.specSteps,
                    if (tasksRefs) db.tasks,
                    if (sessionsRefs) db.sessions,
                    if (reviewCommentsRefs) db.reviewComments,
                    if (specCriteriaRefs) db.specCriteria,
                    if (specSuggestionsRefs) db.specSuggestions,
                    if (specDuelsRefs) db.specDuels,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.workspaceId,
                            referencedTable: $$SpecsTableReferences
                                ._workspaceIdTable(db),
                            referencedColumn: $$SpecsTableReferences
                                ._workspaceIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (specStepsRefs)
                        await $_getPrefetchedData<Spec, $SpecsTable, SpecStep>(
                          currentTable: table,
                          referencedTable: $$SpecsTableReferences
                              ._specStepsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecsTableReferences(
                                db,
                                table,
                                p0,
                              ).specStepsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (tasksRefs)
                        await $_getPrefetchedData<Spec, $SpecsTable, Task>(
                          currentTable: table,
                          referencedTable: $$SpecsTableReferences
                              ._tasksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecsTableReferences(db, table, p0).tasksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sessionsRefs)
                        await $_getPrefetchedData<Spec, $SpecsTable, Session>(
                          currentTable: table,
                          referencedTable: $$SpecsTableReferences
                              ._sessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewCommentsRefs)
                        await $_getPrefetchedData<
                          Spec,
                          $SpecsTable,
                          ReviewCommentRow
                        >(
                          currentTable: table,
                          referencedTable: $$SpecsTableReferences
                              ._reviewCommentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewCommentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (specCriteriaRefs)
                        await $_getPrefetchedData<
                          Spec,
                          $SpecsTable,
                          SpecCriteriaData
                        >(
                          currentTable: table,
                          referencedTable: $$SpecsTableReferences
                              ._specCriteriaRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecsTableReferences(
                                db,
                                table,
                                p0,
                              ).specCriteriaRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (specSuggestionsRefs)
                        await $_getPrefetchedData<
                          Spec,
                          $SpecsTable,
                          SpecSuggestion
                        >(
                          currentTable: table,
                          referencedTable: $$SpecsTableReferences
                              ._specSuggestionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecsTableReferences(
                                db,
                                table,
                                p0,
                              ).specSuggestionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (specDuelsRefs)
                        await $_getPrefetchedData<Spec, $SpecsTable, SpecDuel>(
                          currentTable: table,
                          referencedTable: $$SpecsTableReferences
                              ._specDuelsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SpecsTableReferences(
                                db,
                                table,
                                p0,
                              ).specDuelsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.specId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SpecsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpecsTable,
      Spec,
      $$SpecsTableFilterComposer,
      $$SpecsTableOrderingComposer,
      $$SpecsTableAnnotationComposer,
      $$SpecsTableCreateCompanionBuilder,
      $$SpecsTableUpdateCompanionBuilder,
      (Spec, $$SpecsTableReferences),
      Spec,
      PrefetchHooks Function({
        bool workspaceId,
        bool specStepsRefs,
        bool tasksRefs,
        bool sessionsRefs,
        bool reviewCommentsRefs,
        bool specCriteriaRefs,
        bool specSuggestionsRefs,
        bool specDuelsRefs,
      })
    >;
typedef $$SpecStepsTableCreateCompanionBuilder = SpecStepsCompanion Function({
  required int specId,
  required String step,
  Value<StepStatus> status,
  Value<String?> sessionId,
  Value<DateTime?> doneAt,
  Value<String?> startSha,
  Value<String?> startStash,
  Value<String?> gateReport,
  Value<int> gateAttempts,
  Value<String?> body,
  Value<int> rowid,
});
typedef $$SpecStepsTableUpdateCompanionBuilder = SpecStepsCompanion Function({
  Value<int> specId,
  Value<String> step,
  Value<StepStatus> status,
  Value<String?> sessionId,
  Value<DateTime?> doneAt,
  Value<String?> startSha,
  Value<String?> startStash,
  Value<String?> gateReport,
  Value<int> gateAttempts,
  Value<String?> body,
  Value<int> rowid,
});

final class $$SpecStepsTableReferences
    extends BaseReferences<_$AppDatabase, $SpecStepsTable, SpecStep> {
  $$SpecStepsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SpecsTable _specIdTable(_$AppDatabase db) =>
      db.specs.createAlias('spec_steps__spec_id__specs__id');

  $$SpecsTableProcessedTableManager get specId {
    final $_column = $_itemColumn<int>('spec_id')!;

    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpecStepsTableFilterComposer
    extends Composer<_$AppDatabase, $SpecStepsTable> {
  $$SpecStepsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<StepStatus, StepStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startSha => $composableBuilder(
    column: $table.startSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startStash => $composableBuilder(
    column: $table.startStash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gateReport => $composableBuilder(
    column: $table.gateReport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gateAttempts => $composableBuilder(
    column: $table.gateAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecsTableFilterComposer get specId {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecStepsTableOrderingComposer
    extends Composer<_$AppDatabase, $SpecStepsTable> {
  $$SpecStepsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startSha => $composableBuilder(
    column: $table.startSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startStash => $composableBuilder(
    column: $table.startStash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gateReport => $composableBuilder(
    column: $table.gateReport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gateAttempts => $composableBuilder(
    column: $table.gateAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecsTableOrderingComposer get specId {
    final $$SpecsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableOrderingComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecStepsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpecStepsTable> {
  $$SpecStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumnWithTypeConverter<StepStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<DateTime> get doneAt =>
      $composableBuilder(column: $table.doneAt, builder: (column) => column);

  GeneratedColumn<String> get startSha =>
      $composableBuilder(column: $table.startSha, builder: (column) => column);

  GeneratedColumn<String> get startStash => $composableBuilder(
    column: $table.startStash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gateReport => $composableBuilder(
    column: $table.gateReport,
    builder: (column) => column,
  );

  GeneratedColumn<int> get gateAttempts => $composableBuilder(
    column: $table.gateAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  $$SpecsTableAnnotationComposer get specId {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecStepsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpecStepsTable,
          SpecStep,
          $$SpecStepsTableFilterComposer,
          $$SpecStepsTableOrderingComposer,
          $$SpecStepsTableAnnotationComposer,
          $$SpecStepsTableCreateCompanionBuilder,
          $$SpecStepsTableUpdateCompanionBuilder,
          (SpecStep, $$SpecStepsTableReferences),
          SpecStep,
          PrefetchHooks Function({bool specId})
        > {
  $$SpecStepsTableTableManager(_$AppDatabase db, $SpecStepsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpecStepsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpecStepsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpecStepsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> specId = const Value.absent(),
                Value<String> step = const Value.absent(),
                Value<StepStatus> status = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<DateTime?> doneAt = const Value.absent(),
                Value<String?> startSha = const Value.absent(),
                Value<String?> startStash = const Value.absent(),
                Value<String?> gateReport = const Value.absent(),
                Value<int> gateAttempts = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecStepsCompanion(
                specId: specId,
                step: step,
                status: status,
                sessionId: sessionId,
                doneAt: doneAt,
                startSha: startSha,
                startStash: startStash,
                gateReport: gateReport,
                gateAttempts: gateAttempts,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int specId,
                required String step,
                Value<StepStatus> status = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<DateTime?> doneAt = const Value.absent(),
                Value<String?> startSha = const Value.absent(),
                Value<String?> startStash = const Value.absent(),
                Value<String?> gateReport = const Value.absent(),
                Value<int> gateAttempts = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecStepsCompanion.insert(
                specId: specId,
                step: step,
                status: status,
                sessionId: sessionId,
                doneAt: doneAt,
                startSha: startSha,
                startStash: startStash,
                gateReport: gateReport,
                gateAttempts: gateAttempts,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpecStepsTable, SpecStep>(table),
                  $$SpecStepsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({specId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (specId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.specId,
                        referencedTable: $$SpecStepsTableReferences
                            ._specIdTable(db),
                        referencedColumn: $$SpecStepsTableReferences
                            ._specIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SpecStepsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpecStepsTable,
      SpecStep,
      $$SpecStepsTableFilterComposer,
      $$SpecStepsTableOrderingComposer,
      $$SpecStepsTableAnnotationComposer,
      $$SpecStepsTableCreateCompanionBuilder,
      $$SpecStepsTableUpdateCompanionBuilder,
      (SpecStep, $$SpecStepsTableReferences),
      SpecStep,
      PrefetchHooks Function({bool specId})
    >;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  Value<int> id,
  Value<int?> specId,
  required int workspaceId,
  required String code,
  required String title,
  Value<TaskStatus> status,
  Value<String?> agentName,
  Value<String?> body,
  Value<String?> requirement,
  Value<List<String>> dependsOn,
  Value<DateTime> createdAt,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<int> id,
  Value<int?> specId,
  Value<int> workspaceId,
  Value<String> code,
  Value<String> title,
  Value<TaskStatus> status,
  Value<String?> agentName,
  Value<String?> body,
  Value<String?> requirement,
  Value<List<String>> dependsOn,
  Value<DateTime> createdAt,
});

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, Task> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SpecsTable _specIdTable(_$AppDatabase db) =>
      db.specs.createAlias('tasks__spec_id__specs__id');

  $$SpecsTableProcessedTableManager? get specId {
    final $_column = $_itemColumn<int>('spec_id');
    if ($_column == null) return null;
    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('tasks__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<int>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SessionsTable, List<Session>> _sessionsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: 'tasks__id__sessions__task_id',
  );

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TaskStatus, TaskStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requirement => $composableBuilder(
    column: $table.requirement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get dependsOn => $composableBuilder(
    column: $table.dependsOn,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecsTableFilterComposer get specId {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> sessionsRefs(
    Expression<bool> Function($$SessionsTableFilterComposer f) f,
  ) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requirement => $composableBuilder(
    column: $table.requirement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependsOn => $composableBuilder(
    column: $table.dependsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecsTableOrderingComposer get specId {
    final $$SpecsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableOrderingComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TaskStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get requirement => $composableBuilder(
    column: $table.requirement,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get dependsOn =>
      $composableBuilder(column: $table.dependsOn, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SpecsTableAnnotationComposer get specId {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($$SessionsTableAnnotationComposer a) f,
  ) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          Task,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (Task, $$TasksTableReferences),
          Task,
          PrefetchHooks Function({
            bool specId,
            bool workspaceId,
            bool sessionsRefs,
          })
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> specId = const Value.absent(),
                Value<int> workspaceId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<TaskStatus> status = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> requirement = const Value.absent(),
                Value<List<String>> dependsOn = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                specId: specId,
                workspaceId: workspaceId,
                code: code,
                title: title,
                status: status,
                agentName: agentName,
                body: body,
                requirement: requirement,
                dependsOn: dependsOn,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> specId = const Value.absent(),
                required int workspaceId,
                required String code,
                required String title,
                Value<TaskStatus> status = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> requirement = const Value.absent(),
                Value<List<String>> dependsOn = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                specId: specId,
                workspaceId: workspaceId,
                code: code,
                title: title,
                status: status,
                agentName: agentName,
                body: body,
                requirement: requirement,
                dependsOn: dependsOn,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, Task>(table),
                  $$TasksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({specId = false, workspaceId = false, sessionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (sessionsRefs) db.sessions],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (specId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.specId,
                            referencedTable: $$TasksTableReferences
                                ._specIdTable(db),
                            referencedColumn: $$TasksTableReferences
                                ._specIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (workspaceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.workspaceId,
                            referencedTable: $$TasksTableReferences
                                ._workspaceIdTable(db),
                            referencedColumn: $$TasksTableReferences
                                ._workspaceIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionsRefs)
                        await $_getPrefetchedData<Task, $TasksTable, Session>(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._sessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      Task,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (Task, $$TasksTableReferences),
      Task,
      PrefetchHooks Function({bool specId, bool workspaceId, bool sessionsRefs})
    >;
typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  Value<String> provider,
  Value<String?> externalId,
  Value<String?> runConfig,
  required String id,
  required int workspaceId,
  Value<int?> taskId,
  Value<String?> agentName,
  Value<String?> title,
  Value<String?> permissionMode,
  required String worktreePath,
  required String branch,
  Value<SessionStatus> status,
  required String model,
  Value<int?> specId,
  Value<String?> steps,
  Value<String?> effort,
  Value<double> costUsd,
  Value<int> tokensIn,
  Value<int> tokensOut,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<String?> baseBranch,
  Value<String?> mergeCommit,
  Value<String?> prUrl,
  Value<int?> pid,
  Value<int?> duelId,
  Value<int> rowid,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> provider,
  Value<String?> externalId,
  Value<String?> runConfig,
  Value<String> id,
  Value<int> workspaceId,
  Value<int?> taskId,
  Value<String?> agentName,
  Value<String?> title,
  Value<String?> permissionMode,
  Value<String> worktreePath,
  Value<String> branch,
  Value<SessionStatus> status,
  Value<String> model,
  Value<int?> specId,
  Value<String?> steps,
  Value<String?> effort,
  Value<double> costUsd,
  Value<int> tokensIn,
  Value<int> tokensOut,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<String?> baseBranch,
  Value<String?> mergeCommit,
  Value<String?> prUrl,
  Value<int?> pid,
  Value<int?> duelId,
  Value<int> rowid,
});

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('sessions__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<int>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _taskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias('sessions__task_id__tasks__id');

  $$TasksTableProcessedTableManager? get taskId {
    final $_column = $_itemColumn<int>('task_id');
    if ($_column == null) return null;
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SpecsTable _specIdTable(_$AppDatabase db) =>
      db.specs.createAlias('sessions__spec_id__specs__id');

  $$SpecsTableProcessedTableManager? get specId {
    final $_column = $_itemColumn<int>('spec_id');
    if ($_column == null) return null;
    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SessionEventsTable, List<SessionEvent>>
  _sessionEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sessionEvents,
    aliasName: 'sessions__id__session_events__session_id',
  );

  $$SessionEventsTableProcessedTableManager get sessionEventsRefs {
    final manager = $$SessionEventsTableTableManager(
      $_db,
      $_db.sessionEvents,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ConversationsTable, List<Conversation>>
  _conversationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.conversations,
    aliasName: 'sessions__id__conversations__session_id',
  );

  $$ConversationsTableProcessedTableManager get conversationsRefs {
    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_conversationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PendingNoticesTable, List<PendingNotice>>
  _pendingNoticesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.pendingNotices,
    aliasName: 'sessions__id__pending_notices__session_id',
  );

  $$PendingNoticesTableProcessedTableManager get pendingNoticesRefs {
    final manager = $$PendingNoticesTableTableManager(
      $_db,
      $_db.pendingNotices,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_pendingNoticesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runConfig => $composableBuilder(
    column: $table.runConfig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get permissionMode => $composableBuilder(
    column: $table.permissionMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get worktreePath => $composableBuilder(
    column: $table.worktreePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SessionStatus, SessionStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effort => $composableBuilder(
    column: $table.effort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokensIn => $composableBuilder(
    column: $table.tokensIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokensOut => $composableBuilder(
    column: $table.tokensOut,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseBranch => $composableBuilder(
    column: $table.baseBranch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mergeCommit => $composableBuilder(
    column: $table.mergeCommit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prUrl => $composableBuilder(
    column: $table.prUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duelId => $composableBuilder(
    column: $table.duelId,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecsTableFilterComposer get specId {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> sessionEventsRefs(
    Expression<bool> Function($$SessionEventsTableFilterComposer f) f,
  ) {
    final $$SessionEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionEvents,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionEventsTableFilterComposer(
            $db: $db,
            $table: $db.sessionEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> conversationsRefs(
    Expression<bool> Function($$ConversationsTableFilterComposer f) f,
  ) {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> pendingNoticesRefs(
    Expression<bool> Function($$PendingNoticesTableFilterComposer f) f,
  ) {
    final $$PendingNoticesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pendingNotices,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PendingNoticesTableFilterComposer(
            $db: $db,
            $table: $db.pendingNotices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runConfig => $composableBuilder(
    column: $table.runConfig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get permissionMode => $composableBuilder(
    column: $table.permissionMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get worktreePath => $composableBuilder(
    column: $table.worktreePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effort => $composableBuilder(
    column: $table.effort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokensIn => $composableBuilder(
    column: $table.tokensIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokensOut => $composableBuilder(
    column: $table.tokensOut,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseBranch => $composableBuilder(
    column: $table.baseBranch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mergeCommit => $composableBuilder(
    column: $table.mergeCommit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prUrl => $composableBuilder(
    column: $table.prUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duelId => $composableBuilder(
    column: $table.duelId,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecsTableOrderingComposer get specId {
    final $$SpecsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableOrderingComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get runConfig =>
      $composableBuilder(column: $table.runConfig, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get permissionMode => $composableBuilder(
    column: $table.permissionMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get worktreePath => $composableBuilder(
    column: $table.worktreePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branch =>
      $composableBuilder(column: $table.branch, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SessionStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get steps =>
      $composableBuilder(column: $table.steps, builder: (column) => column);

  GeneratedColumn<String> get effort =>
      $composableBuilder(column: $table.effort, builder: (column) => column);

  GeneratedColumn<double> get costUsd =>
      $composableBuilder(column: $table.costUsd, builder: (column) => column);

  GeneratedColumn<int> get tokensIn =>
      $composableBuilder(column: $table.tokensIn, builder: (column) => column);

  GeneratedColumn<int> get tokensOut =>
      $composableBuilder(column: $table.tokensOut, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get baseBranch => $composableBuilder(
    column: $table.baseBranch,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mergeCommit => $composableBuilder(
    column: $table.mergeCommit,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prUrl =>
      $composableBuilder(column: $table.prUrl, builder: (column) => column);

  GeneratedColumn<int> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get duelId =>
      $composableBuilder(column: $table.duelId, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SpecsTableAnnotationComposer get specId {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> sessionEventsRefs<T extends Object>(
    Expression<T> Function($$SessionEventsTableAnnotationComposer a) f,
  ) {
    final $$SessionEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionEvents,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> conversationsRefs<T extends Object>(
    Expression<T> Function($$ConversationsTableAnnotationComposer a) f,
  ) {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> pendingNoticesRefs<T extends Object>(
    Expression<T> Function($$PendingNoticesTableAnnotationComposer a) f,
  ) {
    final $$PendingNoticesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pendingNotices,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PendingNoticesTableAnnotationComposer(
            $db: $db,
            $table: $db.pendingNotices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({
            bool workspaceId,
            bool taskId,
            bool specId,
            bool sessionEventsRefs,
            bool conversationsRefs,
            bool pendingNoticesRefs,
          })
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> provider = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<String?> runConfig = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> workspaceId = const Value.absent(),
                Value<int?> taskId = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> permissionMode = const Value.absent(),
                Value<String> worktreePath = const Value.absent(),
                Value<String> branch = const Value.absent(),
                Value<SessionStatus> status = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int?> specId = const Value.absent(),
                Value<String?> steps = const Value.absent(),
                Value<String?> effort = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<int> tokensIn = const Value.absent(),
                Value<int> tokensOut = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<String?> baseBranch = const Value.absent(),
                Value<String?> mergeCommit = const Value.absent(),
                Value<String?> prUrl = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<int?> duelId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                provider: provider,
                externalId: externalId,
                runConfig: runConfig,
                id: id,
                workspaceId: workspaceId,
                taskId: taskId,
                agentName: agentName,
                title: title,
                permissionMode: permissionMode,
                worktreePath: worktreePath,
                branch: branch,
                status: status,
                model: model,
                specId: specId,
                steps: steps,
                effort: effort,
                costUsd: costUsd,
                tokensIn: tokensIn,
                tokensOut: tokensOut,
                startedAt: startedAt,
                endedAt: endedAt,
                baseBranch: baseBranch,
                mergeCommit: mergeCommit,
                prUrl: prUrl,
                pid: pid,
                duelId: duelId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> provider = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<String?> runConfig = const Value.absent(),
                required String id,
                required int workspaceId,
                Value<int?> taskId = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> permissionMode = const Value.absent(),
                required String worktreePath,
                required String branch,
                Value<SessionStatus> status = const Value.absent(),
                required String model,
                Value<int?> specId = const Value.absent(),
                Value<String?> steps = const Value.absent(),
                Value<String?> effort = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<int> tokensIn = const Value.absent(),
                Value<int> tokensOut = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<String?> baseBranch = const Value.absent(),
                Value<String?> mergeCommit = const Value.absent(),
                Value<String?> prUrl = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<int?> duelId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                provider: provider,
                externalId: externalId,
                runConfig: runConfig,
                id: id,
                workspaceId: workspaceId,
                taskId: taskId,
                agentName: agentName,
                title: title,
                permissionMode: permissionMode,
                worktreePath: worktreePath,
                branch: branch,
                status: status,
                model: model,
                specId: specId,
                steps: steps,
                effort: effort,
                costUsd: costUsd,
                tokensIn: tokensIn,
                tokensOut: tokensOut,
                startedAt: startedAt,
                endedAt: endedAt,
                baseBranch: baseBranch,
                mergeCommit: mergeCommit,
                prUrl: prUrl,
                pid: pid,
                duelId: duelId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, Session>(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                workspaceId = false,
                taskId = false,
                specId = false,
                sessionEventsRefs = false,
                conversationsRefs = false,
                pendingNoticesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sessionEventsRefs) db.sessionEvents,
                    if (conversationsRefs) db.conversations,
                    if (pendingNoticesRefs) db.pendingNotices,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.workspaceId,
                            referencedTable: $$SessionsTableReferences
                                ._workspaceIdTable(db),
                            referencedColumn: $$SessionsTableReferences
                                ._workspaceIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (taskId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.taskId,
                            referencedTable: $$SessionsTableReferences
                                ._taskIdTable(db),
                            referencedColumn: $$SessionsTableReferences
                                ._taskIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (specId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.specId,
                            referencedTable: $$SessionsTableReferences
                                ._specIdTable(db),
                            referencedColumn: $$SessionsTableReferences
                                ._specIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionEventsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          SessionEvent
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._sessionEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (conversationsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          Conversation
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._conversationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).conversationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (pendingNoticesRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          PendingNotice
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._pendingNoticesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).pendingNoticesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({
        bool workspaceId,
        bool taskId,
        bool specId,
        bool sessionEventsRefs,
        bool conversationsRefs,
        bool pendingNoticesRefs,
      })
    >;
typedef $$SessionEventsTableCreateCompanionBuilder =
    SessionEventsCompanion Function({
      Value<int> id,
      required String sessionId,
      required int seq,
      required String type,
      required String json,
      Value<DateTime> createdAt,
    });
typedef $$SessionEventsTableUpdateCompanionBuilder =
    SessionEventsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<int> seq,
      Value<String> type,
      Value<String> json,
      Value<DateTime> createdAt,
    });

final class $$SessionEventsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionEventsTable, SessionEvent> {
  $$SessionEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias('session_events__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionEventsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionEventsTable,
          SessionEvent,
          $$SessionEventsTableFilterComposer,
          $$SessionEventsTableOrderingComposer,
          $$SessionEventsTableAnnotationComposer,
          $$SessionEventsTableCreateCompanionBuilder,
          $$SessionEventsTableUpdateCompanionBuilder,
          (SessionEvent, $$SessionEventsTableReferences),
          SessionEvent,
          PrefetchHooks Function({bool sessionId})
        > {
  $$SessionEventsTableTableManager(_$AppDatabase db, $SessionEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SessionEventsCompanion(
                id: id,
                sessionId: sessionId,
                seq: seq,
                type: type,
                json: json,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required int seq,
                required String type,
                required String json,
                Value<DateTime> createdAt = const Value.absent(),
              }) => SessionEventsCompanion.insert(
                id: id,
                sessionId: sessionId,
                seq: seq,
                type: type,
                json: json,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionEventsTable, SessionEvent>(table),
                  $$SessionEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$SessionEventsTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$SessionEventsTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SessionEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionEventsTable,
      SessionEvent,
      $$SessionEventsTableFilterComposer,
      $$SessionEventsTableOrderingComposer,
      $$SessionEventsTableAnnotationComposer,
      $$SessionEventsTableCreateCompanionBuilder,
      $$SessionEventsTableUpdateCompanionBuilder,
      (SessionEvent, $$SessionEventsTableReferences),
      SessionEvent,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String?> runConfig,
      Value<int> id,
      required int workspaceId,
      required String title,
      Value<String> provider,
      required String model,
      Value<String?> sessionId,
      Value<DateTime> createdAt,
      Value<String?> claudeSessionId,
      Value<String> mode,
      Value<int> tokensIn,
      Value<int> tokensOut,
      Value<double> costUsd,
      Value<int> messageCount,
      Value<DateTime?> updatedAt,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String?> runConfig,
      Value<int> id,
      Value<int> workspaceId,
      Value<String> title,
      Value<String> provider,
      Value<String> model,
      Value<String?> sessionId,
      Value<DateTime> createdAt,
      Value<String?> claudeSessionId,
      Value<String> mode,
      Value<int> tokensIn,
      Value<int> tokensOut,
      Value<double> costUsd,
      Value<int> messageCount,
      Value<DateTime?> updatedAt,
    });

final class $$ConversationsTableReferences
    extends BaseReferences<_$AppDatabase, $ConversationsTable, Conversation> {
  $$ConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('conversations__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<int>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias('conversations__session_id__sessions__id');

  $$SessionsTableProcessedTableManager? get sessionId {
    final $_column = $_itemColumn<String>('session_id');
    if ($_column == null) return null;
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ConversationEventsTable, List<ConversationEvent>>
  _conversationEventsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.conversationEvents,
        aliasName: 'conversations__id__conversation_events__conversation_id',
      );

  $$ConversationEventsTableProcessedTableManager get conversationEventsRefs {
    final manager = $$ConversationEventsTableTableManager(
      $_db,
      $_db.conversationEvents,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _conversationEventsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get runConfig => $composableBuilder(
    column: $table.runConfig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get claudeSessionId => $composableBuilder(
    column: $table.claudeSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokensIn => $composableBuilder(
    column: $table.tokensIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokensOut => $composableBuilder(
    column: $table.tokensOut,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> conversationEventsRefs(
    Expression<bool> Function($$ConversationEventsTableFilterComposer f) f,
  ) {
    final $$ConversationEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversationEvents,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationEventsTableFilterComposer(
            $db: $db,
            $table: $db.conversationEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get runConfig => $composableBuilder(
    column: $table.runConfig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get claudeSessionId => $composableBuilder(
    column: $table.claudeSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokensIn => $composableBuilder(
    column: $table.tokensIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokensOut => $composableBuilder(
    column: $table.tokensOut,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get runConfig =>
      $composableBuilder(column: $table.runConfig, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get claudeSessionId => $composableBuilder(
    column: $table.claudeSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get tokensIn =>
      $composableBuilder(column: $table.tokensIn, builder: (column) => column);

  GeneratedColumn<int> get tokensOut =>
      $composableBuilder(column: $table.tokensOut, builder: (column) => column);

  GeneratedColumn<double> get costUsd =>
      $composableBuilder(column: $table.costUsd, builder: (column) => column);

  GeneratedColumn<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> conversationEventsRefs<T extends Object>(
    Expression<T> Function($$ConversationEventsTableAnnotationComposer a) f,
  ) {
    final $$ConversationEventsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.conversationEvents,
          getReferencedColumn: (t) => t.conversationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ConversationEventsTableAnnotationComposer(
                $db: $db,
                $table: $db.conversationEvents,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (Conversation, $$ConversationsTableReferences),
          Conversation,
          PrefetchHooks Function({
            bool workspaceId,
            bool sessionId,
            bool conversationEventsRefs,
          })
        > {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String?> runConfig = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<int> workspaceId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> claudeSessionId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> tokensIn = const Value.absent(),
                Value<int> tokensOut = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
              }) => ConversationsCompanion(
                runConfig: runConfig,
                id: id,
                workspaceId: workspaceId,
                title: title,
                provider: provider,
                model: model,
                sessionId: sessionId,
                createdAt: createdAt,
                claudeSessionId: claudeSessionId,
                mode: mode,
                tokensIn: tokensIn,
                tokensOut: tokensOut,
                costUsd: costUsd,
                messageCount: messageCount,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<String?> runConfig = const Value.absent(),
                Value<int> id = const Value.absent(),
                required int workspaceId,
                required String title,
                Value<String> provider = const Value.absent(),
                required String model,
                Value<String?> sessionId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> claudeSessionId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> tokensIn = const Value.absent(),
                Value<int> tokensOut = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
              }) => ConversationsCompanion.insert(
                runConfig: runConfig,
                id: id,
                workspaceId: workspaceId,
                title: title,
                provider: provider,
                model: model,
                sessionId: sessionId,
                createdAt: createdAt,
                claudeSessionId: claudeSessionId,
                mode: mode,
                tokensIn: tokensIn,
                tokensOut: tokensOut,
                costUsd: costUsd,
                messageCount: messageCount,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConversationsTable, Conversation>(table),
                  $$ConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                workspaceId = false,
                sessionId = false,
                conversationEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (conversationEventsRefs) db.conversationEvents,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.workspaceId,
                            referencedTable: $$ConversationsTableReferences
                                ._workspaceIdTable(db),
                            referencedColumn: $$ConversationsTableReferences
                                ._workspaceIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (sessionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.sessionId,
                            referencedTable: $$ConversationsTableReferences
                                ._sessionIdTable(db),
                            referencedColumn: $$ConversationsTableReferences
                                ._sessionIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (conversationEventsRefs)
                        await $_getPrefetchedData<
                          Conversation,
                          $ConversationsTable,
                          ConversationEvent
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._conversationEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).conversationEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (Conversation, $$ConversationsTableReferences),
      Conversation,
      PrefetchHooks Function({
        bool workspaceId,
        bool sessionId,
        bool conversationEventsRefs,
      })
    >;
typedef $$ConversationEventsTableCreateCompanionBuilder =
    ConversationEventsCompanion Function({
      Value<int> id,
      required int conversationId,
      required int seq,
      required String type,
      required String json,
      Value<DateTime> createdAt,
    });
typedef $$ConversationEventsTableUpdateCompanionBuilder =
    ConversationEventsCompanion Function({
      Value<int> id,
      Value<int> conversationId,
      Value<int> seq,
      Value<String> type,
      Value<String> json,
      Value<DateTime> createdAt,
    });

final class $$ConversationEventsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ConversationEventsTable,
          ConversationEvent
        > {
  $$ConversationEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ConversationsTable _conversationIdTable(_$AppDatabase db) => db
      .conversations
      .createAlias('conversation_events__conversation_id__conversations__id');

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<int>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ConversationEventsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationEventsTable> {
  $$ConversationEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationEventsTable> {
  $$ConversationEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationEventsTable> {
  $$ConversationEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationEventsTable,
          ConversationEvent,
          $$ConversationEventsTableFilterComposer,
          $$ConversationEventsTableOrderingComposer,
          $$ConversationEventsTableAnnotationComposer,
          $$ConversationEventsTableCreateCompanionBuilder,
          $$ConversationEventsTableUpdateCompanionBuilder,
          (ConversationEvent, $$ConversationEventsTableReferences),
          ConversationEvent,
          PrefetchHooks Function({bool conversationId})
        > {
  $$ConversationEventsTableTableManager(
    _$AppDatabase db,
    $ConversationEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> conversationId = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ConversationEventsCompanion(
                id: id,
                conversationId: conversationId,
                seq: seq,
                type: type,
                json: json,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int conversationId,
                required int seq,
                required String type,
                required String json,
                Value<DateTime> createdAt = const Value.absent(),
              }) => ConversationEventsCompanion.insert(
                id: id,
                conversationId: conversationId,
                seq: seq,
                type: type,
                json: json,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConversationEventsTable, ConversationEvent>(
                    table,
                  ),
                  $$ConversationEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.conversationId,
                        referencedTable: $$ConversationEventsTableReferences
                            ._conversationIdTable(db),
                        referencedColumn: $$ConversationEventsTableReferences
                            ._conversationIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ConversationEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationEventsTable,
      ConversationEvent,
      $$ConversationEventsTableFilterComposer,
      $$ConversationEventsTableOrderingComposer,
      $$ConversationEventsTableAnnotationComposer,
      $$ConversationEventsTableCreateCompanionBuilder,
      $$ConversationEventsTableUpdateCompanionBuilder,
      (ConversationEvent, $$ConversationEventsTableReferences),
      ConversationEvent,
      PrefetchHooks Function({bool conversationId})
    >;
typedef $$SavedPromptsTableCreateCompanionBuilder =
    SavedPromptsCompanion Function({
      Value<int> id,
      required String command,
      Value<String> description,
      required String body,
      Value<int> uses,
    });
typedef $$SavedPromptsTableUpdateCompanionBuilder =
    SavedPromptsCompanion Function({
      Value<int> id,
      Value<String> command,
      Value<String> description,
      Value<String> body,
      Value<int> uses,
    });

class $$SavedPromptsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedPromptsTable> {
  $$SavedPromptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uses => $composableBuilder(
    column: $table.uses,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedPromptsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedPromptsTable> {
  $$SavedPromptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uses => $composableBuilder(
    column: $table.uses,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedPromptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedPromptsTable> {
  $$SavedPromptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get uses =>
      $composableBuilder(column: $table.uses, builder: (column) => column);
}

class $$SavedPromptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedPromptsTable,
          SavedPrompt,
          $$SavedPromptsTableFilterComposer,
          $$SavedPromptsTableOrderingComposer,
          $$SavedPromptsTableAnnotationComposer,
          $$SavedPromptsTableCreateCompanionBuilder,
          $$SavedPromptsTableUpdateCompanionBuilder,
          (
            SavedPrompt,
            BaseReferences<_$AppDatabase, $SavedPromptsTable, SavedPrompt>,
          ),
          SavedPrompt,
          PrefetchHooks Function()
        > {
  $$SavedPromptsTableTableManager(_$AppDatabase db, $SavedPromptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedPromptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedPromptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedPromptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> command = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> uses = const Value.absent(),
              }) => SavedPromptsCompanion(
                id: id,
                command: command,
                description: description,
                body: body,
                uses: uses,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String command,
                Value<String> description = const Value.absent(),
                required String body,
                Value<int> uses = const Value.absent(),
              }) => SavedPromptsCompanion.insert(
                id: id,
                command: command,
                description: description,
                body: body,
                uses: uses,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavedPromptsTable, SavedPrompt>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SavedPromptsTable,
                    SavedPrompt
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedPromptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedPromptsTable,
      SavedPrompt,
      $$SavedPromptsTableFilterComposer,
      $$SavedPromptsTableOrderingComposer,
      $$SavedPromptsTableAnnotationComposer,
      $$SavedPromptsTableCreateCompanionBuilder,
      $$SavedPromptsTableUpdateCompanionBuilder,
      (
        SavedPrompt,
        BaseReferences<_$AppDatabase, $SavedPromptsTable, SavedPrompt>,
      ),
      SavedPrompt,
      PrefetchHooks Function()
    >;
typedef $$AgentSettingsTableCreateCompanionBuilder =
    AgentSettingsCompanion Function({
      required String agentName,
      required AgentScope scope,
      Value<String?> permissionMode,
      Value<double?> budgetUsd,
      Value<int?> maxTurns,
      Value<List<String>> mcpServers,
      Value<int> rowid,
    });
typedef $$AgentSettingsTableUpdateCompanionBuilder =
    AgentSettingsCompanion Function({
      Value<String> agentName,
      Value<AgentScope> scope,
      Value<String?> permissionMode,
      Value<double?> budgetUsd,
      Value<int?> maxTurns,
      Value<List<String>> mcpServers,
      Value<int> rowid,
    });

class $$AgentSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AgentSettingsTable> {
  $$AgentSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AgentScope, AgentScope, String> get scope =>
      $composableBuilder(
        column: $table.scope,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get permissionMode => $composableBuilder(
    column: $table.permissionMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get budgetUsd => $composableBuilder(
    column: $table.budgetUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxTurns => $composableBuilder(
    column: $table.maxTurns,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get mcpServers => $composableBuilder(
    column: $table.mcpServers,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$AgentSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentSettingsTable> {
  $$AgentSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get permissionMode => $composableBuilder(
    column: $table.permissionMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get budgetUsd => $composableBuilder(
    column: $table.budgetUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxTurns => $composableBuilder(
    column: $table.maxTurns,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mcpServers => $composableBuilder(
    column: $table.mcpServers,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentSettingsTable> {
  $$AgentSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AgentScope, String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get permissionMode => $composableBuilder(
    column: $table.permissionMode,
    builder: (column) => column,
  );

  GeneratedColumn<double> get budgetUsd =>
      $composableBuilder(column: $table.budgetUsd, builder: (column) => column);

  GeneratedColumn<int> get maxTurns =>
      $composableBuilder(column: $table.maxTurns, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get mcpServers =>
      $composableBuilder(
        column: $table.mcpServers,
        builder: (column) => column,
      );
}

class $$AgentSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentSettingsTable,
          AgentSetting,
          $$AgentSettingsTableFilterComposer,
          $$AgentSettingsTableOrderingComposer,
          $$AgentSettingsTableAnnotationComposer,
          $$AgentSettingsTableCreateCompanionBuilder,
          $$AgentSettingsTableUpdateCompanionBuilder,
          (
            AgentSetting,
            BaseReferences<_$AppDatabase, $AgentSettingsTable, AgentSetting>,
          ),
          AgentSetting,
          PrefetchHooks Function()
        > {
  $$AgentSettingsTableTableManager(_$AppDatabase db, $AgentSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AgentSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> agentName = const Value.absent(),
                Value<AgentScope> scope = const Value.absent(),
                Value<String?> permissionMode = const Value.absent(),
                Value<double?> budgetUsd = const Value.absent(),
                Value<int?> maxTurns = const Value.absent(),
                Value<List<String>> mcpServers = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentSettingsCompanion(
                agentName: agentName,
                scope: scope,
                permissionMode: permissionMode,
                budgetUsd: budgetUsd,
                maxTurns: maxTurns,
                mcpServers: mcpServers,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String agentName,
                required AgentScope scope,
                Value<String?> permissionMode = const Value.absent(),
                Value<double?> budgetUsd = const Value.absent(),
                Value<int?> maxTurns = const Value.absent(),
                Value<List<String>> mcpServers = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentSettingsCompanion.insert(
                agentName: agentName,
                scope: scope,
                permissionMode: permissionMode,
                budgetUsd: budgetUsd,
                maxTurns: maxTurns,
                mcpServers: mcpServers,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AgentSettingsTable, AgentSetting>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AgentSettingsTable,
                    AgentSetting
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentSettingsTable,
      AgentSetting,
      $$AgentSettingsTableFilterComposer,
      $$AgentSettingsTableOrderingComposer,
      $$AgentSettingsTableAnnotationComposer,
      $$AgentSettingsTableCreateCompanionBuilder,
      $$AgentSettingsTableUpdateCompanionBuilder,
      (
        AgentSetting,
        BaseReferences<_$AppDatabase, $AgentSettingsTable, AgentSetting>,
      ),
      AgentSetting,
      PrefetchHooks Function()
    >;
typedef $$McpToolRulesTableCreateCompanionBuilder =
    McpToolRulesCompanion Function({
      required String server,
      required String tool,
      required McpRule rule,
      Value<int> rowid,
    });
typedef $$McpToolRulesTableUpdateCompanionBuilder =
    McpToolRulesCompanion Function({
      Value<String> server,
      Value<String> tool,
      Value<McpRule> rule,
      Value<int> rowid,
    });

class $$McpToolRulesTableFilterComposer
    extends Composer<_$AppDatabase, $McpToolRulesTable> {
  $$McpToolRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<McpRule, McpRule, String> get rule =>
      $composableBuilder(
        column: $table.rule,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$McpToolRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $McpToolRulesTable> {
  $$McpToolRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rule => $composableBuilder(
    column: $table.rule,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$McpToolRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpToolRulesTable> {
  $$McpToolRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get server =>
      $composableBuilder(column: $table.server, builder: (column) => column);

  GeneratedColumn<String> get tool =>
      $composableBuilder(column: $table.tool, builder: (column) => column);

  GeneratedColumnWithTypeConverter<McpRule, String> get rule =>
      $composableBuilder(column: $table.rule, builder: (column) => column);
}

class $$McpToolRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $McpToolRulesTable,
          McpToolRule,
          $$McpToolRulesTableFilterComposer,
          $$McpToolRulesTableOrderingComposer,
          $$McpToolRulesTableAnnotationComposer,
          $$McpToolRulesTableCreateCompanionBuilder,
          $$McpToolRulesTableUpdateCompanionBuilder,
          (
            McpToolRule,
            BaseReferences<_$AppDatabase, $McpToolRulesTable, McpToolRule>,
          ),
          McpToolRule,
          PrefetchHooks Function()
        > {
  $$McpToolRulesTableTableManager(_$AppDatabase db, $McpToolRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpToolRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpToolRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpToolRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> server = const Value.absent(),
                Value<String> tool = const Value.absent(),
                Value<McpRule> rule = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpToolRulesCompanion(
                server: server,
                tool: tool,
                rule: rule,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String server,
                required String tool,
                required McpRule rule,
                Value<int> rowid = const Value.absent(),
              }) => McpToolRulesCompanion.insert(
                server: server,
                tool: tool,
                rule: rule,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$McpToolRulesTable, McpToolRule>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $McpToolRulesTable,
                    McpToolRule
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$McpToolRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $McpToolRulesTable,
      McpToolRule,
      $$McpToolRulesTableFilterComposer,
      $$McpToolRulesTableOrderingComposer,
      $$McpToolRulesTableAnnotationComposer,
      $$McpToolRulesTableCreateCompanionBuilder,
      $$McpToolRulesTableUpdateCompanionBuilder,
      (
        McpToolRule,
        BaseReferences<_$AppDatabase, $McpToolRulesTable, McpToolRule>,
      ),
      McpToolRule,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$ProjectPlansTableCreateCompanionBuilder =
    ProjectPlansCompanion Function({
      Value<int> workspaceId,
      Value<String> step,
      Value<String> data,
      Value<String?> plannerSessionId,
      Value<double> costUsd,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> materializedAt,
    });
typedef $$ProjectPlansTableUpdateCompanionBuilder =
    ProjectPlansCompanion Function({
      Value<int> workspaceId,
      Value<String> step,
      Value<String> data,
      Value<String?> plannerSessionId,
      Value<double> costUsd,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> materializedAt,
    });

final class $$ProjectPlansTableReferences
    extends BaseReferences<_$AppDatabase, $ProjectPlansTable, ProjectPlan> {
  $$ProjectPlansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('project_plans__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<int>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProjectPlansTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectPlansTable> {
  $$ProjectPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plannerSessionId => $composableBuilder(
    column: $table.plannerSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get materializedAt => $composableBuilder(
    column: $table.materializedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectPlansTable> {
  $$ProjectPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plannerSessionId => $composableBuilder(
    column: $table.plannerSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get costUsd => $composableBuilder(
    column: $table.costUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get materializedAt => $composableBuilder(
    column: $table.materializedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectPlansTable> {
  $$ProjectPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get plannerSessionId => $composableBuilder(
    column: $table.plannerSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get costUsd =>
      $composableBuilder(column: $table.costUsd, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get materializedAt => $composableBuilder(
    column: $table.materializedAt,
    builder: (column) => column,
  );

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectPlansTable,
          ProjectPlan,
          $$ProjectPlansTableFilterComposer,
          $$ProjectPlansTableOrderingComposer,
          $$ProjectPlansTableAnnotationComposer,
          $$ProjectPlansTableCreateCompanionBuilder,
          $$ProjectPlansTableUpdateCompanionBuilder,
          (ProjectPlan, $$ProjectPlansTableReferences),
          ProjectPlan,
          PrefetchHooks Function({bool workspaceId})
        > {
  $$ProjectPlansTableTableManager(_$AppDatabase db, $ProjectPlansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> workspaceId = const Value.absent(),
                Value<String> step = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<String?> plannerSessionId = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> materializedAt = const Value.absent(),
              }) => ProjectPlansCompanion(
                workspaceId: workspaceId,
                step: step,
                data: data,
                plannerSessionId: plannerSessionId,
                costUsd: costUsd,
                createdAt: createdAt,
                updatedAt: updatedAt,
                materializedAt: materializedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> workspaceId = const Value.absent(),
                Value<String> step = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<String?> plannerSessionId = const Value.absent(),
                Value<double> costUsd = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> materializedAt = const Value.absent(),
              }) => ProjectPlansCompanion.insert(
                workspaceId: workspaceId,
                step: step,
                data: data,
                plannerSessionId: plannerSessionId,
                costUsd: costUsd,
                createdAt: createdAt,
                updatedAt: updatedAt,
                materializedAt: materializedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProjectPlansTable, ProjectPlan>(table),
                  $$ProjectPlansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workspaceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (workspaceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.workspaceId,
                        referencedTable: $$ProjectPlansTableReferences
                            ._workspaceIdTable(db),
                        referencedColumn: $$ProjectPlansTableReferences
                            ._workspaceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProjectPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectPlansTable,
      ProjectPlan,
      $$ProjectPlansTableFilterComposer,
      $$ProjectPlansTableOrderingComposer,
      $$ProjectPlansTableAnnotationComposer,
      $$ProjectPlansTableCreateCompanionBuilder,
      $$ProjectPlansTableUpdateCompanionBuilder,
      (ProjectPlan, $$ProjectPlansTableReferences),
      ProjectPlan,
      PrefetchHooks Function({bool workspaceId})
    >;
typedef $$AutopilotStatesTableCreateCompanionBuilder =
    AutopilotStatesCompanion Function({
      Value<int> workspaceId,
      Value<DateTime> since,
    });
typedef $$AutopilotStatesTableUpdateCompanionBuilder =
    AutopilotStatesCompanion Function({
      Value<int> workspaceId,
      Value<DateTime> since,
    });

final class $$AutopilotStatesTableReferences
    extends
        BaseReferences<_$AppDatabase, $AutopilotStatesTable, AutopilotState> {
  $$AutopilotStatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) => db.workspaces
      .createAlias('autopilot_states__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<int>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AutopilotStatesTableFilterComposer
    extends Composer<_$AppDatabase, $AutopilotStatesTable> {
  $$AutopilotStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get since => $composableBuilder(
    column: $table.since,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AutopilotStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $AutopilotStatesTable> {
  $$AutopilotStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get since => $composableBuilder(
    column: $table.since,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AutopilotStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AutopilotStatesTable> {
  $$AutopilotStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get since =>
      $composableBuilder(column: $table.since, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AutopilotStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AutopilotStatesTable,
          AutopilotState,
          $$AutopilotStatesTableFilterComposer,
          $$AutopilotStatesTableOrderingComposer,
          $$AutopilotStatesTableAnnotationComposer,
          $$AutopilotStatesTableCreateCompanionBuilder,
          $$AutopilotStatesTableUpdateCompanionBuilder,
          (AutopilotState, $$AutopilotStatesTableReferences),
          AutopilotState,
          PrefetchHooks Function({bool workspaceId})
        > {
  $$AutopilotStatesTableTableManager(
    _$AppDatabase db,
    $AutopilotStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AutopilotStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AutopilotStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AutopilotStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> workspaceId = const Value.absent(),
                Value<DateTime> since = const Value.absent(),
              }) => AutopilotStatesCompanion(
                workspaceId: workspaceId,
                since: since,
              ),
          createCompanionCallback:
              ({
                Value<int> workspaceId = const Value.absent(),
                Value<DateTime> since = const Value.absent(),
              }) => AutopilotStatesCompanion.insert(
                workspaceId: workspaceId,
                since: since,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AutopilotStatesTable, AutopilotState>(table),
                  $$AutopilotStatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workspaceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (workspaceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.workspaceId,
                        referencedTable: $$AutopilotStatesTableReferences
                            ._workspaceIdTable(db),
                        referencedColumn: $$AutopilotStatesTableReferences
                            ._workspaceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AutopilotStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AutopilotStatesTable,
      AutopilotState,
      $$AutopilotStatesTableFilterComposer,
      $$AutopilotStatesTableOrderingComposer,
      $$AutopilotStatesTableAnnotationComposer,
      $$AutopilotStatesTableCreateCompanionBuilder,
      $$AutopilotStatesTableUpdateCompanionBuilder,
      (AutopilotState, $$AutopilotStatesTableReferences),
      AutopilotState,
      PrefetchHooks Function({bool workspaceId})
    >;
typedef $$ReviewDraftsTableCreateCompanionBuilder =
    ReviewDraftsCompanion Function({
      required String sessionId,
      required String data,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ReviewDraftsTableUpdateCompanionBuilder =
    ReviewDraftsCompanion Function({
      Value<String> sessionId,
      Value<String> data,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReviewDraftsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewDraftsTable> {
  $$ReviewDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReviewDraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewDraftsTable> {
  $$ReviewDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReviewDraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewDraftsTable> {
  $$ReviewDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReviewDraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewDraftsTable,
          ReviewDraftRow,
          $$ReviewDraftsTableFilterComposer,
          $$ReviewDraftsTableOrderingComposer,
          $$ReviewDraftsTableAnnotationComposer,
          $$ReviewDraftsTableCreateCompanionBuilder,
          $$ReviewDraftsTableUpdateCompanionBuilder,
          (
            ReviewDraftRow,
            BaseReferences<_$AppDatabase, $ReviewDraftsTable, ReviewDraftRow>,
          ),
          ReviewDraftRow,
          PrefetchHooks Function()
        > {
  $$ReviewDraftsTableTableManager(_$AppDatabase db, $ReviewDraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewDraftsCompanion(
                sessionId: sessionId,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String data,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewDraftsCompanion.insert(
                sessionId: sessionId,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewDraftsTable, ReviewDraftRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReviewDraftsTable,
                    ReviewDraftRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReviewDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewDraftsTable,
      ReviewDraftRow,
      $$ReviewDraftsTableFilterComposer,
      $$ReviewDraftsTableOrderingComposer,
      $$ReviewDraftsTableAnnotationComposer,
      $$ReviewDraftsTableCreateCompanionBuilder,
      $$ReviewDraftsTableUpdateCompanionBuilder,
      (
        ReviewDraftRow,
        BaseReferences<_$AppDatabase, $ReviewDraftsTable, ReviewDraftRow>,
      ),
      ReviewDraftRow,
      PrefetchHooks Function()
    >;
typedef $$PendingNoticesTableCreateCompanionBuilder =
    PendingNoticesCompanion Function({
      Value<int> id,
      required String sessionId,
      required String body,
      Value<DateTime> createdAt,
    });
typedef $$PendingNoticesTableUpdateCompanionBuilder =
    PendingNoticesCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<String> body,
      Value<DateTime> createdAt,
    });

final class $$PendingNoticesTableReferences
    extends BaseReferences<_$AppDatabase, $PendingNoticesTable, PendingNotice> {
  $$PendingNoticesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias('pending_notices__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PendingNoticesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingNoticesTable> {
  $$PendingNoticesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PendingNoticesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingNoticesTable> {
  $$PendingNoticesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PendingNoticesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingNoticesTable> {
  $$PendingNoticesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PendingNoticesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingNoticesTable,
          PendingNotice,
          $$PendingNoticesTableFilterComposer,
          $$PendingNoticesTableOrderingComposer,
          $$PendingNoticesTableAnnotationComposer,
          $$PendingNoticesTableCreateCompanionBuilder,
          $$PendingNoticesTableUpdateCompanionBuilder,
          (PendingNotice, $$PendingNoticesTableReferences),
          PendingNotice,
          PrefetchHooks Function({bool sessionId})
        > {
  $$PendingNoticesTableTableManager(
    _$AppDatabase db,
    $PendingNoticesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingNoticesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingNoticesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingNoticesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PendingNoticesCompanion(
                id: id,
                sessionId: sessionId,
                body: body,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required String body,
                Value<DateTime> createdAt = const Value.absent(),
              }) => PendingNoticesCompanion.insert(
                id: id,
                sessionId: sessionId,
                body: body,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingNoticesTable, PendingNotice>(table),
                  $$PendingNoticesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$PendingNoticesTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$PendingNoticesTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PendingNoticesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingNoticesTable,
      PendingNotice,
      $$PendingNoticesTableFilterComposer,
      $$PendingNoticesTableOrderingComposer,
      $$PendingNoticesTableAnnotationComposer,
      $$PendingNoticesTableCreateCompanionBuilder,
      $$PendingNoticesTableUpdateCompanionBuilder,
      (PendingNotice, $$PendingNoticesTableReferences),
      PendingNotice,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$ReviewCommentsTableCreateCompanionBuilder =
    ReviewCommentsCompanion Function({
      Value<int> id,
      required int specId,
      required int round,
      required String author,
      Value<String?> path,
      Value<int?> line,
      required String body,
      Value<String?> severity,
      Value<String?> requirement,
      Value<String?> verdict,
      Value<String?> commitSha,
      Value<bool> resolved,
      Value<DateTime?> resolvedAt,
      Value<String?> externalId,
      Value<DateTime> createdAt,
    });
typedef $$ReviewCommentsTableUpdateCompanionBuilder =
    ReviewCommentsCompanion Function({
      Value<int> id,
      Value<int> specId,
      Value<int> round,
      Value<String> author,
      Value<String?> path,
      Value<int?> line,
      Value<String> body,
      Value<String?> severity,
      Value<String?> requirement,
      Value<String?> verdict,
      Value<String?> commitSha,
      Value<bool> resolved,
      Value<DateTime?> resolvedAt,
      Value<String?> externalId,
      Value<DateTime> createdAt,
    });

final class $$ReviewCommentsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ReviewCommentsTable, ReviewCommentRow> {
  $$ReviewCommentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SpecsTable _specIdTable(_$AppDatabase db) =>
      db.specs.createAlias('review_comments__spec_id__specs__id');

  $$SpecsTableProcessedTableManager get specId {
    final $_column = $_itemColumn<int>('spec_id')!;

    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewCommentsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewCommentsTable> {
  $$ReviewCommentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get round => $composableBuilder(
    column: $table.round,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get line => $composableBuilder(
    column: $table.line,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requirement => $composableBuilder(
    column: $table.requirement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verdict => $composableBuilder(
    column: $table.verdict,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commitSha => $composableBuilder(
    column: $table.commitSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get resolved => $composableBuilder(
    column: $table.resolved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecsTableFilterComposer get specId {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewCommentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewCommentsTable> {
  $$ReviewCommentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get round => $composableBuilder(
    column: $table.round,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get line => $composableBuilder(
    column: $table.line,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requirement => $composableBuilder(
    column: $table.requirement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verdict => $composableBuilder(
    column: $table.verdict,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commitSha => $composableBuilder(
    column: $table.commitSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get resolved => $composableBuilder(
    column: $table.resolved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecsTableOrderingComposer get specId {
    final $$SpecsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableOrderingComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewCommentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewCommentsTable> {
  $$ReviewCommentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get round =>
      $composableBuilder(column: $table.round, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get line =>
      $composableBuilder(column: $table.line, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<String> get requirement => $composableBuilder(
    column: $table.requirement,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verdict =>
      $composableBuilder(column: $table.verdict, builder: (column) => column);

  GeneratedColumn<String> get commitSha =>
      $composableBuilder(column: $table.commitSha, builder: (column) => column);

  GeneratedColumn<bool> get resolved =>
      $composableBuilder(column: $table.resolved, builder: (column) => column);

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SpecsTableAnnotationComposer get specId {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewCommentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewCommentsTable,
          ReviewCommentRow,
          $$ReviewCommentsTableFilterComposer,
          $$ReviewCommentsTableOrderingComposer,
          $$ReviewCommentsTableAnnotationComposer,
          $$ReviewCommentsTableCreateCompanionBuilder,
          $$ReviewCommentsTableUpdateCompanionBuilder,
          (ReviewCommentRow, $$ReviewCommentsTableReferences),
          ReviewCommentRow,
          PrefetchHooks Function({bool specId})
        > {
  $$ReviewCommentsTableTableManager(
    _$AppDatabase db,
    $ReviewCommentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewCommentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewCommentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewCommentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> specId = const Value.absent(),
                Value<int> round = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<int?> line = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> severity = const Value.absent(),
                Value<String?> requirement = const Value.absent(),
                Value<String?> verdict = const Value.absent(),
                Value<String?> commitSha = const Value.absent(),
                Value<bool> resolved = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ReviewCommentsCompanion(
                id: id,
                specId: specId,
                round: round,
                author: author,
                path: path,
                line: line,
                body: body,
                severity: severity,
                requirement: requirement,
                verdict: verdict,
                commitSha: commitSha,
                resolved: resolved,
                resolvedAt: resolvedAt,
                externalId: externalId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int specId,
                required int round,
                required String author,
                Value<String?> path = const Value.absent(),
                Value<int?> line = const Value.absent(),
                required String body,
                Value<String?> severity = const Value.absent(),
                Value<String?> requirement = const Value.absent(),
                Value<String?> verdict = const Value.absent(),
                Value<String?> commitSha = const Value.absent(),
                Value<bool> resolved = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ReviewCommentsCompanion.insert(
                id: id,
                specId: specId,
                round: round,
                author: author,
                path: path,
                line: line,
                body: body,
                severity: severity,
                requirement: requirement,
                verdict: verdict,
                commitSha: commitSha,
                resolved: resolved,
                resolvedAt: resolvedAt,
                externalId: externalId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewCommentsTable, ReviewCommentRow>(table),
                  $$ReviewCommentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({specId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (specId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.specId,
                        referencedTable: $$ReviewCommentsTableReferences
                            ._specIdTable(db),
                        referencedColumn: $$ReviewCommentsTableReferences
                            ._specIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReviewCommentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewCommentsTable,
      ReviewCommentRow,
      $$ReviewCommentsTableFilterComposer,
      $$ReviewCommentsTableOrderingComposer,
      $$ReviewCommentsTableAnnotationComposer,
      $$ReviewCommentsTableCreateCompanionBuilder,
      $$ReviewCommentsTableUpdateCompanionBuilder,
      (ReviewCommentRow, $$ReviewCommentsTableReferences),
      ReviewCommentRow,
      PrefetchHooks Function({bool specId})
    >;
typedef $$SpecCriteriaTableCreateCompanionBuilder =
    SpecCriteriaCompanion Function({
      required int specId,
      required String criterion,
      Value<bool> checked,
      Value<String?> checkedBy,
      Value<DateTime?> checkedAt,
      Value<int> rowid,
    });
typedef $$SpecCriteriaTableUpdateCompanionBuilder =
    SpecCriteriaCompanion Function({
      Value<int> specId,
      Value<String> criterion,
      Value<bool> checked,
      Value<String?> checkedBy,
      Value<DateTime?> checkedAt,
      Value<int> rowid,
    });

final class $$SpecCriteriaTableReferences
    extends
        BaseReferences<_$AppDatabase, $SpecCriteriaTable, SpecCriteriaData> {
  $$SpecCriteriaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SpecsTable _specIdTable(_$AppDatabase db) =>
      db.specs.createAlias('spec_criteria__spec_id__specs__id');

  $$SpecsTableProcessedTableManager get specId {
    final $_column = $_itemColumn<int>('spec_id')!;

    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpecCriteriaTableFilterComposer
    extends Composer<_$AppDatabase, $SpecCriteriaTable> {
  $$SpecCriteriaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get criterion => $composableBuilder(
    column: $table.criterion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get checked => $composableBuilder(
    column: $table.checked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkedBy => $composableBuilder(
    column: $table.checkedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecsTableFilterComposer get specId {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecCriteriaTableOrderingComposer
    extends Composer<_$AppDatabase, $SpecCriteriaTable> {
  $$SpecCriteriaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get criterion => $composableBuilder(
    column: $table.criterion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get checked => $composableBuilder(
    column: $table.checked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkedBy => $composableBuilder(
    column: $table.checkedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecsTableOrderingComposer get specId {
    final $$SpecsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableOrderingComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecCriteriaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpecCriteriaTable> {
  $$SpecCriteriaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get criterion =>
      $composableBuilder(column: $table.criterion, builder: (column) => column);

  GeneratedColumn<bool> get checked =>
      $composableBuilder(column: $table.checked, builder: (column) => column);

  GeneratedColumn<String> get checkedBy =>
      $composableBuilder(column: $table.checkedBy, builder: (column) => column);

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  $$SpecsTableAnnotationComposer get specId {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecCriteriaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpecCriteriaTable,
          SpecCriteriaData,
          $$SpecCriteriaTableFilterComposer,
          $$SpecCriteriaTableOrderingComposer,
          $$SpecCriteriaTableAnnotationComposer,
          $$SpecCriteriaTableCreateCompanionBuilder,
          $$SpecCriteriaTableUpdateCompanionBuilder,
          (SpecCriteriaData, $$SpecCriteriaTableReferences),
          SpecCriteriaData,
          PrefetchHooks Function({bool specId})
        > {
  $$SpecCriteriaTableTableManager(_$AppDatabase db, $SpecCriteriaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpecCriteriaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpecCriteriaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpecCriteriaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> specId = const Value.absent(),
                Value<String> criterion = const Value.absent(),
                Value<bool> checked = const Value.absent(),
                Value<String?> checkedBy = const Value.absent(),
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecCriteriaCompanion(
                specId: specId,
                criterion: criterion,
                checked: checked,
                checkedBy: checkedBy,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int specId,
                required String criterion,
                Value<bool> checked = const Value.absent(),
                Value<String?> checkedBy = const Value.absent(),
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpecCriteriaCompanion.insert(
                specId: specId,
                criterion: criterion,
                checked: checked,
                checkedBy: checkedBy,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpecCriteriaTable, SpecCriteriaData>(table),
                  $$SpecCriteriaTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({specId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (specId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.specId,
                        referencedTable: $$SpecCriteriaTableReferences
                            ._specIdTable(db),
                        referencedColumn: $$SpecCriteriaTableReferences
                            ._specIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SpecCriteriaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpecCriteriaTable,
      SpecCriteriaData,
      $$SpecCriteriaTableFilterComposer,
      $$SpecCriteriaTableOrderingComposer,
      $$SpecCriteriaTableAnnotationComposer,
      $$SpecCriteriaTableCreateCompanionBuilder,
      $$SpecCriteriaTableUpdateCompanionBuilder,
      (SpecCriteriaData, $$SpecCriteriaTableReferences),
      SpecCriteriaData,
      PrefetchHooks Function({bool specId})
    >;
typedef $$SpecSuggestionsTableCreateCompanionBuilder =
    SpecSuggestionsCompanion Function({
      Value<int> id,
      required int specId,
      Value<String?> sessionId,
      Value<String?> steps,
      required String body,
      Value<String> state,
      Value<DateTime> createdAt,
    });
typedef $$SpecSuggestionsTableUpdateCompanionBuilder =
    SpecSuggestionsCompanion Function({
      Value<int> id,
      Value<int> specId,
      Value<String?> sessionId,
      Value<String?> steps,
      Value<String> body,
      Value<String> state,
      Value<DateTime> createdAt,
    });

final class $$SpecSuggestionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $SpecSuggestionsTable, SpecSuggestion> {
  $$SpecSuggestionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SpecsTable _specIdTable(_$AppDatabase db) =>
      db.specs.createAlias('spec_suggestions__spec_id__specs__id');

  $$SpecsTableProcessedTableManager get specId {
    final $_column = $_itemColumn<int>('spec_id')!;

    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpecSuggestionsTableFilterComposer
    extends Composer<_$AppDatabase, $SpecSuggestionsTable> {
  $$SpecSuggestionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecsTableFilterComposer get specId {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecSuggestionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SpecSuggestionsTable> {
  $$SpecSuggestionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecsTableOrderingComposer get specId {
    final $$SpecsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableOrderingComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecSuggestionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpecSuggestionsTable> {
  $$SpecSuggestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get steps =>
      $composableBuilder(column: $table.steps, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SpecsTableAnnotationComposer get specId {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecSuggestionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpecSuggestionsTable,
          SpecSuggestion,
          $$SpecSuggestionsTableFilterComposer,
          $$SpecSuggestionsTableOrderingComposer,
          $$SpecSuggestionsTableAnnotationComposer,
          $$SpecSuggestionsTableCreateCompanionBuilder,
          $$SpecSuggestionsTableUpdateCompanionBuilder,
          (SpecSuggestion, $$SpecSuggestionsTableReferences),
          SpecSuggestion,
          PrefetchHooks Function({bool specId})
        > {
  $$SpecSuggestionsTableTableManager(
    _$AppDatabase db,
    $SpecSuggestionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpecSuggestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpecSuggestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpecSuggestionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> specId = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String?> steps = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SpecSuggestionsCompanion(
                id: id,
                specId: specId,
                sessionId: sessionId,
                steps: steps,
                body: body,
                state: state,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int specId,
                Value<String?> sessionId = const Value.absent(),
                Value<String?> steps = const Value.absent(),
                required String body,
                Value<String> state = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SpecSuggestionsCompanion.insert(
                id: id,
                specId: specId,
                sessionId: sessionId,
                steps: steps,
                body: body,
                state: state,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpecSuggestionsTable, SpecSuggestion>(table),
                  $$SpecSuggestionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({specId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (specId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.specId,
                        referencedTable: $$SpecSuggestionsTableReferences
                            ._specIdTable(db),
                        referencedColumn: $$SpecSuggestionsTableReferences
                            ._specIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SpecSuggestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpecSuggestionsTable,
      SpecSuggestion,
      $$SpecSuggestionsTableFilterComposer,
      $$SpecSuggestionsTableOrderingComposer,
      $$SpecSuggestionsTableAnnotationComposer,
      $$SpecSuggestionsTableCreateCompanionBuilder,
      $$SpecSuggestionsTableUpdateCompanionBuilder,
      (SpecSuggestion, $$SpecSuggestionsTableReferences),
      SpecSuggestion,
      PrefetchHooks Function({bool specId})
    >;
typedef $$NotificationsTableCreateCompanionBuilder =
    NotificationsCompanion Function({
      Value<int> id,
      required String title,
      required String body,
      Value<String?> section,
      Value<String?> sessionId,
      Value<bool> read,
      Value<DateTime> createdAt,
    });
typedef $$NotificationsTableUpdateCompanionBuilder =
    NotificationsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> body,
      Value<String?> section,
      Value<String?> sessionId,
      Value<bool> read,
      Value<DateTime> createdAt,
    });

class $$NotificationsTableFilterComposer
    extends Composer<_$AppDatabase, $NotificationsTable> {
  $$NotificationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get section => $composableBuilder(
    column: $table.section,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotificationsTableOrderingComposer
    extends Composer<_$AppDatabase, $NotificationsTable> {
  $$NotificationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get section => $composableBuilder(
    column: $table.section,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotificationsTable> {
  $$NotificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get section =>
      $composableBuilder(column: $table.section, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<bool> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NotificationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotificationsTable,
          AppNotification,
          $$NotificationsTableFilterComposer,
          $$NotificationsTableOrderingComposer,
          $$NotificationsTableAnnotationComposer,
          $$NotificationsTableCreateCompanionBuilder,
          $$NotificationsTableUpdateCompanionBuilder,
          (
            AppNotification,
            BaseReferences<_$AppDatabase, $NotificationsTable, AppNotification>,
          ),
          AppNotification,
          PrefetchHooks Function()
        > {
  $$NotificationsTableTableManager(_$AppDatabase db, $NotificationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotificationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotificationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> section = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NotificationsCompanion(
                id: id,
                title: title,
                body: body,
                section: section,
                sessionId: sessionId,
                read: read,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required String body,
                Value<String?> section = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NotificationsCompanion.insert(
                id: id,
                title: title,
                body: body,
                section: section,
                sessionId: sessionId,
                read: read,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotificationsTable, AppNotification>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $NotificationsTable,
                    AppNotification
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotificationsTable,
      AppNotification,
      $$NotificationsTableFilterComposer,
      $$NotificationsTableOrderingComposer,
      $$NotificationsTableAnnotationComposer,
      $$NotificationsTableCreateCompanionBuilder,
      $$NotificationsTableUpdateCompanionBuilder,
      (
        AppNotification,
        BaseReferences<_$AppDatabase, $NotificationsTable, AppNotification>,
      ),
      AppNotification,
      PrefetchHooks Function()
    >;
typedef $$SpecDuelsTableCreateCompanionBuilder = SpecDuelsCompanion Function({
  Value<int> id,
  required int specId,
  required String steps,
  required String baseSha,
  Value<String?> sessionA,
  Value<String?> sessionB,
  required String worktreeA,
  required String worktreeB,
  required String branchA,
  required String branchB,
  Value<String?> reportA,
  Value<String?> reportB,
  Value<String> state,
  Value<String?> chosen,
  Value<DateTime> createdAt,
});
typedef $$SpecDuelsTableUpdateCompanionBuilder = SpecDuelsCompanion Function({
  Value<int> id,
  Value<int> specId,
  Value<String> steps,
  Value<String> baseSha,
  Value<String?> sessionA,
  Value<String?> sessionB,
  Value<String> worktreeA,
  Value<String> worktreeB,
  Value<String> branchA,
  Value<String> branchB,
  Value<String?> reportA,
  Value<String?> reportB,
  Value<String> state,
  Value<String?> chosen,
  Value<DateTime> createdAt,
});

final class $$SpecDuelsTableReferences
    extends BaseReferences<_$AppDatabase, $SpecDuelsTable, SpecDuel> {
  $$SpecDuelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SpecsTable _specIdTable(_$AppDatabase db) =>
      db.specs.createAlias('spec_duels__spec_id__specs__id');

  $$SpecsTableProcessedTableManager get specId {
    final $_column = $_itemColumn<int>('spec_id')!;

    final manager = $$SpecsTableTableManager(
      $_db,
      $_db.specs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_specIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpecDuelsTableFilterComposer
    extends Composer<_$AppDatabase, $SpecDuelsTable> {
  $$SpecDuelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseSha => $composableBuilder(
    column: $table.baseSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionA => $composableBuilder(
    column: $table.sessionA,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionB => $composableBuilder(
    column: $table.sessionB,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get worktreeA => $composableBuilder(
    column: $table.worktreeA,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get worktreeB => $composableBuilder(
    column: $table.worktreeB,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchA => $composableBuilder(
    column: $table.branchA,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchB => $composableBuilder(
    column: $table.branchB,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reportA => $composableBuilder(
    column: $table.reportA,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reportB => $composableBuilder(
    column: $table.reportB,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chosen => $composableBuilder(
    column: $table.chosen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SpecsTableFilterComposer get specId {
    final $$SpecsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableFilterComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecDuelsTableOrderingComposer
    extends Composer<_$AppDatabase, $SpecDuelsTable> {
  $$SpecDuelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseSha => $composableBuilder(
    column: $table.baseSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionA => $composableBuilder(
    column: $table.sessionA,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionB => $composableBuilder(
    column: $table.sessionB,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get worktreeA => $composableBuilder(
    column: $table.worktreeA,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get worktreeB => $composableBuilder(
    column: $table.worktreeB,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchA => $composableBuilder(
    column: $table.branchA,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchB => $composableBuilder(
    column: $table.branchB,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reportA => $composableBuilder(
    column: $table.reportA,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reportB => $composableBuilder(
    column: $table.reportB,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chosen => $composableBuilder(
    column: $table.chosen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SpecsTableOrderingComposer get specId {
    final $$SpecsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableOrderingComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecDuelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpecDuelsTable> {
  $$SpecDuelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get steps =>
      $composableBuilder(column: $table.steps, builder: (column) => column);

  GeneratedColumn<String> get baseSha =>
      $composableBuilder(column: $table.baseSha, builder: (column) => column);

  GeneratedColumn<String> get sessionA =>
      $composableBuilder(column: $table.sessionA, builder: (column) => column);

  GeneratedColumn<String> get sessionB =>
      $composableBuilder(column: $table.sessionB, builder: (column) => column);

  GeneratedColumn<String> get worktreeA =>
      $composableBuilder(column: $table.worktreeA, builder: (column) => column);

  GeneratedColumn<String> get worktreeB =>
      $composableBuilder(column: $table.worktreeB, builder: (column) => column);

  GeneratedColumn<String> get branchA =>
      $composableBuilder(column: $table.branchA, builder: (column) => column);

  GeneratedColumn<String> get branchB =>
      $composableBuilder(column: $table.branchB, builder: (column) => column);

  GeneratedColumn<String> get reportA =>
      $composableBuilder(column: $table.reportA, builder: (column) => column);

  GeneratedColumn<String> get reportB =>
      $composableBuilder(column: $table.reportB, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get chosen =>
      $composableBuilder(column: $table.chosen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SpecsTableAnnotationComposer get specId {
    final $$SpecsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.specId,
      referencedTable: $db.specs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpecsTableAnnotationComposer(
            $db: $db,
            $table: $db.specs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpecDuelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpecDuelsTable,
          SpecDuel,
          $$SpecDuelsTableFilterComposer,
          $$SpecDuelsTableOrderingComposer,
          $$SpecDuelsTableAnnotationComposer,
          $$SpecDuelsTableCreateCompanionBuilder,
          $$SpecDuelsTableUpdateCompanionBuilder,
          (SpecDuel, $$SpecDuelsTableReferences),
          SpecDuel,
          PrefetchHooks Function({bool specId})
        > {
  $$SpecDuelsTableTableManager(_$AppDatabase db, $SpecDuelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpecDuelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpecDuelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpecDuelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> specId = const Value.absent(),
                Value<String> steps = const Value.absent(),
                Value<String> baseSha = const Value.absent(),
                Value<String?> sessionA = const Value.absent(),
                Value<String?> sessionB = const Value.absent(),
                Value<String> worktreeA = const Value.absent(),
                Value<String> worktreeB = const Value.absent(),
                Value<String> branchA = const Value.absent(),
                Value<String> branchB = const Value.absent(),
                Value<String?> reportA = const Value.absent(),
                Value<String?> reportB = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> chosen = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SpecDuelsCompanion(
                id: id,
                specId: specId,
                steps: steps,
                baseSha: baseSha,
                sessionA: sessionA,
                sessionB: sessionB,
                worktreeA: worktreeA,
                worktreeB: worktreeB,
                branchA: branchA,
                branchB: branchB,
                reportA: reportA,
                reportB: reportB,
                state: state,
                chosen: chosen,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int specId,
                required String steps,
                required String baseSha,
                Value<String?> sessionA = const Value.absent(),
                Value<String?> sessionB = const Value.absent(),
                required String worktreeA,
                required String worktreeB,
                required String branchA,
                required String branchB,
                Value<String?> reportA = const Value.absent(),
                Value<String?> reportB = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> chosen = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SpecDuelsCompanion.insert(
                id: id,
                specId: specId,
                steps: steps,
                baseSha: baseSha,
                sessionA: sessionA,
                sessionB: sessionB,
                worktreeA: worktreeA,
                worktreeB: worktreeB,
                branchA: branchA,
                branchB: branchB,
                reportA: reportA,
                reportB: reportB,
                state: state,
                chosen: chosen,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpecDuelsTable, SpecDuel>(table),
                  $$SpecDuelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({specId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (specId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.specId,
                        referencedTable: $$SpecDuelsTableReferences
                            ._specIdTable(db),
                        referencedColumn: $$SpecDuelsTableReferences
                            ._specIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SpecDuelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpecDuelsTable,
      SpecDuel,
      $$SpecDuelsTableFilterComposer,
      $$SpecDuelsTableOrderingComposer,
      $$SpecDuelsTableAnnotationComposer,
      $$SpecDuelsTableCreateCompanionBuilder,
      $$SpecDuelsTableUpdateCompanionBuilder,
      (SpecDuel, $$SpecDuelsTableReferences),
      SpecDuel,
      PrefetchHooks Function({bool specId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db, _db.workspaces);
  $$SpecsTableTableManager get specs =>
      $$SpecsTableTableManager(_db, _db.specs);
  $$SpecStepsTableTableManager get specSteps =>
      $$SpecStepsTableTableManager(_db, _db.specSteps);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SessionEventsTableTableManager get sessionEvents =>
      $$SessionEventsTableTableManager(_db, _db.sessionEvents);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$ConversationEventsTableTableManager get conversationEvents =>
      $$ConversationEventsTableTableManager(_db, _db.conversationEvents);
  $$SavedPromptsTableTableManager get savedPrompts =>
      $$SavedPromptsTableTableManager(_db, _db.savedPrompts);
  $$AgentSettingsTableTableManager get agentSettings =>
      $$AgentSettingsTableTableManager(_db, _db.agentSettings);
  $$McpToolRulesTableTableManager get mcpToolRules =>
      $$McpToolRulesTableTableManager(_db, _db.mcpToolRules);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$ProjectPlansTableTableManager get projectPlans =>
      $$ProjectPlansTableTableManager(_db, _db.projectPlans);
  $$AutopilotStatesTableTableManager get autopilotStates =>
      $$AutopilotStatesTableTableManager(_db, _db.autopilotStates);
  $$ReviewDraftsTableTableManager get reviewDrafts =>
      $$ReviewDraftsTableTableManager(_db, _db.reviewDrafts);
  $$PendingNoticesTableTableManager get pendingNotices =>
      $$PendingNoticesTableTableManager(_db, _db.pendingNotices);
  $$ReviewCommentsTableTableManager get reviewComments =>
      $$ReviewCommentsTableTableManager(_db, _db.reviewComments);
  $$SpecCriteriaTableTableManager get specCriteria =>
      $$SpecCriteriaTableTableManager(_db, _db.specCriteria);
  $$SpecSuggestionsTableTableManager get specSuggestions =>
      $$SpecSuggestionsTableTableManager(_db, _db.specSuggestions);
  $$NotificationsTableTableManager get notifications =>
      $$NotificationsTableTableManager(_db, _db.notifications);
  $$SpecDuelsTableTableManager get specDuels =>
      $$SpecDuelsTableTableManager(_db, _db.specDuels);
}
