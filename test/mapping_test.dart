import 'package:commitreview/commitreview.dart';
import 'package:test/test.dart';

FileMap mapFor(String diff, [String path = 'main.go']) =>
    parseDiffMaps(diff.trimLeft())[path]!;

void main() {
  group('lines outside any hunk', () {
    final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -10,0 +11,3 @@ func main() {
+one
+two
+three
''');

    test('a line above the change does not move', () {
      expect(m.map(10).line, 10);
      expect(m.map(10).changed, isFalse);
    });

    test('a line below the change shifts by the insert size', () {
      expect(m.map(11).line, 14);
      expect(m.map(50).line, 53);
    });

    test('an insertion after line N leaves line N alone', () {
      // `@@ -10,0 +11,3 @@` means "inserted after old line 10", so 10 itself
      // is untouched. Getting this wrong shifts every anchor by one.
      expect(m.map(10).line, 10);
    });
  });

  group('deletions', () {
    final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,3 +4,0 @@ func main() {
-gone one
-gone two
-gone three
''');

    test('a deleted line is reported as gone, not relocated', () {
      for (final l in [5, 6, 7]) {
        expect(m.map(l).gone, isTrue, reason: 'line $l was deleted');
      }
    });

    test('lines after a deletion shift up', () {
      expect(m.map(8).line, 5);
    });

    test('lines before a deletion are untouched', () {
      expect(m.map(4).line, 4);
    });
  });

  group('edits', () {
    test('a modified line maps to its new version and is flagged', () {
      // The shape git actually emits for a one-line edit that grows to two.
      final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -20 +24,2 @@ func main() {
-	mux.Handle("/storage/", handler.Storage(st))
+	mux.Handle("/storage/", handler.RequireBearer(handler.Storage(st)))
+	mux.Handle("/.well-known/webfinger", handler.WebFinger(base))
''');
      final r = m.map(20);
      expect(r.line, 24);
      expect(r.changed, isTrue);
      expect(r.gone, isFalse);
    });

    test('a run maps line for line when each has a counterpart', () {
      final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,3 +5,3 @@ func main() {
-	alpha := computeOne(x)
-	beta := computeTwo(y)
-	gamma := computeThree(z)
+	alpha := computeOne(x, opts)
+	beta := computeTwo(y, opts)
+	gamma := computeThree(z, opts)
''');
      expect(m.map(5).line, 5);
      expect(m.map(6).line, 6);
      expect(m.map(7).line, 7);
      expect(m.map(6).changed, isTrue);
    });

    test('a line with no counterpart in a shrunken run is gone', () {
      final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,3 +5,1 @@ func main() {
-	alpha := computeOne(x)
-	beta := computeTwo(y)
-	gamma := computeThree(z)
+	alpha := computeOne(x, opts)
''');
      expect(m.map(5).line, 5);
      expect(m.map(5).changed, isTrue);
      expect(m.map(6).gone, isTrue);
      expect(m.map(7).gone, isTrue);
    });

    test('an inserted line inside a run does not shift its neighbours', () {
      // The case git cannot express: two lines became three, with the new one
      // first. Positional mapping would put every comment one line early.
      final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,2 +5,3 @@ import "fmt"
-func computeValue(a int, b int) int {
-	return a + b
+// Package-level doc comment added above.
+func computeValue(first int, second int) int {
+	return first + second
''');
      expect(m.map(5).line, 6, reason: 'the signature, not the doc comment');
      expect(m.map(6).line, 7, reason: 'the return line');
      expect(m.map(5).changed, isTrue);
    });
  });

  group('several hunks', () {
    final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -3,0 +4,2 @@ func main() {
+added
+added
@@ -10,2 +12,0 @@ func main() {
-removed
-removed
@@ -20 +20,1 @@ func main() {
-old
+new
''');

    test('offsets accumulate across hunks', () {
      expect(m.map(3).line, 3);
      expect(m.map(4).line, 6);
      expect(m.map(9).line, 11);
    });

    test('a deletion in a later hunk still resolves correctly', () {
      expect(m.map(10).gone, isTrue);
      expect(m.map(11).gone, isTrue);
      expect(m.map(12).line, 12);
    });

    test('an edit after both offsets lands on the right line', () {
      expect(m.map(20).line, 20);
      expect(m.map(20).changed, isTrue);
    });
  });

  group('renames', () {
    test('the destination path is carried through a pure rename', () {
      final maps = parseDiffMaps('''
diff --git a/old.go b/new.go
similarity index 100%
rename from old.go
rename to new.go
'''
          .trimLeft());
      final m = maps['old.go']!;
      expect(m.newPath, 'new.go');
      expect(m.map(42).line, 42, reason: 'content did not move');
    });

    test('a rename with edits maps both path and line', () {
      final maps = parseDiffMaps('''
diff --git a/old.go b/new.go
similarity index 90%
rename from old.go
rename to new.go
--- a/old.go
+++ b/new.go
@@ -5,0 +6,2 @@ func main() {
+one
+two
'''
          .trimLeft());
      final m = maps['old.go']!;
      expect(m.newPath, 'new.go');
      expect(m.map(9).line, 11);
    });
  });

  group('parsing', () {
    test('a hunk header with no count means one line', () {
      final m = mapFor('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -7 +7 @@ func main() {
-old
+new
''');
      expect(m.map(7).line, 7);
      expect(m.map(7).changed, isTrue);
      expect(m.map(8).line, 8);
    });

    test('several files each get their own map', () {
      final maps = parseDiffMaps('''
diff --git a/a.go b/a.go
--- a/a.go
+++ b/a.go
@@ -1,0 +2,1 @@
+x
diff --git a/b.go b/b.go
--- a/b.go
+++ b/b.go
@@ -5,1 +5,0 @@
-y
'''
          .trimLeft());
      expect(maps.keys, containsAll(['a.go', 'b.go']));
      expect(maps['a.go']!.map(1).line, 1);
      expect(maps['a.go']!.map(2).line, 3);
      expect(maps['b.go']!.map(5).gone, isTrue);
    });

    test('an empty diff produces no maps, meaning nothing moved', () {
      expect(parseDiffMaps(''), isEmpty);
    });
  });
}
