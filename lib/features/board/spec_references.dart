import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

class SpecReferences {
  const SpecReferences({this.agents = const {}, this.skills = const {}});
  final Set<String> agents, skills;
}

/// Only tool_use Skill events count; init's list of available skills doesn't.
Set<String> loadedSkills(Object? json) {
  final result = <String>{};
  void visit(Object? v) {
    if (v is Map) {
      if (v['name'] == 'Skill' && v['input'] is Map) {
        final skill = v['input']['skill'];
        if (skill is String && skill.isNotEmpty) result.add(skill);
      }
      for (final value in v.values) {
        visit(value);
      }
    } else if (v is List) {
      for (final value in v) {
        visit(value);
      }
    }
  }

  visit(json);
  return result;
}

final specReferencesProvider = FutureProvider.autoDispose
    .family<SpecReferences, int>((ref, specId) async {
      final db = ref.watch(appDatabaseProvider);
      final spec = await ref.read(specsRepoProvider).getById(specId);
      final sessions = await ref.read(sessionsRepoProvider).bySpec(specId);
      final agents = <String>{
        if (spec?.agentName != null) spec!.agentName!,
        for (final s in sessions)
          if (s.agentName != null) s.agentName!,
      };
      final events = await db
          .customSelect(
            'SELECT e.json FROM session_events e JOIN sessions s ON s.id = e.session_id '
            'WHERE s.spec_id = ? AND e.type = ?',
            variables: [
              Variable.withInt(specId),
              Variable.withString('assistant'),
            ],
            readsFrom: {db.sessions, db.sessionEvents},
          )
          .get();
      final skills = <String>{};
      for (final e in events) {
        try {
          skills.addAll(loadedSkills(jsonDecode(e.read<String>('json'))));
        } on FormatException {
          /* invalid historical event */
        }
      }
      return SpecReferences(agents: agents, skills: skills);
    });
