/// `get_context_usage` control request of the CLI (SPEC-087; verified on
/// CLI 2.1.329, docs/pesquisa/contexto-e-compactacao.md).
///
/// `detail: summary` answers from the last call's `usage` and local
/// estimates: no model turn, no token-count call. The answer is turned into
/// a small app event ([contextUsageType]) before it reaches the timeline or
/// the database: only numbers and category names, never skill paths or file
/// content.
library;

/// App event with the sanitized answer.
const contextUsageType = 'promptorium_context_usage';

/// Prefix of the app's `get_context_usage` request ids.
const contextUsageRequestPrefix = 'promptorium-ctx-';

/// The control request line.
Map<String, dynamic> contextUsageRequest(String requestId) => {
  'type': 'control_request',
  'request_id': requestId,
  'request': {'subtype': 'get_context_usage', 'detail': 'summary'},
};

/// `{"type":"promptorium_context_usage","v":1,"total":…,"max":…,
/// "threshold":…,"enabled":…,"source":…,"model":…,"measured":bool,
/// "categories":[{id,name,tokens,kind}],"at":…}`, or null when [response]
/// is not a `get_context_usage` answer.
Map<String, dynamic>? contextUsageEvent(
  Map<String, dynamic> response, {
  DateTime? at,
}) {
  final total = response['totalTokens'];
  if (total is! num) return null;
  int? n(Object? v) => v is num ? v.toInt() : null;
  final model = response['model'];
  final source = response['autocompactSource'];
  final enabled = response['isAutoCompactEnabled'];
  return {
    'type': contextUsageType,
    'v': 1,
    'total': total.toInt(),
    'max': n(response['maxTokens']),
    'threshold': n(response['autoCompactThreshold']),
    'enabled': enabled is bool ? enabled : null,
    'source': source is String ? source : null,
    'model': model is String ? model : null,
    // `apiUsage` null = the total is a local estimate (after compacting).
    'measured': response['apiUsage'] is Map,
    'categories': [
      for (final c in (response['categories'] as List?) ?? const [])
        if (c is Map && c['tokens'] is num)
          {
            'id': '${c['id'] ?? ''}',
            'name': '${c['name'] ?? ''}',
            'tokens': (c['tokens'] as num).toInt(),
            'kind': '${c['kind'] ?? 'used'}',
          },
    ],
    'at': (at ?? DateTime.now()).toIso8601String(),
  };
}
