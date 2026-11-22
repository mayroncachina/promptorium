import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/review/reviewer_provider.dart';

ReviewerConfig _c(String provider, {String? codexModel}) =>
    ReviewerConfig(enabled: true, provider: provider, codexModel: codexModel);

/// SPEC-102 R1–R4: the reviewer's provider and model.
void main() {
  group('resolução (R2)', () {
    test('execucao segue quem executou; sem sessões, o Claude', () {
      expect(
        resolveReviewerChoice(_c('execucao'), executedBy: 'codex').provider,
        'codex',
      );
      expect(
        resolveReviewerChoice(
          _c('execucao'),
          executedBy: executionProviderOf(const []),
        ).provider,
        'claude',
      );
      expect(executionProviderOf(const ['claude', 'claude']), 'claude');
      expect(executionProviderOf(const ['claude', 'codex']), 'codex');
      expect(
        resolveReviewerChoice(
          _c('execucao'),
          executedBy: 'codex',
        ).secondOpinion,
        isFalse,
      );
    });

    test('outro é o provedor que não executou: segunda opinião', () {
      final a = resolveReviewerChoice(_c('outro'), executedBy: 'claude');
      expect(a.provider, 'codex');
      expect(a.secondOpinion, isTrue);
      expect(a.fromConfig, isTrue);
      expect(
        resolveReviewerChoice(_c('outro'), executedBy: 'codex').provider,
        'claude',
      );
    });

    test('claude e codex fixam o provedor', () {
      expect(
        resolveReviewerChoice(_c('claude'), executedBy: 'codex').provider,
        'claude',
      );
      expect(
        resolveReviewerChoice(_c('codex'), executedBy: 'claude').provider,
        'codex',
      );
      expect(
        resolveReviewerChoice(_c('codex'), executedBy: 'codex').secondOpinion,
        isFalse,
      );
    });
  });

  group('Automático (R3)', () {
    test('sem provedor: explícito, vale a regra do plano (Claude)', () {
      final c = resolveReviewerChoice(
        _c('execucao'),
        executedBy: 'claude',
        auto: true,
      );
      expect(c.provider, 'claude');
      expect(c.fromPlan, isTrue);
      expect(c.fromConfig, isFalse);
    });

    test('provedor: explícito vence a regra do plano', () {
      for (final (p, want) in [
        ('codex', 'codex'),
        ('outro', 'codex'),
        ('claude', 'claude'),
      ]) {
        final c = resolveReviewerChoice(
          _c(p),
          executedBy: 'claude',
          auto: true,
        );
        expect(c.provider, want, reason: p);
        expect(c.fromPlan, isFalse);
        expect(c.fromConfig, isTrue);
      }
    });
  });

  group('modelo no Codex (R4)', () {
    test('modelo-codex > codex.model.reviewer > modelo do tipo', () {
      expect(
        reviewerCodexModel(_c('codex', codexModel: 'gpt-6.1-terra'), {
          codexReviewerModelKey: 'gpt-local',
        }),
        'gpt-6.1-terra',
      );
      expect(
        reviewerCodexModel(_c('codex'), {codexReviewerModelKey: 'gpt-local'}),
        'gpt-local',
      );
      expect(reviewerCodexModel(_c('codex'), const {}), isNull);
    });

    test('um alias do Claude nunca chega ao Codex', () {
      for (final alias in ['haiku', 'sonnet', 'opus', 'claude-haiku-4-5']) {
        expect(isClaudeModelAlias(alias), isTrue, reason: alias);
        expect(
          reviewerCodexModel(_c('codex', codexModel: alias), {
            codexReviewerModelKey: alias,
          }),
          isNull,
        );
      }
      expect(isClaudeModelAlias('gpt-6.1-terra'), isFalse);
    });

    test('modelo fora do catálogo em cache é pulado', () {
      final cache = CodexModelsCache(
        version: '0.170.0',
        readAt: DateTime(2026, 11, 20),
        models: const [],
      );
      expect(
        reviewerCodexModel(_c('codex', codexModel: 'sumiu'), {
          codexModelsCacheKey: cache.encode(),
        }),
        isNull,
      );
    });
  });

  test('autoria da rodada (R9)', () {
    expect(reviewerAuthorLabel(null, 'x'), isNull);
    expect(
      reviewerAuthorLabel('codex', 'gpt-6.1-terra', executedBy: 'codex'),
      'Codex gpt-6.1-terra',
    );
    expect(
      reviewerAuthorLabel('claude', 'haiku', executedBy: 'codex'),
      'Claude Code haiku · segunda opinião',
    );
    expect(reviewOnceLabel('codex'), 'Revisar com o Claude Code desta vez');
    expect(reviewOnceLabel('claude'), 'Revisar com o Codex desta vez');
  });
}
