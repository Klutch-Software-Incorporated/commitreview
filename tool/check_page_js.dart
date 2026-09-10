// Extracts the page's JavaScript from the Dart raw string it lives in and
// runs `node --check` over it.
//
// Worth having as a real step: the template is a raw string, so a broken
// string literal or an unescaped apostrophe inside it compiles cleanly, ships,
// and then fails to parse in the browser — taking the entire UI with it. That
// has happened once already.
//
//   dart run tool/check_page_js.dart

import 'dart:io';

void main() async {
  final src = File('lib/src/template.dart').readAsStringSync();

  // The declaration may or may not be wrapped by the formatter, so find the
  // name and then the raw string that opens it.
  final decl = src.indexOf('const pageTemplate');
  final open = decl < 0 ? -1 : src.indexOf("r'''", decl);
  if (open < 0) {
    stderr.writeln('check_page_js: could not find the pageTemplate literal');
    exit(1);
  }
  final tpl = src.substring(open + "r'''".length);
  final end = tpl.indexOf("''';");
  if (end < 0) {
    stderr.writeln('check_page_js: pageTemplate is not terminated');
    exit(1);
  }

  final page = tpl.substring(0, end);
  final scriptStart = page.lastIndexOf('<script>');
  final scriptEnd = page.lastIndexOf('</script>');
  if (scriptStart < 0 || scriptEnd < scriptStart) {
    stderr.writeln('check_page_js: no <script> block in the template');
    exit(1);
  }

  // Placeholders are substituted at render time; give them plausible values so
  // the result is syntactically what the browser will actually receive.
  final js = page
      .substring(scriptStart + '<script>'.length, scriptEnd)
      .replaceAll('__VERSION__', '1')
      .replaceAll('__FORCEVIEW__', '');

  final tmp = await Directory.systemTemp.createTemp('commitreview_js');
  try {
    final f = File('${tmp.path}/page.js')..writeAsStringSync(js);
    final r = Process.runSync('node', ['--check', f.path]);
    if (r.exitCode != 0) {
      stderr.writeln('check_page_js: the page script does not parse\n');
      stderr.writeln(r.stderr);
      exit(1);
    }
    stdout.writeln('check_page_js: ok (${js.length} bytes)');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
