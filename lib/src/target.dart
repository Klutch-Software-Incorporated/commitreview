import 'git.dart';

/// One reviewed state of the branch: a commit, plus when we first saw it.
/// Equivalent to a Gerrit patchset.
class Patchset {
  final int n;
  final String sha;
  final String subject;
  final String at;

  Patchset(this.n, this.sha, this.subject, this.at);

  String get short => shortSha(sha);

  Map<String, dynamic> toJson() =>
      {'n': n, 'sha': sha, 'subject': subject, 'at': at};

  static Patchset fromJson(Map<String, dynamic> m) => Patchset(
        (m['n'] as num).toInt(),
        m['sha'] as String,
        m['subject'] as String? ?? '',
        m['at'] as String? ?? '',
      );
}

/// What is under review: a fixed base commit, and the succession of head
/// commits that have been compared against it.
///
/// The base is resolved once and then pinned. That is what makes both
/// workflows behave: amending rewrites HEAD but leaves the base alone, and
/// committing on top just makes the next patchset cumulative. If the base
/// tracked HEAD~1 it would slide forward and you would end up reviewing only
/// the most recent fix instead of the whole change.
class Target {
  final String repo;
  final String baseLabel;
  final String base;
  final List<Patchset> patchsets = [];

  Target(this.repo, this.baseLabel, this.base);

  Patchset get head => patchsets.last;

  String get label => '$baseLabel..${head.short}';

  /// Resolves the review target. [baseRef] defaults to the commit before
  /// HEAD, so running the tool with no arguments reviews the latest commit.
  /// Returns null when the repository has no commits at all.
  ///
  /// [saved] is a previously persisted target, if any. It wins unless the
  /// caller explicitly asked for a different base — otherwise resuming a
  /// review after new commits would silently re-resolve `HEAD~1` to a
  /// different commit and start over, losing the conversation.
  static Target? resolveFor(String repo, String? baseRef,
      {Map<String, dynamic>? saved}) {
    final headSha = resolve(repo, 'HEAD');
    if (headSha == null) return null;

    final savedBase = saved?['base'] as String?;
    final savedLabel = saved?['baseLabel'] as String?;
    if (savedBase != null && (baseRef == null || baseRef == savedLabel)) {
      final t = Target(repo, savedLabel ?? 'HEAD~1', savedBase);
      for (final p in (saved!['patchsets'] as List?) ?? const []) {
        t.patchsets.add(Patchset.fromJson((p as Map).cast<String, dynamic>()));
      }
      // HEAD may have moved while we were not running.
      if (t.patchsets.isEmpty || t.patchsets.last.sha != headSha) {
        t.record(headSha);
      }
      return t;
    }

    var label = baseRef ?? 'HEAD~1';
    var baseSha = resolve(repo, label);
    if (baseSha == null && baseRef == null) {
      // The very first commit has no parent; diff it against the empty tree.
      label = 'the empty tree';
      baseSha = emptyTree;
    }
    if (baseSha == null) return null;

    final t = Target(repo, label, baseSha);
    t.record(headSha);
    return t;
  }

  /// Adds [sha] as the next patchset, and pins it so that a later rebase or
  /// squash cannot let `git gc` prune a commit someone has reviewed. The ref
  /// lives in its own namespace, so it stays out of branches and tags.
  Patchset record(String sha) {
    final p = Patchset(patchsets.length + 1, sha, subjectOf(repo, sha),
        DateTime.now().toIso8601String());
    patchsets.add(p);
    git(repo, ['update-ref', 'refs/review/${shortSha(base)}/${p.n}', sha]);
    return p;
  }

  /// Records a new patchset if HEAD has moved since the last one.
  /// Returns the previous head sha when it did, so callers can carry threads
  /// across the gap; null when nothing changed.
  String? poll() {
    final now = resolve(repo, 'HEAD');
    if (now == null || now == head.sha) return null;
    final from = head.sha;
    record(now);
    return from;
  }

  /// True when there is work that no patchset covers yet.
  bool get dirty {
    final s = git(repo, ['status', '--porcelain', '--untracked-files=no']);
    return s != null && s.trim().isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
        'baseLabel': baseLabel,
        'base': base,
        'patchsets': patchsets.map((p) => p.toJson()).toList(),
      };
}
