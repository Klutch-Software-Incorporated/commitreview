import 'dart:convert';
import 'dart:io';

import 'package:commitreview/commitreview.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('port_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('reading the port back out of .mcp.json', () {
    // A repository's MCP config is per-repository but a port is machine-wide.
    // If the server does not bind what the config promised, the agent's tools
    // reach a different server, and a reply lands on the wrong repository.
    test('finds the port this repository was configured with', () {
      writeMcpConfig(dir.path, 4983);
      expect(portFromMcpConfig(dir.path), 4983);
    });

    test('finds it alongside other servers', () {
      File('${dir.path}/.mcp.json').writeAsStringSync(jsonEncode({
        'mcpServers': {
          'github': {'type': 'http', 'url': 'https://example.test/mcp'},
          'commitreview': {'type': 'http', 'url': 'http://127.0.0.1:4991/mcp'},
        },
      }));
      expect(portFromMcpConfig(dir.path), 4991);
    });

    test('is null when there is no config at all', () {
      expect(portFromMcpConfig(dir.path), isNull);
    });

    test('is null when the config has no entry for us', () {
      File('${dir.path}/.mcp.json').writeAsStringSync(jsonEncode({
        'mcpServers': {
          'postgres': {'command': 'pg-mcp'},
        },
      }));
      expect(portFromMcpConfig(dir.path), isNull);
    });

    test('survives a malformed config without throwing', () {
      for (final junk in ['{ not json', '[]', '{"mcpServers":3}', '']) {
        File('${dir.path}/.mcp.json').writeAsStringSync(junk);
        expect(() => portFromMcpConfig(dir.path), returnsNormally,
            reason: junk);
        expect(portFromMcpConfig(dir.path), isNull, reason: junk);
      }
    });

    test('survives an entry with no usable url', () {
      File('${dir.path}/.mcp.json').writeAsStringSync(jsonEncode({
        'mcpServers': {
          'commitreview': {'type': 'http'},
        },
      }));
      expect(portFromMcpConfig(dir.path), isNull);
    });

    test('round-trips whatever writeMcpConfig recorded', () {
      for (final p in [4970, 4971, 5009]) {
        writeMcpConfig(dir.path, p);
        expect(portFromMcpConfig(dir.path), p);
      }
    });
  });

  group('choosing a free port', () {
    test('takes the first port when nothing is listening', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final busy = s.port;
      await s.close();
      expect(await freePort(busy), busy);
    });

    test('skips a port that is already in use', () async {
      final held = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final chosen = await freePort(held.port);
      expect(chosen, isNot(held.port));
      expect(chosen, greaterThan(held.port));
      await held.close();
    });
  });
}
