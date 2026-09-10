import 'package:commitreview/commitreview.dart';
import 'package:test/test.dart';

Map<String, FileMap> maps(String diff) => parseDiffMaps(diff.trimLeft());

Thread threadAt(String file, int line, {String side = 'new', int id = 1}) =>
    Thread(id, 'sha1', file, side, line)
      ..msgs.add(Msg('user', 'a comment', '2026-01-01T00:00:00'));

/// What happened to a thread after being carried forward.
String stateOf(Thread t) => t.notInLatest
    ? 'gone'
    : t.changed
        ? 'changed'
        : 'clean';

void main() {
  group('carrying threads to the next patchset', () {
    test('a thread below an insertion follows its line down', () {
      final t = threadAt('main.go', 20);
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,0 +6,3 @@ func main() {
+one
+two
+three
'''));
      expect(t.line, 23);
      expect(stateOf(t), 'clean');
    });

    test('a thread above an insertion does not move', () {
      final t = threadAt('main.go', 3);
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,0 +6,3 @@ func main() {
+one
+two
+three
'''));
      expect(t.line, 3);
      expect(stateOf(t), 'clean');
    });

    test('an edited line keeps its comment, flagged as changed', () {
      // The case that used to send threads to the outdated bin.
      final t = threadAt('main.go', 20);
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -20 +20,1 @@ func main() {
-	mux.Handle("/storage/", handler.Storage(st))
+	mux.Handle("/storage/", handler.RequireBearer(handler.Storage(st)))
'''));
      expect(t.line, 20);
      expect(stateOf(t), 'changed');
      expect(t.notInLatest, isFalse);
    });

    test('a deleted line is reported gone, not relocated onto a neighbour', () {
      final t = threadAt('main.go', 6);
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,3 +4,0 @@ func main() {
-a
-b
-c
'''));
      expect(stateOf(t), 'gone');
    });

    test('a thread in an untouched file is left alone', () {
      final t = threadAt('other.go', 42);
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,0 +6,1 @@ func main() {
+x
'''));
      expect(t.line, 42);
      expect(t.file, 'other.go');
      expect(stateOf(t), 'clean');
    });

    test('a base-side thread never moves, because the base is pinned', () {
      final t = threadAt('main.go', 5, side: 'old');
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -1,0 +2,9 @@ func main() {
+lots
+and
+lots
+of
+new
+lines
+added
+up
+top
'''));
      expect(t.line, 5, reason: 'old-side anchors point into the fixed base');
      expect(stateOf(t), 'clean');
    });

    test('a thread follows its file through a rename', () {
      final t = threadAt('old.go', 9);
      carry([t], maps('''
diff --git a/old.go b/new.go
similarity index 90%
rename from old.go
rename to new.go
--- a/old.go
+++ b/new.go
@@ -5,0 +6,2 @@ func main() {
+one
+two
'''));
      expect(t.file, 'new.go');
      expect(t.line, 11);
    });

    test('a thread already gone stays gone and is not re-mapped', () {
      final t = threadAt('main.go', 6)..notInLatest = true;
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,0 +6,3 @@ func main() {
+one
+two
+three
'''));
      expect(t.line, 6, reason: 'left untouched');
      expect(t.notInLatest, isTrue);
    });

    test('changed stays sticky across a later clean patchset', () {
      final t = threadAt('main.go', 20);
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -20 +20,1 @@ func main() {
-old
+new
'''));
      expect(t.changed, isTrue);
      carry([t], maps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -1,0 +2,1 @@ func main() {
+unrelated
'''));
      expect(t.line, 21);
      expect(t.changed, isTrue, reason: 'the line is still an edited one');
    });

    test('several threads across several files are all carried', () {
      final a = threadAt('a.go', 10, id: 1);
      final b = threadAt('b.go', 5, id: 2);
      final c = threadAt('a.go', 30, id: 3);
      final summary = carry([a, b, c], maps('''
diff --git a/a.go b/a.go
--- a/a.go
+++ b/a.go
@@ -1,0 +2,2 @@
+x
+y
diff --git a/b.go b/b.go
--- a/b.go
+++ b/b.go
@@ -5,1 +5,0 @@
-gone
'''));
      expect(a.line, 12);
      expect(c.line, 32);
      expect(stateOf(b), 'gone');
      expect(summary, contains('3 thread(s)'));
      expect(summary, contains('2 moved'));
      expect(summary, contains('1 no longer in the diff'));
    });
  });
}
