import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';
import 'package:promptorium/features/mcp/mcp_screen.dart';
import 'package:promptorium/features/mcp/mcp_state.dart';

/// Ferramentas › Servidores MCP: the app's own server under "Da sessão",
/// read only (SPEC-052 R10).
void main() {
  test('with the server on, promptorium is a row with no config file and '
      'its seven tools', () {
    final rows = buildMcpRows(
      registry: const McpRegistrySnapshot([]),
      board: const McpStatusBoardState(),
      appServer: true,
    );
    final app = rows.single;
    expect(app.name, 'promptorium');
    expect(app.config, isNull);
    expect(isAppServerRow(app), isTrue);
    expect(app.tools, hasLength(7));
    expect(app.tools, contains('criar_spec'));
  });

  test('off, there is no row; seen in a run, it is not repeated', () {
    expect(
      buildMcpRows(
        registry: const McpRegistrySnapshot([]),
        board: const McpStatusBoardState(),
      ),
      isEmpty,
    );
    final rows = buildMcpRows(
      registry: const McpRegistrySnapshot([]),
      board: const McpStatusBoardState(),
      sessionTools: const ['mcp__promptorium__ler_spec'],
      appServer: true,
    );
    expect(rows.where((r) => r.name == 'promptorium'), hasLength(1));
  });
}
