// Carrying a review comment from one commit to the next.
//
// This is the part of commitreview that is worth reusing on its own: given
// what git reports between two commits, work out where a line ended up. Git
// decides, so there is nothing to tune.
//
//   dart run example/main.dart

import 'package:commitreview/commitreview.dart';

void main() {
  report(
    'A doc comment inserted above an edited signature',
    // Git collapses this into "two old lines became three new ones" and says
    // nothing about which became which, so the run is aligned internally.
    '''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,2 +5,3 @@ import "fmt"
-func computeValue(a int, b int) int {
-\treturn a + b
+// Package-level doc comment added above.
+func computeValue(first int, second int) int {
+\treturn first + second
''',
    // A comment on the signature, and one on the body.
    [5, 6],
  );

  report(
    'Lines inserted well above the comment',
    '''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -1,0 +2,3 @@
+import "os"
+import "io"
+
''',
    [20],
  );

  report(
    'The commented line deleted outright',
    '''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,3 +4,0 @@
-\talpha()
-\tbeta()
-\tgamma()
''',
    [6],
  );

  report(
    'The file renamed underneath it',
    '''
diff --git a/main.go b/app.go
similarity index 98%
rename from main.go
rename to app.go
--- a/main.go
+++ b/app.go
@@ -5,0 +6,1 @@
+\tlogger.Init()
''',
    [12],
  );
}

void report(String title, String diff, List<int> lines) {
  print('$title:');
  final map = parseDiffMaps(diff.trimLeft())['main.go'];
  if (map == null) {
    print('  main.go is untouched between these commits, so nothing moves.\n');
    return;
  }
  for (final line in lines) {
    final to = map.map(line);
    print('  main.go:$line -> ${describe(to)}');
  }
  print('');
}

String describe(Mapped m) {
  if (m.gone) {
    return 'gone; the comment is kept against the patchset it was raised on';
  }
  final where = '${m.file}:${m.line}';
  return m.changed ? '$where, marked as an edited line' : where;
}
