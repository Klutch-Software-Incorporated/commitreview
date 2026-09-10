/// Diff parsing and HTML rendering. Deliberately not a real unified-diff
/// parser: it walks the raw `git diff` output once, and every comment
/// anchors to a raw line index so both views stay in agreement.
library;

/// Per-diff-line bookkeeping: which file the line belongs to and what line
/// number it is on each side. Absent for headers. This is ~20 lines instead of
/// a real unified-diff parser, and degrades to null rather than failing.
class Meta {
  String? file;
  int? oldLine;
  int? newLine;
  Meta(this.file, this.oldLine, this.newLine);
}

/// Walk the diff once, tracking the current file and hunk line counters.
///
/// `---` and `+++` are only file headers *before* the first hunk of a file.
/// Inside a hunk they are ordinary content: deleting a line that reads
/// `-- note` produces `--- note`, which must count as a removed line, not be
/// mistaken for a header.
List<Meta> annotate(List<String> lines) {
  final out = <Meta>[];
  String? file;
  var oldNo = 0, newNo = 0;
  var inHunk = false;

  for (final l in lines) {
    if (l.startsWith('diff --git ')) {
      // "diff --git a/x b/y" — take the b-side as the current file.
      final m = RegExp(r' b/(.*)$').firstMatch(l);
      if (m != null) file = m.group(1);
      inHunk = false;
      out.add(Meta(file, null, null));
    } else if (!inHunk && l.startsWith('+++ ')) {
      final p = l.substring(4).trim();
      if (p != '/dev/null') file = p.startsWith('b/') ? p.substring(2) : p;
      out.add(Meta(file, null, null));
    } else if (!inHunk && l.startsWith('--- ')) {
      out.add(Meta(file, null, null));
    } else if (l.startsWith('@@')) {
      inHunk = true;
      final m =
          RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(l);
      if (m != null) {
        oldNo = int.parse(m.group(1)!);
        newNo = int.parse(m.group(2)!);
      }
      out.add(Meta(file, null, null));
    } else if (l.startsWith('+')) {
      out.add(Meta(file, null, newNo++));
    } else if (l.startsWith('-')) {
      out.add(Meta(file, oldNo++, null));
    } else if (l.startsWith(' ')) {
      out.add(Meta(file, oldNo++, newNo++));
    } else {
      out.add(Meta(file, null, null));
    }
  }
  return out;
}

String esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String cls(String l) {
  if (l.startsWith('@@')) return 'k';
  if (l.startsWith('+++') ||
      l.startsWith('---') ||
      l.startsWith('diff --git') ||
      l.startsWith('index ') ||
      l.startsWith('new file') ||
      l.startsWith('deleted file') ||
      l.startsWith('similarity ') ||
      l.startsWith('rename ')) {
    return 'h';
  }
  if (l.startsWith('+')) return 'a';
  if (l.startsWith('-')) return 'd';
  return 'c';
}

bool _isChange(String l) =>
    (l.startsWith('+') || l.startsWith('-')) &&
    !l.startsWith('+++') &&
    !l.startsWith('---');

/// One diff line as a clickable cell. `data-i` is always the index into the
/// raw diff, in both views — that is what keeps comment anchoring identical.
String cell(List<String> lines, List<Meta> metas, int i, bool rightSide) {
  final m = metas[i];
  final n = rightSide ? (m.newLine ?? m.oldLine) : (m.oldLine ?? m.newLine);
  return '<div class="c l ${cls(lines[i])}" data-i="$i">'
      '<span class="ln">${n ?? ''}</span>'
      '<span class="t">${esc(lines[i])}</span></div>';
}

/// One file in the diff, plus the raw-index range its lines occupy — the
/// range is what lets the sidebar count comments per file.
class FileEntry {
  final String path;
  final int from;
  final int ord;
  int to;
  int adds = 0, dels = 0;
  FileEntry(this.path, this.from, this.ord) : to = from;
}

List<FileEntry> collectFiles(List<String> lines, List<Meta> metas) {
  final out = <FileEntry>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.startsWith('diff --git ')) {
      out.add(FileEntry(metas[i].file ?? '(unknown)', i, out.length));
    } else if (out.isNotEmpty && _isChange(l)) {
      if (l.startsWith('+')) {
        out.last.adds++;
      } else {
        out.last.dels++;
      }
    }
    if (out.isNotEmpty) out.last.to = i;
  }
  return out;
}

class TreeNode {
  final String name;
  final Map<String, TreeNode> dirs = {};
  final List<FileEntry> files = [];
  TreeNode(this.name);
}

TreeNode treeModel(List<FileEntry> files) {
  final root = TreeNode('');
  for (final f in files) {
    final parts = f.path.split('/');
    var cur = root;
    for (var k = 0; k < parts.length - 1; k++) {
      cur = cur.dirs.putIfAbsent(parts[k], () => TreeNode(parts[k]));
    }
    cur.files.add(f);
  }
  return root;
}

