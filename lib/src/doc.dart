import 'dart:io';

import 'diff.dart';
import 'git.dart';
import 'html.dart';
import 'model.dart';
import 'target.dart';

/// The rendered diff for the current patchset, and everything derived from it.
///
/// Rebuilt whenever the head commit moves, which renumbers every raw line
/// index — that is why threads anchor to `(file, line)` and are located into
/// the render, rather than storing a diff offset.
class Doc {
  final Target target;
  final String forceView;

  List<String> lines = [];
  List<Meta> metas = [];
  String html = '';
  int version = 0;

  Doc(this.target, this.forceView);

  String get label => target.label;

  bool rebuild() {
    final raw =
        git(target.repo, ['diff', '--no-color', target.base, target.head.sha]);
    if (raw == null) {
      stderr.writeln('review: git diff ${target.base} ${target.head.sha} '
          'failed; keeping the previous diff.');
      return false;
    }
    final ls = raw.split('\n');
    if (ls.isNotEmpty && ls.last.isEmpty) ls.removeLast();
    lines = ls;
    metas = annotate(ls);
    html = buildHtml(ls, metas, label, forceView, ++version);
    return true;
  }

  /// Where [t] sits in the current render, or null when its line is not part
  /// of this diff at all — either it was dropped, or the code around it
  /// settled back to matching the base.
  int? locate(Thread t) {
    for (var i = 0; i < metas.length; i++) {
      final m = metas[i];
      if (m.file != t.file) continue;
      final n = t.side == 'old' ? m.oldLine : m.newLine;
      if (n == t.line) return i;
    }
    return null;
  }

  /// The `(file, side, line)` a raw diff index corresponds to, or null for
  /// structural rows like hunk headers, which carry no line number.
  ({String file, String side, int line})? coordsOf(int idx) {
    if (idx < 0 || idx >= metas.length) return null;
    final m = metas[idx];
    if (m.file == null) return null;
    if (m.newLine != null) {
      return (file: m.file!, side: 'new', line: m.newLine!);
    }
    if (m.oldLine != null) {
      return (file: m.file!, side: 'old', line: m.oldLine!);
    }
    return null;
  }
}
