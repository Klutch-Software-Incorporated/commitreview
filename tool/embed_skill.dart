// Regenerates lib/src/skill.g.dart from skills/commitreview/SKILL.md, so the
// skill ships inside the compiled binary and `commitreview skill install`
// works without a clone of this repository.
//
// The markdown stays the source of truth, since it is what people read on
// GitHub and edit, and this copies it into Dart. CI regenerates and fails if the
// result differs from what is committed.
//
//   dart run tool/embed_skill.dart

import 'dart:io';

const _source = 'skills/commitreview/SKILL.md';
const _out = 'lib/src/skill.g.dart';

void main() {
  final md = File(_source).readAsStringSync().replaceAll('\r\n', '\n');

  // The generated file uses a raw triple-quoted string, which cannot contain
  // its own delimiter and cannot end with a quote.
  if (md.contains("'''")) {
    stderr.writeln("embed_skill: $_source contains ''' and cannot be embedded "
        'as a raw string');
    exit(1);
  }
  if (md.endsWith("'")) {
    stderr.writeln('embed_skill: $_source must not end with a quote');
    exit(1);
  }

  File(_out).writeAsStringSync('''
// GENERATED. Do not edit. Run: dart run tool/embed_skill.dart
// Source: $_source

/// The agent skill, embedded so it can be installed from the binary alone.
const skillMarkdown = r\'\'\'
$md\'\'\';
''');

  stdout.writeln('embed_skill: wrote $_out (${md.length} bytes)');
}