/// Renders the sidebar. Directory chains with a single child are collapsed
/// into one row ("internal/handler") the way most tree views do it.
String renderTree(TreeNode n) {
  final b = StringBuffer('<ul>');
  for (final name in n.dirs.keys.toList()..sort()) {
    var d = n.dirs[name]!;
    var label = name;
    while (d.files.isEmpty && d.dirs.length == 1) {
      final only = d.dirs.values.first;
      label = '$label/${only.name}';
      d = only;
    }
    b.write('<li class="dir open"><div class="dn">'
        '<span class="ar">&#9662;</span>${esc(label)}</div>'
        '${renderTree(d)}</li>');
  }
  final fs = [...n.files]..sort((a, c) => a.path.compareTo(c.path));
  for (final f in fs) {
    final base = f.path.split('/').last;
    b.write('<li class="fl" data-f="${f.ord}" data-from="${f.from}" '
        'data-to="${f.to}" title="${esc(f.path)}">'
        '<span class="fn">${esc(base)}</span>'
        '<span class="badge" hidden></span>'
        '<span class="st"><i class="pl">+${f.adds}</i>'
        '<i class="mi">-${f.dels}</i></span></li>');
  }
  b.write('</ul>');
  return b.toString();
}

String uniRow(List<String> lines, List<Meta> metas, int i) {
  final m = metas[i];
  final n = m.newLine ?? m.oldLine;
  return '<div class="l ${cls(lines[i])}" data-i="$i">'
      '<span class="ln">${n ?? ''}</span>'
      '<span class="t">${esc(lines[i])}</span></div>';
}

/// Each file gets its own <section> so it can be collapsed once reviewed.
String sectionHead(int idx, FileEntry f) =>
    '<section class="fs" data-f="$idx" data-from="${f.from}" data-to="${f.to}">'
    '<div class="fh">'
    '<label class="vw"><input type="checkbox"><span>Viewed</span></label>'
    '<span class="fp">${esc(f.path)}</span>'
    '<span class="st"><i class="pl">+${f.adds}</i>'
    '<i class="mi">-${f.dels}</i></span>'
    '</div><div class="fb">';

String buildUnified(
    List<String> lines, List<Meta> metas, List<FileEntry> files) {
  final b = StringBuffer();
  var pos = 0;
  for (var fi = 0; fi < files.length; fi++) {
    final f = files[fi];
    while (pos < f.from) {
      b.write(uniRow(lines, metas, pos));
      pos++;
    }
    b.write(sectionHead(fi, f));
    for (var i = f.from; i <= f.to; i++) {
      b.write(uniRow(lines, metas, i));
    }
    b.write('</div></section>');
    pos = f.to + 1;
  }
  while (pos < lines.length) {
    b.write(uniRow(lines, metas, pos));
    pos++;
  }
  return b.toString();
}

/// Side-by-side. Runs of deletions are paired against the additions that
/// follow them, padding the shorter side with blanks; everything else spans
/// the full width.
String splitRange(List<String> lines, List<Meta> metas, int from, int to) {
  final b = StringBuffer();
  final dels = <int>[], adds = <int>[];
  const blank = '<div class="c e"></div>';

  void flush() {
    final n = dels.length > adds.length ? dels.length : adds.length;
    for (var k = 0; k < n; k++) {
      b.write('<div class="r">');
      b.write(k < dels.length ? cell(lines, metas, dels[k], false) : blank);
      b.write(k < adds.length ? cell(lines, metas, adds[k], true) : blank);
      b.write('</div>');
    }
    dels.clear();
    adds.clear();
  }

  for (var i = from; i <= to; i++) {
    final l = lines[i];
    if (_isChange(l)) {
      (l.startsWith('+') ? adds : dels).add(i);
    } else if (l.startsWith(' ')) {
      flush();
      b.write('<div class="r">'
          '${cell(lines, metas, i, false)}${cell(lines, metas, i, true)}'
          '</div>');
    } else {
      flush();
      b.write('<div class="r full">'
          '<div class="l ${cls(l)}" data-i="$i">'
          '<span class="ln"></span>'
          '<span class="t">${esc(l)}</span></div></div>');
    }
  }
  flush();
  return b.toString();
}

String buildSplit(List<String> lines, List<Meta> metas, List<FileEntry> files) {
  final b = StringBuffer();
  var pos = 0;
  for (var fi = 0; fi < files.length; fi++) {
    final f = files[fi];
    if (pos < f.from) b.write(splitRange(lines, metas, pos, f.from - 1));
    b.write(sectionHead(fi, f));
    b.write(splitRange(lines, metas, f.from, f.to));
    b.write('</div></section>');
    pos = f.to + 1;
  }
  if (pos < lines.length) {
    b.write(splitRange(lines, metas, pos, lines.length - 1));
  }
  return b.toString();
}
