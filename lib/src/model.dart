import 'dart:convert';
import 'dart:io';

import 'mapping.dart';
import 'target.dart';

String now() => DateTime.now().toIso8601String();

/// Where a repository's review state lives.
File storeFor(String repoTop) => File('$repoTop/.review/threads.json');

/// Reads the persisted review without committing to it, so the base it was
/// started against can be recovered before the target is resolved.
Map<String, dynamic>? peekSaved(File store) {
  if (!store.existsSync()) return null;
  try {
    return jsonDecode(store.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

class Msg {
  final String role; // 'user' | 'ai'
  final String text;
  final String at;
  Msg(this.role, this.text, this.at);

  Map<String, dynamic> toJson() => {'role': role, 'text': text, 'at': at};

  static Msg fromJson(Map<String, dynamic> m) =>
      Msg(m['role'] as String, m['text'] as String, m['at'] as String? ?? '');
}

/// A conversation attached to one line of one file.
///
/// The anchor is `(file, side, line)` as of the patchset it was raised on —
/// a real coordinate, not a fingerprint. Carrying it to a later patchset is
/// git's job: see [Session.advance].
class Thread {
  final int id;

  /// The patchset sha this comment was written against. The diff for that
  /// patchset is reproducible forever, so the thread can always be shown in
  /// the context it was actually written in.
  final String raisedOn;

  /// `new` — a line in the file as of [raisedOn]; carried forward on each
  /// patchset. `old` — a line in the base, which is pinned, so these anchors
  /// never move and never need mapping.
  final String side;

  String file;
  int line;

  /// Survived a patchset, but the line's content was edited.
  bool changed = false;

  /// Not present in the latest patchset. Never deleted — still readable
  /// against the patchset it was raised on.
  bool notInLatest = false;

  bool resolved = false;
  int delivered = 0;
  final List<Msg> msgs = [];

  /// Diff context frozen when the comment was written, so a thread that has
  /// dropped out of the current diff still shows the code it was about.
  List<String> snap = const [];
  int snapAt = 0;

  Thread(this.id, this.raisedOn, this.file, this.side, this.line);

  bool get needsAgent => !resolved && delivered < msgs.length;

  String get where => '$file:$line';

  Map<String, dynamic> toJson() => {
        'id': id,
        'raisedOn': raisedOn,
        'file': file,
        'side': side,
        'line': line,
        'changed': changed,
        'notInLatest': notInLatest,
        'resolved': resolved,
        'delivered': delivered,
        'snap': snap,
        'snapAt': snapAt,
        'msgs': msgs.map((m) => m.toJson()).toList(),
      };

  static Thread fromJson(Map<String, dynamic> m) {
    final t = Thread(
      (m['id'] as num).toInt(),
      m['raisedOn'] as String? ?? '',
      m['file'] as String? ?? '',
      m['side'] as String? ?? 'new',
      (m['line'] as num?)?.toInt() ?? 0,
    )
      ..changed = m['changed'] as bool? ?? false
      ..notInLatest = m['notInLatest'] as bool? ?? false
      ..resolved = m['resolved'] as bool? ?? false
      ..delivered = (m['delivered'] as num?)?.toInt() ?? 0
      ..snap = ((m['snap'] as List?) ?? const []).cast<String>()
      ..snapAt = (m['snapAt'] as num?)?.toInt() ?? 0;
    for (final j in (m['msgs'] as List? ?? const [])) {
      t.msgs.add(Msg.fromJson((j as Map).cast<String, dynamic>()));
    }
    return t;
  }
}

/// Moves [threads] onto a later patchset given per-file line maps, and
/// summarises what happened. Split out from [Session.advance] so it can be
/// exercised without a repository.
///
/// A file missing from [maps] is byte-identical between the two commits, so
/// its threads keep the line they already have.
String carry(List<Thread> threads, Map<String, FileMap> maps) {
  var moved = 0, edited = 0, dropped = 0;

  for (final t in threads) {
    // Base-side anchors point into the pinned base commit, which by
    // definition did not move.
    if (t.side == 'old' || t.notInLatest) continue;

    final fm = maps[t.file];
    if (fm == null) continue;

    final r = fm.map(t.line);
    if (r.gone) {
      t.notInLatest = true;
      dropped++;
      continue;
    }
    if (r.line != t.line || r.file != t.file) moved++;
    if (r.changed) {
      t.changed = true;
      edited++;
    }
    t.file = r.file;
    t.line = r.line!;
  }

  return '${threads.length} thread(s): $moved moved, $edited on edited '
      'lines, $dropped no longer in the diff';
}

class Session {
  final File store;

  /// The review this belongs to: the pinned base commit. Reviewing a
  /// different base is a different conversation.
  final String base;

  final List<Thread> threads = [];
  int nextId = 1;

  Session(this.store, this.base);

  Thread? byId(int id) {
    for (final t in threads) {
      if (t.id == id) return t;
    }
    return null;
  }

  Thread create(String raisedOn, String file, String side, int line) {
    final t = Thread(nextId++, raisedOn, file, side, line);
    threads.add(t);
    return t;
  }

  /// Carries every open thread from one patchset to the next, using git's own
  /// line mapping. A line git reports as deleted is deleted — there is no
  /// guessing here, and no thresholds to tune.
  ///
  /// Returns a one-line summary of what moved.
  String advance(Target target, String fromSha, String toSha) {
    final summary = carry(threads, diffMaps(target.repo, fromSha, toSha));
    save();
    return summary;
  }

  void load() {
    if (!store.existsSync()) return;
    try {
      final j = jsonDecode(store.readAsStringSync()) as Map<String, dynamic>;
      if (j['base'] != base) {
        stderr.writeln('review: ${store.path} holds a review of a different '
            'base — starting a new one.');
        return;
      }
      for (final raw in (j['threads'] as List? ?? const [])) {
        final th = Thread.fromJson((raw as Map).cast<String, dynamic>());
        threads.add(th);
        if (th.id >= nextId) nextId = th.id + 1;
      }
    } catch (e) {
      threads.clear();
      stderr.writeln('review: could not read ${store.path} ($e) — '
          'starting fresh.');
    }
  }

  Target? _target;

  /// Kept so [save] can persist patchset history alongside the threads.
  set target(Target t) => _target = t;

  void save() {
    try {
      store.parent.createSync(recursive: true);
      // Keep review state out of the repository's own diff — otherwise it
      // shows up as a change to review, and gets committed by `git add -A`.
      final ignore = File('${store.parent.path}/.gitignore');
      if (!ignore.existsSync()) ignore.writeAsStringSync('*\n');
      store.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'base': base,
        if (_target != null) 'target': _target!.toJson(),
        'threads': threads.map((t) => t.toJson()).toList(),
      }));
    } catch (e) {
      stderr.writeln('review: could not save threads ($e)');
    }
  }
}
