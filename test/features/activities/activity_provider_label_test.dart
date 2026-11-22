import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/activities/widgets/activity_row.dart';

/// SPEC-101 R15: the line of the Atividades says who works on the spec.
void main() {
  Activity activity({String? provider, String? model}) => Activity(
    id: 'session:s1',
    workspaceId: 1,
    workspaceName: 'repo',
    kind: ActivityKind.spec,
    column: ActivityColumn.running,
    pose: ActivityPose.edit,
    title: 'SPEC-031 · Pagamento com Stripe',
    subtitle: 'Em execução',
    status: 'R2 de 3',
    provider: provider,
    model: model,
  );

  test('the Codex and its model go with the subtitle', () {
    expect(
      activitySubtitle(activity(provider: 'codex', model: 'gpt-6.1-terra')),
      'Em execução · Codex · gpt-6.1-terra',
    );
  });

  test('a Claude session keeps the subtitle as before', () {
    expect(
      activitySubtitle(activity(provider: 'claude', model: 'sonnet')),
      'Em execução',
    );
    expect(activitySubtitle(activity()), 'Em execução');
  });
}
