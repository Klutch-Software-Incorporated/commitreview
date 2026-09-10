import 'diff.dart';

/// Inclusive `[lo, hi]` window of [n] lines either side of [i], never crossing
/// into an adjacent file's diff.
List<int> ctxWindow(List<String> lines, int i, int n) {
  var lo = i, hi = i;
  while (lo > 0 && i - lo < n && !lines[lo - 1].startsWith('diff --git')) {
    lo--;
  }
  while (hi < lines.length - 1 &&
      hi - i < n &&
      !lines[hi + 1].startsWith('diff --git')) {
    hi++;
  }
  return [lo, hi];
}

/// A slice of diff around [i], with the anchor line called out. Used both for
/// what the agent reads and for the snapshot frozen onto a thread.
({List<String> snap, int at}) snapshotAt(List<String> lines, int i) {
  final w = ctxWindow(lines, i, 4);
  return (snap: lines.sublist(w[0], w[1] + 1), at: i - w[0]);
}

/// Where a diff line lands in real source, for humans.
String whereOf(Meta m) => m.newLine != null
    ? '${m.file}:${m.newLine}'
    : m.oldLine != null
        ? '${m.file}:${m.oldLine} (removed line)'
        : m.file ?? 'diff';
