/// Output schemas of the structured runs on providers that enforce a strict
/// subset of JSON Schema (SPEC-100 R3).
///
/// The Codex `turn/start.outputSchema` follows the strict structured outputs
/// of the OpenAI models: the probe of SPEC-093 (R12) used
/// `{"type":"object","properties":…,"required":[all],"additionalProperties":
/// false}`. The rules kept here are the ones that schema obeys:
///
/// - every object lists **all** its properties in `required`;
/// - every object has `additionalProperties: false`;
/// - only the keywords of [codexSchemaKeywords] appear.
///
/// A schema with optional fields gets a compatible variant
/// ([codexCompatibleSchema]): each optional field becomes required and
/// accepts `null`, and [stripAddedNulls] drops those nulls from the answer,
/// so the service sees the field absent, as with the Claude Code.
library;

/// Keywords the strict output schema accepts (SPEC-100 R3). `default`,
/// `$schema`, `title` and `examples` are dropped by the variant.
const codexSchemaKeywords = {
  'type',
  'properties',
  'required',
  'additionalProperties',
  'items',
  'enum',
  'const',
  'anyOf',
  'description',
  'minItems',
  'maxItems',
  'minimum',
  'maximum',
  'pattern',
  'format',
};

/// Problems of [schema] under the strict rules (empty = compatible).
List<String> codexSchemaProblems(Object? schema, [String path = r'$']) {
  final out = <String>[];
  if (schema is! Map) return out;
  for (final k in schema.keys) {
    if (!codexSchemaKeywords.contains(k)) out.add('$path: palavra-chave $k');
  }
  if (_isObject(schema)) {
    final props = (schema['properties'] as Map?) ?? const {};
    final required = {...(schema['required'] as List? ?? const [])};
    for (final p in props.keys) {
      if (!required.contains(p)) out.add('$path.$p: campo opcional');
    }
    if (schema['additionalProperties'] != false) {
      out.add('$path: additionalProperties precisa ser false');
    }
    for (final MapEntry(:key, :value) in props.entries) {
      out.addAll(codexSchemaProblems(value, '$path.$key'));
    }
  }
  if (schema['items'] case final items?) {
    out.addAll(codexSchemaProblems(items, '$path[]'));
  }
  for (final (i, s) in (schema['anyOf'] as List? ?? const []).indexed) {
    out.addAll(codexSchemaProblems(s, '$path|$i'));
  }
  return out;
}

bool _isObject(Map schema) {
  final t = schema['type'];
  return t == 'object' ||
      (t is List && t.contains('object')) ||
      (t == null && schema['properties'] is Map);
}

/// The strict variant of [schema] (R3): optional fields become required and
/// nullable, objects get `additionalProperties: false`, unknown keywords
/// leave. A schema already compatible comes back equal.
Map<String, Object?> codexCompatibleSchema(Map<String, Object?> schema) =>
    _compat(schema, optional: false) as Map<String, Object?>;

Object? _compat(Object? node, {required bool optional}) {
  if (node is! Map) return node;
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in node.entries) {
    if (!codexSchemaKeywords.contains(key)) continue;
    out['$key'] = value;
  }
  if (_isObject(node)) {
    final props = (node['properties'] as Map?) ?? const {};
    final required = {...(node['required'] as List? ?? const [])};
    out['properties'] = {
      for (final MapEntry(:key, :value) in props.entries)
        '$key': _compat(value, optional: !required.contains(key)),
    };
    out['required'] = [for (final k in props.keys) '$k'];
    out['additionalProperties'] = false;
  }
  if (out['items'] case final items?) {
    out['items'] = _compat(items, optional: false);
  }
  if (out['anyOf'] case final List any) {
    out['anyOf'] = [for (final s in any) _compat(s, optional: false)];
  }
  if (optional) return _nullable(out);
  return out;
}

Map<String, Object?> _nullable(Map<String, Object?> s) {
  final t = s['type'];
  if (t is String) {
    return {
      ...s,
      'type': [t, 'null'],
    };
  }
  if (t is List) {
    return {
      ...s,
      'type': t.contains('null') ? t : [...t, 'null'],
    };
  }
  if (s['anyOf'] case final List any) {
    return {
      ...s,
      'anyOf': [
        ...any,
        {'type': 'null'},
      ],
    };
  }
  return s;
}

/// [data] without the nulls the strict variant added for the optional
/// fields of [schema] (R3: the service treats the null as absent).
Object? stripAddedNulls(Object? data, Object? schema) {
  if (schema is! Map) return data;
  if (data is Map && _isObject(schema)) {
    final props = (schema['properties'] as Map?) ?? const {};
    final required = {...(schema['required'] as List? ?? const [])};
    return <String, Object?>{
      for (final MapEntry(:key, :value) in data.entries)
        if (!(value == null && !required.contains(key)))
          '$key': stripAddedNulls(value, props[key]),
    };
  }
  if (data is List && schema['items'] != null) {
    return [for (final v in data) stripAddedNulls(v, schema['items'])];
  }
  return data;
}

/// Why [data] does not match [schema] (null = it matches). Checks the
/// keywords of [codexSchemaKeywords] except `pattern` and `format`, which
/// the provider already enforces and the services re-check.
String? schemaMismatch(Object? data, Object? schema, [String path = r'$']) {
  if (schema is! Map) return null;
  final type = schema['type'];
  final types = type is String
      ? [type]
      : type is List
      ? [for (final t in type) '$t']
      : const <String>[];
  if (types.isNotEmpty && !types.any((t) => _hasType(data, t))) {
    return '$path deveria ser ${types.join(' ou ')}';
  }
  if (data == null) return null;
  if (schema['enum'] case final List values when !values.contains(data)) {
    return '$path fora das opções';
  }
  if (schema.containsKey('const') && schema['const'] != data) {
    return '$path diferente do esperado';
  }
  if (schema['anyOf'] case final List any) {
    if (!any.any((s) => schemaMismatch(data, s, path) == null)) {
      return '$path não casa com nenhuma alternativa';
    }
  }
  if (data is Map && _isObject(schema)) {
    final props = (schema['properties'] as Map?) ?? const {};
    for (final r in schema['required'] as List? ?? const []) {
      if (!data.containsKey(r)) return '$path.$r ausente';
    }
    if (schema['additionalProperties'] == false) {
      for (final k in data.keys) {
        if (!props.containsKey(k)) return '$path.$k não pedido';
      }
    }
    for (final MapEntry(:key, :value) in data.entries) {
      if (!props.containsKey(key)) continue;
      final why = schemaMismatch(value, props[key], '$path.$key');
      if (why != null) return why;
    }
  }
  if (data is List) {
    final min = schema['minItems'];
    final max = schema['maxItems'];
    if (min is int && data.length < min) return '$path com menos de $min itens';
    if (max is int && data.length > max) return '$path com mais de $max itens';
    if (schema['items'] case final items?) {
      for (final (i, v) in data.indexed) {
        final why = schemaMismatch(v, items, '$path[$i]');
        if (why != null) return why;
      }
    }
  }
  if (data is num) {
    final min = schema['minimum'];
    final max = schema['maximum'];
    if (min is num && data < min) return '$path abaixo de $min';
    if (max is num && data > max) return '$path acima de $max';
  }
  return null;
}

bool _hasType(Object? v, String t) => switch (t) {
  'object' => v is Map,
  'array' => v is List,
  'string' => v is String,
  'integer' => v is int || (v is double && v == v.roundToDouble()),
  'number' => v is num,
  'boolean' => v is bool,
  'null' => v == null,
  _ => true,
};
