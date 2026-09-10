import 'dart:convert';
import 'dart:io';

import 'git.dart';
import 'skill_install.dart';

/// Version of the tool, reported by `--version`.
///
/// Keep this in step with `pubspec.yaml`. A stale install that reports the
/// same version as a newer one is genuinely confusing: `dart pub global
/// activate --source git` pins whatever commit was current at the time, so
/// two people on "0.4.0" can have different builds.
const version = '0.5.2';

const _mcpServerName = 'commitreview';

/// The port this repository's `.mcp.json` points at, if it has an entry.
///
/// A repository's MCP config is per-repository but a port is machine-wide, so
/// two repositories both hardcoding 4970 collide: the second server takes the
/// next free port, its config still says 4970, and the agent's MCP tools end
/// up connected to the *other* repository's review. Silently answering the
/// wrong review is worse than failing, so the server reads the port back out
/// of the config and binds what the agent was told to expect.
int? portFromMcpConfig(String repoTop) {
  try {
    final file = File('$repoTop/.mcp.json');
    if (!file.existsSync()) return null;
    final root = jsonDecode(file.readAsStringSync());
    if (root is! Map) return null;
    final servers = root['mcpServers'];
    if (servers is! Map) return null;
    final entry = servers[_mcpServerName];
    if (entry is! Map) return null;
    final url = entry['url'];
    if (url is! String) return null;
    return Uri.tryParse(url)?.port;
  } catch (_) {
    return null;
  }
}

/// First port from [first] that nothing is currently listening on.
///
/// Used when setting a repository up, so each one is handed a port of its own
/// rather than every repository claiming 4970 and racing for it.
Future<int> freePort(int first, {int span = 40}) async {
  for (var p = first; p < first + span; p++) {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
      await s.close();
      return p;
    } on SocketException {
      continue;
    }
  }
  return first;
}

/// Adds this tool to a repository's `.mcp.json`, keeping anything already
/// configured there. Returns a line describing what happened.
///
/// Never overwrites blindly: a file that is present but unparseable is left
/// alone and reported, because clobbering someone's MCP configuration to fix
/// our own entry is a bad trade.
String writeMcpConfig(String repoTop, int port) {
  final file = File('$repoTop/.mcp.json');
  final entry = {
    'type': 'http',
    'url': 'http://127.0.0.1:$port/mcp',
  };

  Map<String, dynamic> root;
  if (file.existsSync()) {
    try {
      final parsed = jsonDecode(file.readAsStringSync());
      if (parsed is! Map) throw const FormatException('not an object');
      root = parsed.cast<String, dynamic>();
    } catch (e) {
      return 'left ${file.path} alone: it exists but could not be parsed '
          '($e). Add this yourself:\n'
          '  "$_mcpServerName": ${jsonEncode(entry)}';
    }
  } else {
    root = <String, dynamic>{};
  }

  final servers = (root['mcpServers'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
  final existed = servers.containsKey(_mcpServerName);
  final unchanged =
      existed && jsonEncode(servers[_mcpServerName]) == jsonEncode(entry);
  servers[_mcpServerName] = entry;
  root['mcpServers'] = servers;

  if (unchanged) return 'MCP config already correct in ${file.path}';

  file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(root)}\n');
  final others = servers.keys.where((k) => k != _mcpServerName).length;
  return '${existed ? 'updated' : 'added'} "$_mcpServerName" in ${file.path}'
      '${others > 0 ? ' (kept $others other server${others == 1 ? '' : 's'})' : ''}';
}

/// Makes `.review/` ignore itself, so review state never shows up as a change
/// to review. Done up front rather than on first save so it is true from the
/// moment the repository is set up.
String writeReviewIgnore(String repoTop) {
  final dir = Directory('$repoTop/.review');
  final file = File('${dir.path}/.gitignore');
  if (file.existsSync()) return 'review state already ignored';
  dir.createSync(recursive: true);
  file.writeAsStringSync('*\n');
  return 'made ${dir.path} ignore itself';
}

/// One-shot setup for a repository: MCP config, the agent skill, and the
/// ignore rule. Everything the transcript of a first-time setup showed people
/// doing by hand.
Future<void> initRepo(String repo, int? port,
    {bool projectSkill = false}) async {
  final top = repoRoot(repo);
  if (resolve(repo, 'HEAD') == null) {
    stdout.writeln('commitreview: note, $top has no commits yet. '
        'There is nothing to review until you make one.');
  }

  // Pick a port nothing else is on, so this repository's config and its server
  // agree even when another review is already open elsewhere.
  final chosen = port ?? portFromMcpConfig(top) ?? await freePort(4970);
  if (port == null && chosen != 4970) {
    stdout.writeln('commitreview: 4970 is taken, using $chosen for this '
        'repository');
  }

  stdout.writeln('commitreview: ${writeMcpConfig(top, chosen)}');
  stdout.writeln('commitreview: ${writeReviewIgnore(top)}');
  installSkill(project: projectSkill, repo: top);

  stdout.writeln('');
  stdout.writeln('Next:');
  stdout.writeln('  1. Restart your agent, so it picks up the skill and the');
  stdout.writeln('     MCP server. Both are read once, at session start.');
  stdout.writeln('  2. Run `commitreview` to open a review of the latest');
  stdout.writeln('     commit, then tell your agent you have left comments.');
  stdout.writeln('');
  stdout.writeln('Start the server before the agent session, or its MCP tools');
  stdout.writeln('will not be connected and it will fall back to HTTP.');
}
