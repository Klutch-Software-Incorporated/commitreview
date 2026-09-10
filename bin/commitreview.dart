// commitreview: a local code review tool.
//
// Serves a commit's diff in the browser and lets you comment on any line. The
// server stays up and exposes those threads over MCP at /mcp, so an agent can
// read them, reply inline, and pick up the commits you make in response.
//
//   commitreview            # the latest commit (HEAD~1..HEAD)
//   commitreview main       # everything since main
//   commitreview install-skill
//
//   --repo <path>   run against another repo      --port <n>  default 4970
//   --out <file>    also write the review to file --no-open   don't open browser
//   --split         start in side-by-side view    --unified   start in unified
//
// No runtime dependencies. `dart compile exe bin/commitreview.dart` builds a
// standalone binary.

import 'dart:io';

import 'package:commitreview/commitreview.dart';

/// Every subcommand, so an unrecognised one can be named as such instead of
/// being mistaken for a git ref.
const commands = {'init', 'install-skill'};

/// Flags the review command accepts. An unknown flag used to fall through to
/// the ref list, so `--verison` reported "expected at most one base ref".
const flags = {
  '--repo',
  '--port',
  '--out',
  '--no-open',
  '--split',
  '--unified',
  '--version',
  '-v',
  '--help',
  '-h',
};

void usage() {
  stderr.writeln('''
usage: commitreview [<base>] [options]

  (no base)          review the latest commit (HEAD~1..HEAD)
  <base>             review everything since <base>, e.g. `commitreview main`

commands:
  init               set this repository up for an agent, then exit
                     (writes .mcp.json, installs the skill)
  install-skill      install the bundled agent skill, then exit

  Both take --help of their own.

options:
  --repo <path>      repository to run in (default: cwd)
  --port <n>         listen port (default: 4970, or the next one free)
  --out <file>       also write the review to this file
  --no-open          do not launch a browser
  --split            start in side-by-side view
  --unified          start in unified view
  --version, -v      print the version and exit

Commits are the unit of review, as in Gerrit: the base is resolved once and
pinned, and each new head commit becomes the next patchset. Uncommitted work
is not reviewed, so commit it and then refresh.

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

String? _valueAfter(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

void main(List<String> argv) async {
  if (argv.isNotEmpty && argv.first == 'install-skill') {
    final rest = argv.skip(1).toList();
    if (rest.contains('-h') || rest.contains('--help')) {
      stderr.writeln('''
usage: commitreview install-skill [options]

  Writes the bundled agent skill so your coding agent knows how to run a
  review: open one, read your comments, reply inline, commit, and refresh.

options:
  --project          install into ./.claude/skills (travels with the repo)
                     instead of your user-level skills directory
  --repo <path>      with --project, the repository to install into
  --force            overwrite even if the file was edited locally

Restart your agent afterwards so it picks the skill up.
''');
      exit(0);
    }
    installSkill(
      project: rest.contains('--project'),
      repo: _valueAfter(rest, '--repo'),
      force: rest.contains('--force'),
    );
    exit(0);
  }

  // Setting a repository up by hand means writing .mcp.json, installing the
  // skill, and knowing that both are read at agent-session start. That is
  // three chances to get it wrong, so do it in one command.
  if (argv.isNotEmpty && argv.first == 'init') {
    final rest = argv.skip(1).toList();
    if (rest.contains('-h') || rest.contains('--help')) {
      stderr.writeln('''
usage: commitreview init [options]

  Sets a repository up so an agent can take part in reviews:
    - adds this tool to .mcp.json, keeping any servers already configured
    - installs the bundled agent skill
    - makes .review/ ignore itself, so review state is never reviewable

options:
  --repo <path>      repository to set up (default: cwd)
  --port <n>         port to record in .mcp.json (default: 4970)
  --project          install the skill into this repo rather than for your
                     user, so it travels with the code

Safe to re-run: it merges rather than overwrites.
''');
      exit(0);
    }
    await initRepo(
      _valueAfter(rest, '--repo') ?? Directory.current.path,
      int.tryParse(_valueAfter(rest, '--port') ?? ''),
      projectSkill: rest.contains('--project'),
    );
    exit(0);
  }

  if (argv.contains('--version') || argv.contains('-v')) {
    stdout.writeln('commitreview $version');
    exit(0);
  }

  var repo = Directory.current.path;
  var port = 4970;
  var open = true;
  var forceView = ''; // '' = remember last choice, else 'spl' / 'uni'
  var exactPort = false;
  String? outPath;
  final refs = <String>[];

  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (a == '--repo' && i + 1 < argv.length) {
      repo = argv[++i];
    } else if (a == '--port' && i + 1 < argv.length) {
      port = int.parse(argv[++i]);
      exactPort = true; // a port you asked for is not silently substituted
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
    } else if (a.startsWith('-')) {
      // Unknown flags used to land in the ref list, so a typo surfaced as
      // "cannot resolve --verison to a commit", which explains nothing.
      stderr.writeln('commitreview: unknown option "$a"');
      stderr.writeln('Options: ${flags.toList().join(', ')}');
      stderr.writeln('Run `commitreview --help` for details.');
      exit(2);
    } else {
      refs.add(a);
    }
  }

  if (refs.length > 1) {
    stderr.writeln('commitreview: expected at most one base ref, got '
        '${refs.join(' ')}');
    exit(2);
  }

  // A review already under way keeps the base it was started against, even
  // though HEAD~1 has moved on since. Anything unrecognisable in the stored
  // file, including state written by an older version, is ignored rather
  // than allowed to bring the tool down.
  final saved = peekSaved(storeFor(repoRoot(repo)))?['target'];
  final target = Target.resolveFor(repo, refs.isEmpty ? null : refs.first,
      saved: saved is Map ? saved.cast<String, dynamic>() : null);
  if (target == null) {
    if (refs.isEmpty) {
      stderr.writeln('commitreview: no commits in this repository yet.');
      exit(1);
    }
    stderr.writeln('commitreview: cannot resolve "${refs.first}" to a commit.');
    // A word with a hyphen is far more likely to be a mistyped subcommand
    // than a branch. Saying so beats leaving someone to work out why
    // `install-skill` was treated as a git ref.
    if (RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)+$').hasMatch(refs.first)) {
      stderr.writeln('Did you mean a command? '
          'This version has: ${commands.toList().join(', ')}.');
      stderr.writeln('If the command you want is missing, your install is '
          'older than the docs; re-run `dart pub global activate`.');
    }
    exit(1);
  }

  // The agent's MCP client connects to whatever .mcp.json says, so binding a
  // different port hands it someone else's review. Prefer the configured one.
  if (!exactPort) {
    port = portFromMcpConfig(repoRoot(repo)) ?? port;
  }

  final doc = Doc(target, forceView);
  if (!doc.rebuild()) exit(1);
  if (doc.lines.isEmpty) {
    stdout.writeln('No changes to review (${doc.label}).');
    exit(0);
  }
  await serve(repo, port, open, doc, outPath, exactPort: exactPort);
}
