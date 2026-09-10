import 'dart:convert';
import 'dart:io';

/// Git emits UTF-8, but `Process.runSync` decodes with the system encoding by
/// default, which on Windows is the ANSI code page. That turns every accented
/// character, CJK glyph and emoji in a diff into mojibake. Malformed input is
/// allowed through as replacement characters rather than thrown, since a
/// latin-1 file somewhere should not take down a review.
const _gitOut = Utf8Codec(allowMalformed: true);

/// Thin wrapper around the git CLI. Returns null on failure rather than
/// throwing: a review in progress should survive a bad ref or a transient
/// error by keeping what it already has.
///
/// Arguments are passed as a list, never a shell string, so a branch name
/// cannot turn into a command.
String? git(String repo, List<String> args) {
  try {
    final r = Process.runSync(
      'git',
      args,
      workingDirectory: repo,
      stdoutEncoding: _gitOut,
      stderrEncoding: _gitOut,
    );
    if (r.exitCode != 0) return null;
    return (r.stdout as String).replaceAll('\r\n', '\n');
  } catch (_) {
    return null;
  }
}

String? gitLine(String repo, List<String> args) => git(repo, args)?.trim();

/// Resolves [rev] to a full commit sha, or null if it does not exist.
String? resolve(String repo, String rev) {
  final sha = gitLine(repo, ['rev-parse', '--verify', '$rev^{commit}']);
  return (sha == null || sha.isEmpty) ? null : sha;
}

/// The repository root, so state lands next to the repo rather than wherever
/// the process happened to start.
String repoRoot(String repo) =>
    gitLine(repo, ['rev-parse', '--show-toplevel']) ?? repo;

String shortSha(String sha) => sha.length > 8 ? sha.substring(0, 8) : sha;

/// One-line summary of a commit, for labelling patchsets.
String subjectOf(String repo, String sha) =>
    gitLine(repo, ['log', '-1', '--format=%s', sha]) ?? '';

/// Git's own empty-tree object. Lets the first commit in a repository be
/// reviewed with the same code path as any other.
const emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
