import 'anchor.dart';
import 'doc.dart';
import 'git.dart';
import 'model.dart';

/// The diff slice a thread points at — live if it is still in the current
/// patchset, otherwise the snapshot frozen when the comment was written.
String threadCtx(Thread t, Doc doc) {
  final b = StringBuffer();
  final idx = doc.locate(t);
  if (idx == null) {
    if (t.snap.isEmpty) return '(no context available)\n';
    for (var j = 0; j < t.snap.length; j++) {
      b.writeln(
          j == t.snapAt ? '${t.snap[j]}    <<<<<< comment here' : t.snap[j]);
    }
    return b.toString();
  }
  final w = ctxWindow(doc.lines, idx, 4);
  for (var j = w[0]; j <= w[1]; j++) {
    b.writeln(
        j == idx ? '${doc.lines[j]}    <<<<<< comment here' : doc.lines[j]);
  }
  return b.toString();
}

String threadMd(Thread t, Doc doc, {bool markNew = true}) {
  final b = StringBuffer();
  final flags = <String>[
    if (t.notInLatest)
      'no longer in the diff — raised on patchset ${shortSha(t.raisedOn)}',
    if (t.changed) 'the line has been edited since the comment',
    if (t.resolved) 'resolved',
  ];
  b.writeln('\n## Thread ${t.id} — ${t.where}'
      '${flags.isEmpty ? '' : ' (${flags.join('; ')})'}');
  b.writeln('```diff');
  b.write(threadCtx(t, doc));
  b.writeln('```');
  for (var k = 0; k < t.msgs.length; k++) {
    final m = t.msgs[k];
    final fresh = markNew && m.role == 'user' && k >= t.delivered;
    b.writeln('\n**${m.role == 'ai' ? 'you (earlier)' : 'reviewer'}'
        '${fresh ? ' — NEW' : ''}:** ${m.text.trim()}');
  }
  return b.toString();
}

String pendingMd(Session s, Doc doc) {
  final open = s.threads.where((t) => t.needsAgent).toList();
  if (open.isEmpty) {
    return 'No new review comments. '
        '(${s.threads.length} thread(s) total, all seen.)';
  }
  final b = StringBuffer();
  b.writeln('# Review — ${open.length} thread(s) need a response');
  b.writeln('# ${doc.label}, patchset ${doc.target.head.n} '
      '(${doc.target.head.short})');
  for (final t in open) {
    b.write(threadMd(t, doc));
  }
  b.writeln('\n---');
  b.writeln('Answer a question with review_reply(thread, text) so it appears '
      'inline in the browser, and review_resolve(thread) once a thread is '
      'handled. When you have made changes, commit them — then call '
      'review_refresh to pick the commit up as the next patchset. Comments '
      'are carried across by git, so they stay on the right lines.');
  for (final t in open) {
    t.delivered = t.msgs.length;
  }
  s.save();
  return b.toString();
}

String transcript(Session s, Doc doc) {
  if (s.threads.isEmpty) return 'Review closed with no comments.\n';
  final b = StringBuffer();
  b.writeln('# Code review — ${s.threads.length} thread(s)');
  b.writeln('# ${doc.label}, ${doc.target.patchsets.length} patchset(s)');
  for (final t in s.threads) {
    b.write(threadMd(t, doc, markNew: false));
  }
  return b.toString();
}
