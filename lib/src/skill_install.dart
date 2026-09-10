import 'dart:io';

import 'skill.g.dart';

export 'skill.g.dart' show skillMarkdown;

/// Where a Claude Code skill goes. Per-project skills travel with the
/// repository; user skills apply everywhere.
String skillDir({required bool project, String? repo}) {
  if (project) return '${repo ?? Directory.current.path}/.claude/skills';
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  return '$home/.claude/skills';
}

/// Writes the embedded skill to disk. Returns the path written.
///
/// The skill ships inside the binary rather than being fetched or copied out
/// of a checkout, so installing it never requires cloning this repository.
String installSkill({required bool project, String? repo, bool force = false}) {
  final dir =
      Directory('${skillDir(project: project, repo: repo)}/commitreview');
  final file = File('${dir.path}/SKILL.md');

  if (file.existsSync() && !force) {
    final existing = file.readAsStringSync().replaceAll('\r\n', '\n');
    if (existing.trim() == skillMarkdown.trim()) {
      stdout.writeln('commitreview: skill already installed and up to date at '
          '${file.path}');
      return file.path;
    }
    stdout.writeln('commitreview: updating the skill at ${file.path}');
  }

  dir.createSync(recursive: true);
  file.writeAsStringSync(skillMarkdown);
  stdout.writeln('commitreview: installed the skill to ${file.path}');
  stdout.writeln('commitreview: restart your agent, or start a new session, '
      'for it to be picked up.');
  return file.path;
}
