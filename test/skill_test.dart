import 'dart:io';

import 'package:commitreview/commitreview.dart';
import 'package:test/test.dart';

String norm(String s) => s.replaceAll('\r\n', '\n').trim();

void main() {
  group('the embedded skill', () {
    test('matches the markdown it was generated from', () {
      // The binary ships the skill so it can be installed without a clone.
      // If these drift, `install-skill` quietly hands out a stale skill.
      final md = File('skills/commitreview/SKILL.md').readAsStringSync();
      expect(norm(skillMarkdown), norm(md),
          reason: 'run: dart run tool/embed_skill.dart');
    });

    test('carries the frontmatter an agent needs to route on', () {
      expect(skillMarkdown, startsWith('---'));
      final fm = skillMarkdown.split('---')[1];
      expect(fm, contains('name: commitreview'));
      expect(fm, contains('description:'));
    });

    test('still tells the agent the thing it gets wrong unprompted', () {
      // Uncommitted work is invisible to the reviewer; this is the single
      // most load-bearing instruction in the file.
      expect(skillMarkdown, contains('Committing is required'));
      expect(skillMarkdown, contains('review_refresh'));
    });
  });

  group('install location', () {
    test('a project install lands beside the code', () {
      expect(skillDir(project: true, repo: '/tmp/x'), '/tmp/x/.claude/skills');
    });

    test('a user install lands in the home directory', () {
      final d = skillDir(project: false);
      expect(d, endsWith('/.claude/skills'));
    });
  });

  group('installing', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('skill_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes the skill where an agent will find it', () {
      final path = installSkill(project: true, repo: dir.path);
      expect(path, endsWith('.claude/skills/commitreview/SKILL.md'));
      expect(norm(File(path).readAsStringSync()), norm(skillMarkdown));
    });

    test('creating the directory tree is not the caller\'s problem', () {
      final nested = '${dir.path}/a/b/c';
      final path = installSkill(project: true, repo: nested);
      expect(File(path).existsSync(), isTrue);
    });

    test('installing twice is a no-op, not a duplicate or an error', () {
      final first = installSkill(project: true, repo: dir.path);
      final second = installSkill(project: true, repo: dir.path);
      expect(second, first);
      expect(norm(File(first).readAsStringSync()), norm(skillMarkdown));
    });

    test('a locally edited skill is replaced on the next install', () {
      final path = installSkill(project: true, repo: dir.path);
      File(path).writeAsStringSync('locally mangled');
      installSkill(project: true, repo: dir.path);
      expect(norm(File(path).readAsStringSync()), norm(skillMarkdown));
    });
  });
}
