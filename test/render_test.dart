import 'package:commitreview/commitreview.dart';
import 'package:test/test.dart';

const _diff = '''
diff --git a/internal/store/sqlite.go b/internal/store/sqlite.go
index 1111111..2222222 100644
--- a/internal/store/sqlite.go
+++ b/internal/store/sqlite.go
@@ -1,4 +1,5 @@
 package store
-func Get() {}
+func Get(id string) {}
+func Put() {}
diff --git a/internal/handler/auth.go b/internal/handler/auth.go
index 3333333..4444444 100644
--- a/internal/handler/auth.go
+++ b/internal/handler/auth.go
@@ -1,2 +1,2 @@
 package handler
+// added
''';

List<String> lines(String s) => s.trimLeft().split('\n');

Iterable<String> indicesIn(String html) =>
    RegExp(r'data-i="(\d+)"').allMatches(html).map((m) => m.group(1)!);

void main() {
  group('file collection', () {
    test('finds each file with its add/delete counts', () {
      final ls = lines(_diff);
      final files = collectFiles(ls, annotate(ls));
      expect(files.map((f) => f.path),
          ['internal/store/sqlite.go', 'internal/handler/auth.go']);
      expect(files[0].adds, 2);
      expect(files[0].dels, 1);
      expect(files[1].adds, 1);
      expect(files[1].dels, 0);
    });

    test('file ranges cover the diff without overlapping', () {
      final ls = lines(_diff);
      final files = collectFiles(ls, annotate(ls));
      for (var i = 1; i < files.length; i++) {
        expect(files[i].from, greaterThan(files[i - 1].to));
      }
      expect(files.last.to, ls.length - 1);
    });
  });

  group('tree', () {
    test('collapses single-child directory chains into one row', () {
      final ls = lines(_diff);
      final html = renderTree(treeModel(collectFiles(ls, annotate(ls))));
      expect(html, contains('internal/store'));
      expect(html, contains('internal/handler'));
      expect(html, contains('sqlite.go'));
    });

    test('each file row carries the range the sidebar counts against', () {
      final ls = lines(_diff);
      final files = collectFiles(ls, annotate(ls));
      final html = renderTree(treeModel(files));
      for (final f in files) {
        expect(html, contains('data-from="${f.from}"'));
      }
    });
  });

  group('buildHtml', () {
    test('both views anchor to the same raw indices', () {
      final ls = lines(_diff);
      final html = buildHtml(ls, annotate(ls), 'HEAD', '', 1);
      final uni = html.substring(
          html.indexOf('<div id="uni">'), html.indexOf('<div id="spl">'));
      final spl = html.substring(
          html.indexOf('<div id="spl">'), html.indexOf('</main>'));
      // Split view renders context lines twice, so compare the sets: what
      // matters is that a comment index means the same line in either view.
      expect(indicesIn(spl).toSet(), indicesIn(uni).toSet());
    });

    test('every file becomes one collapsible section in each view', () {
      final ls = lines(_diff);
      final html = buildHtml(ls, annotate(ls), 'HEAD', '', 1);
      final uni = html.substring(
          html.indexOf('<div id="uni">'), html.indexOf('<div id="spl">'));
      final spl = html.substring(
          html.indexOf('<div id="spl">'), html.indexOf('</main>'));
      final sections = RegExp(r'<section class="fs" data-f="(\d+)"');
      expect(sections.allMatches(uni).map((m) => m.group(1)), ['0', '1']);
      expect(sections.allMatches(spl).map((m) => m.group(1)), ['0', '1']);
    });

    test('a diff containing the template placeholders does not corrupt it', () {
      // This is a real failure: the tool is checked into the repo it reviews,
      // so its own source -- which contains these tokens -- lands in the diff.
      // Substituting one at a time re-scanned already-injected content and
      // spliced the whole split view in at every occurrence.
      final ls = lines('''
diff --git a/review.dart b/review.dart
index 5555555..6666666 100644
--- a/review.dart
+++ b/review.dart
@@ -1,2 +1,3 @@
 const t = 1;
+// __SPLIT__ __UNIFIED__ __TREE__ __TARGET__ __VERSION__
''');
      final html = buildHtml(ls, annotate(ls), 'HEAD', '', 1);
      expect(RegExp(r'<section class="fs"').allMatches(html), hasLength(2),
          reason: 'one section per file per view, and only one file here');
      expect(html, contains('__SPLIT__'),
          reason: 'the token survives as escaped diff text');
    });

    test('the page carries the version the client compares against', () {
      final ls = lines(_diff);
      expect(buildHtml(ls, annotate(ls), 'HEAD', '', 42),
          contains('const VERSION = 42;'));
    });

    test('diff content is escaped, not injected as markup', () {
      final ls = lines('''
diff --git a/x.html b/x.html
index 7777777..8888888 100644
--- a/x.html
+++ b/x.html
@@ -1 +1,2 @@
 hi
+<script>alert(1)</script>
''');
      final html = buildHtml(ls, annotate(ls), 'HEAD', '', 1);
      expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
      expect(html, isNot(contains('<script>alert(1)</script>')));
    });

    test('the requested starting view is handed to the page', () {
      final ls = lines(_diff);
      expect(buildHtml(ls, annotate(ls), 'HEAD', 'spl', 1),
          contains("let start = 'spl'"));
    });
  });

  group('line classification', () {
    test('separates additions, deletions, hunks and headers', () {
      expect(cls('+added'), 'a');
      expect(cls('-removed'), 'd');
      expect(cls(' context'), 'c');
      expect(cls('@@ -1 +1 @@'), 'k');
      expect(cls('diff --git a/x b/x'), 'h');
      expect(cls('+++ b/x'), 'h');
      expect(cls('index abc..def'), 'h');
    });

    test('structural rows carry no line number, so they cannot be commented on',
        () {
      final ls = lines(_diff);
      final metas = annotate(ls);
      for (var i = 0; i < ls.length; i++) {
        if (cls(ls[i]) == 'h' || cls(ls[i]) == 'k') {
          expect(metas[i].oldLine, isNull, reason: ls[i]);
          expect(metas[i].newLine, isNull, reason: ls[i]);
        }
      }
    });
  });
}
