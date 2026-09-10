import 'dart:convert';
import 'dart:io';

import 'package:commitreview/commitreview.dart';
import 'package:test/test.dart';

const _diff = '''
diff --git a/main.go b/main.go
index 0df7379..6a6a16a 100644
--- a/main.go
+++ b/main.go
@@ -1,3 +1,4 @@
 package main
+// a new line worth commenting on
 func main() {}
''';

/// A target with a hand-built patchset, so nothing here needs a repository.
Target targetAt(String sha) => Target('.', 'HEAD~1', 'base0')
  ..patchsets.add(Patchset(1, sha, 'a commit', '2026-01-01T00:00:00'));

Doc docFrom(String diff, {String sha = 'sha1'}) {
  final lines = diff.trimLeft().split('\n');
  final d = Doc(targetAt(sha), '');
  d.lines = lines;
  d.metas = annotate(lines);
  return d;
}

({Session session, Directory dir}) freshSession(String base) {
  final dir = Directory.systemTemp.createTempSync('review_test');
  return (session: Session(File('${dir.path}/threads.json'), base), dir: dir);
}

Map<String, dynamic> call(
    String tool, Map<String, dynamic> args, Session s, Doc doc) {
  final res = rpc({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {'name': tool, 'arguments': args},
  }, s, doc);
  return (res!['result'] as Map).cast<String, dynamic>();
}

String textOf(Map<String, dynamic> r) =>
    ((r['content'] as List).first as Map)['text'] as String;

