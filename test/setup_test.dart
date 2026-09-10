import 'dart:convert';
import 'dart:io';

import 'package:commitreview/commitreview.dart';
import 'package:test/test.dart';

Map<String, dynamic> readJson(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

Map<String, dynamic> servers(String dir) =>
    (readJson('$dir/.mcp.json')['mcpServers'] as Map).cast<String, dynamic>();

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('setup_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('mcp config', () {
    test('creates the file when there is none', () {
      writeMcpConfig(dir.path, 4970);
      final s = servers(dir.path);
      expect(s.keys, ['commitreview']);
      expect((s['commitreview'] as Map)['url'], 'http://127.0.0.1:4970/mcp');
      expect((s['commitreview'] as Map)['type'], 'http');
    });

    test('records the port it was given', () {
      writeMcpConfig(dir.path, 4988);
      expect((servers(dir.path)['commitreview'] as Map)['url'],
          'http://127.0.0.1:4988/mcp');
    });

    test('keeps other servers already configured', () {
      // Overwriting someone's whole MCP config to add one entry would be a
      // bad trade, and is the kind of thing you only notice later.
      File('${dir.path}/.mcp.json').writeAsStringSync(jsonEncode({
        'mcpServers': {
          'postgres': {'command': 'pg-mcp'},
          'github': {'type': 'http', 'url': 'https://example.test'},
        },
      }));
      final msg = writeMcpConfig(dir.path, 4970);

      final s = servers(dir.path);
      expect(s.keys, containsAll(['postgres', 'github', 'commitreview']));
      expect((s['postgres'] as Map)['command'], 'pg-mcp');
      expect(msg, contains('kept 2 other servers'));
    });

    test('preserves unrelated top-level keys', () {
      File('${dir.path}/.mcp.json')
          .writeAsStringSync(jsonEncode({'somethingElse': 42}));
      writeMcpConfig(dir.path, 4970);
      expect(readJson('${dir.path}/.mcp.json')['somethingElse'], 42);
    });

    test('updates its own entry when the port changes', () {
      writeMcpConfig(dir.path, 4970);
      final msg = writeMcpConfig(dir.path, 4999);
      expect(msg, contains('updated'));
      expect((servers(dir.path)['commitreview'] as Map)['url'],
          'http://127.0.0.1:4999/mcp');
    });

    test('says so when nothing needed changing', () {
      writeMcpConfig(dir.path, 4970);
      expect(writeMcpConfig(dir.path, 4970), contains('already correct'));
    });

    test('refuses to clobber a file it cannot parse', () {
      final f = File('${dir.path}/.mcp.json')..writeAsStringSync('{ not json');
      final msg = writeMcpConfig(dir.path, 4970);
      expect(f.readAsStringSync(), '{ not json', reason: 'left untouched');
      expect(msg, contains('could not be parsed'));
      expect(msg, contains('commitreview'), reason: 'tells you what to add');
    });

    test('refuses a file that is valid json but not an object', () {
      final f = File('${dir.path}/.mcp.json')..writeAsStringSync('[1,2,3]');
      writeMcpConfig(dir.path, 4970);
      expect(f.readAsStringSync(), '[1,2,3]');
    });
  });

  group('review state ignore', () {
    test('makes the directory ignore itself', () {
      writeReviewIgnore(dir.path);
      expect(File('${dir.path}/.review/.gitignore').readAsStringSync().trim(),
          '*');
    });

    test('is a no-op the second time', () {
      writeReviewIgnore(dir.path);
      expect(writeReviewIgnore(dir.path), contains('already'));
    });
  });

  group('version', () {
    test('is reported, so two builds can be told apart', () {
      expect(version, isNotEmpty);
      expect(version, matches(r'^\d+\.\d+\.\d+'));
    });

    test('matches the pubspec', () {
      // A binary that reports a different version than it was built from is
      // exactly how "you are on 0.4.0" stopped meaning anything.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared =
          RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec)!;
      expect(version, declared.group(1)!.trim());
    });
  });
}
