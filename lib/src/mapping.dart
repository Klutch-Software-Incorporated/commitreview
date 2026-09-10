import 'git.dart';

/// Where a line ended up when carried from one commit to another.
class Mapped {
  /// The line in the target commit, or null if it is not present there.
  final int? line;

  /// The path in the target commit, different from the source path when the
  /// file was renamed between the two commits.
  final String file;

  /// True when the line survived but its content was edited.
  final bool changed;

  const Mapped(this.line, this.file, this.changed);

  bool get gone => line == null;
}

/// Character-bigram Dice coefficient. Used only to line up the two halves of
/// a single replaced run against each other, never to search for a line.
double _similar(String a, String b) {
  List<String> grams(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length < 2) return t.isEmpty ? const [] : [t];
    return [for (var i = 0; i + 1 < t.length; i++) t.substring(i, i + 2)];
  }

  final x = grams(a), y = grams(b);
  if (x.isEmpty || y.isEmpty) return 0;
  final pool = <String, int>{};
  for (final g in y) {
    pool[g] = (pool[g] ?? 0) + 1;
  }
  var hits = 0;
  for (final g in x) {
    if ((pool[g] ?? 0) > 0) {
      hits++;
      pool[g] = pool[g]! - 1;
    }
  }
  return 2 * hits / (x.length + y.length);
}

/// Best order-preserving alignment of a run's removed lines onto its added
/// lines. Returns, for each removed line, the index of the added line it
/// became, or null when nothing in the run corresponds to it.
///
/// Needed because git reports a rewritten block as a single "these N lines
/// became these M lines" and says nothing about which became which. Runs are
/// a handful of lines, so an exact dynamic program is cheap.
List<int?> _align(List<String> dels, List<String> adds) {
  final n = dels.length, m = adds.length;
  if (n == 0 || m == 0) return List<int?>.filled(n, null);

  // One line replaced by one line: there is nothing to disambiguate, so the
  // correspondence is certain no matter how different the text is.
  if (n == 1 && m == 1) return <int?>[0];

  final best = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      final pair = _similar(dels[i], adds[j]) + best[i + 1][j + 1];
      final skipDel = best[i + 1][j];
      final skipAdd = best[i][j + 1];
      best[i][j] = pair >= skipDel && pair >= skipAdd
          ? pair
          : (skipDel >= skipAdd ? skipDel : skipAdd);
    }
  }

  final out = List<int?>.filled(n, null);
  var i = 0, j = 0;
  while (i < n && j < m) {
    final pair = _similar(dels[i], adds[j]) + best[i + 1][j + 1];
    if (pair >= best[i + 1][j] && pair >= best[i][j + 1]) {
      // A rewritten line still resembles itself; anything below this is a
      // different line that happens to sit in the same run.
      if (_similar(dels[i], adds[j]) >= 0.25) out[i] = j;
      i++;
      j++;
    } else if (best[i + 1][j] >= best[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

class _Hunk {
  final int oldStart, oldCount, newStart, newCount;
  final List<String> dels, adds;
  List<int?>? _cached;

  _Hunk(this.oldStart, this.oldCount, this.newStart, this.newCount, this.dels,
      this.adds);

  /// A pure insertion is recorded as `@@ -16,0 +17,4 @@`, meaning "inserted
  /// after old line 16". Old line 16 itself is untouched, so the affected
  /// range starts one line later.
  int get rangeStart => oldCount == 0 ? oldStart + 1 : oldStart;

  List<int?> get alignment => _cached ??= _align(dels, adds);
}

/// Line mapping for one file between two commits.
class FileMap {
  final String newPath;
  final List<_Hunk> _hunks;

  FileMap(this.newPath, this._hunks);

  /// Carries [line] from the source commit to the target.
  ///
  /// Three cases:
  ///   * outside every hunk: shifted by the running offset, unchanged
  ///   * inside a replaced run: aligned onto the added line it became
  ///   * removed with nothing in the run corresponding to it: gone
  Mapped map(int line) {
    var delta = 0;
    for (final h in _hunks) {
      if (line < h.rangeStart) return Mapped(line + delta, newPath, false);

      if (h.oldCount > 0 && line < h.oldStart + h.oldCount) {
        final k = line - h.oldStart;
        // Prefer the alignment; positional is the fallback when the hunk
        // bodies were not available (e.g. a hand-written test fixture).
        final a = h.dels.length == h.oldCount ? h.alignment : const <int?>[];
        final j = k < a.length ? a[k] : (k < h.newCount ? k : null);
        if (j == null) return Mapped(null, newPath, false);
        return Mapped(h.newStart + j, newPath, true);
      }

      delta += h.newCount - h.oldCount;
    }
    return Mapped(line + delta, newPath, false);
  }
}

final _hunkRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');
final _pathRe = RegExp(r'^diff --git a/(.*) b/(.*)$');

/// Parses `git diff -U0 -M <a> <b>` into a per-file line mapping, keyed by the
/// path as it exists in [a].
Map<String, FileMap> parseDiffMaps(String diff) {
  final out = <String, FileMap>{};
  String? oldPath, newPath;
  var hunks = <_Hunk>[];

  void flush() {
    final from = oldPath;
    if (from != null) out[from] = FileMap(newPath ?? from, hunks);
    hunks = <_Hunk>[];
  }

  for (final l in diff.split('\n')) {
    final p = _pathRe.firstMatch(l);
    if (p != null) {
      flush();
      oldPath = p.group(1);
      newPath = p.group(2);
      continue;
    }
    // A rename with no content change carries the real destination here.
    if (l.startsWith('rename to ')) {
      newPath = l.substring('rename to '.length).trim();
      continue;
    }
    if (l.startsWith('+++ ')) {
      final t = l.substring(4).trim();
      if (t != '/dev/null') newPath = t.startsWith('b/') ? t.substring(2) : t;
      continue;
    }
    final m = _hunkRe.firstMatch(l);
    if (m != null) {
      hunks.add(_Hunk(
        int.parse(m.group(1)!),
        m.group(2) == null ? 1 : int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        m.group(4) == null ? 1 : int.parse(m.group(4)!),
        <String>[],
        <String>[],
      ));
      continue;
    }
    // Hunk bodies, needed to align a replaced run. With -U0 there are no
    // context lines, so everything inside a hunk is one or the other.
    if (hunks.isNotEmpty && l.isNotEmpty) {
      if (l.startsWith('-')) {
        hunks.last.dels.add(l.substring(1));
      } else if (l.startsWith('+')) {
        hunks.last.adds.add(l.substring(1));
      }
    }
  }
  flush();
  return out;
}

/// Line mappings for every file that differs between the two commits.
/// Files absent from the result are byte-identical, so their lines map to
/// themselves, so callers should treat a missing entry as "unchanged".
Map<String, FileMap> diffMaps(String repo, String fromSha, String toSha) {
  final raw = git(repo, [
    'diff',
    '--no-color',
    '--unified=0',
    '--find-renames',
    fromSha,
    toSha,
  ]);
  return raw == null ? {} : parseDiffMaps(raw);
}
