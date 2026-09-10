# Example

## As a CLI

Set a repository up once, so your agent can take part:

```console
$ commitreview init
commitreview: added "commitreview" in /work/api/.mcp.json
commitreview: made /work/api/.review ignore itself
commitreview: installed the skill to ~/.claude/skills/commitreview/SKILL.md
```

Restart your agent so it picks up the skill and the MCP server, then open a
review of the latest commit:

```console
$ commitreview
review: http://127.0.0.1:4970  HEAD~1..a1b2c3d4  (216 diff lines)
review: patchset 1 a1b2c3d4 "Add rate limiting to the upload endpoint"
review: MCP endpoint http://127.0.0.1:4970/mcp
review: threads -> /work/api/.review/threads.json
```

Comment on the lines you care about in the browser, then tell your agent you
are done. It answers the questions you asked, commits the changes you wanted,
and calls `review_refresh`. The new commit becomes patchset 2, your comments
come with it, and your tab reloads itself.

To review a whole branch rather than one commit, name the base:

```console
$ commitreview main
```

## As a library

The diff handling is usable on its own. Carrying a comment from one commit to
the next is the interesting part: given `git diff -U0 -M <old> <new>`, it will
tell you where a line ended up, and it is git that decides, not a heuristic.

Run `dart run example/main.dart` to see it, or read on:

```dart
import 'package:commitreview/commitreview.dart';

void main() {
  // What git reports when a doc comment is inserted above a function whose
  // signature also changed: two old lines became three new ones.
  final maps = parseDiffMaps('''
diff --git a/main.go b/main.go
--- a/main.go
+++ b/main.go
@@ -5,2 +5,3 @@ import "fmt"
-func computeValue(a int, b int) int {
-\treturn a + b
+// Package-level doc comment added above.
+func computeValue(first int, second int) int {
+\treturn first + second
''');

  final file = maps['main.go']!;

  // A comment left on the signature, old line 5, belongs on line 6 now —
  // not on the doc comment that took its place.
  print(file.map(5).line); // 6
  print(file.map(5).changed); // true, the line was edited

  // And a line git reports as deleted is reported as gone, rather than
  // being attached to whatever happens to sit nearby.
  print(file.map(99).gone);
}
```