void main() {
  group('json-rpc', () {
    late Doc doc;
    late Session s;
    late Directory dir;

    setUp(() {
      doc = docFrom(_diff);
      final f = freshSession('base0');
      s = f.session;
      dir = f.dir;
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('initialize echoes a supported protocol version', () {
      final res = rpc({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-03-26'},
      }, s, doc)!;
      final r = (res['result'] as Map).cast<String, dynamic>();
      expect(r['protocolVersion'], '2025-03-26');
      expect((r['capabilities'] as Map)['tools'], isNotNull);
    });

    test('initialize falls back for an unknown version', () {
      final res = rpc({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '1999-01-01'},
      }, s, doc)!;
      final r = (res['result'] as Map).cast<String, dynamic>();
      expect(protocolVersions, contains(r['protocolVersion']));
    });

    test('a notification gets no response at all', () {
      expect(
          rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'}, s,
              doc),
          isNull);
    });

    test('an unknown method is a method-not-found error', () {
      final res =
          rpc({'jsonrpc': '2.0', 'id': 7, 'method': 'resources/list'}, s, doc)!;
      expect((res['error'] as Map)['code'], -32601);
      expect(res['result'], isNull);
    });

    test('every advertised tool has a name, description and schema', () {
      final res =
          rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}, s, doc)!;
      final list = ((res['result'] as Map)['tools'] as List)
          .cast<Map<String, dynamic>>();
      expect(list.map((t) => t['name']),
          containsAll(['review_pending', 'review_reply', 'review_refresh']));
      for (final t in list) {
        expect(t['description'], isA<String>());
        expect((t['inputSchema'] as Map)['type'], 'object');
      }
    });

    test('review_refresh tells the agent to commit first', () {
      final list = (((rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
              s, doc)!['result'] as Map)['tools'] as List))
          .cast<Map<String, dynamic>>();
      final refresh = list.firstWhere((t) => t['name'] == 'review_refresh');
      expect(refresh['description'], contains('Commit your changes first'));
    });
  });

  group('review tools', () {
    late Doc doc;
    late Session s;
    late Directory dir;

    setUp(() {
      doc = docFrom(_diff);
      final f = freshSession('base0');
      s = f.session;
      dir = f.dir;
      final idx = doc.lines.indexOf('+// a new line worth commenting on');
      final c = doc.coordsOf(idx)!;
      final snap = snapshotAt(doc.lines, idx);
      s.create('sha1', c.file, c.side, c.line)
        ..snap = snap.snap
        ..snapAt = snap.at
        ..msgs.add(Msg('user', 'why is this here?', '2026-01-01T00:00:00'));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('pending reports the thread with its location and context', () {
      final md = textOf(call('review_pending', {}, s, doc));
      expect(md, contains('Thread 1'));
      expect(md, contains('main.go:'));
      expect(md, contains('why is this here?'));
      expect(md, contains('<<<<<< comment here'));
      expect(md, contains('NEW'));
      expect(md, contains('patchset 1'));
    });

    test('pending is idempotent', () {
      call('review_pending', {}, s, doc);
      expect(textOf(call('review_pending', {}, s, doc)),
          contains('No new review comments'));
    });

    test('a reply is recorded and clears the pending state', () {
      call('review_pending', {}, s, doc);
      call('review_reply', {'thread': 1, 'text': 'it guards the nil case'}, s,
          doc);
      expect(s.threads.single.msgs.last.role, 'ai');
      expect(textOf(call('review_pending', {}, s, doc)),
          contains('No new review comments'));
    });

    test('a follow-up flags only the unseen message', () {
      call('review_pending', {}, s, doc);
      call('review_resolve', {'thread': 1}, s, doc);
      s.threads.single
        ..resolved = false
        ..msgs.add(Msg('user', 'still unclear', '2026-01-01T00:01:00'));

      final md = textOf(call('review_pending', {}, s, doc));
      expect(md, contains('still unclear'));
      expect(md, contains('why is this here?'),
          reason: 'earlier messages stay for context');
      expect('NEW'.allMatches(md).length, 1);
    });

    test('replying to a missing thread is an error, not a crash', () {
      final r = call('review_reply', {'thread': 99, 'text': 'x'}, s, doc);
      expect(r['isError'], isTrue);
      expect(textOf(r), contains('No thread 99'));
    });

    test('an empty reply is rejected', () {
      expect(
          call('review_reply', {'thread': 1, 'text': '  '}, s, doc)['isError'],
          isTrue);
    });

    test('a thread that left the diff falls back to its frozen snapshot', () {
      // Simulate the line being deleted in a later patchset.
      s.threads.single
        ..notInLatest = true
        ..line = 999;
      final md = textOf(call('review_pending', {}, s, doc));
      expect(md, contains('no longer in the diff'));
      expect(md, contains('a new line worth commenting on'),
          reason: 'the snapshot still shows what was commented on');
    });

    test('a thread on an edited line says so', () {
      s.threads.single.changed = true;
      expect(textOf(call('review_pending', {}, s, doc)),
          contains('has been edited'));
    });
  });

  group('coordinates', () {
    test('an added line resolves to a new-side coordinate', () {
      final doc = docFrom(_diff);
      final idx = doc.lines.indexOf('+// a new line worth commenting on');
      final c = doc.coordsOf(idx)!;
      expect(c.file, 'main.go');
      expect(c.side, 'new');
      expect(c.line, greaterThan(0));
    });

    test('a removed line resolves to an old-side coordinate', () {
      final doc = docFrom('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -1,2 +1,1 @@
 package main
-func gone() {}
''');
      final c = doc.coordsOf(doc.lines.indexOf('-func gone() {}'))!;
      expect(c.side, 'old');
    });

    test('structural rows cannot be commented on', () {
      final doc = docFrom(_diff);
      for (final l in ['@@ -1,3 +1,4 @@', 'diff --git a/main.go b/main.go']) {
        final i = doc.lines.indexWhere((x) => x.startsWith(l.split(' ').first));
        expect(doc.coordsOf(i), isNull, reason: l);
      }
    });

    test('a thread is located back to the row it was raised on', () {
      final doc = docFrom(_diff);
      final idx = doc.lines.indexOf('+// a new line worth commenting on');
      final c = doc.coordsOf(idx)!;
      final t = Thread(1, 'sha1', c.file, c.side, c.line);
      expect(doc.locate(t), idx);
    });

    test('a thread whose line is not in this diff locates to nothing', () {
      final doc = docFrom(_diff);
      expect(doc.locate(Thread(1, 'sha1', 'main.go', 'new', 9999)), isNull);
    });
  });

  group('persistence', () {
    test('threads survive a save/load round trip', () {
      final doc = docFrom(_diff);
      final f = freshSession('base0');
      f.session.target = doc.target;
      final idx = doc.lines.indexOf('+// a new line worth commenting on');
      final c = doc.coordsOf(idx)!;
      f.session.create('sha1', c.file, c.side, c.line)
        ..resolved = true
        ..changed = true
        ..msgs.add(Msg('user', 'persist me', '2026-01-01T00:00:00'));
      f.session.save();

      final reloaded = Session(f.session.store, 'base0')..load();
      expect(reloaded.threads, hasLength(1));
      final r = reloaded.threads.single;
      expect(r.msgs.single.text, 'persist me');
      expect(r.resolved, isTrue);
      expect(r.changed, isTrue);
      expect(r.file, 'main.go');
      expect(r.line, c.line);
      expect(r.raisedOn, 'sha1');
      expect(reloaded.nextId, greaterThan(r.id));

      f.dir.deleteSync(recursive: true);
    });

    test('a review of a different base is not loaded into this one', () {
      final f = freshSession('base0');
      f.session
          .create('sha1', 'main.go', 'new', 2)
          .msgs
          .add(Msg('user', 'x', '2026-01-01T00:00:00'));
      f.session.save();

      final other = Session(f.session.store, 'someOtherBase')..load();
      expect(other.threads, isEmpty);

      f.dir.deleteSync(recursive: true);
    });

    test('a corrupt threads file starts fresh instead of throwing', () {
      final dir = Directory.systemTemp.createTempSync('review_test');
      final file = File('${dir.path}/threads.json')..writeAsStringSync('{ not');
      final s = Session(file, 'base0');
      expect(() => s.load(), returnsNormally);
      expect(s.threads, isEmpty);
      dir.deleteSync(recursive: true);
    });

    test('a resumed review keeps the base it was started against', () {
      // The default base is HEAD~1, which moves as commits land. Re-resolving
      // it on restart would silently start a new review and orphan every
      // comment, so a saved target has to win.
      final saved = {
        'baseLabel': 'HEAD~1',
        'base': 'theOriginalBase',
        'patchsets': [
          {'n': 1, 'sha': 'sha1', 'subject': 'first', 'at': ''},
        ],
      };
      final t = Target.resolveFor('.', null, saved: saved);
      expect(t, isNotNull);
      expect(t!.base, 'theOriginalBase');
      expect(t.patchsets.first.sha, 'sha1');
    });

    test('naming a different base deliberately starts a new review', () {
      final saved = {
        'baseLabel': 'HEAD~1',
        'base': 'theOriginalBase',
        'patchsets': <Map<String, dynamic>>[],
      };
      // 'main' is not the saved label, so the saved review must not be reused.
      final t = Target.resolveFor('.', 'main', saved: saved);
      expect(t?.base, isNot('theOriginalBase'));
    });

    test('patchset history is persisted alongside the threads', () {
      final doc = docFrom(_diff);
      final f = freshSession('base0');
      f.session.target = doc.target;
      f.session.create('sha1', 'main.go', 'new', 2);
      f.session.save();

      final j = jsonDecode(f.session.store.readAsStringSync())
          as Map<String, dynamic>;
      expect(j['base'], 'base0');
      final t = (j['target'] as Map).cast<String, dynamic>();
      expect((t['patchsets'] as List), hasLength(1));
      expect(t['base'], 'base0');

      f.dir.deleteSync(recursive: true);
    });
  });
}
