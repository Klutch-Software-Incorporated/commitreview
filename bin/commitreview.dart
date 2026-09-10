// review — a local code-review tool.
//
// Renders `git diff` in the browser and lets you comment on any line. The
// server stays up and exposes those threads over MCP at /mcp, so an agent can
// read them, reply inline, and call review_refresh after editing to rebuild
// the diff. Threads re-anchor to the new diff by content.
//
//   dart run commitreview                 # uncommitted changes (git diff HEAD)
//   dart run commitreview main            # working tree vs main
//   dart run commitreview --staged        # staged only
//   dart run commitreview abc123 def456   # any two refs
//
//   --repo <path>   run against another repo      --port <n>  default 4970
//   --out <file>    also write the review to file --no-open   don't open browser
//   --split         start in side-by-side view    --unified   start in unified
//
// No runtime dependencies. `dart compile exe bin/review.dart` for a binary.

import 'dart:io';

import 'package:commitreview/commitreview.dart';

void usage() {
  stderr.writeln('''
usage: review [<base>] [options]

  (no base)          review the latest commit (HEAD~1..HEAD)
  <base>             review everything since <base>, e.g. `review main`

options:
  --repo <path>      repository to run in (default: cwd)
  --port <n>         listen port (default: 4970)
  --out <file>       also write the review to this file
  --no-open          do not launch a browser
  --split            start in side-by-side view
  --unified          start in unified view

Commits are the unit of review, as in Gerrit: the base is resolved once and
pinned, and each new head commit becomes the next patchset. Uncommitted work
is not reviewed — commit it, then refresh.

Comments anchor to (file, line) on the patchset they were raised on, and are
carried onto later patchsets using git's own line mapping, so an edited line
keeps its comment and a deleted one is reported as deleted rather than
guessed at. Nothing is ever discarded: a thread that leaves the diff stays
readable against the patchset it was raised on.

The server runs until you stop it and exposes an MCP endpoint at /mcp, so the
agent can read comments, reply inline, and pick up new commits. Threads
persist in <repo>/.review/threads.json.
''');
}

void main(List<String> argv) async {
  var repo = Directory.current.path;
  var port = 4970;
  var open = true;
  var forceView = ''; // '' = remember last choice, else 'spl' / 'uni'
  String? outPath;
  final refs = <String>[];

  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (a == '--repo' && i + 1 < argv.length) {
      repo = argv[++i];
    } else if (a == '--port' && i + 1 < argv.length) {
      port = int.parse(argv[++i]);
    } else if (a == '--out' && i + 1 < argv.length) {
      outPath = argv[++i];
    } else if (a == '--no-open') {
      open = false;
    } else if (a == '--split') {
      forceView = 'spl';
    } else if (a == '--unified') {
      forceView = 'uni';
    } else if (a == '-h' || a == '--help') {
      usage();
      exit(0);
    } else if (a == 'serve' && refs.isEmpty) {
      // Accepted and ignored: serving is the only mode.
    } else {
      refs.add(a);
    }
  }

  if (refs.length > 1) {
    stderr.writeln('review: expected at most one base ref, got '
        '${refs.join(' ')}');
    exit(2);
  }

  // A review already under way keeps the base it was started against, even
  // though HEAD~1 has moved on since.
  final saved = peekSaved(storeFor(repoRoot(repo)));
  final target = Target.resolveFor(repo, refs.isEmpty ? null : refs.first,
      saved: (saved?['target'] as Map?)?.cast<String, dynamic>());
  if (target == null) {
    stderr.writeln(refs.isEmpty
        ? 'review: no commits in this repository yet.'
        : 'review: cannot resolve "${refs.first}" to a commit.');
    exit(1);
  }

  final doc = Doc(target, forceView);
  if (!doc.rebuild()) exit(1);
  if (doc.lines.isEmpty) {
    stdout.writeln('No changes to review (${doc.label}).');
    exit(0);
  }
  await serve(repo, port, open, doc, outPath);
}
