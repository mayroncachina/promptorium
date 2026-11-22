import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/structured_schema.dart';
import 'package:promptorium/features/board/step_decision.dart';
import 'package:promptorium/features/board/step_decision_compiler.dart';
import 'package:promptorium/features/project/project_planner.dart';
import 'package:promptorium/features/review/auto_reviewer.dart';
import 'package:promptorium/features/skills/skill_writer.dart';
import 'package:promptorium/features/specs/spec_answers.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_planner.dart';
import 'package:promptorium/features/specs/spec_verifier.dart';
import 'package:promptorium/features/vibe/vibe_guard.dart';

/// The schemas of every flow the Codex runs (SPEC-100 R8).
final codexFlowSchemas = <String, Map<String, Object?>>{
  'visão': visionSchema,
  'stack': stackSchema,
  'stack própria': customStackSchema,
  'roadmap': roadmapSchema,
  'ideia': ideaSpecSchema,
  'nova spec': specPlannerSchema,
  'perguntas': questionOptionsSchema,
  'respostas': applyAnswersSchema,
  'design': designSchema,
  'planejar': autoPlanSchema,
  'verificar': verificationSchema,
  'nova skill': skillDraftSchema,
  'decidir na etapa': stepDecisionSchema,
  'compilar a decisão': stepDecisionCompileSchema,
  'checagem da VIBE': unrelatedSchema,
  'revisor': reviewerSchema,
};

void main() {
  test('R3: every schema of the Codex flows passes the strict rules of the '
      'outputSchema after its variant', () {
    for (final MapEntry(:key, :value) in codexFlowSchemas.entries) {
      expect(
        codexSchemaProblems(codexCompatibleSchema(value)),
        isEmpty,
        reason: key,
      );
    }
  });

  test('R3: the schema of the SPEC-093 probe is already strict and comes '
      'back equal', () {
    const probe = {
      'type': 'object',
      'properties': {
        'ok': {'type': 'boolean'},
      },
      'required': ['ok'],
      'additionalProperties': false,
    };
    expect(codexSchemaProblems(probe), isEmpty);
    expect(codexCompatibleSchema(probe), probe);
  });

  test('R3: optional fields become required and nullable; the null leaves '
      'the answer', () {
    const schema = {
      'type': 'object',
      'required': ['a'],
      'properties': {
        'a': {'type': 'string'},
        'b': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'c': {'type': 'integer', 'default': 1},
            },
          },
        },
      },
    };
    expect(codexSchemaProblems(schema), isNotEmpty);
    final strict = codexCompatibleSchema(schema);
    expect(codexSchemaProblems(strict), isEmpty);
    expect((strict['properties'] as Map)['b']['type'], ['array', 'null']);
    final item = (strict['properties'] as Map)['b']['items'] as Map;
    expect(item['required'], ['c']);
    expect(item['properties']['c'], {
      'type': ['integer', 'null'],
    });
    expect(
      stripAddedNulls({
        'a': 'x',
        'b': [
          {'c': null},
        ],
      }, schema),
      {
        'a': 'x',
        'b': [<String, Object?>{}],
      },
    );
    expect(stripAddedNulls({'a': 'x', 'b': null}, schema), {'a': 'x'});
  });

  test('R3: schemaMismatch says where the answer breaks the schema', () {
    const schema = {
      'type': 'object',
      'additionalProperties': false,
      'required': ['n', 'tipo'],
      'properties': {
        'n': {'type': 'integer', 'minimum': 0},
        'tipo': {
          'type': 'string',
          'enum': ['a', 'b'],
        },
      },
    };
    expect(schemaMismatch({'n': 1, 'tipo': 'a'}, schema), isNull);
    expect(schemaMismatch({'n': 1}, schema), contains('tipo ausente'));
    expect(schemaMismatch({'n': -1, 'tipo': 'a'}, schema), contains('abaixo'));
    expect(schemaMismatch({'n': 1, 'tipo': 'c'}, schema), contains('opções'));
    expect(
      schemaMismatch({'n': 1, 'tipo': 'a', 'x': 1}, schema),
      contains('não pedido'),
    );
    expect(schemaMismatch('texto', schema), contains('object'));
  });
}
